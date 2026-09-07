from decimal import Decimal

import pytest

from app.dependencies import get_analysis_service
from app.domain.models import (
    AnalysisMode,
    OrderSide,
    PortfolioActionType,
    RecommendationAction,
    RecommendationPlan,
    RiskLevel,
)
from app.infrastructure.static_market_data import StaticMarketDataProvider
from app.main import app
from app.services.analysis import DeterministicPortfolioAnalysisService
from app.services.analysis_context import AnalysisContextBuilder
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.recommendations import OpenAIUnavailableError
from app.services.risk_engine import RiskEngine
from tests.factories import make_snapshot
from tests.test_portfolio_analysis import post_analysis, valid_payload


class FakeReasoner:
    def __init__(
        self,
        plan: RecommendationPlan | None = None,
        error: Exception | None = None,
    ) -> None:
        self.plan = plan or plan_with(hold_action())
        self.error = error
        self.calls = 0

    async def recommend(self, _context):
        self.calls += 1
        if self.error is not None:
            raise self.error
        return self.plan


def hold_action() -> RecommendationAction:
    return RecommendationAction(
        asset=None,
        type=PortfolioActionType.HOLD,
        side=None,
        price=None,
        amount_usd=None,
        priority=1,
        reason="Hold while the supplied context remains within policy.",
    )


def wait_action() -> RecommendationAction:
    return RecommendationAction(
        asset=None,
        type=PortfolioActionType.WAIT,
        side=None,
        price=None,
        amount_usd=None,
        priority=1,
        reason="Wait for a safer setup.",
    )


def buy_action(amount: str) -> RecommendationAction:
    return RecommendationAction(
        asset="BTC",
        type=PortfolioActionType.BUY,
        side=OrderSide.BUY,
        price=None,
        amount_usd=Decimal(amount),
        priority=2,
        reason="Use only supplied deployable stable capital.",
    )


def plan_with(*actions: RecommendationAction) -> RecommendationPlan:
    return RecommendationPlan(
        summary="Use the supplied metrics only; do not change deterministic totals.",
        actions=tuple(actions),
        observations=("BTC allocation reflects the supplied portfolio.",),
    )


def snapshot_for_ai():
    return make_snapshot(
        positions=(("BTC", Decimal("0.01")), ("USDT", Decimal("1000"))),
        reserve=Decimal("100"),
    )


def make_service(reasoner: FakeReasoner | None = None):
    return DeterministicPortfolioAnalysisService(
        market_data_provider=StaticMarketDataProvider.development(),
        portfolio_calculator=PortfolioCalculator(),
        risk_engine=RiskEngine(),
        analysis_context_builder=AnalysisContextBuilder(),
        recommendation_reasoner=reasoner,
    )


@pytest.mark.asyncio
async def test_safe_buy_is_accepted_after_risk_validation() -> None:
    analysis = await make_service(FakeReasoner(plan_with(buy_action("50")))).analyze(
        snapshot_for_ai()
    )

    assert analysis.actions[0].type is PortfolioActionType.BUY
    assert analysis.actions[0].amount_usd == Decimal("50")


@pytest.mark.parametrize("amount", ["901", "81"])
@pytest.mark.asyncio
async def test_buy_above_capital_or_max_new_buy_is_removed(amount: str) -> None:
    analysis = await make_service(FakeReasoner(plan_with(buy_action(amount)))).analyze(
        snapshot_for_ai()
    )

    assert [action.type for action in analysis.actions] == [PortfolioActionType.WAIT]
    assert "AI_ACTIONS_REJECTED" in [warning.code for warning in analysis.warnings]


@pytest.mark.asyncio
async def test_leverage_invalid_action_is_removed() -> None:
    action = RecommendationAction(
        asset=None,
        type=PortfolioActionType.HOLD,
        side=None,
        price=None,
        amount_usd=None,
        priority=1,
        reason="Unsafe fake action.",
        requires_leverage=True,
    )

    analysis = await make_service(FakeReasoner(plan_with(action))).analyze(snapshot_for_ai())

    assert analysis.actions[0].type is PortfolioActionType.WAIT


