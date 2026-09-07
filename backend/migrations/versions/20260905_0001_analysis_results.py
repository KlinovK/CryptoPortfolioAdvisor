"""Create durable analysis idempotency records.

Revision ID: 20260905_0001
Revises:
Create Date: 2026-09-05
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260905_0001"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "analysis_results",
        sa.Column("snapshot_id", sa.String(length=36), nullable=False),
        sa.Column("snapshot_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("state", sa.String(length=16), nullable=False),
        sa.Column("owner_token", sa.String(length=36), nullable=True),
        sa.Column("analysis_id", sa.String(length=36), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=True),
        sa.Column("failure_category", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "state IN ('pending', 'completed', 'failed')",
            name="ck_analysis_results_state",
        ),
        sa.PrimaryKeyConstraint("snapshot_id"),
        sa.UniqueConstraint("analysis_id"),
    )
    op.create_index(
        op.f("ix_analysis_results_expires_at"),
        "analysis_results",
        ["expires_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_analysis_results_expires_at"), table_name="analysis_results")
    op.drop_table("analysis_results")
