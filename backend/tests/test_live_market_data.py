import json
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import httpx
import pytest

from app.domain.errors import (
    MalformedMarketDataError,
    ProviderRateLimitedError,
    ProviderUnavailableError,
    StaleMarketDataError,
    UnsupportedSymbolError,
)
from app.infrastructure.live_market_data import (
    COINGECKO_DEMO_API_KEY_HEADER,
    COINGECKO_DEMO_BASE_URL,
    COINGECKO_PRO_API_KEY_HEADER,
    COINGECKO_PRO_BASE_URL,
    COINGECKO_SYMBOL_IDS,
    CoinGeckoMarketDataProvider,
    CoinGeckoSymbolMapper,
)
from app.services.market_data import MarketDataPolicy
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.technical_features import TechnicalFeatureCalculator
from tests.factories import make_snapshot

NOW = datetime(2026, 9, 4, 12, tzinfo=UTC)


def timestamp_seconds(value: datetime) -> int:
    return int((value - datetime(1970, 1, 1, tzinfo=UTC)).total_seconds())


def timestamp_milliseconds(value: datetime) -> int:
    return timestamp_seconds(value) * 1000


def candle_payload(*, count: int = 60, include_incomplete: bool = False) -> list[list[int]]:
    first_close = NOW - timedelta(hours=4 * (count - 1))
    payload = [
        [
            timestamp_milliseconds(first_close + timedelta(hours=4 * index)),
            100 + index,
            102 + index,
            99 + index,
            101 + index,
        ]
        for index in range(count)
    ]
    if include_incomplete:
        payload.append([timestamp_milliseconds(NOW + timedelta(hours=4)), 999, 1002, 998, 1001])
    return payload


def market_handler(
    prices: dict[str, str] | None = None,
    *,
    quoted_at: datetime = NOW,
    candles: list[list[int]] | None = None,
) -> Callable[[httpx.Request], httpx.Response]:
    configured_prices = prices or {"bitcoin": "61000"}
    configured_candles = candle_payload() if candles is None else candles

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/simple/price"):
            entries = ",".join(
                f'"{identifier}":{{"usd":{price},"last_updated_at":{timestamp_seconds(quoted_at)}}}'
                for identifier, price in configured_prices.items()
            )
            return httpx.Response(200, content=("{" + entries + "}").encode())
        return httpx.Response(200, content=json.dumps(configured_candles).encode())

    return handler


def make_provider(
    handler: Callable[[httpx.Request], httpx.Response],
    *,
    now: datetime = NOW,
    api_key_header: str = COINGECKO_DEMO_API_KEY_HEADER,
    base_url: str = "https://market.test/api/v3",
) -> tuple[CoinGeckoMarketDataProvider, httpx.AsyncClient]:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = CoinGeckoMarketDataProvider(
        api_key="test-key",
        api_key_header=api_key_header,
        feature_calculator=TechnicalFeatureCalculator(),
        policy=MarketDataPolicy(
            max_quote_age=timedelta(minutes=10),
            max_closed_candle_lag=timedelta(hours=5),
        ),
        http_client=client,
        now=lambda: now,
        base_url=base_url,
    )
    return provider, client


