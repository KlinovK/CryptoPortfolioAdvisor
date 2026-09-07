import os
from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from urllib.parse import urlsplit


class AppEnvironment(StrEnum):
    DEVELOPMENT = "development"
    TEST = "test"
    STAGING = "staging"
    PRODUCTION = "production"


class MarketDataMode(StrEnum):
    STATIC = "static"
    LIVE = "live"


class CoinGeckoAPITier(StrEnum):
    DEMO = "demo"
    PRO = "pro"


class IdempotencyMode(StrEnum):
    MEMORY = "memory"
    DATABASE = "database"


class OpenAIReasoningEffort(StrEnum):
    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    XHIGH = "xhigh"
    MAX = "max"


class ConfigurationError(RuntimeError):
    """The backend process has an invalid deployment configuration."""


@dataclass(frozen=True, slots=True)
class MarketDataSettings:
    mode: MarketDataMode = MarketDataMode.STATIC
    coingecko_api_tier: CoinGeckoAPITier = CoinGeckoAPITier.DEMO
    coingecko_api_key: str | None = field(default=None, repr=False)
    request_timeout_seconds: float = 10.0
    max_retries: int = 1
    max_quote_age_seconds: int = 600
    max_closed_candle_lag_seconds: int = 18_000

    @classmethod
    def from_environment(
        cls,
        environment: Mapping[str, str] | None = None,
    ) -> "MarketDataSettings":
        values = os.environ if environment is None else environment
        raw_mode = values.get("MARKET_DATA_MODE", MarketDataMode.STATIC.value).lower()
        try:
            mode = MarketDataMode(raw_mode)
        except ValueError as error:
            raise ConfigurationError("MARKET_DATA_MODE must be 'static' or 'live'.") from error

        raw_tier = values.get("COINGECKO_API_TIER", CoinGeckoAPITier.DEMO.value).lower()
        try:
            api_tier = CoinGeckoAPITier(raw_tier)
        except ValueError as error:
            raise ConfigurationError("COINGECKO_API_TIER must be 'demo' or 'pro'.") from error

        api_key = values.get("COINGECKO_API_KEY", "").strip() or None
        if mode is MarketDataMode.LIVE and api_key is None:
            raise ConfigurationError("COINGECKO_API_KEY is required in live market-data mode.")

        return cls(
            mode=mode,
            coingecko_api_tier=api_tier,
            coingecko_api_key=api_key,
            request_timeout_seconds=_positive_float(values, "MARKET_DATA_TIMEOUT_SECONDS", 10.0),
            max_retries=_nonnegative_int(values, "MARKET_DATA_MAX_RETRIES", 1),
            max_quote_age_seconds=_positive_int(values, "MARKET_QUOTE_MAX_AGE_SECONDS", 600),
            max_closed_candle_lag_seconds=_positive_int(
                values,
                "MARKET_CANDLE_MAX_LAG_SECONDS",
                18_000,
            ),
        )


@dataclass(frozen=True, slots=True)
class OpenAISettings:
    enabled: bool = False
    api_key: str | None = field(default=None, repr=False)
    model: str = "gpt-5.6-terra"
    reasoning_effort: OpenAIReasoningEffort = OpenAIReasoningEffort.LOW
    timeout_seconds: float = 30.0
    max_retries: int = 0

    @classmethod
    def from_environment(
        cls,
        environment: Mapping[str, str] | None = None,
    ) -> "OpenAISettings":
        values = os.environ if environment is None else environment
        enabled = _boolean(values, "OPENAI_ENABLED", False)
        api_key = values.get("OPENAI_API_KEY", "").strip() or None
        model = values.get("OPENAI_MODEL", "gpt-5.6-terra").strip()
        if not model:
            raise ConfigurationError("OPENAI_MODEL must not be empty.")

        raw_effort = values.get(
            "OPENAI_REASONING_EFFORT",
            OpenAIReasoningEffort.LOW.value,
        ).lower()
        try:
            reasoning_effort = OpenAIReasoningEffort(raw_effort)
        except ValueError as error:
            allowed = ", ".join(item.value for item in OpenAIReasoningEffort)
            raise ConfigurationError(
                f"OPENAI_REASONING_EFFORT must be one of: {allowed}."
            ) from error

        if enabled and api_key is None:
            raise ConfigurationError("OPENAI_API_KEY is required when OPENAI_ENABLED=true.")

        return cls(
            enabled=enabled,
            api_key=api_key,
            model=model,
            reasoning_effort=reasoning_effort,
            timeout_seconds=_positive_float(values, "OPENAI_TIMEOUT_SECONDS", 30.0),
            max_retries=_nonnegative_int(values, "OPENAI_MAX_RETRIES", 0),
        )


@dataclass(frozen=True, slots=True)
class DatabaseSettings:
    idempotency_mode: IdempotencyMode
    url: str | None = field(default=None, repr=False)
    retention_days: int = 14

    @classmethod
    def from_environment(
        cls,
        environment: AppEnvironment,
        values: Mapping[str, str],
    ) -> "DatabaseSettings":
        default_mode = (
            IdempotencyMode.DATABASE
            if environment in {AppEnvironment.STAGING, AppEnvironment.PRODUCTION}
            else IdempotencyMode.MEMORY
        )
        raw_mode = values.get("ANALYSIS_IDEMPOTENCY_MODE", default_mode.value).lower()
        try:
            mode = IdempotencyMode(raw_mode)
        except ValueError as error:
            raise ConfigurationError(
                "ANALYSIS_IDEMPOTENCY_MODE must be 'memory' or 'database'."
            ) from error

        database_url = values.get("DATABASE_URL", "").strip() or None
        if mode is IdempotencyMode.DATABASE and database_url is None:
            raise ConfigurationError(
                "DATABASE_URL is required when ANALYSIS_IDEMPOTENCY_MODE=database."
            )
        if database_url is not None:
            _validate_database_url(database_url, environment)

        return cls(
            idempotency_mode=mode,
            url=database_url,
            retention_days=_positive_int(
                values,
                "ANALYSIS_IDEMPOTENCY_RETENTION_DAYS",
                14,
            ),
        )


