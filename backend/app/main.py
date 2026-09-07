import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from time import perf_counter

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.portfolio import router as portfolio_router
from app.config import AppSettings
from app.dependencies import ApplicationRuntime, build_runtime, get_runtime
from app.domain.errors import MarketDataError, PortfolioValidationError, ServiceError
from app.observability import (
    bind_request_id,
    bind_snapshot_id,
    configure_structured_logging,
    get_logger,
    log_event,
    normalized_request_id,
    reset_request_id,
    reset_snapshot_id,
)

logger = get_logger("http")


def _error_response(status_code: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message}},
    )


def create_app(
    settings: AppSettings | None = None,
    runtime: ApplicationRuntime | None = None,
) -> FastAPI:
    resolved_settings = settings or AppSettings.from_environment()
    resolved_runtime = runtime or build_runtime(resolved_settings)
    configure_structured_logging(resolved_settings.log_level)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        yield
        await resolved_runtime.close()

    api = FastAPI(
        title="CryptoPortfolioAdvisor API",
        version="0.1.0",
        debug=False,
        docs_url="/docs" if resolved_settings.docs_enabled else None,
        redoc_url="/redoc" if resolved_settings.docs_enabled else None,
        openapi_url="/openapi.json" if resolved_settings.docs_enabled else None,
        lifespan=lifespan,
    )
    api.state.runtime = resolved_runtime

    @api.middleware("http")
    async def request_boundary(request: Request, call_next):  # type: ignore[no-untyped-def]
        request_id = normalized_request_id(request.headers.get("X-Request-ID"))
        request_token = bind_request_id(request_id)
        snapshot_token = bind_snapshot_id(None)
        started = perf_counter()
        response = None
        try:
            content_length = request.headers.get("content-length")
            if content_length is not None:
                try:
                    declared_size = int(content_length)
                except ValueError:
                    declared_size = 0
                if declared_size > resolved_settings.max_request_body_bytes:
                    response = _error_response(
                        413,
                        "request_too_large",
                        "Request payload is too large.",
                    )
                    return response

            if request.method in {"POST", "PUT", "PATCH"}:
                body = await request.body()
                if len(body) > resolved_settings.max_request_body_bytes:
                    response = _error_response(
                        413,
                        "request_too_large",
                        "Request payload is too large.",
                    )
                    return response

            response = await call_next(request)
            return response
        except Exception as error:
            log_event(
                logger,
                "request_failed",
                error_category="internal_error",
                exception_type=type(error).__name__,
                level=logging.ERROR,
            )
            response = _error_response(
                500,
                "internal_error",
                "An internal server error occurred.",
            )
            return response
        finally:
            status_code = response.status_code if response is not None else 500
            latency_ms = round((perf_counter() - started) * 1_000, 2)
            log_event(
                logger,
                "http_request_completed",
                endpoint=request.url.path,
                method=request.method,
                status_code=status_code,
                latency_ms=latency_ms,
                level=logging.ERROR if status_code >= 500 else logging.INFO,
            )
            if response is not None:
                response.headers["X-Request-ID"] = request_id
            reset_snapshot_id(snapshot_token)
            reset_request_id(request_token)

    @api.exception_handler(PortfolioValidationError)
    async def portfolio_validation_error_handler(
        _request: Request,
        error: PortfolioValidationError,
    ) -> JSONResponse:
        log_event(logger, "request_failed", error_category="portfolio_validation")
        return _error_response(400, "invalid_request", str(error))

    @api.exception_handler(MarketDataError)
    async def market_data_error_handler(
        _request: Request,
        error: MarketDataError,
    ) -> JSONResponse:
        log_event(
            logger,
            "request_failed",
            error_category=error.code,
            market_provider_outcome=error.code,
        )
        return _error_response(error.status_code, error.code, str(error))

    @api.exception_handler(ServiceError)
    async def service_error_handler(
        _request: Request,
        error: ServiceError,
    ) -> JSONResponse:
        log_event(logger, "request_failed", error_category=error.code)
        return _error_response(error.status_code, error.code, str(error))

    @api.exception_handler(RequestValidationError)
    async def request_validation_error_handler(
        _request: Request,
        _error: RequestValidationError,
    ) -> JSONResponse:
        log_event(logger, "request_failed", error_category="malformed_request")
        return _error_response(422, "malformed_request", "Request payload is malformed.")

    @api.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/ready")
    async def ready(request: Request) -> JSONResponse:
        application_runtime = get_runtime(request)
        if await application_runtime.is_ready():
            database_status = "ok" if application_runtime.database is not None else "not_required"
            return JSONResponse(
                status_code=200,
                content={"status": "ready", "database": database_status},
            )
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "unavailable"},
        )

    api.include_router(portfolio_router)
    return api


app = create_app()
