import asyncio
from decimal import Decimal
from typing import Protocol
from uuid import UUID, uuid5

from app.domain.errors import ActionValidationError, AnalysisTimeoutError, PortfolioValidationError
from app.domain.models import (
    AnalysisContext,
    AnalysisMode,
    AssetAnalysis,
    MarketAssetSnapshot,
    MarketSnapshot,
    MarketSummary,
    OrderStatus,
    PortfolioAnalysis,
    PortfolioSnapshot,
    PortfolioSummary,
    PortfolioWarning,
    ProposedAction,
    RecommendationAction,
    RecommendationPlan,
    WarningSeverity,
)
from app.observability import get_logger, log_event
from app.services.analysis_context import AnalysisContextBuilder
from app.services.market_data import MarketDataProvider
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.recommendations import (
    DeterministicRecommendationService,
    OpenAIInvalidResponseError,
    RecommendationReasoner,
    RecommendationReasoningError,
    safe_wait_plan,
)
from app.services.risk_engine import RiskEngine

ANALYSIS_NAMESPACE = UUID("723966d7-8f0c-4c70-a1c8-e70365151670")
logger = get_logger("analysis")


class AnalysisService(Protocol):
    async def analyze(self, snapshot: PortfolioSnapshot) -> PortfolioAnalysis: ...


class BudgetedAnalysisService:
    def __init__(self, wrapped: AnalysisService, timeout_seconds: float) -> None:
        self._wrapped = wrapped
        self._timeout_seconds = timeout_seconds

    async def analyze(self, snapshot: PortfolioSnapshot) -> PortfolioAnalysis:
        try:
            async with asyncio.timeout(self._timeout_seconds):
                return await self._wrapped.analyze(snapshot)
        except TimeoutError as error:
            log_event(logger, "analysis_timeout", error_category="analysis_timeout")
            raise AnalysisTimeoutError() from error