@pytest.mark.parametrize(
    ("base_url", "key_header"),
    [
        (COINGECKO_DEMO_BASE_URL, COINGECKO_DEMO_API_KEY_HEADER),
        (COINGECKO_PRO_BASE_URL, COINGECKO_PRO_API_KEY_HEADER),
    ],
)
@pytest.mark.asyncio
async def test_provider_uses_plan_specific_host_and_header(
    base_url: str,
    key_header: str,
) -> None:
    requests: list[httpx.Request] = []
    success = market_handler()

    def capture(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return success(request)

    provider, client = make_provider(
        capture,
        api_key_header=key_header,
        base_url=base_url,
    )
    try:
        await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    assert requests
    assert {request.url.host for request in requests} == {httpx.URL(base_url).host}
    assert all(request.headers[key_header] == "test-key" for request in requests)
    other_header = (
        COINGECKO_PRO_API_KEY_HEADER
        if key_header == COINGECKO_DEMO_API_KEY_HEADER
        else COINGECKO_DEMO_API_KEY_HEADER
    )
    assert all(other_header not in request.headers for request in requests)


@pytest.mark.parametrize(
    ("symbol", "provider_id"),
    [
        ("BTC", "bitcoin"),
        ("ETH", "ethereum"),
        ("SOL", "solana"),
        ("LINK", "chainlink"),
        ("USDT", "tether"),
        ("USDC", "usd-coin"),
    ],
)
def test_supported_symbol_mapping(symbol: str, provider_id: str) -> None:
    assert CoinGeckoSymbolMapper().provider_id(symbol) == provider_id
    assert COINGECKO_SYMBOL_IDS[symbol] == provider_id


def test_unsupported_symbol_has_explicit_failure() -> None:
    with pytest.raises(UnsupportedSymbolError, match="JITO"):
        CoinGeckoSymbolMapper().provider_id("JITO")


@pytest.mark.asyncio
async def test_provider_timeout_maps_to_unavailable() -> None:
    def timeout(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("fixture timeout", request=request)

    provider, client = make_provider(timeout)
    try:
        with pytest.raises(ProviderUnavailableError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_provider_429_maps_to_rate_limit_error() -> None:
    calls = 0

    def rate_limited(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(429)

    provider, client = make_provider(rate_limited)
    try:
        with pytest.raises(ProviderRateLimitedError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    assert calls == 1


@pytest.mark.asyncio
async def test_one_transient_server_failure_is_retried_for_idempotent_get() -> None:
    calls = 0
    success = market_handler()

    def transient_then_success(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return httpx.Response(503)
        return success(request)

    provider, client = make_provider(transient_then_success)
    try:
        snapshot = await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    assert snapshot.assets[0].price_usd == Decimal("61000")
    assert calls == 3  # Failed price GET, successful retry, then one candle GET.


@pytest.mark.asyncio
async def test_malformed_provider_json_is_rejected() -> None:
    provider, client = make_provider(lambda _request: httpx.Response(200, content=b"not-json"))
    try:
        with pytest.raises(MalformedMarketDataError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_missing_requested_price_is_rejected() -> None:
    provider, client = make_provider(market_handler({"ethereum": "3000"}))
    try:
        with pytest.raises(MalformedMarketDataError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_non_positive_price_is_rejected() -> None:
    provider, client = make_provider(market_handler({"bitcoin": "0"}))
    try:
        with pytest.raises(MalformedMarketDataError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_stale_quote_is_rejected() -> None:
    provider, client = make_provider(market_handler(quoted_at=NOW - timedelta(minutes=11)))
    try:
        with pytest.raises(StaleMarketDataError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_stale_closed_candle_is_rejected() -> None:
    stale_candles = candle_payload(count=10)
    shift = timedelta(hours=6)
    for row in stale_candles:
        row[0] -= int(shift.total_seconds()) * 1000
    provider, client = make_provider(market_handler(candles=stale_candles))
    try:
        with pytest.raises(StaleMarketDataError):
            await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()


@pytest.mark.asyncio
async def test_closed_candles_populate_market_snapshot_features() -> None:
    provider, client = make_provider(market_handler())
    try:
        snapshot = await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    assert snapshot.is_live is True
    assert snapshot.as_of == NOW
    assert snapshot.assets[0].symbol == "BTC"
    assert snapshot.assets[0].price_usd == Decimal("61000")
    assert snapshot.assets[0].ema20_4h is not None
    assert snapshot.assets[0].ema50_4h is not None
    assert snapshot.assets[0].rsi_4h == Decimal("100")


@pytest.mark.asyncio
async def test_incomplete_future_candle_is_excluded() -> None:
    provider, client = make_provider(
        market_handler(candles=candle_payload(include_incomplete=True))
    )
    try:
        snapshot = await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    assert snapshot.assets[0].resistance == Decimal("161")


@pytest.mark.asyncio
async def test_insufficient_history_keeps_price_and_degrades_features() -> None:
    provider, client = make_provider(market_handler(candles=candle_payload(count=10)))
    try:
        snapshot = await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    asset = snapshot.assets[0]
    assert asset.price_usd == Decimal("61000")
    assert asset.change_24h_pct is not None
    assert asset.change_7d_pct is None
    assert asset.ema20_4h is None
    assert asset.ema50_4h is None


@pytest.mark.asyncio
async def test_live_stablecoins_use_provider_prices_not_static_parity() -> None:
    provider, client = make_provider(market_handler({"tether": "0.9987", "usd-coin": "1.0004"}))
    try:
        snapshot = await provider.get_market_snapshot(("USDT", "USDC"))
    finally:
        await client.aclose()

    assert [asset.price_usd for asset in snapshot.assets] == [
        Decimal("0.9987"),
        Decimal("1.0004"),
    ]


@pytest.mark.asyncio
async def test_portfolio_calculator_uses_normalized_live_price() -> None:
    provider, client = make_provider(market_handler())
    try:
        market = await provider.get_market_snapshot(("BTC",))
    finally:
        await client.aclose()

    metrics = PortfolioCalculator().calculate(
        make_snapshot(positions=(("BTC", Decimal("0.5")),)),
        market,
    )

    assert metrics.total_value_usd == Decimal("30500.0")
