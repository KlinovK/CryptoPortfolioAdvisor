from decimal import Decimal

import pytest

from app.domain.errors import ActionValidationError
from app.domain.models import OrderSide, PortfolioActionType, RiskAssessment, RiskLevel
from app.services.risk_engine import RiskEngine
from tests.factories import make_action, make_constraints, make_metrics


def warning_codes(assessment: RiskAssessment) -> list[str]:
    return [warning.code for warning in assessment.warnings]


def test_high_concentration_creates_flag_and_warning() -> None:
    metrics = make_metrics(allocations=(("BTC", Decimal("60")), ("USDT", Decimal("40"))))

    assessment = RiskEngine().assess(metrics, make_constraints())

    assert assessment.level is RiskLevel.MODERATE
    assert assessment.concentration_flags[0].asset == "BTC"
    assert "HIGH_CONCENTRATION" in warning_codes(assessment)


def test_extreme_concentration_is_high_risk() -> None:
    metrics = make_metrics(allocations=(("BTC", Decimal("80")), ("USDT", Decimal("20"))))

    assessment = RiskEngine().assess(metrics, make_constraints())

    assert assessment.level is RiskLevel.HIGH
    assert "EXTREME_CONCENTRATION" in warning_codes(assessment)


def test_low_stable_allocation_creates_warning() -> None:
    metrics = make_metrics(stable=Decimal("10"), stable_pct=Decimal("10"))

    assessment = RiskEngine().assess(metrics, make_constraints())

    assert assessment.level is RiskLevel.MODERATE
    assert "LOW_STABLE_ALLOCATION" in warning_codes(assessment)


def test_stable_reserve_shortfall_is_high_risk() -> None:
    metrics = make_metrics(stable=Decimal("100"), stable_pct=Decimal("10"))

    assessment = RiskEngine().assess(
        metrics,
        make_constraints(reserve=Decimal("200")),
    )

    assert assessment.level is RiskLevel.HIGH
    assert "STABLE_RESERVE_SHORTFALL" in warning_codes(assessment)


def test_significant_open_buy_commitment_creates_warning() -> None:
    metrics = make_metrics(open_buys=Decimal("200"))

    assessment = RiskEngine().assess(metrics, make_constraints())

    assert assessment.level is RiskLevel.MODERATE
    assert "SIGNIFICANT_OPEN_BUY_COMMITMENT" in warning_codes(assessment)


def test_safe_buy_within_deployable_and_policy_limit_passes() -> None:
    metrics = make_metrics(deployable=Decimal("300"))
    action = make_action(amount=Decimal("50"))

    validated = RiskEngine().validate_actions(
        (action,),
        metrics,
        make_constraints(),
    )

    assert validated[0].amount_usd == Decimal("50")


def test_buy_above_deployable_capital_is_rejected() -> None:
    metrics = make_metrics(total=Decimal("10000"), deployable=Decimal("100"))
    action = make_action(amount=Decimal("101"))

    with pytest.raises(ActionValidationError, match="exceeds deployable"):
        RiskEngine().validate_actions((action,), metrics, make_constraints())


def test_buy_above_max_new_buy_policy_is_rejected() -> None:
    metrics = make_metrics(total=Decimal("1000"), deployable=Decimal("300"))
    action = make_action(amount=Decimal("50.01"))

    with pytest.raises(ActionValidationError, match="maximum-new-buy"):
        RiskEngine().validate_actions((action,), metrics, make_constraints())


def test_leverage_dependent_action_is_rejected_when_leverage_is_disabled() -> None:
    action = make_action(
        action_type=PortfolioActionType.HOLD,
        side=None,
        amount=None,
        requires_leverage=True,
    )

    with pytest.raises(ActionValidationError, match="prohibited leverage"):
        RiskEngine().validate_actions(
            (action,),
            make_metrics(),
            make_constraints(leverage_allowed=False),
        )


def test_invalid_action_amount_is_rejected() -> None:
    action = make_action(amount=Decimal("0"))

    with pytest.raises(ActionValidationError, match="amount must be greater"):
        RiskEngine().validate_actions((action,), make_metrics(), make_constraints())


def test_invalid_required_action_price_is_rejected() -> None:
    action = make_action(
        action_type=PortfolioActionType.PLACE_LIMIT_ORDER,
        side=OrderSide.BUY,
        amount=Decimal("25"),
        price=Decimal("0"),
    )

    with pytest.raises(ActionValidationError, match="price must be greater"):
        RiskEngine().validate_actions((action,), make_metrics(), make_constraints())


def test_zero_portfolio_assessment_is_valid_and_has_zero_buy_limit() -> None:
    metrics = make_metrics(
        total=Decimal("0"),
        stable=Decimal("0"),
        stable_pct=Decimal("0"),
        deployable=Decimal("0"),
        allocations=(),
    )

    assessment = RiskEngine().assess(metrics, make_constraints())

    assert assessment.level is RiskLevel.LOW
    assert assessment.max_new_buy_usd == 0
    assert assessment.concentration_flags == ()
