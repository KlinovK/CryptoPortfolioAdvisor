from decimal import Decimal

import pytest

from app.infrastructure.static_market_data import (
    DEVELOPMENT_MARKET_AS_OF,
    StaticMarketDataProvider,
)


@pytest.mark.asyncio
async def test_static_provider_is_deterministic() -> None:
    provider = StaticMarketDataProvider.development()

    first = await provider.get_market_snapshot(("BTC", "LINK", "BTC"))
    second = await provider.get_market_snapshot(("BTC", "LINK", "BTC"))

    assert first == second
    assert first.as_of == DEVELOPMENT_MARKET_AS_OF
    assert [asset.symbol for asset in first.assets] == ["BTC", "LINK"]


@pytest.mark.asyncio
async def test_development_stablecoin_prices_are_explicitly_one() -> None:
    provider = StaticMarketDataProvider.development()

    snapshot = await provider.get_market_snapshot(("USDT", "USDC"))

    assert [asset.price_usd for asset in snapshot.assets] == [Decimal("1"), Decimal("1")]
    assert all(asset.change_24h_pct is None for asset in snapshot.assets)
