import json
from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.domain.models import (
    AnalysisMode,
    AssetAnalysis,
    MarketSummary,
    OrderSide,
    PortfolioAction,
    PortfolioActionType,
    PortfolioAllocation,
    PortfolioAnalysis,
    PortfolioSummary,
    PortfolioWarning,
    RiskLevel,
    WarningSeverity,
)


class JSONPortfolioAnalysisCodec:
    """Lossless internal JSON codec; financial values are always decimal strings."""

    def encode(self, analysis: PortfolioAnalysis) -> str:
        return json.dumps(
            _to_payload(analysis),
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        )

    def decode(self, payload_json: str) -> PortfolioAnalysis:
        payload = json.loads(payload_json)
        if not isinstance(payload, dict):
            raise ValueError("Persisted analysis payload must be an object.")
        return _from_payload(payload)


def _to_payload(analysis: PortfolioAnalysis) -> dict[str, Any]:
    summary = analysis.portfolio_summary
    return {
        "analysis_id": str(analysis.id),
        "generated_at": analysis.generated_at.isoformat(),
        "snapshot_id": str(analysis.snapshot_id),
        "analysis_mode": analysis.analysis_mode.value,
        "risk_level": analysis.risk_level.value,
        "portfolio_summary": {
            "total_value_usd": _decimal(summary.total_value_usd),
            "stable_value_usd": _decimal(summary.stable_value_usd),
            "invested_value_usd": _decimal(summary.invested_value_usd),
            "stable_allocation_pct": _decimal(summary.stable_allocation_percentage),
            "open_buy_orders_usd": _decimal(summary.open_buy_orders_usd),
            "open_sell_orders_usd": _decimal(summary.open_sell_orders_usd),
            "deployable_stable_usd": _decimal(summary.deployable_stable_usd),
            "allocations": [
                {
                    "asset": allocation.asset,
                    "value_usd": _decimal(allocation.value_usd),
                    "allocation_pct": _decimal(allocation.allocation_percentage),
                }
                for allocation in summary.allocations
            ],
        },
        "market_summary": {
            "as_of": analysis.market_summary.as_of.isoformat(),
            "overview": analysis.market_summary.overview,
        },
        "actions": [
            {
                "id": str(action.id),
                "asset": action.asset,
                "type": action.type.value,
                "side": action.side.value if action.side is not None else None,
                "price": _optional_decimal(action.price),
                "amount_usd": _optional_decimal(action.amount_usd),
                "priority": action.priority,
                "reason": action.reason,
            }
            for action in analysis.actions
        ],
        "asset_analysis": [
            {
                "asset": item.asset,
                "value_usd": _decimal(item.value_usd),
                "allocation_pct": _decimal(item.allocation_percentage),
                "assessment": item.assessment,
                "recommendation": item.recommendation,
            }
            for item in analysis.asset_analysis
        ],
        "warnings": [
            {
                "code": warning.code,
                "severity": warning.severity.value,
                "message": warning.message,
                "asset": warning.asset,
            }
            for warning in analysis.warnings
        ],
    }


def _from_payload(payload: dict[str, Any]) -> PortfolioAnalysis:
    summary = _object(payload, "portfolio_summary")
    market = _object(payload, "market_summary")
    return PortfolioAnalysis(
        id=UUID(_string(payload, "analysis_id")),
        generated_at=datetime.fromisoformat(_string(payload, "generated_at")),
        snapshot_id=UUID(_string(payload, "snapshot_id")),
        analysis_mode=AnalysisMode(_string(payload, "analysis_mode")),
        risk_level=RiskLevel(_string(payload, "risk_level")),
        portfolio_summary=PortfolioSummary(
            total_value_usd=Decimal(_string(summary, "total_value_usd")),
            stable_value_usd=Decimal(_string(summary, "stable_value_usd")),
            invested_value_usd=Decimal(_string(summary, "invested_value_usd")),
            stable_allocation_percentage=Decimal(_string(summary, "stable_allocation_pct")),
            open_buy_orders_usd=Decimal(_string(summary, "open_buy_orders_usd")),
            open_sell_orders_usd=Decimal(_string(summary, "open_sell_orders_usd")),
            deployable_stable_usd=Decimal(_string(summary, "deployable_stable_usd")),
            allocations=tuple(
                PortfolioAllocation(
                    asset=_string(item, "asset"),
                    value_usd=Decimal(_string(item, "value_usd")),
                    allocation_percentage=Decimal(_string(item, "allocation_pct")),
                )
                for item in _object_list(summary, "allocations")
            ),
        ),
        market_summary=MarketSummary(
            as_of=datetime.fromisoformat(_string(market, "as_of")),
            overview=_string(market, "overview"),
        ),
        actions=tuple(_action_from_payload(item) for item in _object_list(payload, "actions")),
        asset_analysis=tuple(
            AssetAnalysis(
                asset=_string(item, "asset"),
                value_usd=Decimal(_string(item, "value_usd")),
                allocation_percentage=Decimal(_string(item, "allocation_pct")),
                assessment=_string(item, "assessment"),
                recommendation=_string(item, "recommendation"),
            )
            for item in _object_list(payload, "asset_analysis")
        ),
        warnings=tuple(
            PortfolioWarning(
                code=_string(item, "code"),
                severity=WarningSeverity(_string(item, "severity")),
                message=_string(item, "message"),
                asset=_optional_string(item, "asset"),
            )
            for item in _object_list(payload, "warnings")
        ),
    )


def _action_from_payload(payload: dict[str, Any]) -> PortfolioAction:
    side = _optional_string(payload, "side")
    return PortfolioAction(
        id=UUID(_string(payload, "id")),
        asset=_optional_string(payload, "asset"),
        type=PortfolioActionType(_string(payload, "type")),
        side=OrderSide(side) if side is not None else None,
        price=_optional_decimal_from_payload(payload, "price"),
        amount_usd=_optional_decimal_from_payload(payload, "amount_usd"),
        priority=_integer(payload, "priority"),
        reason=_string(payload, "reason"),
    )


def _object(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload[key]
    if not isinstance(value, dict):
        raise ValueError(f"{key} must be an object.")
    return value


def _object_list(payload: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = payload[key]
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValueError(f"{key} must be an object array.")
    return value


def _string(payload: dict[str, Any], key: str) -> str:
    value = payload[key]
    if not isinstance(value, str):
        raise ValueError(f"{key} must be a string.")
    return value


def _optional_string(payload: dict[str, Any], key: str) -> str | None:
    value = payload[key]
    if value is not None and not isinstance(value, str):
        raise ValueError(f"{key} must be a string or null.")
    return value


def _integer(payload: dict[str, Any], key: str) -> int:
    value = payload[key]
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{key} must be an integer.")
    return value


def _optional_decimal_from_payload(payload: dict[str, Any], key: str) -> Decimal | None:
    value = _optional_string(payload, key)
    return Decimal(value) if value is not None else None


def _decimal(value: Decimal) -> str:
    return format(value, "f")


def _optional_decimal(value: Decimal | None) -> str | None:
    return _decimal(value) if value is not None else None
