import json
import logging
import re
import sys
from contextvars import ContextVar, Token
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
_request_id: ContextVar[str] = ContextVar("request_id", default="-")
_snapshot_id: ContextVar[str | None] = ContextVar("snapshot_id", default=None)

_LOG_FIELDS = (
    "event",
    "request_id",
    "endpoint",
    "method",
    "status_code",
    "latency_ms",
    "snapshot_id",
    "analysis_mode",
    "market_data_mode",
    "market_provider_outcome",
    "openai_outcome",
    "openai_model",
    "openai_request_id",
    "input_tokens",
    "output_tokens",
    "total_tokens",
    "proposed_actions",
    "accepted_actions",
    "rejected_actions",
    "idempotency_outcome",
    "error_category",
    "exception_type",
    "record_count",
)


class StructuredJSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "severity": record.levelname,
        }
        for field in _LOG_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        if "event" not in payload:
            payload["event"] = record.getMessage()
        return json.dumps(payload, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def configure_structured_logging(level: str) -> None:
    logger = logging.getLogger("crypto_portfolio_advisor")
    logger.setLevel(level)
    logger.propagate = False
    if any(getattr(handler, "_crypto_portfolio_handler", False) for handler in logger.handlers):
        for handler in logger.handlers:
            if getattr(handler, "_crypto_portfolio_handler", False):
                handler.setLevel(level)
        return

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(level)
    handler.setFormatter(StructuredJSONFormatter())
    handler._crypto_portfolio_handler = True  # type: ignore[attr-defined]
    logger.addHandler(handler)


def get_logger(component: str) -> logging.Logger:
    return logging.getLogger(f"crypto_portfolio_advisor.{component}")


def normalized_request_id(candidate: str | None) -> str:
    if candidate is not None:
        normalized = candidate.strip()
        if _REQUEST_ID_PATTERN.fullmatch(normalized):
            return normalized
    return str(uuid4())


def bind_request_id(value: str) -> Token[str]:
    return _request_id.set(value)


def reset_request_id(token: Token[str]) -> None:
    _request_id.reset(token)


def current_request_id() -> str:
    return _request_id.get()


def bind_snapshot_id(value: str | None) -> Token[str | None]:
    return _snapshot_id.set(value)


def reset_snapshot_id(token: Token[str | None]) -> None:
    _snapshot_id.reset(token)


def log_event(
    logger: logging.Logger,
    event: str,
    *,
    level: int = logging.INFO,
    **fields: object,
) -> None:
    safe_fields = {
        "event": event,
        "request_id": current_request_id(),
        "snapshot_id": _snapshot_id.get(),
    }
    safe_fields.update({key: value for key, value in fields.items() if key in _LOG_FIELDS})
    logger.log(level, event, extra=safe_fields)
