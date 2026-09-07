import asyncio
from dataclasses import replace
from decimal import Decimal
from uuid import UUID

import pytest

from app.domain.errors import IdempotencyConflictError
from app.domain.models import (
    MarketAssetSnapshot,
    MarketSnapshot,
    PortfolioActionType,
    RecommendationAction,
    RecommendationPlan,
)
from app.infrastructure.static_market_data import StaticMarketDataProvider
from app.services.analysis import DeterministicPortfolioAnalysisService
from app.services.analysis_context import AnalysisContextBuilder
from app.services.idempotency import (
    IdempotentAnalysisService,
    InProcessAnalysisIdempotencyStore,
)
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.risk_engine import RiskEngine
from tests.factories import FIXED_DATE, make_snapshot


class CountingReasoner:
    def __init__(self) -> None:
        self.calls = 0

    async def recommend(self, _context):
        self.calls += 1
        return RecommendationPlan(
            summary="Safe fixture plan.",
            actions=(
                RecommendationAction(
                    asset=None,
                    type=PortfolioActionType.HOLD,
                    side=None,
                    price=None,
                    amount_usd=None,
                    priority=1,
                    reason="Hold.",
                ),
            ),
            observations=(),
        )


class GatedReasoner(CountingReasoner):
    def __init__(self) -> None:
        super().__init__()
        self.started = asyncio.Event()
        self.release = asyncio.Event()

    async def recommend(self, context):
        self.calls += 1
        self.started.set()
        await self.release.wait()
        return await _plan_without_count(context)


async def _plan_without_count(_context):
    return RecommendationPlan(
        summary="Safe fixture plan.",
        actions=(
            RecommendationAction(
                asset=None,
                type=PortfolioActionType.HOLD,
                side=None,
                price=None,
                amount_usd=None,
                priority=1,
                reason="Hold.",
            ),
        ),
        observations=(),
    )


class ChangingMarketProvider:
    def __init__(self) -> None:
        self.calls = 0

    async def get_market_snapshot(self, _symbols: tuple[str, ...]) -> MarketSnapshot:
        self.calls += 1
        return MarketSnapshot(
            as_of=FIXED_DATE,
            assets=(
                MarketAssetSnapshot(
                    symbol="BTC",
                    price_usd=Decimal(60_000 + self.calls),
                ),
            ),
        )


def core_service(reasoner, provider=None):
    return DeterministicPortfolioAnalysisService(
        market_data_provider=provider or StaticMarketDataProvider.development(),
        portfolio_calculator=PortfolioCalculator(),
        risk_engine=RiskEngine(),
        analysis_context_builder=AnalysisContextBuilder(),
        recommendation_reasoner=reasoner,
    )


def snapshot(snapshot_id: str = "10000000-0000-0000-0000-000000000001"):
    value = make_snapshot(positions=(("BTC", Decimal("0.01")),))
    return replace(value, id=UUID(snapshot_id))


@pytest.mark.asyncio
async def test_duplicate_snapshot_reuses_completed_analysis_and_reasoning() -> None:
    reasoner = CountingReasoner()
    service = IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(),
    )
    submitted = snapshot()

    first = await service.analyze(submitted)
    second = await service.analyze(submitted)

    assert first == second
    assert reasoner.calls == 1


@pytest.mark.asyncio
async def test_concurrent_duplicate_requests_share_one_reasoning_call() -> None:
    reasoner = GatedReasoner()
    service = IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(),
    )
    submitted = snapshot()
    first_task = asyncio.create_task(service.analyze(submitted))
    await reasoner.started.wait()
    second_task = asyncio.create_task(service.analyze(submitted))
    reasoner.release.set()

    first, second = await asyncio.gather(first_task, second_task)

    assert first == second
    assert reasoner.calls == 1


@pytest.mark.asyncio
async def test_cached_analysis_preserves_original_market_context() -> None:
    reasoner = CountingReasoner()
    provider = ChangingMarketProvider()
    service = IdempotentAnalysisService(
        core_service(reasoner, provider),
        InProcessAnalysisIdempotencyStore(),
    )

    first = await service.analyze(snapshot())
    second = await service.analyze(snapshot())

    assert first.portfolio_summary == second.portfolio_summary
    assert provider.calls == 1


@pytest.mark.asyncio
async def test_cache_expiry_recomputes_predictably() -> None:
    now = [100.0]
    reasoner = CountingReasoner()
    service = IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(ttl_seconds=10, clock=lambda: now[0]),
    )

    await service.analyze(snapshot())
    now[0] = 111.0
    await service.analyze(snapshot())

    assert reasoner.calls == 2


@pytest.mark.asyncio
async def test_cache_evicts_oldest_completed_entry_at_capacity() -> None:
    reasoner = CountingReasoner()
    service = IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(max_entries=1),
    )
    first = snapshot("10000000-0000-0000-0000-000000000001")
    second = snapshot("20000000-0000-0000-0000-000000000002")

    await service.analyze(first)
    await service.analyze(second)
    await service.analyze(first)

    assert reasoner.calls == 3


@pytest.mark.asyncio
async def test_same_id_with_different_snapshot_data_is_rejected() -> None:
    reasoner = CountingReasoner()
    service = IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(),
    )
    submitted = snapshot()
    changed = replace(
        submitted,
        portfolio=replace(
            submitted.portfolio,
            positions=(replace(submitted.portfolio.positions[0], amount=Decimal("0.02")),),
        ),
    )
    await service.analyze(submitted)

    with pytest.raises(IdempotencyConflictError, match="different portfolio data"):
        await service.analyze(changed)


@pytest.mark.asyncio
async def test_new_store_recomputes_because_cache_is_process_local_only() -> None:
    reasoner = CountingReasoner()
    submitted = snapshot()

    await IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(),
    ).analyze(submitted)
    await IdempotentAnalysisService(
        core_service(reasoner),
        InProcessAnalysisIdempotencyStore(),
    ).analyze(submitted)

    assert reasoner.calls == 2
