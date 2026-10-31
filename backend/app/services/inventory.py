"""Inventory batches: manual stock-in, listing, adjustments."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Select, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import geometry
from ..deps import ProjectContext
from ..errors import ApiError
from ..models import InventoryBatch, InventoryMovement, Project
from ..schemas import InventoryCreateIn, InventoryPatchIn
from ..units import DimensionError, parse_length_mm
from ..utils import iso, new_id, utcnow
from . import audit
from .serializers import batch_payload


def _next_batch_no(db: Session, project_id: str) -> int:
    current = db.scalar(select(func.max(InventoryBatch.batch_no)).where(InventoryBatch.project_id == project_id))
    return int(current or 0) + 1


def create_batch(db: Session, ctx: ProjectContext, payload: InventoryCreateIn, ip: str = "") -> dict:
    project = ctx.project
    unit = payload.unit or project.default_unit
    try:
        length_mm = parse_length_mm(payload.length, unit, "长度")
        width_mm = parse_length_mm(payload.width, unit, "宽度")
    except DimensionError as exc:
        raise ApiError(422, "invalid_dimension", str(exc)) from exc

    w, h, region = geometry.build_rectangle_region(width_mm, length_mm)
    geom = geometry.describe(region, w, h)
    quantity = payload.quantity

    last_error: Exception | None = None
    for _ in range(5):
        batch_no = _next_batch_no(db, project.id)
        batch = InventoryBatch(
            id=new_id(),
            project_id=project.id,
            batch_no=batch_no,
            shape_type="rectangle",
            width_mm=w,
            height_mm=h,
            geometry=geom,
            area_mm2=w * h,
            quantity=quantity,
            initial_quantity=quantity,
            source_type="manual",
            root_batch_id=None,
            location=payload.location or "",
            note=payload.note or "",
            status="available",
            created_by_device_id=ctx.device.id,
        )
        batch.root_batch_id = batch.id
        db.add(batch)
        try:
            db.flush()
        except IntegrityError as exc:
            db.rollback()
            last_error = exc
            # re-attach project after rollback
            project = db.get(Project, project.id)
            ctx.project = project
            continue

        db.add(
            InventoryMovement(
                id=new_id(),
                project_id=project.id,
                batch_id=batch.id,
                batch_no=batch.batch_no,
                root_batch_id=batch.root_batch_id,
                type="stock_in",
                quantity_delta=quantity,
                quantity_before=0,
                quantity_after=quantity,
                width_before_mm=None,
                height_before_mm=None,
                width_after_mm=w,
                height_after_mm=h,
                area_before_mm2=0,
                area_after_mm2=w * h,
                device_id=ctx.device.id,
                note="主动录入矩形余砖",
            )
        )
        audit.log(
            db,
            "inventory.create",
            project_id=project.id,
            device_id=ctx.device.id,
            target_type="batch",
            target_id=batch.id,
            detail={"width_mm": w, "height_mm": h, "quantity": quantity},
            ip=ip,
        )
        db.commit()
        return {"batch": batch_payload(batch, project.min_usable_mm)}
    raise ApiError(409, "batch_no_conflict", "批次号分配冲突，请重试。") from last_error


def _apply_filters(stmt: Select, filters: dict) -> Select:
    if filters.get("q"):
        raw = filters["q"].strip()
        needle = f"%{raw}%"
        conditions = [
            InventoryBatch.note.ilike(needle),
            InventoryBatch.location.ilike(needle),
        ]
        if raw.isdigit():
            conditions.append(InventoryBatch.batch_no == int(raw))
        stmt = stmt.where(or_(*conditions))
    if filters.get("batch_id"):
        stmt = stmt.where(InventoryBatch.id == filters["batch_id"])
    if filters.get("shape_type"):
        stmt = stmt.where(InventoryBatch.shape_type == filters["shape_type"])
    if filters.get("source_type"):
        stmt = stmt.where(InventoryBatch.source_type == filters["source_type"])
    if filters.get("location"):
        stmt = stmt.where(InventoryBatch.location == filters["location"])
    if filters.get("status"):
        stmt = stmt.where(InventoryBatch.status == filters["status"])
    if filters.get("min_quantity") is not None:
        stmt = stmt.where(InventoryBatch.quantity >= filters["min_quantity"])
    if filters.get("max_quantity") is not None:
        stmt = stmt.where(InventoryBatch.quantity <= filters["max_quantity"])
    if filters.get("min_short_mm") is not None:
        stmt = stmt.where(InventoryBatch.width_mm >= filters["min_short_mm"])
    if filters.get("max_short_mm") is not None:
        stmt = stmt.where(InventoryBatch.width_mm <= filters["max_short_mm"])
    if filters.get("min_long_mm") is not None:
        stmt = stmt.where(InventoryBatch.height_mm >= filters["min_long_mm"])
    if filters.get("max_long_mm") is not None:
        stmt = stmt.where(InventoryBatch.height_mm <= filters["max_long_mm"])
    if filters.get("created_from"):
        stmt = stmt.where(InventoryBatch.created_at >= filters["created_from"])
    if filters.get("created_to"):
        stmt = stmt.where(InventoryBatch.created_at <= filters["created_to"])
    if filters.get("only_available"):
        stmt = stmt.where(InventoryBatch.status == "available", InventoryBatch.quantity > 0)
    return stmt


def list_batches(
    db: Session,
    project: Project,
    filters: dict,
    page: int = 1,
    page_size: int = 20,
    sort: str = "created_desc",
) -> dict:
    base = select(InventoryBatch).where(InventoryBatch.project_id == project.id)
    base = _apply_filters(base, filters)

    sub = base.subquery()
    total = db.scalar(select(func.count()).select_from(sub)) or 0
    summary_row = db.execute(
        select(
            func.coalesce(func.sum(sub.c.quantity), 0),
            func.coalesce(func.sum(sub.c.area_mm2 * sub.c.quantity), 0),
        )
    ).one()

    order = {
        "created_desc": InventoryBatch.created_at.desc(),
        "created_asc": InventoryBatch.created_at.asc(),
        "area_desc": (InventoryBatch.area_mm2 * InventoryBatch.quantity).desc(),
        "quantity_desc": InventoryBatch.quantity.desc(),
        "batch_no_desc": InventoryBatch.batch_no.desc(),
    }.get(sort, InventoryBatch.created_at.desc())

    rows = db.scalars(base.order_by(order, InventoryBatch.batch_no.desc()).offset((page - 1) * page_size).limit(page_size)).all()

    locations = db.scalars(
        select(InventoryBatch.location)
        .where(InventoryBatch.project_id == project.id, InventoryBatch.location != "")
        .distinct()
        .order_by(InventoryBatch.location)
    ).all()

    return {
        "items": [batch_payload(b, project.min_usable_mm) for b in rows],
        "page": page,
        "page_size": page_size,
        "total": int(total),
        "has_more": page * page_size < int(total),
        "summary": {
            "pieces": int(summary_row[0] or 0),
            "area_mm2": int(summary_row[1] or 0),
            "batches": int(total),
        },
        "filters": {"locations": list(locations)},
    }


def get_batch(db: Session, project: Project, batch_id: str) -> InventoryBatch:
    batch = db.get(InventoryBatch, batch_id)
    if batch is None or batch.project_id != project.id:
        raise ApiError(404, "batch_not_found", "余砖批次不存在。")
    return batch


def update_batch(db: Session, ctx: ProjectContext, batch_id: str, payload: InventoryPatchIn, ip: str = "") -> dict:
    batch = get_batch(db, ctx.project, batch_id)
    project = ctx.project
    changed: dict[str, object] = {}

    if payload.location is not None and payload.location != batch.location:
        changed["location"] = payload.location
        batch.location = payload.location
    if payload.note is not None and payload.note != batch.note:
        changed["note"] = payload.note
        batch.note = payload.note

    if payload.quantity is not None and payload.quantity != batch.quantity:
        before = batch.quantity
        delta = payload.quantity - before
        db.add(
            InventoryMovement(
                id=new_id(),
                project_id=project.id,
                batch_id=batch.id,
                batch_no=batch.batch_no,
                root_batch_id=batch.root_batch_id,
                type="adjust",
                quantity_delta=delta,
                quantity_before=before,
                quantity_after=payload.quantity,
                width_before_mm=batch.width_mm,
                height_before_mm=batch.height_mm,
                width_after_mm=batch.width_mm,
                height_after_mm=batch.height_mm,
                area_before_mm2=batch.area_mm2,
                area_after_mm2=batch.area_mm2,
                device_id=ctx.device.id,
                note=payload.adjust_reason or "人工调整片数",
            )
        )
        batch.quantity = payload.quantity
        batch.version += 1
        if batch.quantity > 0 and batch.status == "depleted":
            batch.status = "available"
        elif batch.quantity == 0 and batch.status == "available":
            batch.status = "depleted"
        changed["quantity"] = payload.quantity

    if payload.status is not None and payload.status != batch.status:
        if payload.status == "available" and batch.quantity == 0:
            raise ApiError(409, "empty_batch_cannot_activate", "片数为 0 的批次不能置为可用。")
        db.add(
            InventoryMovement(
                id=new_id(),
                project_id=project.id,
                batch_id=batch.id,
                batch_no=batch.batch_no,
                root_batch_id=batch.root_batch_id,
                type="void" if payload.status in ("void", "depleted") else "adjust",
                quantity_delta=0,
                quantity_before=batch.quantity,
                quantity_after=batch.quantity,
                width_before_mm=batch.width_mm,
                height_before_mm=batch.height_mm,
                width_after_mm=batch.width_mm,
                height_after_mm=batch.height_mm,
                area_before_mm2=batch.area_mm2,
                area_after_mm2=batch.area_mm2,
                device_id=ctx.device.id,
                note=f"状态变更为 {payload.status}",
            )
        )
        batch.status = payload.status
        batch.version += 1
        changed["status"] = payload.status

    if changed:
        batch.updated_at = utcnow()
        audit.log(
            db,
            "inventory.update",
            project_id=project.id,
            device_id=ctx.device.id,
            target_type="batch",
            target_id=batch.id,
            detail=changed,
            ip=ip,
        )
        db.commit()
    return {"batch": batch_payload(batch, project.min_usable_mm)}


def parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as exc:
        raise ApiError(422, "invalid_date", f"日期格式不正确：{value}") from exc
    return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed


__all__ = ["create_batch", "list_batches", "get_batch", "update_batch", "parse_date", "iso"]
