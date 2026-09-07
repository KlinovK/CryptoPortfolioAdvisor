import pytest

from app.config import (
    AppEnvironment,
    AppSettings,
    CoinGeckoAPITier,
    ConfigurationError,
    IdempotencyMode,
    MarketDataMode,
    MarketDataSettings,
    OpenAIReasoningEffort,
    OpenAISettings,
)
from app.dependencies import build_market_data_provider, build_recommendation_reasoner
from app.infrastructure.live_market_data import CoinGeckoMarketDataProvider
from app.infrastructure.static_market_data import StaticMarketDataProvider


def test_market_data_mode_defaults_to_static() -> None:
    settings = MarketDataSettings.from_environment({})

    assert settings.mode is MarketDataMode.STATIC
    assert isinstance(build_market_data_provider(settings), StaticMarketDataProvider)


def test_live_mode_requires_backend_api_key() -> None:
    with pytest.raises(ConfigurationError, match="COINGECKO_API_KEY"):
        MarketDataSettings.from_environment({"MARKET_DATA_MODE": "live"})


def test_live_mode_and_freshness_configuration_are_explicit() -> None:
    settings = MarketDataSettings.from_environment(
        {
            "MARKET_DATA_MODE": "live",
            "COINGECKO_API_TIER": "pro",
            "COINGECKO_API_KEY": "secret-test-key",
            "MARKET_DATA_TIMEOUT_SECONDS": "7.5",
            "MARKET_QUOTE_MAX_AGE_SECONDS": "300",
            "MARKET_CANDLE_MAX_LAG_SECONDS": "14400",
        }
    )

    assert settings.mode is MarketDataMode.LIVE
    assert settings.coingecko_api_tier is CoinGeckoAPITier.PRO
    assert settings.request_timeout_seconds == 7.5
    assert settings.max_quote_age_seconds == 300
    assert settings.max_closed_candle_lag_seconds == 14_400
    assert isinstance(build_market_data_provider(settings), CoinGeckoMarketDataProvider)


def test_invalid_market_data_mode_fails_process_configuration() -> None:
    with pytest.raises(ConfigurationError, match="static.*live"):
        MarketDataSettings.from_environment({"MARKET_DATA_MODE": "automatic"})


def test_invalid_coingecko_api_tier_fails_process_configuration() -> None:
    with pytest.raises(ConfigurationError, match="COINGECKO_API_TIER"):
        MarketDataSettings.from_environment({"COINGECKO_API_TIER": "enterprise"})


def test_openai_defaults_to_disabled_without_a_key() -> None:
    settings = OpenAISettings.from_environment({})

    assert settings.enabled is False
    assert settings.model == "gpt-5.6-terra"
    assert settings.reasoning_effort is OpenAIReasoningEffort.LOW
    assert build_recommendation_reasoner(settings) is None


def test_enabled_openai_requires_backend_key() -> None:
    with pytest.raises(ConfigurationError, match="OPENAI_API_KEY"):
        OpenAISettings.from_environment({"OPENAI_ENABLED": "true"})


def test_openai_settings_are_explicit_and_configurable() -> None:
    settings = OpenAISettings.from_environment(
        {
            "OPENAI_ENABLED": "true",
            "OPENAI_API_KEY": "server-only-test-key",
            "OPENAI_MODEL": "gpt-5.6-terra",
            "OPENAI_REASONING_EFFORT": "medium",
            "OPENAI_TIMEOUT_SECONDS": "12.5",
        }
    )

    assert settings.enabled is True
    assert settings.api_key == "server-only-test-key"
    assert settings.reasoning_effort is OpenAIReasoningEffort.MEDIUM
    assert settings.timeout_seconds == 12.5


@pytest.mark.parametrize(
    "environment",
    [
        {"OPENAI_ENABLED": "yes"},
        {"OPENAI_REASONING_EFFORT": "extreme"},
        {"OPENAI_MODEL": ""},
        {"OPENAI_TIMEOUT_SECONDS": "0"},
    ],
)
def test_invalid_openai_configuration_fails_clearly(
    environment: dict[str, str],
) -> None:
    with pytest.raises(ConfigurationError):
        OpenAISettings.from_environment(environment)


def test_development_configuration_remains_offline_and_process_local() -> None:
    settings = AppSettings.from_environment({})

    assert settings.environment is AppEnvironment.DEVELOPMENT
    assert settings.market_data.mode is MarketDataMode.STATIC
    assert settings.openai.enabled is False
    assert settings.database.idempotency_mode is IdempotencyMode.MEMORY


def test_production_rejects_static_market_data() -> None:
    with pytest.raises(ConfigurationError, match="Production requires MARKET_DATA_MODE=live"):
        AppSettings.from_environment(
            {
                "APP_ENV": "production",
                "OPENAI_ENABLED": "false",
                "COINGECKO_API_TIER": "pro",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            }
        )


