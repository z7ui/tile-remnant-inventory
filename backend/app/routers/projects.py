"""Project, invite and membership endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..deps import ProjectContext, client_ip, get_device, get_project_context, project_summary
from ..models import Device
from ..ratelimit import enforce
from ..schemas import InviteResetIn, MembershipRemoveIn, ProjectCreateIn, ProjectJoinIn, ProjectPatchIn
from ..services import projects as project_service
from ..services import audit

router = APIRouter(prefix="/projects", tags=["projects"])


@router.get("/name-available", summary="校验项目名是否可用（不区分大小写、忽略首尾空格）")
def name_available(
    request: Request,
    name: str = Query(..., min_length=1, max_length=120),
    exclude_project_id: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: Device = Depends(get_device),
) -> dict:
    # 单独限流：正常情况下建一个项目只查一两次名字，
    # 12 次/分钟对真实用户绰绰有余，对枚举项目名则远远不够。
    enforce(client_ip(request), "projects.name", name_check=True)
    return project_service.check_name_available(db, name, exclude_project_id)


@router.post("", summary="新建项目（名称全局唯一）", status_code=201)
def create_project(
    payload: ProjectCreateIn,
    request: Request,
    db: Session = Depends(get_db),
    device: Device = Depends(get_device),
) -> dict:
    enforce(client_ip(request), "projects.create", write=True)
    return project_service.create_project(db, device, payload, ip=client_ip(request))


@router.get("", summary="当前设备已加入的项目列表")
def list_projects(db: Session = Depends(get_db), device: Device = Depends(get_device)) -> dict:
    return project_service.list_projects(db, device)


@router.post("/join", summary="使用邀请码加入项目")
def join_project(
    payload: ProjectJoinIn,
    request: Request,
    db: Session = Depends(get_db),
    device: Device = Depends(get_device),
) -> dict:
    enforce(client_ip(request), "projects.join", write=True)
    return project_service.join_project(db, device, payload, ip=client_ip(request))


@router.get("/{project_id}", summary="项目详情")
def get_project(ctx: ProjectContext = Depends(get_project_context), db: Session = Depends(get_db)) -> dict:
    return {
        "project": project_service.project_payload(
            ctx.project, "owner" if ctx.is_owner else "member", project_service.project_stats(db, ctx.project.id)
        ),
        "server_base_url": settings.public_base_url,
        "membership": {
            "device_id": ctx.device.id,
            "role": "owner" if ctx.is_owner else "member",
            "joined_at": ctx.member.joined_at.isoformat() if ctx.member.joined_at else None,
        },
    }


@router.patch("/{project_id}", summary="修改项目设置（拥有者）")
def patch_project(
    payload: ProjectPatchIn,
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "projects.patch", write=True)
    return project_service.update_project(db, ctx, payload, ip=client_ip(request))


@router.delete("/{project_id}", summary="软删除项目（拥有者）")
def delete_project(
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "projects.delete", write=True)
    return project_service.soft_delete_project(db, ctx, ip=client_ip(request))


@router.get("/{project_id}/invite", summary="查看当前邀请码与二维码内容（拥有者）")
def get_invite(
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "invite.read")
    return project_service.get_invite(db, ctx)


@router.post("/{project_id}/invite/revoke", summary="撤销邀请码（拥有者）")
def revoke_invite(
    request: Request,
    payload: InviteResetIn | None = None,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "invite.revoke", write=True)
    return project_service.revoke_invite(db, ctx, ip=client_ip(request))


@router.post("/{project_id}/invite/reset", summary="重置邀请码（拥有者，旧码立即失效）")
def reset_invite(
    request: Request,
    payload: InviteResetIn | None = None,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "invite.reset", write=True)
    return project_service.reset_invite(db, ctx, ip=client_ip(request))


@router.get("/{project_id}/members", summary="成员设备列表（拥有者）")
def list_members(ctx: ProjectContext = Depends(get_project_context), db: Session = Depends(get_db)) -> dict:
    ctx.require_owner()
    return project_service.list_members(db, ctx)


@router.delete("/{project_id}/membership", summary="移除本设备与项目的关联")
def remove_own_membership(
    request: Request,
    payload: MembershipRemoveIn | None = None,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "membership.remove", write=True)
    return project_service.remove_membership(db, ctx, None, ip=client_ip(request))


@router.delete("/{project_id}/members/{device_id}", summary="移除指定成员设备（拥有者）")
def remove_member(
    request: Request,
    device_id: str = Path(..., min_length=8, max_length=40),
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "membership.remove.member", write=True)
    return project_service.remove_membership(db, ctx, device_id, ip=client_ip(request))


@router.get("/{project_id}/summary", summary="项目概览：库存统计 + 最近流水")
def project_home(ctx: ProjectContext = Depends(get_project_context), db: Session = Depends(get_db)) -> dict:
    from sqlalchemy import func, select

    from ..models import InventoryBatch, InventoryMovement
    from ..services.serializers import movement_payload

    stats = project_service.project_stats(db, ctx.project.id)
    recent = db.scalars(
        select(InventoryMovement)
        .where(InventoryMovement.project_id == ctx.project.id)
        .order_by(InventoryMovement.created_at.desc(), InventoryMovement.sequence.desc())
        .limit(3)
    ).all()
    locations = db.scalars(
        select(InventoryBatch.location)
        .where(InventoryBatch.project_id == ctx.project.id, InventoryBatch.location != "")
        .distinct()
    ).all()
    available = db.scalar(
        select(func.count(InventoryBatch.id)).where(
            InventoryBatch.project_id == ctx.project.id,
            InventoryBatch.status == "available",
            InventoryBatch.quantity > 0,
        )
    )
    return {
        "project": project_summary(ctx),
        "stats": {**stats, "available_batches": int(available or 0)},
        "recent_movements": [movement_payload(m) for m in recent],
        "known_locations": list(locations),
    }


@router.get("/{project_id}/audit", summary="审计日志（拥有者）")
def audit_log(ctx: ProjectContext = Depends(get_project_context), db: Session = Depends(get_db), limit: int = Query(50, ge=1, le=200)) -> dict:
    from sqlalchemy import select

    from ..models import AuditLog

    ctx.require_owner()
    rows = db.scalars(
        select(AuditLog).where(AuditLog.project_id == ctx.project.id).order_by(AuditLog.created_at.desc()).limit(limit)
    ).all()
    return {
        "items": [
            {
                "id": r.id,
                "action": r.action,
                "target_type": r.target_type,
                "target_id": r.target_id,
                "device_id": r.device_id,
                "detail": r.detail,
                "ip": r.ip,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ]
    }
