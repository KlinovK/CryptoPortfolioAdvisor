from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, String, Text, select
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.pool import NullPool

from app.domain.errors import PersistenceUnavailableError


class Base(DeclarativeBase):
    pass


class AnalysisResultRecord(Base):
    __tablename__ = "analysis_results"
    __table_args__ = (
        CheckConstraint(
            "state IN ('pending', 'completed', 'failed')",
            name="ck_analysis_results_state",
        ),
    )

    snapshot_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    snapshot_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False)
    owner_token: Mapped[str | None] = mapped_column(String(36), nullable=True)
    analysis_id: Mapped[str | None] = mapped_column(String(36), unique=True, nullable=True)
    payload_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    failure_category: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        index=True,
    )


class Database:
    def __init__(self, url: str) -> None:
        engine_arguments: dict[str, object] = {
            "pool_pre_ping": True,
        }
        if url.startswith("sqlite+"):
            engine_arguments["poolclass"] = NullPool
        self.engine: AsyncEngine = create_async_engine(url, **engine_arguments)
        self.session_factory = async_sessionmaker(
            self.engine,
            class_=AsyncSession,
            expire_on_commit=False,
        )

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.session_factory() as session:
            yield session

    async def is_ready(self) -> bool:
        try:
            async with self.session() as session:
                await session.execute(select(AnalysisResultRecord.snapshot_id).limit(1))
        except Exception:
            return False
        return True

    async def require_ready(self) -> None:
        if not await self.is_ready():
            raise PersistenceUnavailableError()

    async def dispose(self) -> None:
        await self.engine.dispose()