@dataclass(frozen=True, slots=True)
class AppSettings:
    environment: AppEnvironment
    market_data: MarketDataSettings
    openai: OpenAISettings
    database: DatabaseSettings
    analysis_timeout_seconds: float
    max_request_body_bytes: int
    docs_enabled: bool
    log_level: str

    @classmethod
    def from_environment(
        cls,
        environment: Mapping[str, str] | None = None,
    ) -> "AppSettings":
        values = os.environ if environment is None else environment
        raw_environment = values.get("APP_ENV", AppEnvironment.DEVELOPMENT.value).lower()
        try:
            app_environment = AppEnvironment(raw_environment)
        except ValueError as error:
            raise ConfigurationError(
                "APP_ENV must be 'development', 'test', 'staging', or 'production'."
            ) from error

        market_data = MarketDataSettings.from_environment(values)
        openai = OpenAISettings.from_environment(values)
        database = DatabaseSettings.from_environment(app_environment, values)
        analysis_timeout_seconds = _positive_float(
            values,
            "ANALYSIS_TIMEOUT_SECONDS",
            45.0,
        )
        longest_dependency_timeout = max(
            market_data.request_timeout_seconds,
            openai.timeout_seconds if openai.enabled else 0,
        )
        if analysis_timeout_seconds <= longest_dependency_timeout:
            raise ConfigurationError(
                "ANALYSIS_TIMEOUT_SECONDS must exceed each enabled dependency timeout."
            )

        is_deployment = app_environment in {
            AppEnvironment.STAGING,
            AppEnvironment.PRODUCTION,
        }
        if is_deployment:
            environment_name = app_environment.value.capitalize()
            if "OPENAI_ENABLED" not in values:
                raise ConfigurationError(
                    f"{environment_name} requires OPENAI_ENABLED to be set explicitly."
                )
            if market_data.mode is not MarketDataMode.LIVE:
                raise ConfigurationError(f"{environment_name} requires MARKET_DATA_MODE=live.")
            if "COINGECKO_API_TIER" not in values:
                raise ConfigurationError(
                    f"{environment_name} requires COINGECKO_API_TIER to be set explicitly."
                )
            if database.idempotency_mode is not IdempotencyMode.DATABASE:
                raise ConfigurationError(
                    f"{environment_name} requires ANALYSIS_IDEMPOTENCY_MODE=database."
                )

        default_docs_enabled = not is_deployment
        docs_enabled = _boolean(values, "API_DOCS_ENABLED", default_docs_enabled)
        log_level = values.get("LOG_LEVEL", "INFO").strip().upper()
        if log_level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            raise ConfigurationError("LOG_LEVEL is invalid.")

        max_request_body_bytes = _positive_int(values, "MAX_REQUEST_BODY_BYTES", 65_536)
        if max_request_body_bytes < 1_024:
            raise ConfigurationError("MAX_REQUEST_BODY_BYTES must be at least 1024.")

        return cls(
            environment=app_environment,
            market_data=market_data,
            openai=openai,
            database=database,
            analysis_timeout_seconds=analysis_timeout_seconds,
            max_request_body_bytes=max_request_body_bytes,
            docs_enabled=docs_enabled,
            log_level=log_level,
        )


def _validate_database_url(database_url: str, environment: AppEnvironment) -> None:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {
        "sqlite+aiosqlite",
        "postgresql+psycopg",
        "postgresql+psycopg_async",
    }:
        raise ConfigurationError(
            "DATABASE_URL must use sqlite+aiosqlite or PostgreSQL with psycopg."
        )
    if environment in {
        AppEnvironment.STAGING,
        AppEnvironment.PRODUCTION,
    } and not parsed.scheme.startswith("postgresql+"):
        raise ConfigurationError("Staging and production DATABASE_URL must use PostgreSQL.")


def _positive_float(values: Mapping[str, str], name: str, default: float) -> float:
    raw_value = values.get(name)
    if raw_value is None:
        return default
    try:
        value = float(raw_value)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be a positive number.") from error
    if value <= 0:
        raise ConfigurationError(f"{name} must be a positive number.")
    return value


def _positive_int(values: Mapping[str, str], name: str, default: int) -> int:
    raw_value = values.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be a positive integer.") from error
    if value <= 0:
        raise ConfigurationError(f"{name} must be a positive integer.")
    return value


def _nonnegative_int(values: Mapping[str, str], name: str, default: int) -> int:
    raw_value = values.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be zero or a positive integer.") from error
    if value < 0:
        raise ConfigurationError(f"{name} must be zero or a positive integer.")
    return value


def _boolean(values: Mapping[str, str], name: str, default: bool) -> bool:
    raw_value = values.get(name)
    if raw_value is None:
        return default
    normalized = raw_value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise ConfigurationError(f"{name} must be 'true' or 'false'.")
