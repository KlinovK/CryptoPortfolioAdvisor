import json
from decimal import Decimal

from app.domain.models import MarketAssetSnapshot, MarketSnapshot, OrderSide, OrderStatus
from app.services.analysis_context import AnalysisContextBuilder
from app.services.openai_context import AnalysisContextSerializer
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.risk_engine import RiskEngine
from tests.factories import FIXED_DATE, make_order, make_snapshot


def make_context():
    snapshot = make_snapshot(
        positions=(("BTC", Decimal("0.125")), ("USDT", Decimal("1000.0001"))),
        reserve=Decimal("500.0001"),
        orders=(
            make_order(
                side=OrderSide.BUY,
                status=OrderStatus.OPEN,
                amount=Decimal("125.25"),
            ),
        ),
    )
    market = MarketSnapshot(
        as_of=FIXED_DATE,
        assets=(
            MarketAssetSnapshot(
                symbol="BTC",
                price_usd=Decimal("60000.125"),
                change_24h_pct=Decimal("1.25"),
                change_7d_pct=Decimal("-2.5"),
                rsi_4h=Decimal("54.125"),
                ema20_4h=Decimal("59000"),
                ema50_4h=Decimal("57000"),
                atr_4h=Decimal("1200.5"),
                support=Decimal("55000"),
                resistance=Decimal("63000"),
            ),
            MarketAssetSnapshot(symbol="USDT", price_usd=Decimal("1")),
        ),
        is_live=True,
    )
    metrics = PortfolioCalculator().calculate(snapshot, market)
    risk = RiskEngine().assess(metrics, snapshot.constraints)
    return AnalysisContextBuilder().build(snapshot, market, metrics, risk)


def test_context_maps_to_explicit_compact_openai_shape() -> None:
    payload = AnalysisContextSerializer().to_dict(make_context())

    assert set(payload) == {
        "portfolio",
        "constraints",
        "orders",
        "risk",
        "market_features",
    }
    assert set(payload["portfolio"]) == {
        "total_value_usd",
        "stable_value_usd",
        "invested_value_usd",
        "stable_allocation_pct",
        "open_buy_orders_usd",
        "open_sell_orders_usd",
        "deployable_stable_usd",
        "allocations",
    }
    assert set(payload["orders"][0]) == {
        "asset",
        "side",
        "amount_usd",
        "price",
        "status",
    }


def test_context_omits_candles_provider_data_history_and_identifiers() -> None:
    payload = AnalysisContextSerializer().to_dict(make_context())
    serialized = json.dumps(payload).lower()

    assert "candle" not in serialized
    assert "provider" not in serialized
    assert "conversation" not in serialized
    assert "history" not in serialized
    assert "snapshot_id" not in serialized
    assert "analysis_id" not in serialized
    assert "created_at" not in serialized
    assert "resolved_at" not in serialized


def test_financial_values_are_predictable_decimal_strings() -> None:
    payload = AnalysisContextSerializer().to_dict(make_context())

    assert payload["portfolio"]["stable_value_usd"] == "1000.0001"
    assert payload["constraints"]["minimum_stable_reserve_usd"] == "500.0001"
    assert payload["orders"][0]["amount_usd"] == "125.25"
    assert payload["market_features"][0]["price_usd"] == "60000.125"
    assert payload["market_features"][0]["change_7d_pct"] == "-2.5"


def test_optional_technical_features_are_explicit_nulls() -> None:
    payload = AnalysisContextSerializer().to_dict(make_context())
    stable = payload["market_features"][1]

    assert stable["rsi_4h"] is None
    assert stable["ema20_4h"] is None
    assert stable["support"] is None


def test_serialized_context_size_regression_guard() -> None:
    serialized = AnalysisContextSerializer().serialize(make_context())

    assert len(serialized.encode("utf-8")) < 12_000
    assert "\n" not in serialized
