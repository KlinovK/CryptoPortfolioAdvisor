import asyncio
import json
from collections import OrderedDict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from hashlib import sha256
from time import monotonic
from typing import Protocol
from uuid import UUID

from app.domain.errors import IdempotencyConflictError
from app.domain.models import PortfolioAnalysis, PortfolioSnapshot
from app.observability import get_logger, log_event
from app.services.analysis import AnalysisService

logger = get_logger("idempotency")


class AnalysisIdempotencyStore(Protocol):
    """Coordinates result reuse before and after an analysis operation."""

    async def get_or_compute(
        self,
        snapshot: PortfolioSnapshot,
        operation: Callable[[], Awaitable[PortfolioAnalysis]],
    ) -> PortfolioAnalysis: ...

    async def is_ready(self) -> bool: ...

    async def cleanup_expired(self) -> int: ...


@dataclass(frozen=True, slots=True)
class _CacheEntry:
    fingerprint: str
    analysis: PortfolioAnalysis
    expires_at: float


@dataclass(frozen=True, slots=True)
class _InFlightEntry:
    fingerprint: str
    task: asyncio.Task[PortfolioAnalysis]


class InProcessAnalysisIdempotencyStore:
    """Bounded process-local result reuse; no durability is implied."""

    def __init__(
        self,
        *,
        ttl_seconds: float = 3_600,
        max_entries: int = 256,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        if ttl_seconds <= 0 or max_entries <= 0:
            raise ValueError("Idempotency TTL and capacity must be positive.")
        self._ttl_seconds = ttl_seconds
        self._max_entries = max_entries
        self._clock = clock
        self._completed: OrderedDict[UUID, _CacheEntry] = OrderedDict()
        self._in_flight: dict[UUID, _InFlightEntry] = {}
        self._lock = asyncio.Lock()

    async def get_or_compute(
        self,
        snapshot: PortfolioSnapshot,
        operation: Callable[[], Awaitable[PortfolioAnalysis]],
    ) -> PortfolioAnalysis:
        fingerprint = snapshot_fingerprint(snapshot)
        async with self._lock:
            self._prune_expired()
            cached = self._completed.get(snapshot.id)
            if cached is not None:
                self._ensure_matching_fingerprint(cached.fingerprint, fingerprint)
                self._completed.move_to_end(snapshot.id)
                log_event(logger, "idempotency_lookup", idempotency_outcome="completed_hit")
                return cached.analysis

            in_flight = self._in_flight.get(snapshot.id)
            if in_flight is not None:
                self._ensure_matching_fingerprint(in_flight.fingerprint, fingerprint)
                task = in_flight.task
                log_event(logger, "idempotency_lookup", idempotency_outcome="in_flight_hit")
            else:
                task = asyncio.create_task(operation())
                self._in_flight[snapshot.id] = _InFlightEntry(
                    fingerprint=fingerprint,
                    task=task,
                )
                log_event(logger, "idempotency_lookup", idempotency_outcome="miss")

        try:
            analysis = await asyncio.shield(task)
        except asyncio.CancelledError:
            raise
        except BaseException:
            async with self._lock:
                current = self._in_flight.get(snapshot.id)
                if current is not None and current.task is task:
                    self._in_flight.pop(snapshot.id, None)
            raise

        async with self._lock:
            current = self._in_flight.get(snapshot.id)
            if current is not None and current.task is task:
                self._in_flight.pop(snapshot.id, None)
            self._completed[snapshot.id] = _CacheEntry(
                fingerprint=fingerprint,
                analysis=analysis,
                expires_at=self._clock() + self._ttl_seconds,
            )
            self._completed.move_to_end(snapshot.id)
            while len(self._completed) > self._max_entries:
                self._completed.popitem(last=False)
        return analysis

    async def is_ready(self) -> bool:
        return True

    async def cleanup_expired(self) -> int:
        async with self._lock:
            return self._prune_expired()

    def _prune_expired(self) -> int:
        now = self._clock()
        expired = [key for key, entry in self._completed.items() if entry.expires_at <= now]
        for key in expired:
            self._completed.pop(key, None)
        return len(expired)

    @staticmethod
    def _ensure_matching_fingerprint(existing: str, received: str) -> None:
        if existing != received:
            log_event(logger, "idempotency_lookup", idempotency_outcome="conflict")
            raise IdempotencyConflictError()


class IdempotentAnalysisService:
    def __init__(
        self,
        wrapped: AnalysisService,
        store: AnalysisIdempotencyStore,
    ) -> None:
        self._wrapped = wrapped
        self._store = store

    async def analyze(self, snapshot: PortfolioSnapshot) -> PortfolioAnalysis:
        return await self._store.get_or_compute(
            snapshot,
            lambda: self._wrapped.analyze(snapshot),
        )


def snapshot_fingerprint(snapshot: PortfolioSnapshot) -> str:
    payload = {
        "id": str(snapshot.id),
        "created_at": snapshot.created_at.isoformat(),
        "portfolio": [
            {"symbol": position.symbol, "amount": format(position.amount, "f")}
            for position in snapshot.portfolio.positions
        ],
        "constraints": {
            "trading_style": snapshot.constraints.trading_style.value,
            "risk_tolerance": snapshot.constraints.risk_tolerance.value,
            "leverage_allowed": snapshot.constraints.leverage_allowed,
            "additional_monthly_income_usd": format(
                snapshot.constraints.additional_monthly_income_usd,
                "f",
            ),
            "minimum_stable_reserve_usd": format(
                snapshot.constraints.minimum_stable_reserve_usd,
                "f",
            ),
        },
        "orders": [
            {
                "id": str(order.id),
                "symbol": order.symbol,
                "side": order.side.value,
                "amount_usd": format(order.amount_usd, "f"),
                "target_price": format(order.target_price, "f"),
                "status": order.status.value,
                "created_at": order.created_at.isoformat(),
                "resolved_at": order.resolved_at.isoformat() if order.resolved_at else None,
            }
            for order in snapshot.orders
        ],
    }
    canonical_json = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return sha256(canonical_json.encode("utf-8")).hexdigest()