class DeterministicPortfolioAnalysisService:
    def __init__(
        self,
        market_data_provider: MarketDataProvider,
        portfolio_calculator: PortfolioCalculator,
        risk_engine: RiskEngine,
        analysis_context_builder: AnalysisContextBuilder,
        recommendation_reasoner: RecommendationReasoner | None = None,
        deterministic_reasoner: RecommendationReasoner | None = None,
    ) -> None:
        self._market_data_provider = market_data_provider
        self._portfolio_calculator = portfolio_calculator
        self._risk_engine = risk_engine
        self._analysis_context_builder = analysis_context_builder
        self._recommendation_reasoner = recommendation_reasoner
        self._deterministic_reasoner = (
            deterministic_reasoner or DeterministicRecommendationService()
        )

    async def analyze(self, snapshot: PortfolioSnapshot) -> PortfolioAnalysis:
        self._validate_snapshot(snapshot)
        symbols = tuple(position.symbol for position in snapshot.portfolio.positions)
        market_snapshot = await self._market_data_provider.get_market_snapshot(symbols)
        log_event(
            logger,
            "market_snapshot_acquired",
            market_data_mode="live" if market_snapshot.is_live else "static",
            market_provider_outcome="success",
        )
        metrics = self._portfolio_calculator.calculate(snapshot, market_snapshot)
        risk = self._risk_engine.assess(metrics, snapshot.constraints)
        context = self._analysis_context_builder.build(snapshot, market_snapshot, metrics, risk)
        mode, plan, fallback_warning = await self._recommend(context)
        proposed_actions = self._to_proposed_actions(snapshot, plan.actions)
        validated_actions = []
        rejected_count = 0
        for proposed_action in proposed_actions:
            try:
                validated_actions.append(
                    self._risk_engine.validate_action(
                        proposed_action,
                        metrics,
                        snapshot.constraints,
                    )
                )
            except ActionValidationError:
                rejected_count += 1

        rejection_warning = None
        if rejected_count:
            rejection_warning = PortfolioWarning(
                code="AI_ACTIONS_REJECTED",
                severity=WarningSeverity.WARNING,
                message=(
                    f"Deterministic risk policy removed {rejected_count} of "
                    f"{len(proposed_actions)} proposed actions."
                ),
                asset=None,
            )

        if proposed_actions and not validated_actions:
            wait_plan = safe_wait_plan(
                "Wait because deterministic risk policy rejected every proposed action."
            )
            validated_actions = [
                self._risk_engine.validate_action(
                    self._to_proposed_actions(snapshot, wait_plan.actions)[0],
                    metrics,
                    snapshot.constraints,
                )
            ]

        actions = tuple(validated_actions)
        market_by_symbol = {asset.symbol: asset for asset in market_snapshot.assets}
        allocation_by_symbol = {item.asset: item for item in metrics.allocations}
        concentration_symbols = {flag.asset for flag in risk.concentration_flags}

        asset_analysis = tuple(
            AssetAnalysis(
                asset=position.symbol,
                value_usd=allocation_by_symbol[position.symbol].value_usd,
                allocation_percentage=(allocation_by_symbol[position.symbol].allocation_percentage),
                assessment=self._asset_assessment(
                    position.amount,
                    market_by_symbol[position.symbol],
                    market_snapshot.is_live,
                ),
                recommendation=(
                    self._asset_recommendation(
                        symbol=position.symbol,
                        is_concentrated=position.symbol in concentration_symbols,
                        mode=mode,
                        plan=plan,
                    )
                ),
            )
            for position in snapshot.portfolio.positions
        )
        warnings = (
            self._market_data_warning(market_snapshot.is_live),
            *risk.warnings,
            *((fallback_warning,) if fallback_warning is not None else ()),
            *((rejection_warning,) if rejection_warning is not None else ()),
        )

        log_event(
            logger,
            "portfolio_analysis_completed",
            analysis_mode=mode.value,
            proposed_actions=len(proposed_actions),
            accepted_actions=len(actions),
            rejected_actions=rejected_count,
        )

        return PortfolioAnalysis(
            id=uuid5(ANALYSIS_NAMESPACE, f"analysis:{snapshot.id}"),
            generated_at=snapshot.created_at,
            snapshot_id=snapshot.id,
            analysis_mode=mode,
            risk_level=risk.level,
            portfolio_summary=PortfolioSummary(
                total_value_usd=metrics.total_value_usd,
                stable_value_usd=metrics.stable_value_usd,
                invested_value_usd=metrics.invested_value_usd,
                stable_allocation_percentage=metrics.stable_allocation_percentage,
                open_buy_orders_usd=metrics.open_buy_orders_usd,
                open_sell_orders_usd=metrics.open_sell_orders_usd,
                deployable_stable_usd=metrics.deployable_stable_usd,
                allocations=metrics.allocations,
            ),
            market_summary=self._market_summary(market_snapshot, mode),
            actions=actions,
            asset_analysis=asset_analysis,
            warnings=warnings,
        )

    async def _recommend(
        self,
        context: AnalysisContext,
    ) -> tuple[AnalysisMode, RecommendationPlan, PortfolioWarning | None]:
        if self._recommendation_reasoner is None:
            plan = await self._deterministic_reasoner.recommend(context)
            log_event(logger, "recommendation_completed", openai_outcome="disabled")
            return AnalysisMode.DETERMINISTIC, plan, None

        try:
            plan = await self._recommendation_reasoner.recommend(context)
            if not plan.actions:
                raise OpenAIInvalidResponseError("OpenAI returned an empty recommendation plan.")
            return AnalysisMode.AI_ASSISTED, plan, None
        except RecommendationReasoningError:
            plan = await self._deterministic_reasoner.recommend(context)
            return (
                AnalysisMode.AI_FALLBACK,
                plan,
                PortfolioWarning(
                    code="AI_REASONING_UNAVAILABLE",
                    severity=WarningSeverity.WARNING,
                    message="AI reasoning unavailable; deterministic risk analysis returned.",
                    asset=None,
                ),
            )

    @staticmethod
    def _to_proposed_actions(
        snapshot: PortfolioSnapshot,
        actions: tuple[RecommendationAction, ...],
    ) -> tuple[ProposedAction, ...]:
        return tuple(
            ProposedAction(
                id=uuid5(
                    ANALYSIS_NAMESPACE,
                    f"action:{snapshot.id}:{index}:{action.type.value}:{action.asset or ''}",
                ),
                asset=action.asset,
                type=action.type,
                side=action.side,
                price=action.price,
                amount_usd=action.amount_usd,
                priority=action.priority,
                reason=action.reason,
                requires_leverage=action.requires_leverage,
            )
            for index, action in enumerate(actions)
        )

    @staticmethod
    def _market_summary(
        market_snapshot: MarketSnapshot,
        mode: AnalysisMode,
    ) -> MarketSummary:
        if market_snapshot.is_live:
            available_rsi = ", ".join(
                f"{asset.symbol} 4H RSI {format(asset.rsi_4h, '.2f')}"
                for asset in market_snapshot.assets
                if asset.rsi_4h is not None
            )
            feature_summary = (
                f" Compact features: {available_rsi}."
                if available_rsi
                else " Compact technical features are unavailable for the submitted assets."
            )
            overview = (
                f"Live public market data as of {market_snapshot.as_of.isoformat()}."
                f"{feature_summary} {DeterministicPortfolioAnalysisService._mode_summary(mode)}"
            )
        else:
            overview = (
                f"Development market snapshot as of {market_snapshot.as_of.isoformat()}. "
                f"Fixed prices are available for {len(market_snapshot.assets)} submitted "
                "assets. Technical indicators are unavailable. Values are not live. "
                f"{DeterministicPortfolioAnalysisService._mode_summary(mode)}"
            )
        return MarketSummary(
            as_of=market_snapshot.as_of,
            overview=overview,
        )

    @staticmethod
    def _mode_summary(mode: AnalysisMode) -> str:
        if mode is AnalysisMode.AI_ASSISTED:
            return "Recommendations are AI-assisted and deterministically risk-validated."
        if mode is AnalysisMode.AI_FALLBACK:
            return "AI was unavailable; deterministic analysis was used."
        return "Analysis is deterministic; AI reasoning is not enabled."

    @staticmethod
    def _asset_recommendation(
        *,
        symbol: str,
        is_concentrated: bool,
        mode: AnalysisMode,
        plan: RecommendationPlan,
    ) -> str:
        if mode is AnalysisMode.AI_ASSISTED:
            observations = [
                observation
                for observation in plan.observations
                if symbol in observation.upper().replace("-", " ").split()
            ]
            return " ".join(observations) if observations else plan.summary
        if mode is AnalysisMode.AI_FALLBACK:
            return "AI was unavailable; this recommendation uses deterministic policy only."
        if is_concentrated:
            return "The deterministic policy flags this allocation for concentration review."
        return "No deterministic hard rule requires a change to this allocation."

    @staticmethod
    def _asset_assessment(
        amount: Decimal,
        market_asset: MarketAssetSnapshot,
        is_live: bool,
    ) -> str:
        price = market_asset.price_usd
        if is_live:
            return (
                f"Live public-market valuation: quantity {format(amount, 'f')} "
                f"at USD {format(price, 'f')}."
            )
        return (
            f"Static development valuation: quantity {format(amount, 'f')} "
            f"at configured price USD {format(price, 'f')}."
        )

    @staticmethod
    def _market_data_warning(is_live: bool) -> PortfolioWarning:
        if is_live:
            return PortfolioWarning(
                code="LIVE_PUBLIC_MARKET_DATA",
                severity=WarningSeverity.INFO,
                message=(
                    "Valuations use fresh public-provider prices. Recommendations are separately "
                    "validated by deterministic risk policy."
                ),
                asset=None,
            )
        return PortfolioWarning(
            code="DEVELOPMENT_MARKET_DATA",
            severity=WarningSeverity.INFO,
            message="Valuations use fixed development prices, not live market data.",
            asset=None,
        )

    @staticmethod
    def _validate_snapshot(snapshot: PortfolioSnapshot) -> None:
        symbols: set[str] = set()
        for position in snapshot.portfolio.positions:
            if position.symbol in symbols:
                raise PortfolioValidationError(f"Duplicate portfolio symbol: {position.symbol}.")
            symbols.add(position.symbol)
            if position.amount < 0:
                raise PortfolioValidationError("Asset amount must be zero or greater.")

        constraints = snapshot.constraints
        if constraints.additional_monthly_income_usd < 0:
            raise PortfolioValidationError("Monthly income must be zero or greater.")
        if constraints.minimum_stable_reserve_usd < 0:
            raise PortfolioValidationError("Stable reserve must be zero or greater.")

        for order in snapshot.orders:
            if order.amount_usd <= 0:
                raise PortfolioValidationError("Order amount must be greater than zero.")
            if order.target_price <= 0:
                raise PortfolioValidationError("Order target price must be greater than zero.")
            if order.status is OrderStatus.OPEN and order.resolved_at is not None:
                raise PortfolioValidationError("An open order cannot have a resolved date.")
