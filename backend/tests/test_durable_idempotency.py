import asyncio
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import httpx
import pytest
from sqlalchemy import func, select

from app.config import AppSettings
from app.dependencies import ApplicationRuntime
from app.domain.errors import IdempotencyConflictError, PersistenceUnavailableError
from app.domain.models import MarketSnapshot
from app.infrastructure.analysis_codec import JSONPortfolioAnalysisCodec
from app.infrastructure.database import AnalysisResultRecord, Base, Database
from app.infrastructure.sqlalchemy_idempotency import SQLAlchemyAnalysisIdempotencyStore
from app.infrastructure.static_market_data import StaticMarketDataProvider
from app.main import create_app
from app.services.analysis import DeterministicPortfolioAnalysisService
from app.services.analysis_context import AnalysisContextBuilder
from app.services.idempotency import IdempotentAnalysisService
from app.services.portfolio_calculator import PortfolioCalculator
from app.services.recommendations import OpenAIUnavailableError
from app.services.risk_engine import RiskEngine
from tests.factories import make_snapshot
from tests.test_ai_analysis import FakeReasoner, hold_action, plan_with
from tests.test_portfolio_analysis import valid_payload


class CountingMarketProvider:
    def __init__(self) -> None:
        self.calls = 0
        self._wrapped = StaticMarketDataProvider.development()

    async def get_market_snapshot(self, symbols: tuple[str, ...]) -> MarketSnapshot:
        self.calls += 1
        return await self._wrapped.get_market_snapshot(symbols)


def _snapshot():
    return make_snapshot(
        positions=(
            ("BTC", Decimal("0.1234567890123456789012345678")),
            ("USDT", Decimal("1000.000000000000001")),
        ),
        reserve=Decimal("500.000000000000001"),
    )


def _core(provider, reasoner=None):
    return DeterministicPortfolioAnalysisService(
        market_data_provider=provider,
        portfolio_calculator=PortfolioCalculator(),
        risk_engine=RiskEngine(),
        analysis_context_builder=AnalysisContextBuilder(),
        recommendation_reasoner=reasoner,
    )


async def _database(path) -> Database:
    database = Database(f"sqlite+aiosqlite:///{path}")
    async with database.engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    return database


def _store(database: Database, now=None) -> SQLAlchemyAnalysisIdempotencyStore:
    return SQLAlchemyAnalysisIdempotencyStore(
        database,
        retention_days=1,
        lease_seconds=2,
        wait_timeout_seconds=3,
        poll_interval_seconds=0.01,
        now=now,
    )


@pytest.mark.asyncio
async def test_completed_analysis_persists_with_one_completed_record(tmp_path) -> None:
    database = await _database(tmp_path / "analysis.sqlite3")
    provider = CountingMarketProvider()

    analysis = await IdempotentAnalysisService(_core(provider), _store(database)).analyze(
        _snapshot()
    )

    async with database.session() as session:
        record = await session.get(AnalysisResultRecord, str(_snapshot().id))
        completed_count = await session.scalar(
            select(func.count())
            .select_from(AnalysisResultRecord)
            .where(AnalysisResultRecord.state == "completed")
        )
    assert record is not None
    assert record.analysis_id == str(analysis.id)
    assert record.payload_json is not None
    assert completed_count == 1
    await database.dispose()


@pytest.mark.asyncio
async def test_decimal_strings_round_trip_exactly_through_persisted_payload(tmp_path) -> None:
    database = await _database(tmp_path / "decimal.sqlite3")
    analysis = await IdempotentAnalysisService(
        _core(CountingMarketProvider()),
        _store(database),
    ).analyze(_snapshot())

    restored = JSONPortfolioAnalysisCodec().decode(JSONPortfolioAnalysisCodec().encode(analysis))

    assert restored == analysis
    assert restored.portfolio_summary.allocations[0].value_usd == Decimal(
        "7407.4073407407407340740740680000"
    )
    await database.dispose()


@pytest.mark.asyncio
async def test_store_recreation_returns_original_without_dependencies(tmp_path) -> None:
    path = tmp_path / "restart.sqlite3"
    first_database = await _database(path)
    first_provider = CountingMarketProvider()
    first_reasoner = FakeReasoner(plan_with(hold_action()))
    first = await IdempotentAnalysisService(
        _core(first_provider, first_reasoner),
        _store(first_database),
    ).analyze(_snapshot())
    await first_database.dispose()

    second_database = Database(f"sqlite+aiosqlite:///{path}")
    second_provider = CountingMarketProvider()
    second_reasoner = FakeReasoner(plan_with(hold_action()))
    second = await IdempotentAnalysisService(
        _core(second_provider, second_reasoner),
        _store(second_database),
    ).analyze(_snapshot())

    assert second == first
    assert first_provider.calls == 1
    assert first_reasoner.calls == 1
    assert second_provider.calls == 0
    assert second_reasoner.calls == 0
    await second_database.dispose()


@pytest.mark.asyncio
async def test_same_snapshot_id_with_different_fingerprint_conflicts(tmp_path) -> None:
    database = await _database(tmp_path / "conflict.sqlite3")
    service = IdempotentAnalysisService(_core(CountingMarketProvider()), _store(database))
    original = _snapshot()
    changed = replace(
        original,
        portfolio=replace(
            original.portfolio,
            positions=(replace(original.portfolio.positions[0], amount=Decimal("1")),),
        ),
    )
    await service.analyze(original)

    with pytest.raises(IdempotencyConflictError):
        await service.analyze(changed)
    await database.dispose()


