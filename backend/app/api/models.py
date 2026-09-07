from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Annotated
from uuid import UUID

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    PlainSerializer,
    WithJsonSchema,
)

from app.domain.models import (
    AnalysisMode,
    OrderSide,
    OrderStatus,
    PortfolioActionType,
    RiskLevel,
    RiskTolerance,
    TradingStyle,
    WarningSeverity,
)


def _parse_decimal_string(value: object) -> Decimal:
    if not isinstance(value, str):
        raise ValueError("Financial values must be decimal strings.")
    try:
        decimal = Decimal(value)
    except InvalidOperation as error:
        raise ValueError("Invalid decimal string.") from error
    if not decimal.is_finite():
        raise ValueError("Financial values must be finite.")
    return decimal


def _serialize_decimal(value: Decimal) -> str:
    return format(value, "f")


DecimalString = Annotated[
    Decimal,
    BeforeValidator(_parse_decimal_string),
    PlainSerializer(_serialize_decimal, return_type=str, when_used="json"),
    WithJsonSchema(
        {
            "type": "string",
            "pattern": r"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$",
        }
    ),
]
AssetSymbol = Annotated[str, Field(pattern=r"^[A-Z0-9][A-Z0-9._-]{0,19}$")]


class APIModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AssetPositionDTO(APIModel):
    symbol: AssetSymbol
    amount: DecimalString


class PortfolioDTO(APIModel):
    positions: list[AssetPositionDTO]


class TradingConstraintsDTO(APIModel):
    trading_style: TradingStyle
    risk_tolerance: RiskTolerance
    leverage_allowed: bool
    additional_monthly_income_usd: DecimalString
    minimum_stable_reserve_usd: DecimalString


class LimitOrderDTO(APIModel):
    id: UUID
    symbol: AssetSymbol
    side: OrderSide
    amount_usd: DecimalString
    target_price: DecimalString
    status: OrderStatus
    created_at: datetime
    resolved_at: datetime | None


class AnalyzePortfolioRequestDTO(APIModel):
    snapshot_id: UUID
    created_at: datetime
    portfolio: PortfolioDTO
    constraints: TradingConstraintsDTO
    orders: list[LimitOrderDTO]


class PortfolioAllocationDTO(APIModel):
    asset: AssetSymbol
    value_usd: DecimalString
    allocation_pct: DecimalString


class PortfolioSummaryDTO(APIModel):
    total_value_usd: DecimalString
    stable_value_usd: DecimalString
    invested_value_usd: DecimalString
    stable_allocation_pct: DecimalString
    open_buy_orders_usd: DecimalString
    open_sell_orders_usd: DecimalString
    deployable_stable_usd: DecimalString
    allocations: list[PortfolioAllocationDTO]


class MarketSummaryDTO(APIModel):
    as_of: datetime
    overview: str


class PortfolioActionDTO(APIModel):
    id: UUID
    asset: AssetSymbol | None
    type: PortfolioActionType
    side: OrderSide | None
    price: DecimalString | None
    amount_usd: DecimalString | None
    priority: int
    reason: str


class AssetAnalysisDTO(APIModel):
    asset: AssetSymbol
    value_usd: DecimalString
    allocation_pct: DecimalString
    assessment: str
    recommendation: str


class PortfolioWarningDTO(APIModel):
    code: str
    severity: WarningSeverity
    message: str
    asset: AssetSymbol | None


class PortfolioAnalysisResponseDTO(APIModel):
    analysis_id: UUID
    generated_at: datetime
    snapshot_id: UUID
    analysis_mode: AnalysisMode
    risk_level: RiskLevel
    portfolio_summary: PortfolioSummaryDTO
    market_summary: MarketSummaryDTO
    actions: list[PortfolioActionDTO]
    asset_analysis: list[AssetAnalysisDTO]
    warnings: list[PortfolioWarningDTO]


class ErrorDetailDTO(APIModel):
    code: str
    message: str


class ErrorResponseDTO(APIModel):
    error: ErrorDetailDTO
