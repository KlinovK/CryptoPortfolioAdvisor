from dataclasses import dataclass
from datetime import timedelta
from typing import Protocol

from app.domain.models import MarketSnapshot


class MarketDataProvider(Protocol):
    async def get_market_snapshot(self, symbols: tuple[str, ...]) -> MarketSnapshot: ...


@dataclass(frozen=True, slots=True)
class MarketDataPolicy:
    max_quote_age: timedelta = timedelta(minutes=10)
    max_closed_candle_lag: timedelta = timedelta(hours=5)
