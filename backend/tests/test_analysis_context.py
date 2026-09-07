from dataclasses import asdict
from decimal import Decimal

from app.domain.models import MarketAssetSnapshot, MarketSnapshot
from app.services.analysis import DeterministicPortfolioAnalysisService
from app.services.analysis_context import AnalysisContextBuilder
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.risk_engine import RiskEngine
from tests.factories import FIXED_DATE, make_market, make_snapshot


def test_analysis_context_contains_compact_market_features_and_allocation() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("1")),))
    market = MarketSnapshot(
        as_of=FIXED_DATE,
        assets=(
            MarketAssetSnapshot(
                symbol="BTC",
                price_usd=Decimal("60000"),
                change_24h_pct=Decimal("1.25"),
                change_7d_pct=Decimal("4.5"),
                rsi_4h=Decimal("55"),
                ema20_4h=Decimal("59000"),
                ema50_4h=Decimal("57000"),
                atr_4h=Decimal("1200"),
                support=Decimal("55000"),
                resistance=Decimal("63000"),
            ),
        ),
        is_live=True,
    )
    metrics = PortfolioCalculator().calculate(snapshot, market)
    risk = RiskEngine().assess(metrics, snapshot.constraints)

    context = AnalysisContextBuilder().build(snapshot, market, metrics, risk)

    assert context.market_features[0].price_usd == Decimal("60000")
    assert context.market_features[0].portfolio_allocation_percentage == Decimal("100")
    assert context.market_features[0].rsi_4h == Decimal("55")


def test_analysis_context_never_contains_raw_candles() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("1")),))
    market = make_market((("BTC", Decimal("60000")),))
    metrics = PortfolioCalculator().calculate(snapshot, market)
    risk = RiskEngine().assess(metrics, snapshot.constraints)

    context = AnalysisContextBuilder().build(snapshot, market, metrics, risk)
    serialized_shape = repr(asdict(context)).lower()

    assert "candle" not in serialized_shape


def test_risk_engine_result_is_independent_of_market_source_label() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("1")),))
    static_market = make_market((("BTC", Decimal("60000")),))
    live_market = MarketSnapshot(
        as_of=static_market.as_of,
        assets=static_market.assets,
        is_live=True,
    )
    static_metrics = PortfolioCalculator().calculate(snapshot, static_market)
    live_metrics = PortfolioCalculator().calculate(snapshot, live_market)

    assert RiskEngine().assess(static_metrics, snapshot.constraints) == RiskEngine().assess(
        live_metrics,
        snapshot.constraints,
    )


async def test_deterministic_analysis_labels_live_context_without_claiming_ai() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("1")),))
    market = MarketSnapshot(
        as_of=FIXED_DATE,
        assets=(
            MarketAssetSnapshot(
                symbol="BTC",
                price_usd=Decimal("60000"),
                rsi_4h=Decimal("55"),
            ),
        ),
        is_live=True,
    )

    class LiveFixtureProvider:
        async def get_market_snapshot(self, _symbols: tuple[str, ...]) -> MarketSnapshot:
            return market

    service = DeterministicPortfolioAnalysisService(
        market_data_provider=LiveFixtureProvider(),
        portfolio_calculator=PortfolioCalculator(),
        risk_engine=RiskEngine(),
        analysis_context_builder=AnalysisContextBuilder(),
    )

    analysis = await service.analyze(snapshot)

    assert "Live public market data" in analysis.market_summary.overview
    assert "AI reasoning is not enabled" in analysis.market_summary.overview
    assert analysis.warnings[0].code == "LIVE_PUBLIC_MARKET_DATA"
    assert analysis.asset_analysis[0].assessment.startswith("Live public-market valuation")
