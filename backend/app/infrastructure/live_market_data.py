import asyncio
import json
from collections.abc import Callable, Mapping
from datetime import UTC, datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any

import httpx

from app.domain.errors import (
    MalformedMarketDataError,
    ProviderRateLimitedError,
    ProviderUnavailableError,
    StaleMarketDataError,
    UnsupportedSymbolError,
)
from app.domain.models import MarketAssetSnapshot, MarketSnapshot
from app.observability import get_logger, log_event
from app.services.market_data import MarketDataPolicy
from app.services.technical_features import NormalizedCandle, TechnicalFeatureCalculator

COINGECKO_DEMO_BASE_URL = "https://api.coingecko.com/api/v3"
COINGECKO_PRO_BASE_URL = "https://pro-api.coingecko.com/api/v3"
COINGECKO_DEMO_API_KEY_HEADER = "x-cg-demo-api-key"
COINGECKO_PRO_API_KEY_HEADER = "x-cg-pro-api-key"
COINGECKO_SYMBOL_IDS: Mapping[str, str] = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "SOL": "solana",
    "LINK": "chainlink",
    "USDT": "tether",
    "USDC": "usd-coin",
}
COINGECKO_OHLC_DAYS = 30
COINGECKO_CANDLE_INTERVAL = timedelta(hours=4)
UNIX_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
logger = get_logger("market_data")


class CoinGeckoSymbolMapper:
    def __init__(self, mapping: Mapping[str, str] = COINGECKO_SYMBOL_IDS) -> None:
        self._mapping = dict(mapping)

    def provider_id(self, symbol: str) -> str:
        try:
            return self._mapping[symbol]
        except KeyError as error:
            raise UnsupportedSymbolError(symbol) from error


