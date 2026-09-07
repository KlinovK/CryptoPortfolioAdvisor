from decimal import Decimal

import pytest

from app.domain.errors import PortfolioCalculationError
from app.domain.models import OrderSide, OrderStatus
from app.services.portfolio_calculator import PortfolioCalculator
from tests.factories import make_market, make_order, make_snapshot


def test_portfolio_total_valuation() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("2")), ("LINK", Decimal("3"))))
    market = make_market((("BTC", Decimal("100")), ("LINK", Decimal("10"))))

    metrics = PortfolioCalculator().calculate(snapshot, market)

    assert metrics.total_value_usd == Decimal("230")
    assert metrics.invested_value_usd == Decimal("230")


def test_stablecoin_valuation_uses_configured_classification() -> None:
    snapshot = make_snapshot(
        positions=(
            ("USDT", Decimal("100")),
            ("USDC", Decimal("50")),
            ("BTC", Decimal("1")),
        )
    )
    market = make_market((("USDT", Decimal("1")), ("USDC", Decimal("1")), ("BTC", Decimal("100"))))

    metrics = PortfolioCalculator().calculate(snapshot, market)

    assert metrics.total_value_usd == Decimal("250")
    assert metrics.stable_value_usd == Decimal("150")
    assert metrics.invested_value_usd == Decimal("100")


def test_asset_allocation_percentages() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("2")), ("ETH", Decimal("3"))))
    market = make_market((("BTC", Decimal("100")), ("ETH", Decimal("100"))))

    metrics = PortfolioCalculator().calculate(snapshot, market)

    assert [item.allocation_percentage for item in metrics.allocations] == [
        Decimal("40"),
        Decimal("60"),
    ]


def test_open_buy_orders_reduce_deployable_stable_capital() -> None:
    order = make_order(side=OrderSide.BUY, status=OrderStatus.OPEN, amount=Decimal("300"))
    snapshot = make_snapshot(
        positions=(("USDT", Decimal("1000")),),
        reserve=Decimal("200"),
        orders=(order,),
    )

    metrics = PortfolioCalculator().calculate(
        snapshot,
        make_market((("USDT", Decimal("1")),)),
    )

    assert metrics.open_buy_orders_usd == Decimal("300")
    assert metrics.deployable_stable_usd == Decimal("500")


@pytest.mark.parametrize("status", [OrderStatus.FILLED, OrderStatus.CANCELLED])
def test_resolved_buy_orders_do_not_reduce_deployable_capital(status: OrderStatus) -> None:
    order = make_order(side=OrderSide.BUY, status=status, amount=Decimal("300"))
    snapshot = make_snapshot(
        positions=(("USDT", Decimal("1000")),),
        reserve=Decimal("200"),
        orders=(order,),
    )

    metrics = PortfolioCalculator().calculate(
        snapshot,
        make_market((("USDT", Decimal("1")),)),
    )

    assert metrics.stable_value_usd == Decimal("1000")
    assert metrics.open_buy_orders_usd == 0
    assert metrics.deployable_stable_usd == Decimal("800")


def test_open_sell_is_tracked_without_increasing_stable_capital() -> None:
    order = make_order(side=OrderSide.SELL, status=OrderStatus.OPEN, amount=Decimal("300"))
    snapshot = make_snapshot(
        positions=(("USDT", Decimal("1000")),),
        reserve=Decimal("200"),
        orders=(order,),
    )

    metrics = PortfolioCalculator().calculate(
        snapshot,
        make_market((("USDT", Decimal("1")),)),
    )

    assert metrics.stable_value_usd == Decimal("1000")
    assert metrics.open_sell_orders_usd == Decimal("300")
    assert metrics.deployable_stable_usd == Decimal("800")


def test_minimum_reserve_is_respected_and_deployable_never_negative() -> None:
    order = make_order(side=OrderSide.BUY, status=OrderStatus.OPEN, amount=Decimal("50"))
    snapshot = make_snapshot(
        positions=(("USDC", Decimal("100")),),
        reserve=Decimal("80"),
        orders=(order,),
    )

    metrics = PortfolioCalculator().calculate(
        snapshot,
        make_market((("USDC", Decimal("1")),)),
    )

    assert metrics.deployable_stable_usd == Decimal("0")


def test_largest_asset_concentration_is_detected() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("8")), ("ETH", Decimal("2"))))
    market = make_market((("BTC", Decimal("100")), ("ETH", Decimal("100"))))

    metrics = PortfolioCalculator().calculate(snapshot, market)

    assert metrics.largest_asset == "BTC"
    assert metrics.largest_asset_allocation_percentage == Decimal("80")


def test_arbitrary_asset_with_market_price_is_calculated() -> None:
    snapshot = make_snapshot(positions=(("JITO", Decimal("2.5")),))
    market = make_market((("JITO", Decimal("3.2")),))

    metrics = PortfolioCalculator().calculate(snapshot, market)

    assert metrics.total_value_usd == Decimal("8.00")
    assert metrics.allocations[0].asset == "JITO"


def test_missing_market_price_is_an_explicit_failure() -> None:
    snapshot = make_snapshot(positions=(("JITO", Decimal("2.5")),))

    with pytest.raises(
        PortfolioCalculationError,
        match="Market price is unavailable for JITO",
    ):
        PortfolioCalculator().calculate(snapshot, make_market(()))


def test_zero_value_portfolio_has_safe_zero_percentages() -> None:
    snapshot = make_snapshot(positions=(("BTC", Decimal("0")),))

    metrics = PortfolioCalculator().calculate(
        snapshot,
        make_market((("BTC", Decimal("60000")),)),
    )

    assert metrics.total_value_usd == 0
    assert metrics.stable_allocation_percentage == 0
    assert metrics.allocations[0].allocation_percentage == 0
