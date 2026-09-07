from decimal import Decimal, localcontext

from app.domain.errors import PortfolioCalculationError
from app.domain.models import (
    MarketSnapshot,
    OrderSide,
    OrderStatus,
    PortfolioAllocation,
    PortfolioMetrics,
    PortfolioSnapshot,
)

DEFAULT_STABLECOIN_SYMBOLS = frozenset({"USDT", "USDC"})


class PortfolioCalculator:
    def __init__(self, stablecoin_symbols: frozenset[str] = DEFAULT_STABLECOIN_SYMBOLS) -> None:
        self._stablecoin_symbols = stablecoin_symbols

    def calculate(
        self,
        snapshot: PortfolioSnapshot,
        market_snapshot: MarketSnapshot,
    ) -> PortfolioMetrics:
        market_by_symbol = {asset.symbol: asset for asset in market_snapshot.assets}
        if len(market_by_symbol) != len(market_snapshot.assets):
            raise PortfolioCalculationError("Market snapshot contains duplicate asset symbols.")

        with localcontext() as context:
            context.prec = 38
            values: list[tuple[str, Decimal]] = []
            for position in snapshot.portfolio.positions:
                market_asset = market_by_symbol.get(position.symbol)
                if market_asset is None:
                    raise PortfolioCalculationError(
                        f"Market price is unavailable for {position.symbol}."
                    )
                if market_asset.price_usd <= 0:
                    raise PortfolioCalculationError(
                        f"Market price must be greater than zero for {position.symbol}."
                    )
                values.append((position.symbol, position.amount * market_asset.price_usd))

            total_value = sum((value for _, value in values), Decimal("0"))
            stable_value = sum(
                (value for symbol, value in values if symbol in self._stablecoin_symbols),
                Decimal("0"),
            )
            invested_value = total_value - stable_value
            allocations = tuple(
                PortfolioAllocation(
                    asset=symbol,
                    value_usd=value,
                    allocation_percentage=(
                        value * Decimal("100") / total_value if total_value > 0 else Decimal("0")
                    ),
                )
                for symbol, value in values
            )
            stable_allocation = (
                stable_value * Decimal("100") / total_value if total_value > 0 else Decimal("0")
            )
            open_buy_orders = sum(
                (
                    order.amount_usd
                    for order in snapshot.orders
                    if order.status is OrderStatus.OPEN and order.side is OrderSide.BUY
                ),
                Decimal("0"),
            )
            open_sell_orders = sum(
                (
                    order.amount_usd
                    for order in snapshot.orders
                    if order.status is OrderStatus.OPEN and order.side is OrderSide.SELL
                ),
                Decimal("0"),
            )
            deployable = max(
                stable_value - snapshot.constraints.minimum_stable_reserve_usd - open_buy_orders,
                Decimal("0"),
            )

        largest = max(
            allocations,
            key=lambda allocation: allocation.allocation_percentage,
            default=None,
        )
        return PortfolioMetrics(
            total_value_usd=total_value,
            stable_value_usd=stable_value,
            invested_value_usd=invested_value,
            stable_allocation_percentage=stable_allocation,
            open_buy_orders_usd=open_buy_orders,
            open_sell_orders_usd=open_sell_orders,
            deployable_stable_usd=deployable,
            allocations=allocations,
            largest_asset=largest.asset if largest is not None else None,
            largest_asset_allocation_percentage=(
                largest.allocation_percentage if largest is not None else Decimal("0")
            ),
        )
