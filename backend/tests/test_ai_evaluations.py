from decimal import Decimal
from uuid import UUID

import pytest

from app.domain.errors import ActionValidationError
from app.domain.models import (
    OrderSide,
    PortfolioActionType,
    PortfolioAllocation,
    PortfolioMetrics,
    ProposedAction,
)
from app.evaluations.fixtures import evaluation_fixtures
from app.services.risk_engine import RiskEngine


def _metrics(fixture) -> PortfolioMetrics:
    context = fixture.context
    allocations = tuple(
        (
            feature.symbol,
            feature.portfolio_allocation_percentage,
            feature.price_usd,
        )
        for feature in context.market_features
    )
    total = context.portfolio_metrics.total_value_usd
    return PortfolioMetrics(
        total_value_usd=total,
        stable_value_usd=context.portfolio_metrics.stable_value_usd,
        invested_value_usd=context.portfolio_metrics.invested_value_usd,
        stable_allocation_percentage=(context.portfolio_metrics.stable_allocation_percentage),
        open_buy_orders_usd=context.portfolio_metrics.open_buy_orders_usd,
        open_sell_orders_usd=context.portfolio_metrics.open_sell_orders_usd,
        deployable_stable_usd=context.portfolio_metrics.deployable_stable_usd,
        allocations=tuple(
            PortfolioAllocation(
                asset=symbol,
                value_usd=total * percentage / Decimal("100") if total else Decimal("0"),
                allocation_percentage=percentage,
            )
            for symbol, percentage, _price in allocations
        ),
        largest_asset=(max(allocations, key=lambda item: item[1])[0] if allocations else None),
        largest_asset_allocation_percentage=max(
            (item[1] for item in allocations),
            default=Decimal("0"),
        ),
    )


@pytest.mark.parametrize("fixture", evaluation_fixtures(), ids=lambda fixture: fixture.name)
def test_offline_ai_evaluation_contexts_enforce_risk_invariants(fixture) -> None:
    engine = RiskEngine()
    metrics = _metrics(fixture)
    assessment = engine.assess(metrics, fixture.context.constraints)
    assert assessment.level is fixture.expected_risk_level
    assert fixture.invariant

    asset = fixture.context.market_features[0].symbol if fixture.context.market_features else None
    unsafe = ProposedAction(
        id=UUID("30000000-0000-0000-0000-000000000003"),
        asset=asset,
        type=PortfolioActionType.BUY,
        side=OrderSide.BUY,
        price=None,
        amount_usd=assessment.max_new_buy_usd + Decimal("0.000000000000001"),
        priority=1,
        reason="Offline evaluation boundary proposal.",
    )
    with pytest.raises(ActionValidationError):
        engine.validate_action(unsafe, metrics, fixture.context.constraints)


def test_near_boundary_fixture_accepts_exact_deterministic_cap() -> None:
    fixture = next(
        item for item in evaluation_fixtures() if item.name == "near_buy_policy_boundary"
    )
    metrics = _metrics(fixture)
    assessment = RiskEngine().assess(metrics, fixture.context.constraints)
    action = ProposedAction(
        id=UUID("30000000-0000-0000-0000-000000000003"),
        asset="BTC",
        type=PortfolioActionType.BUY,
        side=OrderSide.BUY,
        price=None,
        amount_usd=assessment.max_new_buy_usd,
        priority=1,
        reason="Offline evaluation at the exact policy boundary.",
    )

    accepted = RiskEngine().validate_action(action, metrics, fixture.context.constraints)

    assert accepted.amount_usd == Decimal("95")
