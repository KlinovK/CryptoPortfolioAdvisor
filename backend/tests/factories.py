from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from app.domain.models import (
    AssetPosition,
    LimitOrder,
    MarketAssetSnapshot,
    MarketSnapshot,
    OrderSide,
    OrderStatus,
    Portfolio,
    PortfolioActionType,
    PortfolioAllocation,
    PortfolioMetrics,
    PortfolioSnapshot,
    ProposedAction,
    RiskTolerance,
    TradingConstraints,
    TradingStyle,
)

FIXED_DATE = datetime(2026, 1, 1, tzinfo=UTC)


def make_constraints(
    *,
    reserve: Decimal = Decimal("0"),
    leverage_allowed: bool = False,
) -> TradingConstraints:
    return TradingConstraints(
        trading_style=TradingStyle.ACTIVE,
        risk_tolerance=RiskTolerance.CONSERVATIVE,
        leverage_allowed=leverage_allowed,
        additional_monthly_income_usd=Decimal("0"),
        minimum_stable_reserve_usd=reserve,
    )


def make_order(
    *,
    side: OrderSide,
    status: OrderStatus,
    amount: Decimal,
) -> LimitOrder:
    return LimitOrder(
        id=UUID("40000000-0000-0000-0000-000000000004"),
        symbol="BTC",
        side=side,
        amount_usd=amount,
        target_price=Decimal("50000"),
        status=status,
        created_at=FIXED_DATE,
        resolved_at=None if status is OrderStatus.OPEN else FIXED_DATE,
    )


def make_snapshot(
    *,
    positions: tuple[tuple[str, Decimal], ...],
    reserve: Decimal = Decimal("0"),
    orders: tuple[LimitOrder, ...] = (),
    leverage_allowed: bool = False,
) -> PortfolioSnapshot:
    return PortfolioSnapshot(
        id=UUID("10000000-0000-0000-0000-000000000001"),
        created_at=FIXED_DATE,
        portfolio=Portfolio(
            positions=tuple(
                AssetPosition(symbol=symbol, amount=amount) for symbol, amount in positions
            )
        ),
        constraints=make_constraints(
            reserve=reserve,
            leverage_allowed=leverage_allowed,
        ),
        orders=orders,
    )


def make_market(prices: tuple[tuple[str, Decimal], ...]) -> MarketSnapshot:
    return MarketSnapshot(
        as_of=FIXED_DATE,
        assets=tuple(
            MarketAssetSnapshot(symbol=symbol, price_usd=price) for symbol, price in prices
        ),
    )


def make_metrics(
    *,
    total: Decimal = Decimal("1000"),
    stable: Decimal = Decimal("300"),
    stable_pct: Decimal = Decimal("30"),
    open_buys: Decimal = Decimal("0"),
    deployable: Decimal = Decimal("300"),
    allocations: tuple[tuple[str, Decimal], ...] = (
        ("BTC", Decimal("40")),
        ("ETH", Decimal("30")),
        ("USDT", Decimal("30")),
    ),
) -> PortfolioMetrics:
    return PortfolioMetrics(
        total_value_usd=total,
        stable_value_usd=stable,
        invested_value_usd=total - stable,
        stable_allocation_percentage=stable_pct,
        open_buy_orders_usd=open_buys,
        open_sell_orders_usd=Decimal("0"),
        deployable_stable_usd=deployable,
        allocations=tuple(
            PortfolioAllocation(
                asset=symbol,
                value_usd=total * percentage / Decimal("100"),
                allocation_percentage=percentage,
            )
            for symbol, percentage in allocations
        ),
        largest_asset=max(allocations, key=lambda item: item[1])[0] if allocations else None,
        largest_asset_allocation_percentage=(
            max((item[1] for item in allocations), default=Decimal("0"))
        ),
    )


def make_action(
    *,
    action_type: PortfolioActionType = PortfolioActionType.BUY,
    side: OrderSide | None = OrderSide.BUY,
    amount: Decimal | None = Decimal("25"),
    price: Decimal | None = None,
    requires_leverage: bool = False,
) -> ProposedAction:
    return ProposedAction(
        id=UUID("30000000-0000-0000-0000-000000000003"),
        asset="BTC",
        type=action_type,
        side=side,
        price=price,
        amount_usd=amount,
        priority=1,
        reason="Deterministic test proposal.",
        requires_leverage=requires_leverage,
    )
