from decimal import Decimal

from app.api.models import (
    AnalyzePortfolioRequestDTO,
    AssetAnalysisDTO,
    MarketSummaryDTO,
    PortfolioActionDTO,
    PortfolioAllocationDTO,
    PortfolioAnalysisResponseDTO,
    PortfolioSummaryDTO,
    PortfolioWarningDTO,
)
from app.domain import models as domain


def _decimal_string(value: Decimal) -> str:
    return format(value, "f")


def request_to_domain(request: AnalyzePortfolioRequestDTO) -> domain.PortfolioSnapshot:
    return domain.PortfolioSnapshot(
        id=request.snapshot_id,
        created_at=request.created_at,
        portfolio=domain.Portfolio(
            positions=tuple(
                domain.AssetPosition(symbol=position.symbol, amount=position.amount)
                for position in request.portfolio.positions
            )
        ),
        constraints=domain.TradingConstraints(
            trading_style=request.constraints.trading_style,
            risk_tolerance=request.constraints.risk_tolerance,
            leverage_allowed=request.constraints.leverage_allowed,
            additional_monthly_income_usd=(request.constraints.additional_monthly_income_usd),
            minimum_stable_reserve_usd=request.constraints.minimum_stable_reserve_usd,
        ),
        orders=tuple(
            domain.LimitOrder(
                id=order.id,
                symbol=order.symbol,
                side=order.side,
                amount_usd=order.amount_usd,
                target_price=order.target_price,
                status=order.status,
                created_at=order.created_at,
                resolved_at=order.resolved_at,
            )
            for order in request.orders
        ),
    )


def analysis_to_response(analysis: domain.PortfolioAnalysis) -> PortfolioAnalysisResponseDTO:
    return PortfolioAnalysisResponseDTO(
        analysis_id=analysis.id,
        generated_at=analysis.generated_at,
        snapshot_id=analysis.snapshot_id,
        analysis_mode=analysis.analysis_mode,
        risk_level=analysis.risk_level,
        portfolio_summary=PortfolioSummaryDTO(
            total_value_usd=_decimal_string(analysis.portfolio_summary.total_value_usd),
            stable_value_usd=_decimal_string(analysis.portfolio_summary.stable_value_usd),
            invested_value_usd=_decimal_string(analysis.portfolio_summary.invested_value_usd),
            stable_allocation_pct=_decimal_string(
                analysis.portfolio_summary.stable_allocation_percentage
            ),
            open_buy_orders_usd=_decimal_string(analysis.portfolio_summary.open_buy_orders_usd),
            open_sell_orders_usd=_decimal_string(analysis.portfolio_summary.open_sell_orders_usd),
            deployable_stable_usd=_decimal_string(analysis.portfolio_summary.deployable_stable_usd),
            allocations=[
                PortfolioAllocationDTO(
                    asset=allocation.asset,
                    value_usd=_decimal_string(allocation.value_usd),
                    allocation_pct=_decimal_string(allocation.allocation_percentage),
                )
                for allocation in analysis.portfolio_summary.allocations
            ],
        ),
        market_summary=MarketSummaryDTO(
            as_of=analysis.market_summary.as_of,
            overview=analysis.market_summary.overview,
        ),
        actions=[
            PortfolioActionDTO(
                id=action.id,
                asset=action.asset,
                type=action.type,
                side=action.side,
                price=(_decimal_string(action.price) if action.price is not None else None),
                amount_usd=(
                    _decimal_string(action.amount_usd) if action.amount_usd is not None else None
                ),
                priority=action.priority,
                reason=action.reason,
            )
            for action in analysis.actions
        ],
        asset_analysis=[
            AssetAnalysisDTO(
                asset=item.asset,
                value_usd=_decimal_string(item.value_usd),
                allocation_pct=_decimal_string(item.allocation_percentage),
                assessment=item.assessment,
                recommendation=item.recommendation,
            )
            for item in analysis.asset_analysis
        ],
        warnings=[
            PortfolioWarningDTO(
                code=warning.code,
                severity=warning.severity,
                message=warning.message,
                asset=warning.asset,
            )
            for warning in analysis.warnings
        ],
    )
