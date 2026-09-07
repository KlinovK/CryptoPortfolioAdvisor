import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from time import monotonic
from uuid import UUID, uuid4

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from app.domain.errors import (
    AnalysisTimeoutError,
    IdempotencyConflictError,
    PersistenceUnavailableError,
)
from app.domain.models import PortfolioAnalysis, PortfolioSnapshot
from app.infrastructure.analysis_codec import JSONPortfolioAnalysisCodec
from app.infrastructure.database import AnalysisResultRecord, Database
from app.observability import get_logger, log_event
from app.services.idempotency import snapshot_fingerprint

logger = get_logger("durable_idempotency")


class ReservationStatus(StrEnum):
    ACQUIRED = "acquired"
    PENDING = "pending"
    COMPLETED = "completed"


@dataclass(frozen=True, slots=True)
class AnalysisReservation:
    status: ReservationStatus
    analysis: PortfolioAnalysis | None = None


class SQLAlchemyAnalysisIdempotencyStore:
    """Durable result reuse with a database-backed pending lease."""

    def __init__(
        self,
        database: Database,
        *,
        retention_days: int,
        lease_seconds: float,
        wait_timeout_seconds: float,
        poll_interval_seconds: float = 0.1,
        codec: JSONPortfolioAnalysisCodec | None = None,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        self._database = database
        self._retention = timedelta(days=retention_days)
        self._lease = timedelta(seconds=lease_seconds)
        self._wait_timeout_seconds = wait_timeout_seconds
        self._poll_interval_seconds = poll_interval_seconds
        self._codec = codec or JSONPortfolioAnalysisCodec()
        self._now = now or (lambda: datetime.now(UTC))

    async def get_or_compute(
        self,
        snapshot: PortfolioSnapshot,
        operation: Callable[[], Awaitable[PortfolioAnalysis]],
    ) -> PortfolioAnalysis:
        fingerprint = snapshot_fingerprint(snapshot)
        owner_token = str(uuid4())
        deadline = monotonic() + self._wait_timeout_seconds

        while True:
            reservation = await self.reserve(snapshot.id, fingerprint, owner_token)
            if reservation.status is ReservationStatus.COMPLETED:
                log_event(logger, "idempotency_lookup", idempotency_outcome="completed_hit")
                if reservation.analysis is None:
                    raise PersistenceUnavailableError()
                return reservation.analysis

            if reservation.status is ReservationStatus.ACQUIRED:
                log_event(logger, "idempotency_lookup", idempotency_outcome="miss")
                try:
                    analysis = await operation()
                except BaseException as error:
                    await self.mark_failed(snapshot.id, fingerprint, owner_token, error)
                    raise
                await self.store_completed(snapshot.id, fingerprint, owner_token, analysis)
                return analysis

            log_event(logger, "idempotency_lookup", idempotency_outcome="in_flight_hit")
            remaining = deadline - monotonic()
            if remaining <= 0:
                raise AnalysisTimeoutError()
            await asyncio.sleep(min(self._poll_interval_seconds, remaining))

    async def reserve(
        self,
        snapshot_id: UUID,
        fingerprint: str,
        owner_token: str,
    ) -> AnalysisReservation:
        try:
            return await self._reserve_once(snapshot_id, fingerprint, owner_token)
        except IntegrityError:
            try:
                return await self._reserve_once(snapshot_id, fingerprint, owner_token)
            except (IdempotencyConflictError, PersistenceUnavailableError):
                raise
            except Exception as error:
                raise PersistenceUnavailableError() from error
        except IdempotencyConflictError:
            raise
        except SQLAlchemyError as error:
            raise PersistenceUnavailableError() from error
        except (ValueError, KeyError, TypeError) as error:
            raise PersistenceUnavailableError() from error

    async def _reserve_once(
        self,
        snapshot_id: UUID,
        fingerprint: str,
        owner_token: str,
    ) -> AnalysisReservation:
        now = self._normalized_now()
        async with self._database.session() as session, session.begin():
            statement = (
                select(AnalysisResultRecord)
                .where(AnalysisResultRecord.snapshot_id == str(snapshot_id))
                .with_for_update()
            )
            record = (await session.execute(statement)).scalar_one_or_none()
            if record is None:
                session.add(
                    AnalysisResultRecord(
                        snapshot_id=str(snapshot_id),
                        snapshot_fingerprint=fingerprint,
                        state="pending",
                        owner_token=owner_token,
                        analysis_id=None,
                        payload_json=None,
                        failure_category=None,
                        created_at=now,
                        updated_at=now,
                        lease_expires_at=now + self._lease,
                        expires_at=now + self._retention,
                    )
                )
                return AnalysisReservation(ReservationStatus.ACQUIRED)

            if record.snapshot_fingerprint != fingerprint:
                log_event(logger, "idempotency_lookup", idempotency_outcome="conflict")
                raise IdempotencyConflictError()

            if record.state == "completed" and self._is_future(record.expires_at, now):
                if record.payload_json is None:
                    raise PersistenceUnavailableError()
                analysis = self._codec.decode(record.payload_json)
                if analysis.snapshot_id != snapshot_id:
                    raise PersistenceUnavailableError()
                return AnalysisReservation(ReservationStatus.COMPLETED, analysis)

            lease_is_active = (
                record.state == "pending"
                and record.lease_expires_at is not None
                and self._is_future(record.lease_expires_at, now)
            )
            if lease_is_active:
                return AnalysisReservation(ReservationStatus.PENDING)

            record.state = "pending"
            record.owner_token = owner_token
            record.analysis_id = None
            record.payload_json = None
            record.failure_category = None
            record.updated_at = now
            record.lease_expires_at = now + self._lease
            record.expires_at = now + self._retention
            return AnalysisReservation(ReservationStatus.ACQUIRED)

    async def retrieve_completed(
        self,
        snapshot_id: UUID,
        fingerprint: str,
    ) -> PortfolioAnalysis | None:
        try:
            async with self._database.session() as session:
                record = await session.get(AnalysisResultRecord, str(snapshot_id))
                if record is None:
                    return None
                if record.snapshot_fingerprint != fingerprint:
                    raise IdempotencyConflictError()
                if (
                    record.state != "completed"
                    or record.payload_json is None
                    or not self._is_future(record.expires_at, self._normalized_now())
                ):
                    return None
                return self._codec.decode(record.payload_json)
        except IdempotencyConflictError:
            raise
        except Exception as error:
            raise PersistenceUnavailableError() from error

    async def store_completed(
        self,
        snapshot_id: UUID,
        fingerprint: str,
        owner_token: str,
        analysis: PortfolioAnalysis,
    ) -> None:
        now = self._normalized_now()
        try:
            async with self._database.session() as session, session.begin():
                record = await session.get(
                    AnalysisResultRecord,
                    str(snapshot_id),
                    with_for_update=True,
                )
                if (
                    record is None
                    or record.snapshot_fingerprint != fingerprint
                    or record.owner_token != owner_token
                    or record.state != "pending"
                ):
                    raise PersistenceUnavailableError()
                record.state = "completed"
                record.analysis_id = str(analysis.id)
                record.payload_json = self._codec.encode(analysis)
                record.failure_category = None
                record.owner_token = None
                record.lease_expires_at = None
                record.updated_at = now
                record.expires_at = now + self._retention
        except PersistenceUnavailableError:
            raise
        except Exception as error:
            raise PersistenceUnavailableError() from error

    async def mark_failed(
        self,
        snapshot_id: UUID,
        fingerprint: str,
        owner_token: str,
        error: BaseException,
    ) -> None:
        now = self._normalized_now()
        try:
            async with self._database.session() as session, session.begin():
                record = await session.get(
                    AnalysisResultRecord,
                    str(snapshot_id),
                    with_for_update=True,
                )
                if (
                    record is not None
                    and record.snapshot_fingerprint == fingerprint
                    and record.owner_token == owner_token
                ):
                    record.state = "failed"
                    record.owner_token = None
                    record.failure_category = type(error).__name__
                    record.lease_expires_at = None
                    record.updated_at = now
        except Exception as persistence_error:
            raise PersistenceUnavailableError() from persistence_error

    async def cleanup_expired(self) -> int:
        now = self._normalized_now()
        try:
            async with self._database.session() as session, session.begin():
                result = await session.execute(
                    delete(AnalysisResultRecord).where(AnalysisResultRecord.expires_at <= now)
                )
                count = result.rowcount or 0
        except Exception as error:
            raise PersistenceUnavailableError() from error
        log_event(logger, "idempotency_cleanup", record_count=count)
        return count

    async def is_ready(self) -> bool:
        return await self._database.is_ready()

    def _normalized_now(self) -> datetime:
        now = self._now()
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Idempotency clock must be timezone-aware.")
        return now.astimezone(UTC)

    @staticmethod
    def _is_future(value: datetime, now: datetime) -> bool:
        if value.tzinfo is None or value.utcoffset() is None:
            value = value.replace(tzinfo=UTC)
        return value.astimezone(UTC) > now