@pytest.mark.parametrize(
    ("environment", "message"),
    [
        (
            {
                "APP_ENV": "production",
                "OPENAI_ENABLED": "false",
                "MARKET_DATA_MODE": "live",
                "COINGECKO_API_TIER": "pro",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            },
            "COINGECKO_API_KEY",
        ),
        (
            {
                "APP_ENV": "production",
                "MARKET_DATA_MODE": "live",
                "COINGECKO_API_TIER": "pro",
                "COINGECKO_API_KEY": "placeholder",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            },
            "OPENAI_ENABLED",
        ),
        (
            {
                "APP_ENV": "production",
                "OPENAI_ENABLED": "true",
                "MARKET_DATA_MODE": "live",
                "COINGECKO_API_TIER": "pro",
                "COINGECKO_API_KEY": "placeholder",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            },
            "OPENAI_API_KEY",
        ),
    ],
)
def test_missing_required_production_configuration_fails_clearly(
    environment: dict[str, str],
    message: str,
) -> None:
    with pytest.raises(ConfigurationError, match=message):
        AppSettings.from_environment(environment)


def test_production_requires_postgresql_durable_idempotency() -> None:
    base = {
        "APP_ENV": "production",
        "OPENAI_ENABLED": "false",
        "MARKET_DATA_MODE": "live",
        "COINGECKO_API_TIER": "pro",
        "COINGECKO_API_KEY": "placeholder",
    }
    with pytest.raises(ConfigurationError, match="PostgreSQL"):
        AppSettings.from_environment(
            {**base, "DATABASE_URL": "sqlite+aiosqlite:///production.sqlite3"}
        )
    with pytest.raises(ConfigurationError, match="IDEMPOTENCY"):
        AppSettings.from_environment(
            {
                **base,
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
                "ANALYSIS_IDEMPOTENCY_MODE": "memory",
            }
        )


def test_secret_values_are_redacted_from_configuration_repr() -> None:
    settings = AppSettings.from_environment(
        {
            "MARKET_DATA_MODE": "live",
            "COINGECKO_API_KEY": "coingecko-secret-value",
            "OPENAI_ENABLED": "true",
            "OPENAI_API_KEY": "openai-secret-value",
        }
    )

    representation = repr(settings)
    assert "coingecko-secret-value" not in representation
    assert "openai-secret-value" not in representation


def test_staging_requires_live_market_data_and_explicit_provider_tier() -> None:
    with pytest.raises(ConfigurationError, match="Staging requires MARKET_DATA_MODE=live"):
        AppSettings.from_environment(
            {
                "APP_ENV": "staging",
                "OPENAI_ENABLED": "false",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            }
        )

    with pytest.raises(ConfigurationError, match="COINGECKO_API_TIER"):
        AppSettings.from_environment(
            {
                "APP_ENV": "staging",
                "MARKET_DATA_MODE": "live",
                "COINGECKO_API_KEY": "placeholder",
                "OPENAI_ENABLED": "false",
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
            }
        )


def test_staging_requires_postgresql_durable_idempotency() -> None:
    base = {
        "APP_ENV": "staging",
        "OPENAI_ENABLED": "false",
        "MARKET_DATA_MODE": "live",
        "COINGECKO_API_TIER": "demo",
        "COINGECKO_API_KEY": "placeholder",
    }
    with pytest.raises(ConfigurationError, match="PostgreSQL"):
        AppSettings.from_environment(
            {**base, "DATABASE_URL": "sqlite+aiosqlite:///staging.sqlite3"}
        )
    with pytest.raises(ConfigurationError, match="IDEMPOTENCY"):
        AppSettings.from_environment(
            {
                **base,
                "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
                "ANALYSIS_IDEMPOTENCY_MODE": "memory",
            }
        )


@pytest.mark.parametrize("environment_name", ["staging", "production"])
def test_deployment_configuration_is_explicit_and_portable(environment_name: str) -> None:
    settings = AppSettings.from_environment(
        {
            "APP_ENV": environment_name,
            "MARKET_DATA_MODE": "live",
            "COINGECKO_API_TIER": "pro",
            "COINGECKO_API_KEY": "backend-only-placeholder",
            "OPENAI_ENABLED": "false",
            "ANALYSIS_IDEMPOTENCY_MODE": "database",
            "DATABASE_URL": "postgresql+psycopg://service:secret@db/app",
        }
    )

    assert settings.environment is AppEnvironment(environment_name)
    assert settings.market_data.mode is MarketDataMode.LIVE
    assert settings.market_data.coingecko_api_tier is CoinGeckoAPITier.PRO
    assert settings.database.idempotency_mode is IdempotencyMode.DATABASE
    assert settings.docs_enabled is False
