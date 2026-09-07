from collections.abc import Mapping
from datetime import UTC, datetime
from decimal import Decimal

from app.domain.models import MarketAssetSnapshot, MarketSnapshot

DEVELOPMENT_MARKET_AS_OF = datetime(2026, 1, 1, tzinfo=UTC)
DEVELOPMENT_STATIC_PRICES: Mapping[str, Decimal] = {
    "BTC": Decimal("60000"),
    "ETH": Decimal("3000"),
    "SOL": Decimal("150"),
    "LINK": Decimal("15"),
    "USDT": Decimal("1"),
    "USDC": Decimal("1"),
}


class StaticMarketDataProvider:
    """A deterministic provider for development and focused tests; values are not live."""

    def __init__(
        self,
        prices: Mapping[str, Decimal],
        *,
        as_of: datetime,
    ) -> None:
        self._prices = dict(prices)
        self._as_of = as_of

    @classmethod
    def development(cls) -> "StaticMarketDataProvider":
        return cls(DEVELOPMENT_STATIC_PRICES, as_of=DEVELOPMENT_MARKET_AS_OF)

    async def get_market_snapshot(self, symbols: tuple[str, ...]) -> MarketSnapshot:
        unique_symbols = tuple(dict.fromkeys(symbols))
        return MarketSnapshot(
            as_of=self._as_of,
            assets=tuple(
                MarketAssetSnapshot(symbol=symbol, price_usd=self._prices[symbol])
                for symbol in unique_symbols
                if symbol in self._prices
            ),
            is_live=False,
        )
