"""Projects, invites, membership and access tokens."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..deps import ProjectContext
from ..errors import ApiError
from ..models import (
    Device,
    InventoryBatch,
    InventoryMovement,
    Project,
    ProjectAccessToken,
    ProjectInvite,
    ProjectMember,
)
from ..schemas import ProjectCreateIn, ProjectJoinIn, ProjectPatchIn
from ..security import new_project_token, token_fingerprint
from ..utils import iso, new_id, new_invite_code, normalise_project_name, project_name_key, utcnow
from . import audit
from .serializers import project_payload


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _issue_token(db: Session, project: Project, device: Device) -> str:
    # rotate: a device keeps one active token per project
    for old in db.scalars(
        select(ProjectAccessToken).where(
            ProjectAccessToken.project_id == project.id,
            ProjectAccessToken.device_id == device.id,
            ProjectAccessToken.revoked_at.is_(None),
        )
    ):
        old.revoked_at = utcnow()

    token = new_project_token()
    record = ProjectAccessToken(
        id=new_id(),
        project_id=project.id,
        device_id=device.id,
        token_hash=token_fingerprint(token),
        token_hint=token[:6],
        expires_at=(utcnow() + timedelta(days=settings.token_ttl_days)) if settings.token_ttl_days else None,
    )
    db.add(record)
    db.flush()
    return token


def _create_invite(db: Session, project: Project, device: Device) -> ProjectInvite:
    for _ in range(8):
        code = new_invite_code(settings.invite_code_length)
        if db.scalar(select(ProjectInvite.id).where(ProjectInvite.code == code)) is None:
            invite = ProjectInvite(
                id=new_id(),
                project_id=project.id,
                code=code,
                status="active",
                generation=1,
                created_by_device_id=device.id,
            )
            db.add(invite)
            db.flush()
            return invite
    raise ApiError(500, "invite_generation_failed", "邀请码生成失败，请重试。")


def invite_payload(invite: ProjectInvite, project: Project) -> dict:
    code = invite.code if invite.status == "active" else None
    qr_payload = None
    if code:
        qr_payload = f"tileremnant://join?server={settings.public_base_url.rstrip('/')}&code={code}"
    return {
        "project_id": project.id,
        "code": code,
        "status": invite.status,
        "generation": invite.generation,
        "qr_payload": qr_payload,
        "join_url": f"{settings.public_base_url.rstrip('/')}/join?code={code}" if code else None,
        "never_expires": True,
        "created_at": iso(invite.created_at),
        "revoked_at": iso(invite.revoked_at),
        "notice": "邀请码长期有效，可随时撤销或重置；撤销后旧码立即失效。",
    }


def active_invite(db: Session, project_id: str) -> ProjectInvite | None:
    return db.scalar(
        select(ProjectInvite)
        .where(ProjectInvite.project_id == project_id, ProjectInvite.status == "active")
        .order_by(ProjectInvite.created_at.desc())
    )


# ---------------------------------------------------------------------------
# create / list / join
# ---------------------------------------------------------------------------
# 与 models.Project.name_key 的列宽一致。NFKC 归一化会把某些字符展开
# （㍿ U+337F → 株式会社，ﬁ → fi），120 字符的名称归一化后可能超过列宽，
# SQLite 不校验但 PostgreSQL 会直接报错，所以入表前挡掉。
_NAME_KEY_MAX = 160


def _guard_key_length(key: str) -> str:
    if len(key) > _NAME_KEY_MAX:
        raise ApiError(
            422,
            "project_name_too_long",
            f"项目名称归一化后超过 {_NAME_KEY_MAX} 个字符（当前 {len(key)}），"
            "请缩短，或换用更简单的字符（全角符号/合字会被展开）。",
        )
    return key

def check_name_available(db: Session, name: str, exclude_project_id: str | None = None) -> dict:
    key = _guard_key_length(project_name_key(name))
    if not key:
        raise ApiError(422, "project_name_blank", "项目名称不能为空。")
    stmt = select(Project).where(Project.name_key == key)
    existing = db.scalar(stmt)
    available = existing is None or existing.id == exclude_project_id
    return {
        "name": normalise_project_name(name),
        "key": key,
        "available": available,
        "conflict_project": None
        if available
        else {"id": existing.id, "name": existing.name, "created_at": iso(existing.created_at)},
    }


def create_project(db: Session, device: Device, payload: ProjectCreateIn, ip: str = "") -> dict:
    name = normalise_project_name(payload.name)
    key = _guard_key_length(project_name_key(payload.name))
    if not key:
        raise ApiError(422, "project_name_blank", "项目名称不能为空。")

    existing = db.scalar(select(Project).where(Project.name_key == key))
    if existing is not None:
        raise ApiError(
            409,
            "project_name_taken",
            f"项目名称「{name}」已被占用（不区分大小写、忽略首尾空格），请换一个名称。",
            {"conflict_project_id": existing.id, "conflict_project_name": existing.name},
        )

    project = Project(
        id=new_id(),
        name=name,
        name_key=key,
        default_unit=payload.default_unit,
        min_usable_mm=payload.min_usable_mm,
        owner_device_id=device.id,
        status="active",
    )
    db.add(project)
    db.flush()

    db.add(ProjectMember(id=new_id(), project_id=project.id, device_id=device.id, role="owner"))
    invite = _create_invite(db, project, device)
    token = _issue_token(db, project, device)
    audit.log(
        db,
        "project.create",
        project_id=project.id,
        device_id=device.id,
        target_type="project",
        target_id=project.id,
        detail={"name": name},
        ip=ip,
    )
    try:
        db.commit()
    except IntegrityError as exc:  # concurrent create with the same name
        db.rollback()
        raise ApiError(409, "project_name_taken", f"项目名称「{name}」已被占用，请换一个名称。") from exc

    return {
        "project": project_payload(project, "owner", {"total_pieces": 0, "batch_count": 0}),
        "project_token": token,
        "invite": invite_payload(invite, project),
        "server_base_url": settings.public_base_url,
    }


def _project_stats(db: Session, project_id: str) -> dict:
    row = db.execute(
        select(
            func.coalesce(func.sum(InventoryBatch.quantity), 0),
            func.count(InventoryBatch.id),
            func.coalesce(func.sum(InventoryBatch.area_mm2 * InventoryBatch.quantity), 0),
        ).where(InventoryBatch.project_id == project_id, InventoryBatch.status == "available")
    ).one()
    l_shapes = db.scalar(
        select(func.count(InventoryBatch.id)).where(
            InventoryBatch.project_id == project_id,
            InventoryBatch.status == "available",
            InventoryBatch.shape_type == "l_shape",
        )
    )
    last_movement = db.scalar(
        select(func.max(InventoryMovement.created_at)).where(InventoryMovement.project_id == project_id)
    )
    return {
        "total_pieces": int(row[0] or 0),
        "batch_count": int(row[1] or 0),
        "total_area_mm2": int(row[2] or 0),
        "l_shape_batches": int(l_shapes or 0),
        "last_activity_at": iso(last_movement),
    }


def project_stats(db: Session, project_id: str) -> dict:
    return _project_stats(db, project_id)


def list_projects(db: Session, device: Device) -> dict:
    rows = db.execute(
        select(Project, ProjectMember)
        .join(ProjectMember, ProjectMember.project_id == Project.id)
        .where(
            ProjectMember.device_id == device.id,
            ProjectMember.removed_at.is_(None),
            Project.status == "active",
        )
        .order_by(Project.created_at.desc())
    ).all()
    items = [project_payload(project, member.role, _project_stats(db, project.id)) for project, member in rows]
    return {"items": items, "total": len(items)}


def join_project(db: Session, device: Device, payload: ProjectJoinIn, ip: str = "") -> dict:
    code = payload.invite_code.strip().upper()
    invite = db.scalar(select(ProjectInvite).where(ProjectInvite.code == code))
    if invite is None or invite.status != "active":
        raise ApiError(404, "invite_invalid", "邀请码不存在或已被撤销，请向项目拥有者索取新的邀请码。")

    project = db.get(Project, invite.project_id)
    if project is None or project.status != "active":
        raise ApiError(404, "project_not_found", "项目不存在或已删除。")

    member = db.scalar(
        select(ProjectMember).where(
            ProjectMember.project_id == project.id, ProjectMember.device_id == device.id
        )
    )
    if member is None:
        member = ProjectMember(
            id=new_id(),
            project_id=project.id,
            device_id=device.id,
            role="owner" if project.owner_device_id == device.id else "member",
        )
        db.add(member)
        db.flush()
    elif member.removed_at is not None:
        member.removed_at = None
        member.joined_at = utcnow()
        if project.owner_device_id == device.id:
            member.role = "owner"

    token = _issue_token(db, project, device)
    audit.log(
        db,
        "project.join",
        project_id=project.id,
        device_id=device.id,
        target_type="invite",
        target_id=invite.id,
        ip=ip,
    )
    db.commit()
    return {
        "project": project_payload(project, member.role, _project_stats(db, project.id)),
        "project_token": token,
        "invite": invite_payload(invite, project),
    }


def update_project(db: Session, ctx: ProjectContext, payload: ProjectPatchIn, ip: str = "") -> dict:
    ctx.require_owner()
    project = ctx.project
    if payload.name is not None:
        new_name = normalise_project_name(payload.name)
        new_key = _guard_key_length(project_name_key(payload.name))
        conflict = db.scalar(select(Project).where(Project.name_key == new_key, Project.id != project.id))
        if conflict is not None:
            raise ApiError(409, "project_name_taken", f"项目名称「{new_name}」已被占用，请换一个名称。")
        project.name = new_name
        project.name_key = new_key
    if payload.default_unit is not None:
        project.default_unit = payload.default_unit
    if payload.min_usable_mm is not None:
        project.min_usable_mm = payload.min_usable_mm
    audit.log(
        db, "project.update", project_id=project.id, device_id=ctx.device.id, target_type="project", target_id=project.id, ip=ip
    )
    db.commit()
    return {"project": project_payload(project, "owner", _project_stats(db, project.id))}


# ---------------------------------------------------------------------------
# invites
# ---------------------------------------------------------------------------
def get_invite(db: Session, ctx: ProjectContext) -> dict:
    ctx.require_owner()
    invite = active_invite(db, ctx.project.id)
    if invite is None:
        invite = _create_invite(db, ctx.project, ctx.device)
        db.commit()
    return {"invite": invite_payload(invite, ctx.project)}


def revoke_invite(db: Session, ctx: ProjectContext, ip: str = "") -> dict:
    ctx.require_owner()
    invite = active_invite(db, ctx.project.id)
    if invite is None:
        raise ApiError(404, "invite_not_found", "当前没有生效的邀请码。")
    invite.status = "revoked"
    invite.revoked_at = utcnow()
    audit.log(
        db, "invite.revoke", project_id=ctx.project.id, device_id=ctx.device.id, target_type="invite", target_id=invite.id, ip=ip
    )
    db.commit()
    return {"invite": invite_payload(invite, ctx.project)}


def reset_invite(db: Session, ctx: ProjectContext, ip: str = "") -> dict:
    ctx.require_owner()
    current = active_invite(db, ctx.project.id)
    generation = 1
    if current is not None:
        current.status = "revoked"
        current.revoked_at = utcnow()
        generation = current.generation + 1
        db.flush()

    for _ in range(8):
        code = new_invite_code(settings.invite_code_length)
        if db.scalar(select(ProjectInvite.id).where(ProjectInvite.code == code)) is not None:
            continue
        invite = ProjectInvite(
            id=new_id(),
            project_id=ctx.project.id,
            code=code,
            status="active",
            generation=generation,
            created_by_device_id=ctx.device.id,
        )
        db.add(invite)
        audit.log(
            db, "invite.reset", project_id=ctx.project.id, device_id=ctx.device.id, target_type="invite", target_id=invite.id, ip=ip
        )
        db.commit()
        return {"invite": invite_payload(invite, ctx.project)}
    raise ApiError(500, "invite_generation_failed", "邀请码生成失败，请重试。")


# ---------------------------------------------------------------------------
# membership
# ---------------------------------------------------------------------------
def list_members(db: Session, ctx: ProjectContext) -> dict:
    rows = db.execute(
        select(ProjectMember, Device)
        .join(Device, Device.id == ProjectMember.device_id)
        .where(ProjectMember.project_id == ctx.project.id, ProjectMember.removed_at.is_(None))
        .order_by(ProjectMember.joined_at.asc())
    ).all()
    items = [
        {
            "device_id": device.id,
            "name": device.name,
            "platform": device.platform,
            "role": member.role,
            "is_current": device.id == ctx.device.id,
            "joined_at": iso(member.joined_at),
            "last_seen_at": iso(device.last_seen_at),
        }
        for member, device in rows
    ]
    return {"items": items, "total": len(items)}


def remove_membership(db: Session, ctx: ProjectContext, target_device_id: str | None = None, ip: str = "") -> dict:
    """Leave the project (self) or remove another device (owner only)."""
    if target_device_id and target_device_id != ctx.device.id:
        ctx.require_owner()
    if target_device_id is None:
        target_device_id = ctx.device.id

    if target_device_id == ctx.project.owner_device_id:
        raise ApiError(409, "owner_cannot_leave", "项目拥有者不能退出项目，请先转让或删除项目。")

    member = db.scalar(
        select(ProjectMember).where(
            ProjectMember.project_id == ctx.project.id,
            ProjectMember.device_id == target_device_id,
            ProjectMember.removed_at.is_(None),
        )
    )
    if member is None:
        raise ApiError(404, "member_not_found", "该设备不在项目成员中。")

    member.removed_at = utcnow()
    for token in db.scalars(
        select(ProjectAccessToken).where(
            ProjectAccessToken.project_id == ctx.project.id,
            ProjectAccessToken.device_id == target_device_id,
            ProjectAccessToken.revoked_at.is_(None),
        )
    ):
        token.revoked_at = utcnow()

    audit.log(
        db,
        "membership.remove",
        project_id=ctx.project.id,
        device_id=ctx.device.id,
        target_type="device",
        target_id=target_device_id,
        detail={"self": target_device_id == ctx.device.id},
        ip=ip,
    )
    db.commit()
    return {"ok": True, "removed_device_id": target_device_id}


def soft_delete_project(db: Session, ctx: ProjectContext, ip: str = "") -> dict:
    ctx.require_owner()
    ctx.project.status = "deleted"
    ctx.project.deleted_at = utcnow()
    for token in db.scalars(
        select(ProjectAccessToken).where(
            ProjectAccessToken.project_id == ctx.project.id, ProjectAccessToken.revoked_at.is_(None)
        )
    ):
        token.revoked_at = utcnow()
    audit.log(
        db, "project.delete", project_id=ctx.project.id, device_id=ctx.device.id, target_type="project", target_id=ctx.project.id, ip=ip
    )
    db.commit()
    return {"ok": True, "project_id": ctx.project.id, "deleted_at": iso(ctx.project.deleted_at)}