@pytest.mark.asyncio
async def test_invalid_required_limit_price_is_removed() -> None:
    action = RecommendationAction(
        asset="BTC",
        type=PortfolioActionType.PLACE_LIMIT_ORDER,
        side=OrderSide.BUY,
        price=None,
        amount_usd=Decimal("25"),
        priority=1,
        reason="Malformed fake proposal.",
    )

    analysis = await make_service(FakeReasoner(plan_with(action))).analyze(snapshot_for_ai())

    assert analysis.actions[0].type is PortfolioActionType.WAIT


@pytest.mark.parametrize(
    "action",
    [
        RecommendationAction(
            asset="DOGE",
            type=PortfolioActionType.BUY,
            side=OrderSide.BUY,
            price=None,
            amount_usd=Decimal("25"),
            priority=1,
            reason="Unknown asset.",
        ),
        RecommendationAction(
            asset="BTC",
            type=PortfolioActionType.BUY,
            side=OrderSide.SELL,
            price=None,
            amount_usd=Decimal("25"),
            priority=1,
            reason="Inconsistent action semantics.",
        ),
    ],
)
@pytest.mark.asyncio
async def test_unknown_asset_or_invalid_action_semantics_are_removed(
    action: RecommendationAction,
) -> None:
    analysis = await make_service(FakeReasoner(plan_with(action))).analyze(snapshot_for_ai())

    assert analysis.actions[0].type is PortfolioActionType.WAIT


@pytest.mark.parametrize("action", [hold_action(), wait_action()])
@pytest.mark.asyncio
async def test_valid_hold_and_wait_survive(action: RecommendationAction) -> None:
    analysis = await make_service(FakeReasoner(plan_with(action))).analyze(snapshot_for_ai())

    assert analysis.actions[0].type is action.type


@pytest.mark.asyncio
async def test_mixed_valid_and_invalid_actions_returns_valid_subset() -> None:
    analysis = await make_service(
        FakeReasoner(plan_with(hold_action(), buy_action("901")))
    ).analyze(snapshot_for_ai())

    assert [action.type for action in analysis.actions] == [PortfolioActionType.HOLD]
    assert "AI_ACTIONS_REJECTED" in [warning.code for warning in analysis.warnings]


@pytest.mark.asyncio
async def test_model_plan_cannot_overwrite_deterministic_fields() -> None:
    analysis = await make_service(FakeReasoner(plan_with(hold_action()))).analyze(snapshot_for_ai())

    assert analysis.portfolio_summary.total_value_usd == Decimal("1600.00")
    assert analysis.portfolio_summary.stable_value_usd == Decimal("1000")
    assert analysis.market_summary.as_of.isoformat() == "2026-01-01T00:00:00+00:00"
    assert analysis.risk_level is RiskLevel.MODERATE
    assert analysis.analysis_mode is AnalysisMode.AI_ASSISTED


@pytest.mark.asyncio
async def test_openai_disabled_returns_deterministic_mode() -> None:
    analysis = await make_service().analyze(snapshot_for_ai())

    assert analysis.analysis_mode is AnalysisMode.DETERMINISTIC


@pytest.mark.asyncio
async def test_reasoning_failure_returns_explicit_ai_fallback() -> None:
    reasoner = FakeReasoner(error=OpenAIUnavailableError("offline"))

    analysis = await make_service(reasoner).analyze(snapshot_for_ai())

    assert analysis.analysis_mode is AnalysisMode.AI_FALLBACK
    assert "AI_REASONING_UNAVAILABLE" in [warning.code for warning in analysis.warnings]
    assert analysis.actions


@pytest.mark.asyncio
async def test_empty_reasoning_plan_returns_explicit_ai_fallback() -> None:
    reasoner = FakeReasoner(RecommendationPlan(summary="Empty", actions=(), observations=()))

    analysis = await make_service(reasoner).analyze(snapshot_for_ai())

    assert analysis.analysis_mode is AnalysisMode.AI_FALLBACK
    assert analysis.actions[0].type in {
        PortfolioActionType.HOLD,
        PortfolioActionType.REBALANCE,
        PortfolioActionType.WAIT,
    }


@pytest.mark.asyncio
async def test_endpoint_can_use_injected_ai_reasoner_offline() -> None:
    reasoner = FakeReasoner(plan_with(hold_action()))
    service = make_service(reasoner)
    app.dependency_overrides[get_analysis_service] = lambda: service
    try:
        response = await post_analysis(valid_payload())
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["analysis_mode"] == "ai_assisted"
    assert reasoner.calls == 1
