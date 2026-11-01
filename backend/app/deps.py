"""FastAPI dependencies: device credentials and project membership checks."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta

from fastapi import Depends, Header, Path, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .errors import ApiError
from .models import Device, Project, ProjectAccessToken, ProjectMember
from .security import token_fingerprint, verify_device_secret_cached
from .utils import iso, utcnow


def client_ip(request: Request) -> str:
    if settings.trust_proxy_headers:
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            return forwarded.split(",")[0].strip()
        real_ip = request.headers.get("x-real-ip", "")
        if real_ip:
            return real_ip.strip()
    return request.client.host if request.client else "unknown"


def get_device(
    request: Request,
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    x_device_secret: str | None = Header(default=None, alias="X-Device-Secret"),
) -> Device:
    if not x_device_id or not x_device_secret:
        raise ApiError(401, "device_credentials_missing", "缺少设备凭证，请先注册设备。")
    device = db.get(Device, x_device_id)
    if device is None or device.revoked_at is not None:
        raise ApiError(401, "device_not_found", "设备未注册或已被停用，请重新注册。")
    if not verify_device_secret_cached(device.id, x_device_secret, device.secret_hash):
        raise ApiError(401, "device_secret_invalid", "设备密钥不正确。")
    if device.last_seen_at is None or utcnow() - device.last_seen_at > timedelta(minutes=5):
        device.last_seen_at = utcnow()
        db.commit()
    return device


@dataclass
class ProjectContext:
    project: Project
    device: Device
    member: ProjectMember
    token: ProjectAccessToken

    @property
    def is_owner(self) -> bool:
        return self.member.role == "owner" or self.project.owner_device_id == self.device.id

    def require_owner(self) -> None:
        if not self.is_owner:
            raise ApiError(403, "owner_only", "该操作仅项目拥有者设备可以执行。")


def get_project_context(
    request: Request,
    project_id: str = Path(..., min_length=8, max_length=40),
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    x_project_token: str | None = Header(default=None, alias="X-Project-Token"),
) -> ProjectContext:
    if not x_device_id:
        raise ApiError(401, "device_credentials_missing", "缺少设备标识。")
    if not x_project_token:
        raise ApiError(403, "project_token_missing", "缺少项目访问令牌，请重新加入项目。")

    device = db.get(Device, x_device_id)
    if device is None or device.revoked_at is not None:
        raise ApiError(401, "device_not_found", "设备未注册或已被停用。")

    token = db.scalar(
        select(ProjectAccessToken).where(
            ProjectAccessToken.token_hash == token_fingerprint(x_project_token),
            ProjectAccessToken.project_id == project_id,
            ProjectAccessToken.device_id == device.id,
        )
    )
    if token is None or token.revoked_at is not None:
        # Never reveal whether the project exists: always 403.
        raise ApiError(403, "project_access_denied", "无权访问该项目：令牌无效或已被移除。")
    if token.expires_at is not None and token.expires_at < utcnow():
        raise ApiError(403, "project_token_expired", "项目访问令牌已过期，请重新扫码加入。")

    project = db.get(Project, project_id)
    if project is None or project.status != "active":
        raise ApiError(403, "project_access_denied", "项目不存在或已删除。")

    member = db.scalar(
        select(ProjectMember).where(
            ProjectMember.project_id == project_id,
            ProjectMember.device_id == device.id,
            ProjectMember.removed_at.is_(None),
        )
    )
    if member is None:
        raise ApiError(403, "not_a_member", "你已不在该项目成员中。")

    if token.last_used_at is None or utcnow() - token.last_used_at > timedelta(hours=6):
        token.last_used_at = utcnow()
        db.commit()

    return ProjectContext(project=project, device=device, member=member, token=token)


def project_summary(ctx: ProjectContext) -> dict:
    return {
        "id": ctx.project.id,
        "name": ctx.project.name,
        "default_unit": ctx.project.default_unit,
        "min_usable_mm": ctx.project.min_usable_mm,
        "role": "owner" if ctx.is_owner else "member",
        "created_at": iso(ctx.project.created_at),
    }
