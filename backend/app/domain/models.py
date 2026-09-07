from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from uuid import UUID


class TradingStyle(StrEnum):
    ACTIVE = "active"


class RiskTolerance(StrEnum):
    CONSERVATIVE = "conservative"
    MODERATE = "moderate"
    AGGRESSIVE = "aggressive"


class OrderSide(StrEnum):
    BUY = "buy"
    SELL = "sell"


class OrderStatus(StrEnum):
    OPEN = "open"
    FILLED = "filled"
    CANCELLED = "cancelled"


class RiskLevel(StrEnum):
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"


class AnalysisMode(StrEnum):
    DETERMINISTIC = "deterministic"
    AI_ASSISTED = "ai_assisted"
    AI_FALLBACK = "ai_fallback"


class PortfolioActionType(StrEnum):
    BUY = "buy"
    SELL = "sell"
    HOLD = "hold"
    MONITOR = "monitor"
    WAIT = "wait"
    PLACE_LIMIT_ORDER = "place_limit_order"
    KEEP_LIMIT_ORDER = "keep_limit_order"
    CANCEL_LIMIT_ORDER = "cancel_limit_order"
    REBALANCE = "rebalance"


class WarningSeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


@dataclass(frozen=True, slots=True)
class MarketAssetSnapshot:
    symbol: str
    price_usd: Decimal
    change_24h_pct: Decimal | None = None
    change_7d_pct: Decimal | None = None
    rsi_4h: Decimal | None = None
    ema20_4h: Decimal | None = None
    ema50_4h: Decimal | None = None
    atr_4h: Decimal | None = None
    support: Decimal | None = None
    resistance: Decimal | None = None


@dataclass(frozen=True, slots=True)
class MarketSnapshot:
    as_of: datetime
    assets: tuple[MarketAssetSnapshot, ...]
    is_live: bool = False


@dataclass(frozen=True, slots=True)
class AssetPosition:
    symbol: str
    amount: Decimal


@dataclass(frozen=True, slots=True)
class Portfolio:
    positions: tuple[AssetPosition, ...]


@dataclass(frozen=True, slots=True)
class TradingConstraints:
    trading_style: TradingStyle
    risk_tolerance: RiskTolerance
    leverage_allowed: bool
    additional_monthly_income_usd: Decimal
    minimum_stable_reserve_usd: Decimal


@dataclass(frozen=True, slots=True)
class LimitOrder:
    id: UUID
    symbol: str
    side: OrderSide
    amount_usd: Decimal
    target_price: Decimal
    status: OrderStatus
    created_at: datetime
    resolved_at: datetime | None


@dataclass(frozen=True, slots=True)
class PortfolioSnapshot:
    id: UUID
    created_at: datetime
    portfolio: Portfolio
    constraints: TradingConstraints
    orders: tuple[LimitOrder, ...]


@dataclass(frozen=True, slots=True)
class PortfolioAllocation:
    asset: str
    value_usd: Decimal
    allocation_percentage: Decimal


@dataclass(frozen=True, slots=True)
class PortfolioSummary:
    total_value_usd: Decimal
    stable_value_usd: Decimal
    invested_value_usd: Decimal
    stable_allocation_percentage: Decimal
    open_buy_orders_usd: Decimal
    open_sell_orders_usd: Decimal
    deployable_stable_usd: Decimal
    allocations: tuple[PortfolioAllocation, ...]


@dataclass(frozen=True, slots=True)
class PortfolioMetrics:
    total_value_usd: Decimal
    stable_value_usd: Decimal
    invested_value_usd: Decimal
    stable_allocation_percentage: Decimal
    open_buy_orders_usd: Decimal
    open_sell_orders_usd: Decimal
    deployable_stable_usd: Decimal
    allocations: tuple[PortfolioAllocation, ...]
    largest_asset: str | None
    largest_asset_allocation_percentage: Decimal


@dataclass(frozen=True, slots=True)
class MarketSummary:
    as_of: datetime
    overview: str


@dataclass(frozen=True, slots=True)
class PortfolioAction:
    id: UUID
    asset: str | None
    type: PortfolioActionType
    side: OrderSide | None
    price: Decimal | None
    amount_usd: Decimal | None
    priority: int
    reason: str


@dataclass(frozen=True, slots=True)
class ProposedAction:
    id: UUID
    asset: str | None
    type: PortfolioActionType
    side: OrderSide | None
    price: Decimal | None
    amount_usd: Decimal | None
    priority: int
    reason: str
    requires_leverage: bool = False


@dataclass(frozen=True, slots=True)
class RecommendationAction:
    asset: str | None
    type: PortfolioActionType
    side: OrderSide | None
    price: Decimal | None
    amount_usd: Decimal | None
    priority: int
    reason: str
    requires_leverage: bool = False


@dataclass(frozen=True, slots=True)
class RecommendationPlan:
    summary: str
    actions: tuple[RecommendationAction, ...]
    observations: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ConcentrationFlag:
    asset: str
    allocation_percentage: Decimal


@dataclass(frozen=True, slots=True)
class RiskAssessment:
    level: RiskLevel
    warnings: tuple["PortfolioWarning", ...]
    max_new_buy_usd: Decimal
    deployable_stable_usd: Decimal
    concentration_flags: tuple[ConcentrationFlag, ...]


@dataclass(frozen=True, slots=True)
class AnalysisMarketFeature:
    symbol: str
    price_usd: Decimal
    change_24h_pct: Decimal | None
    change_7d_pct: Decimal | None
    rsi_4h: Decimal | None
    ema20_4h: Decimal | None
    ema50_4h: Decimal | None
    atr_4h: Decimal | None
    support: Decimal | None
    resistance: Decimal | None
    portfolio_allocation_percentage: Decimal


@dataclass(frozen=True, slots=True)
class AnalysisPortfolioMetrics:
    total_value_usd: Decimal
    stable_value_usd: Decimal
    invested_value_usd: Decimal
    stable_allocation_percentage: Decimal
    open_buy_orders_usd: Decimal
    open_sell_orders_usd: Decimal
    deployable_stable_usd: Decimal


@dataclass(frozen=True, slots=True)
class AnalysisContext:
    portfolio_metrics: AnalysisPortfolioMetrics
    constraints: TradingConstraints
    orders: tuple[LimitOrder, ...]
    risk_assessment: RiskAssessment
    market_features: tuple[AnalysisMarketFeature, ...]


@dataclass(frozen=True, slots=True)
class AssetAnalysis:
    asset: str
    value_usd: Decimal
    allocation_percentage: Decimal
    assessment: str
    recommendation: str


@dataclass(frozen=True, slots=True)
class PortfolioWarning:
    code: str
    severity: WarningSeverity
    message: str
    asset: str | None


@dataclass(frozen=True, slots=True)
class PortfolioAnalysis:
    id: UUID
    generated_at: datetime
    snapshot_id: UUID
    analysis_mode: AnalysisMode
    risk_level: RiskLevel
    portfolio_summary: PortfolioSummary
    market_summary: MarketSummary
    actions: tuple[PortfolioAction, ...]
    asset_analysis: tuple[AssetAnalysis, ...]
    warnings: tuple[PortfolioWarning, ...]
