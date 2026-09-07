import json
from decimal import Decimal

from app.domain.models import AnalysisContext


class AnalysisContextSerializer:
    """Maps only reviewed, compact fields into the OpenAI data boundary."""

    def to_dict(self, context: AnalysisContext) -> dict[str, object]:
        metrics = context.portfolio_metrics
        constraints = context.constraints
        risk = context.risk_assessment
        return {
            "portfolio": {
                "total_value_usd": _decimal(metrics.total_value_usd),
                "stable_value_usd": _decimal(metrics.stable_value_usd),
                "invested_value_usd": _decimal(metrics.invested_value_usd),
                "stable_allocation_pct": _decimal(metrics.stable_allocation_percentage),
                "open_buy_orders_usd": _decimal(metrics.open_buy_orders_usd),
                "open_sell_orders_usd": _decimal(metrics.open_sell_orders_usd),
                "deployable_stable_usd": _decimal(metrics.deployable_stable_usd),
                "allocations": [
                    {
                        "asset": feature.symbol,
                        "allocation_pct": _decimal(feature.portfolio_allocation_percentage),
                    }
                    for feature in context.market_features
                ],
            },
            "constraints": {
                "trading_style": constraints.trading_style.value,
                "risk_tolerance": constraints.risk_tolerance.value,
                "leverage_allowed": constraints.leverage_allowed,
                "minimum_stable_reserve_usd": _decimal(constraints.minimum_stable_reserve_usd),
                "additional_monthly_income_usd": _decimal(
                    constraints.additional_monthly_income_usd
                ),
            },
            "orders": [
                {
                    "asset": order.symbol,
                    "side": order.side.value,
                    "amount_usd": _decimal(order.amount_usd),
                    "price": _decimal(order.target_price),
                    "status": order.status.value,
                }
                for order in context.orders
            ],
            "risk": {
                "level": risk.level.value,
                "max_new_buy_usd": _decimal(risk.max_new_buy_usd),
                "deployable_stable_usd": _decimal(risk.deployable_stable_usd),
                "warnings": [
                    {
                        "code": warning.code,
                        "severity": warning.severity.value,
                        "message": warning.message,
                        "asset": warning.asset,
                    }
                    for warning in risk.warnings
                ],
                "concentration_flags": [
                    {
                        "asset": flag.asset,
                        "allocation_pct": _decimal(flag.allocation_percentage),
                    }
                    for flag in risk.concentration_flags
                ],
            },
            "market_features": [
                {
                    "asset": feature.symbol,
                    "price_usd": _decimal(feature.price_usd),
                    "change_24h_pct": _optional_decimal(feature.change_24h_pct),
                    "change_7d_pct": _optional_decimal(feature.change_7d_pct),
                    "rsi_4h": _optional_decimal(feature.rsi_4h),
                    "ema20_4h": _optional_decimal(feature.ema20_4h),
                    "ema50_4h": _optional_decimal(feature.ema50_4h),
                    "atr_4h": _optional_decimal(feature.atr_4h),
                    "support": _optional_decimal(feature.support),
                    "resistance": _optional_decimal(feature.resistance),
                    "allocation_pct": _decimal(feature.portfolio_allocation_percentage),
                }
                for feature in context.market_features
            ],
        }

    def serialize(self, context: AnalysisContext) -> str:
        return json.dumps(
            self.to_dict(context),
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        )


def _decimal(value: Decimal) -> str:
    return format(value, "f")


def _optional_decimal(value: Decimal | None) -> str | None:
    return _decimal(value) if value is not None else None
