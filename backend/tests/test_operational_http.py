import json
import logging
from dataclasses import dataclass

import httpx
import pytest

from app.config import AppSettings
from app.dependencies import ApplicationRuntime
from app.main import create_app
from app.observability import StructuredJSONFormatter


class UnusedAnalysisService:
    async def analyze(self, _snapshot):
        raise AssertionError("Health probes must not analyze a portfolio.")


@dataclass
class ReadinessStore:
    ready: bool
    checks: int = 0

    async def is_ready(self) -> bool:
        self.checks += 1
        return self.ready

    async def get_or_compute(self, _snapshot, _operation):
        raise AssertionError("Not used by operational endpoint tests.")

    async def cleanup_expired(self) -> int:
        return 0


def _app(ready: bool = True):
    settings = AppSettings.from_environment({"APP_ENV": "test"})
    store = ReadinessStore(ready)
    runtime = ApplicationRuntime(
        settings=settings,
        analysis_service=UnusedAnalysisService(),
        idempotency_store=store,
    )
    return create_app(settings, runtime), store


def test_production_disables_debug_and_api_docs_by_default() -> None:
    settings = AppSettings.from_environment(
        {
            "APP_ENV": "production",
            "MARKET_DATA_MODE": "live",
            "COINGECKO_API_TIER": "pro",
            "COINGECKO_API_KEY": "backend-only-placeholder",
            "OPENAI_ENABLED": "false",
            "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
        }
    )
    store = ReadinessStore(True)
    runtime = ApplicationRuntime(settings, UnusedAnalysisService(), store)

    api = create_app(settings, runtime)

    assert api.debug is False
    assert api.docs_url is None
    assert api.redoc_url is None
    assert api.openapi_url is None


@pytest.mark.asyncio
async def test_valid_incoming_request_id_is_preserved() -> None:
    api, _ = _app()
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health", headers={"X-Request-ID": "ios.retry-42"})

    assert response.headers["X-Request-ID"] == "ios.retry-42"


@pytest.mark.asyncio
async def test_invalid_incoming_request_id_is_replaced() -> None:
    api, _ = _app()
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health", headers={"X-Request-ID": "bad id/value"})

    generated = response.headers["X-Request-ID"]
    assert generated != "bad id/value"
    assert len(generated) == 36


@pytest.mark.asyncio
async def test_health_does_not_probe_database_or_external_providers() -> None:
    api, store = _app(ready=False)
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert store.checks == 0


@pytest.mark.asyncio
async def test_readiness_reports_unavailable_dependency_safely() -> None:
    api, store = _app(ready=False)
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "database": "unavailable"}
    assert store.checks == 1


@pytest.mark.asyncio
async def test_process_local_readiness_reports_database_not_required() -> None:
    api, _ = _app(ready=True)
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready", "database": "not_required"}


@pytest.mark.asyncio
async def test_request_body_limit_uses_sanitized_error() -> None:
    api, _ = _app()
    transport = httpx.ASGITransport(app=api)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/v1/portfolio/analyze",
            content=b"x" * 65_537,
            headers={"Content-Type": "application/json"},
        )

    assert response.status_code == 413
    assert response.json() == {
        "error": {
            "code": "request_too_large",
            "message": "Request payload is too large.",
        }
    }


def test_structured_formatter_excludes_secrets_prompts_and_provider_payloads() -> None:
    record = logging.makeLogRecord(
        {
            "levelname": "INFO",
            "msg": "untrusted message containing secret-api-key",
            "event": "safe_event",
            "request_id": "request-1",
            "api_key": "secret-api-key",
            "raw_prompt": "private portfolio prompt",
            "provider_payload": "raw provider response",
        }
    )

    output = StructuredJSONFormatter().format(record)
    decoded = json.loads(output)

    assert decoded["event"] == "safe_event"
    assert decoded["request_id"] == "request-1"
    assert "secret-api-key" not in output
    assert "private portfolio prompt" not in output
    assert "raw provider response" not in output