class CoinGeckoMarketDataProvider:
    """Async read-only CoinGecko adapter; it never falls back to static prices."""

    def __init__(
        self,
        *,
        api_key: str,
        api_key_header: str = COINGECKO_DEMO_API_KEY_HEADER,
        feature_calculator: TechnicalFeatureCalculator,
        policy: MarketDataPolicy | None = None,
        symbol_mapper: CoinGeckoSymbolMapper | None = None,
        request_timeout_seconds: float = 10.0,
        max_retries: int = 1,
        http_client: httpx.AsyncClient | None = None,
        now: Callable[[], datetime] | None = None,
        base_url: str = COINGECKO_DEMO_BASE_URL,
    ) -> None:
        self._api_key = api_key
        self._api_key_header = api_key_header
        self._feature_calculator = feature_calculator
        self._policy = policy or MarketDataPolicy()
        self._symbol_mapper = symbol_mapper or CoinGeckoSymbolMapper()
        self._request_timeout_seconds = request_timeout_seconds
        self._max_retries = max_retries
        self._http_client = http_client
        self._now = now or (lambda: datetime.now(UTC))
        self._base_url = base_url.rstrip("/")

    async def get_market_snapshot(self, symbols: tuple[str, ...]) -> MarketSnapshot:
        unique_symbols = tuple(dict.fromkeys(symbols))
        mapped_symbols = tuple(
            (symbol, self._symbol_mapper.provider_id(symbol)) for symbol in unique_symbols
        )
        now = self._normalized_now()
        if not mapped_symbols:
            return MarketSnapshot(as_of=now, assets=(), is_live=True)

        if self._http_client is not None:
            return await self._build_snapshot(self._http_client, mapped_symbols, now)

        headers = {self._api_key_header: self._api_key}
        timeout = httpx.Timeout(self._request_timeout_seconds)
        async with httpx.AsyncClient(headers=headers, timeout=timeout) as client:
            return await self._build_snapshot(client, mapped_symbols, now)

    async def _build_snapshot(
        self,
        client: httpx.AsyncClient,
        mapped_symbols: tuple[tuple[str, str], ...],
        now: datetime,
    ) -> MarketSnapshot:
        prices = await self._fetch_prices(client, mapped_symbols, now)
        assets: list[MarketAssetSnapshot] = []
        for symbol, provider_id in mapped_symbols:
            candles = await self._fetch_closed_candles(client, provider_id, now)
            features = self._feature_calculator.calculate(candles)
            price, _quoted_at = prices[symbol]
            assets.append(
                MarketAssetSnapshot(
                    symbol=symbol,
                    price_usd=price,
                    change_24h_pct=features.change_24h_pct,
                    change_7d_pct=features.change_7d_pct,
                    rsi_4h=features.rsi_4h,
                    ema20_4h=features.ema20_4h,
                    ema50_4h=features.ema50_4h,
                    atr_4h=features.atr_4h,
                    support=features.support,
                    resistance=features.resistance,
                )
            )

        return MarketSnapshot(
            as_of=min(quoted_at for _price, quoted_at in prices.values()),
            assets=tuple(assets),
            is_live=True,
        )

    async def _fetch_prices(
        self,
        client: httpx.AsyncClient,
        mapped_symbols: tuple[tuple[str, str], ...],
        now: datetime,
    ) -> dict[str, tuple[Decimal, datetime]]:
        response = await self._get(
            client,
            "/simple/price",
            params={
                "ids": ",".join(provider_id for _symbol, provider_id in mapped_symbols),
                "vs_currencies": "usd",
                "include_last_updated_at": "true",
                "precision": "full",
            },
        )
        payload = self._decode_json(response)
        if not isinstance(payload, dict):
            raise MalformedMarketDataError()

        prices: dict[str, tuple[Decimal, datetime]] = {}
        for symbol, provider_id in mapped_symbols:
            entry = payload.get(provider_id)
            if not isinstance(entry, dict):
                raise MalformedMarketDataError()
            price = self._positive_decimal(entry.get("usd"))
            quoted_at = self._unix_seconds(entry.get("last_updated_at"))
            if quoted_at > now + timedelta(minutes=1):
                raise MalformedMarketDataError()
            if now - quoted_at > self._policy.max_quote_age:
                raise StaleMarketDataError()
            prices[symbol] = (price, quoted_at)
        return prices

    async def _fetch_closed_candles(
        self,
        client: httpx.AsyncClient,
        provider_id: str,
        now: datetime,
    ) -> tuple[NormalizedCandle, ...]:
        response = await self._get(
            client,
            f"/coins/{provider_id}/ohlc",
            params={
                "vs_currency": "usd",
                "days": str(COINGECKO_OHLC_DAYS),
                "precision": "full",
            },
        )
        payload = self._decode_json(response)
        if not isinstance(payload, list):
            raise MalformedMarketDataError()

        candles = tuple(self._parse_candle(row) for row in payload)
        closed = tuple(candle for candle in candles if candle.closed_at <= now)
        ordered = tuple(sorted(closed, key=lambda candle: candle.closed_at))
        if len({candle.closed_at for candle in ordered}) != len(ordered):
            raise MalformedMarketDataError()
        if any(
            current.closed_at - previous.closed_at != COINGECKO_CANDLE_INTERVAL
            for previous, current in zip(ordered, ordered[1:], strict=False)
        ):
            raise MalformedMarketDataError()
        if ordered and now - ordered[-1].closed_at > self._policy.max_closed_candle_lag:
            raise StaleMarketDataError()
        return ordered

    async def _get(
        self,
        client: httpx.AsyncClient,
        path: str,
        *,
        params: Mapping[str, str],
    ) -> httpx.Response:
        for attempt in range(self._max_retries + 1):
            try:
                response = await client.get(
                    f"{self._base_url}{path}",
                    params=params,
                    headers={self._api_key_header: self._api_key},
                    timeout=self._request_timeout_seconds,
                )
            except (httpx.TimeoutException, httpx.RequestError) as error:
                if attempt < self._max_retries:
                    log_event(
                        logger,
                        "market_provider_retry",
                        market_provider_outcome="transient_transport_failure",
                    )
                    await asyncio.sleep(0.1)
                    continue
                raise ProviderUnavailableError() from error

            if response.status_code == 429:
                raise ProviderRateLimitedError()
            if 500 <= response.status_code < 600 and attempt < self._max_retries:
                log_event(
                    logger,
                    "market_provider_retry",
                    market_provider_outcome="transient_server_failure",
                )
                await asyncio.sleep(0.1)
                continue
            if not 200 <= response.status_code < 300:
                raise ProviderUnavailableError()
            return response

        raise ProviderUnavailableError()

    @staticmethod
    def _decode_json(response: httpx.Response) -> Any:
        try:
            return json.loads(
                response.content,
                parse_float=Decimal,
                parse_int=Decimal,
            )
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise MalformedMarketDataError() from error

    @staticmethod
    def _positive_decimal(value: object) -> Decimal:
        if not isinstance(value, Decimal):
            raise MalformedMarketDataError()
        try:
            if not value.is_finite() or value <= 0:
                raise MalformedMarketDataError()
        except InvalidOperation as error:
            raise MalformedMarketDataError() from error
        return value

    @classmethod
    def _parse_candle(cls, value: object) -> NormalizedCandle:
        if not isinstance(value, list) or len(value) != 5:
            raise MalformedMarketDataError()
        closed_at = cls._unix_milliseconds(value[0])
        open_price, high, low, close = (cls._positive_decimal(item) for item in value[1:])
        if high < max(open_price, low, close) or low > min(open_price, high, close):
            raise MalformedMarketDataError()
        return NormalizedCandle(
            closed_at=closed_at,
            open=open_price,
            high=high,
            low=low,
            close=close,
        )

    @staticmethod
    def _unix_seconds(value: object) -> datetime:
        if not isinstance(value, Decimal) or value != value.to_integral_value() or value <= 0:
            raise MalformedMarketDataError()
        return UNIX_EPOCH + timedelta(seconds=int(value))

    @staticmethod
    def _unix_milliseconds(value: object) -> datetime:
        if not isinstance(value, Decimal) or value != value.to_integral_value() or value <= 0:
            raise MalformedMarketDataError()
        return UNIX_EPOCH + timedelta(milliseconds=int(value))

    def _normalized_now(self) -> datetime:
        now = self._now()
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Market-data clock must return a timezone-aware datetime.")
        return now.astimezone(UTC)
