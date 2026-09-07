class PortfolioValidationError(ValueError):
    """A stable business-validation failure safe to return to API clients."""


class PortfolioCalculationError(PortfolioValidationError):
    """The submitted snapshot cannot be calculated with the available market context."""


class ActionValidationError(PortfolioValidationError):
    """A proposed recommendation violates a deterministic risk rule."""


class ServiceError(Exception):
    """A sanitized operational failure suitable for the API error envelope."""

    code = "service_unavailable"
    status_code = 503


class PersistenceUnavailableError(ServiceError):
    code = "persistence_unavailable"

    def __init__(self) -> None:
        super().__init__("The analysis service is temporarily unavailable.")


class IdempotencyConflictError(ServiceError):
    code = "idempotency_conflict"
    status_code = 409

    def __init__(self) -> None:
        super().__init__("The snapshot ID was already used with different portfolio data.")


class AnalysisTimeoutError(ServiceError):
    code = "analysis_timeout"

    def __init__(self) -> None:
        super().__init__("The analysis request exceeded its time budget. Try again later.")


class MarketDataError(Exception):
    """A safe, categorized market-data failure suitable for the API envelope."""

    code = "market_data_error"
    status_code = 503


class UnsupportedSymbolError(MarketDataError):
    code = "unsupported_symbol"
    status_code = 400

    def __init__(self, symbol: str) -> None:
        super().__init__(f"Live market data is unavailable for {symbol}.")


class ProviderUnavailableError(MarketDataError):
    code = "provider_unavailable"

    def __init__(self) -> None:
        super().__init__("The public market-data provider is currently unavailable.")


class ProviderRateLimitedError(MarketDataError):
    code = "provider_rate_limited"

    def __init__(self) -> None:
        super().__init__("The public market-data provider rate limit was reached.")


class StaleMarketDataError(MarketDataError):
    code = "stale_market_data"

    def __init__(self) -> None:
        super().__init__("The public market data is too stale for portfolio analysis.")


class MalformedMarketDataError(MarketDataError):
    code = "malformed_market_data"
    status_code = 502

    def __init__(self) -> None:
        super().__init__("The public market-data provider returned invalid data.")
