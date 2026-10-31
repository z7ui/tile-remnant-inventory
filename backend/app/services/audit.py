"""Append-only audit log helper."""

from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from ..models import AuditLog


def log(
    db: Session,
    action: str,
    *,
    project_id: str | None = None,
    device_id: str | None = None,
    target_type: str = "",
    target_id: str = "",
    detail: dict[str, Any] | None = None,
    ip: str = "",
    ok: bool = True,
) -> None:
    db.add(
        AuditLog(
            project_id=project_id,
            device_id=device_id,
            action=action,
            target_type=target_type,
            target_id=target_id,
            detail=detail or {},
            ip=ip,
            ok=ok,
        )
    )
