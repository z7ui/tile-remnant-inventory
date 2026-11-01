"""SQLAlchemy ORM models.

Every project-scoped table carries ``project_id`` and is indexed by it so the
service layer can never accidentally run a cross-project query without a
filter (and PostgreSQL can use index scans).
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base
from .utils import new_id, utcnow


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)


# ---------------------------------------------------------------------------
# devices
# ---------------------------------------------------------------------------
class Device(Base):
    __tablename__ = "devices"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(120), default="", nullable=False)
    platform: Mapped[str] = mapped_column(String(40), default="android", nullable=False)
    app_version: Mapped[str] = mapped_column(String(40), default="", nullable=False)
    secret_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    memberships: Mapped[list["ProjectMember"]] = relationship(back_populates="device")


# ---------------------------------------------------------------------------
# projects
# ---------------------------------------------------------------------------
class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    name_key: Mapped[str] = mapped_column(String(160), nullable=False, unique=True)
    # 特征码：4 位大写字母数字（去掉 0/O/1/I/L 这类易混字符）。
    # 项目名现在允许重复，靠它区分——「金域蓝湾 3 栋 1802 · K7M2」和
    # 「金域蓝湾 3 栋 1802 · W9TA」是两个不同的项目。
    short_code: Mapped[str | None] = mapped_column(String(8), nullable=True, index=True)
    default_unit: Mapped[str] = mapped_column(String(4), default="mm", nullable=False)
    min_usable_mm: Mapped[int] = mapped_column(Integer, default=50, nullable=False)
    owner_device_id: Mapped[str] = mapped_column(String(32), ForeignKey("devices.id"), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="active", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    members: Mapped[list["ProjectMember"]] = relationship(
        back_populates="project", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_projects_status", "status"),
        Index("ix_projects_owner", "owner_device_id"),
    )


class ProjectMember(Base):
    __tablename__ = "project_members"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(32), ForeignKey("devices.id"), nullable=False)
    role: Mapped[str] = mapped_column(String(16), default="member", nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    removed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    project: Mapped[Project] = relationship(back_populates="members")
    device: Mapped[Device] = relationship(back_populates="memberships")

    __table_args__ = (
        UniqueConstraint("project_id", "device_id", name="uq_member_project_device"),
        Index("ix_members_device", "device_id"),
    )


class ProjectInvite(Base):
    __tablename__ = "project_invites"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    code: Mapped[str] = mapped_column(String(32), nullable=False, unique=True)
    status: Mapped[str] = mapped_column(String(16), default="active", nullable=False)
    generation: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_by_device_id: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    __table_args__ = (Index("ix_invites_project_status", "project_id", "status"),)


class ProjectAccessToken(Base):
    __tablename__ = "project_access_tokens"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(32), ForeignKey("devices.id"), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    token_hint: Mapped[str] = mapped_column(String(12), default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    __table_args__ = (Index("ix_tokens_project_device", "project_id", "device_id"),)


# ---------------------------------------------------------------------------
# inventory
# ---------------------------------------------------------------------------
class InventoryBatch(Base):
    __tablename__ = "inventory_batches"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    batch_no: Mapped[int] = mapped_column(Integer, nullable=False)

    shape_type: Mapped[str] = mapped_column(String(16), default="rectangle", nullable=False)
    width_mm: Mapped[int] = mapped_column(Integer, nullable=False)
    height_mm: Mapped[int] = mapped_column(Integer, nullable=False)
    geometry: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    area_mm2: Mapped[int] = mapped_column(BigInteger, nullable=False)
    notch_w_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notch_h_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notch_corner: Mapped[str | None] = mapped_column(String(16), nullable=True)

    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    initial_quantity: Mapped[int] = mapped_column(Integer, nullable=False)

    source_type: Mapped[str] = mapped_column(String(16), default="manual", nullable=False)
    parent_batch_id: Mapped[str | None] = mapped_column(String(32), ForeignKey("inventory_batches.id"), nullable=True)
    root_batch_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    cut_option: Mapped[str | None] = mapped_column(String(20), nullable=True)
    used_length_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    used_width_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)

    location: Mapped[str] = mapped_column(String(120), default="", nullable=False)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="available", nullable=False)

    created_by_device_id: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    __table_args__ = (
        UniqueConstraint("project_id", "batch_no", name="uq_batch_project_no"),
        Index("ix_batches_project_status", "project_id", "status"),
        Index("ix_batches_project_created", "project_id", "created_at"),
        Index("ix_batches_parent", "parent_batch_id"),
        Index("ix_batches_root", "root_batch_id"),
        Index("ix_batches_location", "project_id", "location"),
    )


class UsageRecord(Base):
    __tablename__ = "usage_records"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    device_id: Mapped[str] = mapped_column(String(32), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(80), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), default="", nullable=False)

    demand_length_mm: Mapped[int] = mapped_column(Integer, nullable=False)
    demand_width_mm: Mapped[int] = mapped_column(Integer, nullable=False)
    demand_quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    total_waste_mm2: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    cut_option: Mapped[str | None] = mapped_column(String(20), nullable=True)
    remnant_action: Mapped[str | None] = mapped_column(String(16), nullable=True)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("project_id", "idempotency_key", name="uq_usage_idempotency"),
        Index("ix_usage_project_created", "project_id", "created_at"),
    )


class InventoryMovement(Base):
    __tablename__ = "inventory_movements"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str] = mapped_column(String(32), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    batch_id: Mapped[str] = mapped_column(String(32), nullable=False)
    batch_no: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    root_batch_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    sequence: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    type: Mapped[str] = mapped_column(String(24), nullable=False)
    quantity_delta: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    quantity_before: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    quantity_after: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    width_before_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height_before_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    width_after_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height_after_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    area_before_mm2: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    area_after_mm2: Mapped[int | None] = mapped_column(BigInteger, nullable=True)

    used_length_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    used_width_mm: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cut_option: Mapped[str | None] = mapped_column(String(20), nullable=True)
    remnant_action: Mapped[str | None] = mapped_column(String(16), nullable=True)
    remnant_shape: Mapped[str | None] = mapped_column(String(16), nullable=True)
    remnant_area_mm2: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    produced_batch_id: Mapped[str | None] = mapped_column(String(32), nullable=True)

    usage_record_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    device_id: Mapped[str] = mapped_column(String(32), nullable=False)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)

    __table_args__ = (
        Index("ix_movements_project_created", "project_id", "created_at"),
        Index("ix_movements_project_type", "project_id", "type"),
        Index("ix_movements_batch", "batch_id"),
        Index("ix_movements_usage", "usage_record_id"),
    )


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    project_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    device_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    target_type: Mapped[str] = mapped_column(String(40), default="", nullable=False)
    target_id: Mapped[str] = mapped_column(String(40), default="", nullable=False)
    detail: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    ip: Mapped[str] = mapped_column(String(64), default="", nullable=False)
    ok: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, nullable=False)

    __table_args__ = (Index("ix_audit_project_created", "project_id", "created_at"),)
