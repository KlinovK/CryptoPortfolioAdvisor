from typing import Protocol

from app.domain.models import (
    AnalysisContext,
    PortfolioActionType,
    RecommendationAction,
    RecommendationPlan,
)


class RecommendationReasoner(Protocol):
    async def recommend(self, context: AnalysisContext) -> RecommendationPlan: ...


class RecommendationReasoningError(RuntimeError):
    category = "openai_unavailable"


class OpenAIUnavailableError(RecommendationReasoningError):
    category = "openai_unavailable"


class OpenAIRateLimitedError(RecommendationReasoningError):
    category = "openai_rate_limited"


class OpenAIInvalidResponseError(RecommendationReasoningError):
    category = "openai_invalid_response"


class OpenAIRefusalError(RecommendationReasoningError):
    category = "openai_refusal"


class DeterministicRecommendationService:
    async def recommend(self, context: AnalysisContext) -> RecommendationPlan:
        total_value = context.portfolio_metrics.total_value_usd
        risk = context.risk_assessment
        if total_value == 0:
            action_type = PortfolioActionType.WAIT
            asset = None
            reason = "Wait because the submitted portfolio has no calculated value."
        elif risk.deployable_stable_usd == 0:
            action_type = PortfolioActionType.WAIT
            asset = None
            reason = "Wait because no stable capital is currently deployable."
        elif risk.concentration_flags:
            action_type = PortfolioActionType.REBALANCE
            asset = risk.concentration_flags[0].asset
            reason = "Review the concentrated allocation under the configured policy."
        else:
            action_type = PortfolioActionType.HOLD
            asset = None
            reason = "No deterministic hard rule requires a portfolio change."

        return RecommendationPlan(
            summary="Deterministic portfolio and risk policy evaluation.",
            actions=(
                RecommendationAction(
                    asset=asset,
                    type=action_type,
                    side=None,
                    price=None,
                    amount_usd=None,
                    priority=1,
                    reason=reason,
                ),
            ),
            observations=(),
        )


def safe_wait_plan(reason: str) -> RecommendationPlan:
    return RecommendationPlan(
        summary="Deterministic safety fallback.",
        actions=(
            RecommendationAction(
                asset=None,
                type=PortfolioActionType.WAIT,
                side=None,
                price=None,
                amount_usd=None,
                priority=1,
                reason=reason,
            ),
        ),
        observations=(),
    )
