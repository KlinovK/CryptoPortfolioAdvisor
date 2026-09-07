from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, localcontext


@dataclass(frozen=True, slots=True)
class NormalizedCandle:
    closed_at: datetime
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal


@dataclass(frozen=True, slots=True)
class TechnicalFeatureConfig:
    rsi_period: int = 14
    ema_short_period: int = 20
    ema_long_period: int = 50
    atr_period: int = 14
    support_resistance_period: int = 20
    change_24h_periods: int = 6
    change_7d_periods: int = 42


@dataclass(frozen=True, slots=True)
class TechnicalFeatures:
    change_24h_pct: Decimal | None
    change_7d_pct: Decimal | None
    rsi_4h: Decimal | None
    ema20_4h: Decimal | None
    ema50_4h: Decimal | None
    atr_4h: Decimal | None
    support: Decimal | None
    resistance: Decimal | None


class TechnicalFeatureCalculator:
    """Calculates compact deterministic features from ordered, closed 4H candles."""

    def __init__(self, config: TechnicalFeatureConfig | None = None) -> None:
        self.config = config or TechnicalFeatureConfig()

    def calculate(self, candles: tuple[NormalizedCandle, ...]) -> TechnicalFeatures:
        closes = tuple(candle.close for candle in candles)
        with localcontext() as context:
            context.prec = 38
            return TechnicalFeatures(
                change_24h_pct=self._percentage_change(
                    closes,
                    self.config.change_24h_periods,
                ),
                change_7d_pct=self._percentage_change(
                    closes,
                    self.config.change_7d_periods,
                ),
                rsi_4h=self._rsi(closes, self.config.rsi_period),
                ema20_4h=self._ema(closes, self.config.ema_short_period),
                ema50_4h=self._ema(closes, self.config.ema_long_period),
                atr_4h=self._atr(candles, self.config.atr_period),
                support=(
                    min(candle.low for candle in candles[-self.config.support_resistance_period :])
                    if len(candles) >= self.config.support_resistance_period
                    else None
                ),
                resistance=(
                    max(candle.high for candle in candles[-self.config.support_resistance_period :])
                    if len(candles) >= self.config.support_resistance_period
                    else None
                ),
            )

    @staticmethod
    def _percentage_change(
        closes: tuple[Decimal, ...],
        periods: int,
    ) -> Decimal | None:
        if len(closes) <= periods:
            return None
        previous = closes[-(periods + 1)]
        if previous <= 0:
            return None
        return (closes[-1] - previous) * Decimal("100") / previous

    @staticmethod
    def _ema(closes: tuple[Decimal, ...], period: int) -> Decimal | None:
        if len(closes) < period:
            return None
        multiplier = Decimal("2") / Decimal(period + 1)
        value = sum(closes[:period], Decimal("0")) / Decimal(period)
        for close in closes[period:]:
            value = (close - value) * multiplier + value
        return value

    @staticmethod
    def _rsi(closes: tuple[Decimal, ...], period: int) -> Decimal | None:
        if len(closes) <= period:
            return None
        changes = tuple(
            current - previous for previous, current in zip(closes, closes[1:], strict=False)
        )
        gains = tuple(max(change, Decimal("0")) for change in changes)
        losses = tuple(max(-change, Decimal("0")) for change in changes)
        average_gain = sum(gains[:period], Decimal("0")) / Decimal(period)
        average_loss = sum(losses[:period], Decimal("0")) / Decimal(period)
        for gain, loss in zip(gains[period:], losses[period:], strict=True):
            average_gain = (average_gain * Decimal(period - 1) + gain) / Decimal(period)
            average_loss = (average_loss * Decimal(period - 1) + loss) / Decimal(period)
        if average_loss == 0:
            return Decimal("50") if average_gain == 0 else Decimal("100")
        relative_strength = average_gain / average_loss
        return Decimal("100") - Decimal("100") / (Decimal("1") + relative_strength)

    @staticmethod
    def _atr(
        candles: tuple[NormalizedCandle, ...],
        period: int,
    ) -> Decimal | None:
        if len(candles) <= period:
            return None
        true_ranges = tuple(
            max(
                candle.high - candle.low,
                abs(candle.high - previous.close),
                abs(candle.low - previous.close),
            )
            for previous, candle in zip(candles, candles[1:], strict=False)
        )
        value = sum(true_ranges[:period], Decimal("0")) / Decimal(period)
        for true_range in true_ranges[period:]:
            value = (value * Decimal(period - 1) + true_range) / Decimal(period)
        return value
