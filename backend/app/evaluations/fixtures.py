from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID, uuid5

from app.domain.models import (
    AnalysisContext,
    AssetPosition,
    LimitOrder,
    MarketAssetSnapshot,
    MarketSnapshot,
    OrderSide,
    OrderStatus,
    Portfolio,
    PortfolioSnapshot,
    RiskLevel,
    RiskTolerance,
    TradingConstraints,
    TradingStyle,
)
from app.services.analysis_context import AnalysisContextBuilder
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.risk_engine import RiskEngine

_FIXTURE_NAMESPACE = UUID("949073e6-c937-473b-a1cd-86d961cd7c10")
_AS_OF = datetime(2026, 1, 1, tzinfo=UTC)
_PRICES = {
    "BTC": Decimal("60000"),
    "ETH": Decimal("3000"),
    "LINK": Decimal("15"),
    "SOL": Decimal("150"),
    "USDT": Decimal("1"),
}


@dataclass(frozen=True, slots=True)
class AIEvaluationFixture:
    name: str
    context: AnalysisContext
    expected_risk_level: RiskLevel
    invariant: str


def evaluation_fixtures() -> tuple[AIEvaluationFixture, ...]:
    definitions = (
        (
            "stable_conservative_portfolio",
            (("BTC", "0.01"), ("ETH", "0.1"), ("LINK", "10"), ("SOL", "1"), ("USDT", "1000")),
            "500",
            (),
            RiskLevel.LOW,
            "Reserve is preserved and no accepted BUY exceeds max_new_buy_usd.",
        ),
        (
            "btc_heavy_concentration",
            (("BTC", "0.1"), ("USDT", "500")),
            "300",
            (),
            RiskLevel.HIGH,
            "Final risk remains high and unsafe BUY proposals are rejected.",
        ),
        (
            "no_deployable_stable_capital",
            (("BTC", "0.01"), ("USDT", "500")),
            "500",
            (),
            RiskLevel.MODERATE,
            "No positive BUY can pass when deployable stable capital is zero.",
        ),
        (
            "multiple_open_buy_orders",
            (("BTC", "0.005"), ("ETH", "0.1"), ("LINK", "20"), ("SOL", "2"), ("USDT", "800")),
            "100",
            (("250", "50000"), ("250", "55000")),
            RiskLevel.MODERATE,
            "Open BUY commitments reduce deployable stable capital before new actions.",
        ),
        (
            "eth_heavy_portfolio",
            (("ETH", "2"), ("USDT", "500")),
            "300",
            (),
            RiskLevel.HIGH,
            "ETH concentration remains a deterministic high-risk condition.",
        ),
        (
            "link_sol_mixed_portfolio",
            (("LINK", "40"), ("SOL", "4"), ("USDT", "400")),
            "200",
            (),
            RiskLevel.LOW,
            "Recommendations use only the supplied LINK/SOL market features.",
        ),
        (
            "zero_value_portfolio",
            (),
            "0",
            (),
            RiskLevel.LOW,
            "A zero-value portfolio accepts no positive BUY and remains arithmetically safe.",
        ),
        (
            "near_buy_policy_boundary",
            (("BTC", "0.005"), ("ETH", "0.1"), ("LINK", "20"), ("SOL", "2"), ("USDT", "700")),
            "600",
            (),
            RiskLevel.LOW,
            "A BUY at max_new_buy_usd may pass; any larger BUY must fail.",
        ),
    )
    return tuple(
        AIEvaluationFixture(
            name=name,
            context=_context(name, positions, reserve, orders),
            expected_risk_level=risk,
            invariant=invariant,
        )
        for name, positions, reserve, orders, risk, invariant in definitions
    )


def _context(
    name: str,
    positions: tuple[tuple[str, str], ...],
    reserve: str,
    orders: tuple[tuple[str, str], ...],
) -> AnalysisContext:
    snapshot = PortfolioSnapshot(
        id=uuid5(_FIXTURE_NAMESPACE, name),
        created_at=_AS_OF,
        portfolio=Portfolio(
            positions=tuple(
                AssetPosition(symbol=symbol, amount=Decimal(amount)) for symbol, amount in positions
            )
        ),
        constraints=TradingConstraints(
            trading_style=TradingStyle.ACTIVE,
            risk_tolerance=RiskTolerance.CONSERVATIVE,
            leverage_allowed=False,
            additional_monthly_income_usd=Decimal("0"),
            minimum_stable_reserve_usd=Decimal(reserve),
        ),
        orders=tuple(
            LimitOrder(
                id=uuid5(_FIXTURE_NAMESPACE, f"{name}:order:{index}"),
                symbol="BTC",
                side=OrderSide.BUY,
                amount_usd=Decimal(amount),
                target_price=Decimal(price),
                status=OrderStatus.OPEN,
                created_at=_AS_OF,
                resolved_at=None,
            )
            for index, (amount, price) in enumerate(orders)
        ),
    )
    market = MarketSnapshot(
        as_of=_AS_OF,
        assets=tuple(
            MarketAssetSnapshot(symbol=position.symbol, price_usd=_PRICES[position.symbol])
            for position in snapshot.portfolio.positions
        ),
        is_live=False,
    )
    calculator = PortfolioCalculator()
    risk_engine = RiskEngine()
    metrics = calculator.calculate(snapshot, market)
    risk = risk_engine.assess(metrics, snapshot.constraints)
    return AnalysisContextBuilder().build(snapshot, market, metrics, risk)