@pytest.mark.asyncio
async def test_expired_completed_result_is_recomputed_and_cleanup_is_bounded(tmp_path) -> None:
    current = [datetime(2026, 9, 5, tzinfo=UTC)]
    database = await _database(tmp_path / "expiry.sqlite3")
    provider = CountingMarketProvider()
    store = _store(database, now=lambda: current[0])
    service = IdempotentAnalysisService(_core(provider), store)
    await service.analyze(_snapshot())
    current[0] += timedelta(days=2)

    removed = await store.cleanup_expired()
    await service.analyze(_snapshot())

    assert removed == 1
    assert provider.calls == 2
    await database.dispose()


@pytest.mark.asyncio
async def test_two_store_instances_coordinate_one_expensive_analysis(tmp_path) -> None:
    path = tmp_path / "concurrent.sqlite3"
    database_one = await _database(path)
    database_two = Database(f"sqlite+aiosqlite:///{path}")
    provider = CountingMarketProvider()
    reasoner = FakeReasoner(plan_with(hold_action()))
    service_one = IdempotentAnalysisService(_core(provider, reasoner), _store(database_one))
    service_two = IdempotentAnalysisService(_core(provider, reasoner), _store(database_two))

    first, second = await asyncio.gather(
        service_one.analyze(_snapshot()),
        service_two.analyze(_snapshot()),
    )

    assert first == second
    assert provider.calls == 1
    assert reasoner.calls == 1
    await database_one.dispose()
    await database_two.dispose()


@pytest.mark.asyncio
async def test_database_unavailable_prevents_expensive_analysis(tmp_path) -> None:
    unavailable = Database(f"sqlite+aiosqlite:///{tmp_path / 'missing' / 'db.sqlite3'}")
    provider = CountingMarketProvider()
    service = IdempotentAnalysisService(_core(provider), _store(unavailable))

    with pytest.raises(PersistenceUnavailableError):
        await service.analyze(_snapshot())

    assert provider.calls == 0
    await unavailable.dispose()


@pytest.mark.asyncio
async def test_lost_response_retry_reuses_ai_fallback_result(tmp_path) -> None:
    path = tmp_path / "lost-response.sqlite3"
    first_database = await _database(path)
    provider = CountingMarketProvider()
    reasoner = FakeReasoner(error=OpenAIUnavailableError("simulated outage"))
    original = await IdempotentAnalysisService(
        _core(provider, reasoner),
        _store(first_database),
    ).analyze(_snapshot())
    await first_database.dispose()  # The completed response is treated as lost here.

    retry_database = Database(f"sqlite+aiosqlite:///{path}")
    retry_provider = CountingMarketProvider()
    retry_reasoner = FakeReasoner(plan_with(hold_action()))
    retried = await IdempotentAnalysisService(
        _core(retry_provider, retry_reasoner),
        _store(retry_database),
    ).analyze(_snapshot())

    assert retried == original
    assert retried.analysis_mode.value == "ai_fallback"
    assert provider.calls == 1
    assert reasoner.calls == 1
    assert retry_provider.calls == 0
    assert retry_reasoner.calls == 0
    await retry_database.dispose()


@pytest.mark.asyncio
async def test_http_pipeline_retry_after_runtime_recreation_returns_same_response(
    tmp_path,
) -> None:
    path = tmp_path / "integration.sqlite3"
    settings = AppSettings.from_environment(
        {
            "APP_ENV": "test",
            "ANALYSIS_IDEMPOTENCY_MODE": "database",
            "DATABASE_URL": f"sqlite+aiosqlite:///{path}",
        }
    )
    payload = valid_payload()

    first_database = await _database(path)
    first_provider = CountingMarketProvider()
    first_reasoner = FakeReasoner(plan_with(hold_action()))
    first_store = _store(first_database)
    first_runtime = ApplicationRuntime(
        settings=settings,
        analysis_service=IdempotentAnalysisService(
            _core(first_provider, first_reasoner),
            first_store,
        ),
        idempotency_store=first_store,
        database=first_database,
    )
    first_app = create_app(settings, first_runtime)
    first_transport = httpx.ASGITransport(app=first_app)
    async with httpx.AsyncClient(
        transport=first_transport,
        base_url="http://test",
    ) as client:
        first_response = await client.post("/v1/portfolio/analyze", json=payload)
    await first_runtime.close()

    retry_database = Database(f"sqlite+aiosqlite:///{path}")
    retry_provider = CountingMarketProvider()
    retry_reasoner = FakeReasoner(plan_with(hold_action()))
    retry_store = _store(retry_database)
    retry_runtime = ApplicationRuntime(
        settings=settings,
        analysis_service=IdempotentAnalysisService(
            _core(retry_provider, retry_reasoner),
            retry_store,
        ),
        idempotency_store=retry_store,
        database=retry_database,
    )
    retry_app = create_app(settings, retry_runtime)
    retry_transport = httpx.ASGITransport(app=retry_app)
    async with httpx.AsyncClient(
        transport=retry_transport,
        base_url="http://test",
    ) as client:
        retry_response = await client.post("/v1/portfolio/analyze", json=payload)

    assert first_response.status_code == 200
    assert retry_response.status_code == 200
    assert retry_response.json() == first_response.json()
    assert first_provider.calls == 1
    assert first_reasoner.calls == 1
    assert retry_provider.calls == 0
    assert retry_reasoner.calls == 0
    await retry_runtime.close()
