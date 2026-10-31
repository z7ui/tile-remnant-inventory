"""Confirming usage: transactional deduction, remnants and traceable movements."""

from __future__ import annotations

import hashlib
import json
import time

from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from .. import geometry
from ..config import settings
from ..deps import ProjectContext
from ..errors import ApiError
from ..models import InventoryBatch, InventoryMovement, Project, UsageRecord
from ..schemas import AllocationIn, UsageConfirmIn
from ..units import DimensionError, parse_length_mm
from ..utils import iso, new_id, utcnow
from . import audit
from .inventory import _next_batch_no
from .matching import evaluate_batch, load_available_batches, match, resolve_demand
from .serializers import CUT_LABELS, REMNANT_LABELS, batch_payload, movement_payload


class ConcurrencyConflict(Exception):
    """Raised when an optimistic lock check fails."""


def _request_hash(payload: UsageConfirmIn) -> str:
    raw = json.dumps(payload.model_dump(mode="json"), sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _find_usage(db: Session, project_id: str, key: str) -> UsageRecord | None:
    return db.scalar(
        select(UsageRecord).where(UsageRecord.project_id == project_id, UsageRecord.idempotency_key == key)
    )


def _auto_allocations(db: Session, project: Project, short: int, long: int, qty: int) -> list[dict]:
    plan = match(db, project, short, long, qty, limit=50)
    allocations: list[dict] = []
    remaining = qty
    for c in plan["candidates"]:
        if remaining <= 0:
            break
        take = min(remaining, c["match"]["max_pieces"], c["batch"]["quantity"])
        if take <= 0:
            continue
        allocations.append(
            {
                "batch_id": c["batch"]["id"],
                "quantity": take,
                "cut_option": c["match"]["cut_option"],
                "remnant_action": "store" if c["match"]["remnant"] else None,
            }
        )
        remaining -= take
    if remaining > 0:
        raise ApiError(
            409,
            "insufficient_inventory",
            f"库存不足：还差 {remaining} 片无法匹配，请先录入更多余砖。",
            {"unfulfilled_quantity": remaining},
        )
    return allocations


def confirm_usage(db: Session, ctx: ProjectContext, payload: UsageConfirmIn, ip: str = "") -> dict:
    key = payload.idempotency_key
    existing = _find_usage(db, ctx.project.id, key)
    if existing is not None:
        return build_usage_response(db, ctx.project, existing, replayed=True)

    short, long, qty = resolve_demand(ctx.project, payload.length, payload.width, payload.quantity, payload.unit)

    for attempt in range(4):
        try:
            return _do_confirm(db, ctx, payload, short, long, qty, ip)
        except (ConcurrencyConflict, OperationalError):
            db.rollback()
            if attempt >= 3:
                raise ApiError(409, "concurrent_update", "库存正在被其他设备修改，请稍后重试。") from None
            time.sleep(0.05 * (attempt + 1))
        except IntegrityError:
            db.rollback()
            replay = _find_usage(db, ctx.project.id, key)
            if replay is not None:
                return build_usage_response(db, ctx.project, replay, replayed=True)
            raise ApiError(409, "conflict", "提交冲突，请重试。") from None

    raise ApiError(409, "concurrent_update", "库存正在被其他设备修改，请稍后重试。")


def _do_confirm(
    db: Session,
    ctx: ProjectContext,
    payload: UsageConfirmIn,
    short: int,
    long: int,
    qty: int,
    ip: str,
) -> dict:
    project = ctx.project
    auto = payload.allocations is None
    if auto:
        raw_allocations = _auto_allocations(db, project, short, long, qty)
    else:
        raw_allocations = [a.model_dump() for a in payload.allocations or []]

    if sum(a["quantity"] for a in raw_allocations) != qty:
        raise ApiError(422, "allocation_mismatch", "分配数量之和必须等于需求数量。")

    usage = UsageRecord(
        id=new_id(),
        project_id=project.id,
        device_id=ctx.device.id,
        idempotency_key=payload.idempotency_key,
        request_hash=_request_hash(payload),
        demand_length_mm=long,
        demand_width_mm=short,
        demand_quantity=qty,
        note=payload.note or "",
        cut_option=raw_allocations[0]["cut_option"] if len(raw_allocations) == 1 else None,
        remnant_action=raw_allocations[0].get("remnant_action") if len(raw_allocations) == 1 else None,
    )
    db.add(usage)
    db.flush()

    results: list[dict] = []
    total_waste = 0
    sequence = 0

    for alloc in raw_allocations:
        batch = db.execute(
            select(InventoryBatch)
            .where(InventoryBatch.id == alloc["batch_id"])
            .with_for_update()
        ).scalar_one_or_none()
        if batch is None or batch.project_id != project.id:
            raise ApiError(404, "batch_not_found", "选定的余砖批次不存在。")
        if batch.status != "available" or batch.quantity <= 0:
            raise ApiError(409, "batch_unavailable", f"批次 #{batch.batch_no:04d} 已不可用。")

        count = int(alloc["quantity"])
        if count > batch.quantity:
            raise ApiError(
                409,
                "insufficient_quantity",
                f"批次 #{batch.batch_no:04d} 只剩 {batch.quantity} 片，不足以取出 {count} 片。",
                {"batch_id": batch.id, "available": batch.quantity, "requested": count},
            )

        bw, bh, region = geometry.region_from_geometry(batch.geometry)
        if not geometry.fits(region, short, long):
            raise ApiError(
                409,
                "demand_too_large",
                f"需求 {long}×{short}mm 超出批次 #{batch.batch_no:04d} 的可用区域。",
            )

        option = alloc.get("cut_option")
        if option not in ("long_side_cut", "short_side_cut"):
            evaluated = evaluate_batch(batch, short, long, project.min_usable_mm, count)
            option = evaluated["match"]["cut_option"] if evaluated else "long_side_cut"

        preview = geometry.usage_preview(region, bw, bh, short, long, option, project.min_usable_mm)
        if not preview["feasible"]:
            raise ApiError(
                409,
                "cut_option_infeasible",
                f"批次 #{batch.batch_no:04d} 无法按「{CUT_LABELS[option]}」切出该尺寸，请换一种切法。",
                {"batch_id": batch.id, "cut_option": option},
            )

        remnant = preview["remnant"]
        action = alloc.get("remnant_action")
        if remnant is None:
            action = None
        elif action not in ("store", "discard"):
            if auto:
                action = payload.default_remnant_action
            else:
                raise ApiError(
                    422,
                    "remnant_action_required",
                    "该切法会产生余料，请选择「直接入库」或「丢弃」。",
                    {
                        "batch_id": batch.id,
                        "remnant": {
                            "shape_type": remnant["shape_type"],
                            "width_mm": remnant["width_mm"],
                            "height_mm": remnant["height_mm"],
                            "area_mm2": remnant["area_mm2"],
                        },
                    },
                )

        before_qty = batch.quantity
        after_qty = before_qty - count
        stmt = (
            update(InventoryBatch)
            .where(
                InventoryBatch.id == batch.id,
                InventoryBatch.version == batch.version,
                InventoryBatch.quantity >= count,
                InventoryBatch.status == "available",
            )
            .values(
                quantity=after_qty,
                version=batch.version + 1,
                status="depleted" if after_qty == 0 else batch.status,
                updated_at=utcnow(),
            )
        )
        outcome = db.execute(stmt)
        if outcome.rowcount != 1:
            raise ConcurrencyConflict()

        # one movement per piece keeps the ledger literally "per tile"
        for i in range(count):
            sequence += 1
            db.add(
                InventoryMovement(
                    id=new_id(),
                    project_id=project.id,
                    batch_id=batch.id,
                    batch_no=batch.batch_no,
                    root_batch_id=batch.root_batch_id,
                    sequence=sequence,
                    type="usage",
                    quantity_delta=-1,
                    quantity_before=before_qty - i,
                    quantity_after=before_qty - i - 1,
                    width_before_mm=batch.width_mm,
                    height_before_mm=batch.height_mm,
                    width_after_mm=batch.width_mm,
                    height_after_mm=batch.height_mm,
                    area_before_mm2=batch.area_mm2,
                    area_after_mm2=batch.area_mm2,
                    used_length_mm=long,
                    used_width_mm=short,
                    cut_option=option,
                    remnant_action=action,
                    remnant_shape=remnant["shape_type"] if remnant else None,
                    remnant_area_mm2=remnant["area_mm2"] if remnant else None,
                    usage_record_id=usage.id,
                    device_id=ctx.device.id,
                    note=f"使用 {long}×{short}mm",
                )
            )

        produced = None
        if remnant is not None and action == "store":
            produced = _create_remnant_batch(db, project, ctx, batch, remnant, count, option, long, short)
            sequence += 1
            db.add(
                InventoryMovement(
                    id=new_id(),
                    project_id=project.id,
                    batch_id=produced.id,
                    batch_no=produced.batch_no,
                    root_batch_id=produced.root_batch_id,
                    sequence=sequence,
                    type="cut_remnant",
                    quantity_delta=count,
                    quantity_before=0,
                    quantity_after=count,
                    width_before_mm=batch.width_mm,
                    height_before_mm=batch.height_mm,
                    width_after_mm=produced.width_mm,
                    height_after_mm=produced.height_mm,
                    area_before_mm2=batch.area_mm2,
                    area_after_mm2=produced.area_mm2,
                    used_length_mm=long,
                    used_width_mm=short,
                    cut_option=option,
                    remnant_action="store",
                    remnant_shape=produced.shape_type,
                    remnant_area_mm2=produced.area_mm2,
                    produced_batch_id=produced.id,
                    usage_record_id=usage.id,
                    device_id=ctx.device.id,
                    note=f"切割生成余料，来自 #{batch.batch_no:04d}",
                )
            )
        elif remnant is not None and action == "discard":
            sequence += 1
            db.add(
                InventoryMovement(
                    id=new_id(),
                    project_id=project.id,
                    batch_id=batch.id,
                    batch_no=batch.batch_no,
                    root_batch_id=batch.root_batch_id,
                    sequence=sequence,
                    type="remnant_discard",
                    quantity_delta=0,
                    quantity_before=after_qty,
                    quantity_after=after_qty,
                    width_before_mm=batch.width_mm,
                    height_before_mm=batch.height_mm,
                    width_after_mm=batch.width_mm,
                    height_after_mm=batch.height_mm,
                    area_before_mm2=batch.area_mm2,
                    area_after_mm2=batch.area_mm2 - remnant["area_mm2"],
                    used_length_mm=long,
                    used_width_mm=short,
                    cut_option=option,
                    remnant_action="discard",
                    remnant_shape=remnant["shape_type"],
                    remnant_area_mm2=remnant["area_mm2"],
                    usage_record_id=usage.id,
                    device_id=ctx.device.id,
                    note="余料按用户选择丢弃，不入库",
                )
            )

        piece_waste = max(0, batch.area_mm2 - short * long)
        total_waste += piece_waste * count
        results.append(
            {
                "batch_id": batch.id,
                "batch_no": batch.batch_no,
                "quantity": count,
                "cut_option": option,
                "cut_option_label": CUT_LABELS[option],
                "remnant_action": action,
                "remnant_action_label": REMNANT_LABELS.get(action or "", None),
                "remnant": remnant,
                "remnant_batch": batch_payload(produced, project.min_usable_mm) if produced else None,
                "waste_mm2": piece_waste * count,
                "placement": preview["placement"],
                "rotation": preview["rotation"],
                "utilization": preview["utilization"],
                "quantity_before": before_qty,
                "quantity_after": after_qty,
                "trace_url": f"{settings.api_prefix}/projects/{project.id}/trace/{produced.id if produced else batch.id}",
            }
        )

    usage.total_waste_mm2 = total_waste
    audit.log(
        db,
        "usage.confirm",
        project_id=project.id,
        device_id=ctx.device.id,
        target_type="usage",
        target_id=usage.id,
        detail={"quantity": qty, "demand": f"{long}x{short}", "allocations": len(raw_allocations)},
        ip=ip,
    )
    db.commit()

    return build_usage_response(db, project, usage, replayed=False, results=results)


def _create_remnant_batch(
    db: Session,
    project: Project,
    ctx: ProjectContext,
    parent: InventoryBatch,
    remnant: dict,
    count: int,
    option: str,
    used_long: int,
    used_short: int,
) -> InventoryBatch:
    geom = remnant["geometry"]
    batch = InventoryBatch(
        id=new_id(),
        project_id=project.id,
        batch_no=_next_batch_no(db, project.id),
        shape_type=geom["type"],
        width_mm=remnant["width_mm"],
        height_mm=remnant["height_mm"],
        geometry=geom,
        area_mm2=remnant["area_mm2"],
        notch_w_mm=(geom.get("notch") or {}).get("w"),
        notch_h_mm=(geom.get("notch") or {}).get("h"),
        notch_corner=geom.get("notch_corner"),
        quantity=count,
        initial_quantity=count,
        source_type="cut",
        parent_batch_id=parent.id,
        root_batch_id=parent.root_batch_id or parent.id,
        cut_option=option,
        used_length_mm=used_long,
        used_width_mm=used_short,
        location=parent.location,
        note=f"切割余料（父批次 #{parent.batch_no:04d}）",
        status="available",
        created_by_device_id=ctx.device.id,
    )
    db.add(batch)
    db.flush()
    return batch


def build_usage_response(
    db: Session,
    project: Project,
    usage: UsageRecord,
    replayed: bool,
    results: list[dict] | None = None,
) -> dict:
    movements = list(
        db.scalars(
            select(InventoryMovement)
            .where(InventoryMovement.usage_record_id == usage.id)
            .order_by(InventoryMovement.created_at.asc(), InventoryMovement.sequence.asc())
        ).all()
    )

    if results is None:
        results = _rebuild_results(db, project, usage, movements)

    pieces_after = db.scalar(
        select(func.coalesce(func.sum(InventoryBatch.quantity), 0)).where(
            InventoryBatch.project_id == project.id, InventoryBatch.status == "available"
        )
    )
    return {
        "usage_id": usage.id,
        "replayed": replayed,
        "created_at": iso(usage.created_at),
        "demand": {
            "length_mm": usage.demand_length_mm,
            "width_mm": usage.demand_width_mm,
            "quantity": usage.demand_quantity,
            "area_mm2": usage.demand_length_mm * usage.demand_width_mm,
        },
        "results": results,
        "total_waste_mm2": usage.total_waste_mm2,
        "inventory_after": {"pieces": int(pieces_after or 0)},
        "movements": [movement_payload(m) for m in movements],
        "trace_url": f"/api/projects/{project.id}/trace/{results[0]['batch_id']}" if results else None,
    }


def _rebuild_results(
    db: Session,
    project: Project,
    usage: UsageRecord,
    movements: list[InventoryMovement],
) -> list[dict]:
    """Reconstruct the confirm response from the ledger (idempotent replay)."""
    grouped: dict[str, list[InventoryMovement]] = {}
    for m in movements:
        if m.type == "usage":
            grouped.setdefault(m.batch_id, []).append(m)

    produced_by_parent: dict[str, InventoryBatch] = {}
    for m in movements:
        if m.type == "cut_remnant" and m.produced_batch_id:
            child = db.get(InventoryBatch, m.produced_batch_id)
            if child is not None and child.parent_batch_id:
                produced_by_parent[child.parent_batch_id] = child

    results: list[dict] = []
    for batch_id, rows in grouped.items():
        batch = db.get(InventoryBatch, batch_id)
        first = rows[0]
        produced_batch = produced_by_parent.get(batch_id)
        results.append(
            {
                "batch_id": batch_id,
                "batch_no": first.batch_no,
                "quantity": len(rows),
                "cut_option": first.cut_option,
                "cut_option_label": CUT_LABELS.get(first.cut_option or "", None),
                "remnant_action": first.remnant_action,
                "remnant_action_label": REMNANT_LABELS.get(first.remnant_action or "", None),
                "remnant": None,
                "remnant_batch": batch_payload(produced_batch, project.min_usable_mm) if produced_batch else None,
                "waste_mm2": max(0, (batch.area_mm2 if batch else 0) - usage.demand_length_mm * usage.demand_width_mm)
                * len(rows),
                "quantity_before": first.quantity_before,
                "quantity_after": rows[-1].quantity_after,
                "trace_url": f"{settings.api_prefix}/projects/{project.id}/trace/{produced_batch.id if produced_batch else batch_id}",
            }
        )
    return results


__all__ = ["confirm_usage", "build_usage_response"]
