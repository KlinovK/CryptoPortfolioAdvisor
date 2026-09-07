from decimal import Decimal

from app.domain.models import (
    AnalysisContext,
    AnalysisMarketFeature,
    AnalysisPortfolioMetrics,
    MarketSnapshot,
    PortfolioMetrics,
    PortfolioSnapshot,
    RiskAssessment,
)


class AnalysisContextBuilder:
    """Builds the compact deterministic context reserved for future AI reasoning."""

    def build(
        self,
        snapshot: PortfolioSnapshot,
        market_snapshot: MarketSnapshot,
        metrics: PortfolioMetrics,
        risk_assessment: RiskAssessment,
    ) -> AnalysisContext:
        allocations = {
            allocation.asset: allocation.allocation_percentage for allocation in metrics.allocations
        }
        return AnalysisContext(
            portfolio_metrics=AnalysisPortfolioMetrics(
                total_value_usd=metrics.total_value_usd,
                stable_value_usd=metrics.stable_value_usd,
                invested_value_usd=metrics.invested_value_usd,
                stable_allocation_percentage=metrics.stable_allocation_percentage,
                open_buy_orders_usd=metrics.open_buy_orders_usd,
                open_sell_orders_usd=metrics.open_sell_orders_usd,
                deployable_stable_usd=metrics.deployable_stable_usd,
            ),
            constraints=snapshot.constraints,
            orders=snapshot.orders,
            risk_assessment=risk_assessment,
            market_features=tuple(
                AnalysisMarketFeature(
                    symbol=asset.symbol,
                    price_usd=asset.price_usd,
                    change_24h_pct=asset.change_24h_pct,
                    change_7d_pct=asset.change_7d_pct,
                    rsi_4h=asset.rsi_4h,
                    ema20_4h=asset.ema20_4h,
                    ema50_4h=asset.ema50_4h,
                    atr_4h=asset.atr_4h,
                    support=asset.support,
                    resistance=asset.resistance,
                    portfolio_allocation_percentage=allocations.get(
                        asset.symbol,
                        Decimal("0"),
                    ),
                )
                for asset in market_snapshot.assets
            ),
        )
