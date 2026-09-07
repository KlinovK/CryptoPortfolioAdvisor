from dataclasses import dataclass
from decimal import Decimal, localcontext

from app.domain.errors import ActionValidationError
from app.domain.models import (
    ConcentrationFlag,
    OrderSide,
    PortfolioAction,
    PortfolioActionType,
    PortfolioMetrics,
    PortfolioWarning,
    ProposedAction,
    RiskAssessment,
    RiskLevel,
    TradingConstraints,
    WarningSeverity,
)


@dataclass(frozen=True, slots=True)
class RiskPolicyConfig:
    max_new_buy_pct: Decimal = Decimal("5")
    concentration_warning_pct: Decimal = Decimal("50")
    extreme_concentration_pct: Decimal = Decimal("75")
    low_stable_allocation_pct: Decimal = Decimal("15")
    significant_open_buy_commitment_pct: Decimal = Decimal("20")
    leverage_permitted: bool = False


class RiskEngine:
    def __init__(self, config: RiskPolicyConfig | None = None) -> None:
        self.config = config or RiskPolicyConfig()

    def assess(
        self,
        metrics: PortfolioMetrics,
        constraints: TradingConstraints,
    ) -> RiskAssessment:
        with localcontext() as context:
            context.prec = 38
            max_by_policy = metrics.total_value_usd * self.config.max_new_buy_pct / Decimal("100")
            max_new_buy = min(max_by_policy, metrics.deployable_stable_usd)
            open_buy_commitment_pct = (
                metrics.open_buy_orders_usd * Decimal("100") / metrics.total_value_usd
                if metrics.total_value_usd > 0
                else Decimal("0")
            )

        concentration_flags = tuple(
            ConcentrationFlag(
                asset=allocation.asset,
                allocation_percentage=allocation.allocation_percentage,
            )
            for allocation in metrics.allocations
            if allocation.allocation_percentage > self.config.concentration_warning_pct
        )
        warnings: list[PortfolioWarning] = []
        high_risk = False
        moderate_risk = False

        if constraints.leverage_allowed and not self.config.leverage_permitted:
            high_risk = True
            warnings.append(
                PortfolioWarning(
                    code="LEVERAGE_POLICY_VIOLATION",
                    severity=WarningSeverity.CRITICAL,
                    message="Leverage is enabled but prohibited by the development risk policy.",
                    asset=None,
                )
            )

        if metrics.stable_value_usd < constraints.minimum_stable_reserve_usd:
            high_risk = True
            warnings.append(
                PortfolioWarning(
                    code="STABLE_RESERVE_SHORTFALL",
                    severity=WarningSeverity.CRITICAL,
                    message=("Stable capital is below the user-defined minimum stable reserve."),
                    asset=None,
                )
            )

        for flag in concentration_flags:
            moderate_risk = True
            is_extreme = flag.allocation_percentage > self.config.extreme_concentration_pct
            high_risk = high_risk or is_extreme
            warnings.append(
                PortfolioWarning(
                    code="EXTREME_CONCENTRATION" if is_extreme else "HIGH_CONCENTRATION",
                    severity=(WarningSeverity.CRITICAL if is_extreme else WarningSeverity.WARNING),
                    message=(
                        f"{flag.asset} exceeds the configured "
                        f"{self.config.concentration_warning_pct}% concentration threshold."
                    ),
                    asset=flag.asset,
                )
            )

        if (
            metrics.total_value_usd > 0
            and metrics.stable_allocation_percentage < self.config.low_stable_allocation_pct
        ):
            moderate_risk = True
            warnings.append(
                PortfolioWarning(
                    code="LOW_STABLE_ALLOCATION",
                    severity=WarningSeverity.WARNING,
                    message=("Stable allocation is below the configured development threshold."),
                    asset=None,
                )
            )

        if open_buy_commitment_pct >= self.config.significant_open_buy_commitment_pct:
            moderate_risk = True
            warnings.append(
                PortfolioWarning(
                    code="SIGNIFICANT_OPEN_BUY_COMMITMENT",
                    severity=WarningSeverity.WARNING,
                    message=(
                        "Open BUY orders commit a significant share of current portfolio value."
                    ),
                    asset=None,
                )
            )

        level = (
            RiskLevel.HIGH if high_risk else RiskLevel.MODERATE if moderate_risk else RiskLevel.LOW
        )
        return RiskAssessment(
            level=level,
            warnings=tuple(warnings),
            max_new_buy_usd=max_new_buy,
            deployable_stable_usd=metrics.deployable_stable_usd,
            concentration_flags=concentration_flags,
        )

    def validate_actions(
        self,
        actions: tuple[ProposedAction, ...],
        metrics: PortfolioMetrics,
        constraints: TradingConstraints,
    ) -> tuple[PortfolioAction, ...]:
        return tuple(self.validate_action(action, metrics, constraints) for action in actions)

    def validate_action(
        self,
        action: ProposedAction,
        metrics: PortfolioMetrics,
        constraints: TradingConstraints,
    ) -> PortfolioAction:
        assessment = self.assess(metrics, constraints)
        known_assets = {allocation.asset for allocation in metrics.allocations}
        asset_required = action.type in {
            PortfolioActionType.BUY,
            PortfolioActionType.SELL,
            PortfolioActionType.MONITOR,
            PortfolioActionType.PLACE_LIMIT_ORDER,
            PortfolioActionType.KEEP_LIMIT_ORDER,
            PortfolioActionType.CANCEL_LIMIT_ORDER,
            PortfolioActionType.REBALANCE,
        }
        if asset_required and action.asset is None:
            raise ActionValidationError("The proposed action requires an asset.")
        if action.asset is not None and action.asset not in known_assets:
            raise ActionValidationError("The proposed action references an unknown asset.")

        if action.requires_leverage and (
            not constraints.leverage_allowed or not self.config.leverage_permitted
        ):
            raise ActionValidationError("The proposed action requires prohibited leverage.")

        if action.priority < 1 or action.priority > 5:
            raise ActionValidationError("Recommendation priority must be between 1 and 5.")
        if not action.reason.strip():
            raise ActionValidationError("Recommendation reason must not be empty.")

        if action.amount_usd is not None and action.amount_usd <= 0:
            raise ActionValidationError("Recommendation amount must be greater than zero.")

        requires_amount = action.type in {
            PortfolioActionType.BUY,
            PortfolioActionType.SELL,
            PortfolioActionType.PLACE_LIMIT_ORDER,
        }
        if requires_amount and action.amount_usd is None:
            raise ActionValidationError("The proposed action requires an amount.")

        if action.type is PortfolioActionType.BUY and action.side is not OrderSide.BUY:
            raise ActionValidationError("A BUY action must use the BUY side.")
        if action.type is PortfolioActionType.SELL and action.side is not OrderSide.SELL:
            raise ActionValidationError("A SELL action must use the SELL side.")
        if action.type in {
            PortfolioActionType.PLACE_LIMIT_ORDER,
            PortfolioActionType.KEEP_LIMIT_ORDER,
            PortfolioActionType.CANCEL_LIMIT_ORDER,
        } and action.side not in {OrderSide.BUY, OrderSide.SELL}:
            raise ActionValidationError("A limit-order action requires an order side.")
        if (
            action.type
            in {
                PortfolioActionType.HOLD,
                PortfolioActionType.MONITOR,
                PortfolioActionType.WAIT,
                PortfolioActionType.REBALANCE,
            }
            and action.side is not None
        ):
            raise ActionValidationError("The proposed action type must not include a side.")

        is_new_buy = (
            action.type
            in {
                PortfolioActionType.BUY,
                PortfolioActionType.PLACE_LIMIT_ORDER,
            }
            and action.side is OrderSide.BUY
        )
        if is_new_buy and action.amount_usd is not None:
            if action.amount_usd > metrics.deployable_stable_usd:
                raise ActionValidationError("The proposed BUY exceeds deployable stable capital.")
            if action.amount_usd > assessment.max_new_buy_usd:
                raise ActionValidationError("The proposed BUY exceeds the maximum-new-buy policy.")
            stable_after_commitment = (
                metrics.stable_value_usd - metrics.open_buy_orders_usd - action.amount_usd
            )
            if stable_after_commitment < constraints.minimum_stable_reserve_usd:
                raise ActionValidationError(
                    "The proposed BUY would violate the minimum stable reserve."
                )

        if (
            action.type is PortfolioActionType.SELL
            and action.amount_usd is not None
            and action.asset is not None
        ):
            asset_value = next(
                allocation.value_usd
                for allocation in metrics.allocations
                if allocation.asset == action.asset
            )
            if action.amount_usd > asset_value:
                raise ActionValidationError("The proposed SELL exceeds the current asset value.")

        price_required = action.type in {
            PortfolioActionType.PLACE_LIMIT_ORDER,
            PortfolioActionType.KEEP_LIMIT_ORDER,
        }
        if price_required and action.price is None:
            raise ActionValidationError("The proposed limit-order action requires a price.")
        if action.price is not None and action.price <= 0:
            raise ActionValidationError("Recommendation price must be greater than zero.")

        return PortfolioAction(
            id=action.id,
            asset=action.asset,
            type=action.type,
            side=action.side,
            price=action.price,
            amount_usd=action.amount_usd,
            priority=action.priority,
            reason=action.reason,
        )
