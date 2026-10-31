"""Traceability: original tile vs. demand vs. remnant, plus the batch family tree."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..models import InventoryBatch, InventoryMovement, Project, UsageRecord
from ..utils import iso
from .serializers import CUT_LABELS, REMNANT_LABELS, batch_payload, movement_payload


def _ancestors(db: Session, batch: InventoryBatch) -> list[InventoryBatch]:
    chain: list[InventoryBatch] = []
    seen: set[str] = set()
    current = batch
    while current.parent_batch_id and current.parent_batch_id not in seen:
        seen.add(current.parent_batch_id)
        parent = db.get(InventoryBatch, current.parent_batch_id)
        if parent is None or parent.project_id != batch.project_id:
            break
        chain.append(parent)
        current = parent
    chain.reverse()
    return chain


def _node(batch: InventoryBatch, is_current: bool = False) -> dict:
    return {
        "id": batch.id,
        "batch_no": batch.batch_no,
        "code": f"#{batch.batch_no:04d}",
        "shape_type": batch.shape_type,
        "width_mm": batch.width_mm,
        "height_mm": batch.height_mm,
        "area_mm2": batch.area_mm2,
        "quantity": batch.quantity,
        "initial_quantity": batch.initial_quantity,
        "status": batch.status,
        "source_type": batch.source_type,
        "is_current": is_current,
    }


def build_trace(db: Session, project: Project, batch_id: str) -> dict:
    batch = db.get(InventoryBatch, batch_id)
    if batch is None or batch.project_id != project.id:
        from ..errors import ApiError

        raise ApiError(404, "batch_not_found", "余砖批次不存在。")

    root = db.get(InventoryBatch, batch.root_batch_id) if batch.root_batch_id else batch
    root = root or batch
    ancestors = _ancestors(db, batch)
    children = list(
        db.scalars(
            select(InventoryBatch)
            .where(InventoryBatch.project_id == project.id, InventoryBatch.parent_batch_id == batch.id)
            .order_by(InventoryBatch.batch_no.asc())
        ).all()
    )

    creation = db.scalar(
        select(InventoryMovement)
        .where(InventoryMovement.batch_id == batch.id, InventoryMovement.type == "cut_remnant")
        .order_by(InventoryMovement.created_at.asc())
    )
    usage = db.get(UsageRecord, creation.usage_record_id) if creation and creation.usage_record_id else None

    related_stmt = select(InventoryMovement).where(
        InventoryMovement.project_id == project.id,
        (InventoryMovement.batch_id == batch.id) | (InventoryMovement.produced_batch_id == batch.id),
    )
    if creation is not None and creation.usage_record_id:
        # the cut that produced this remnant also lives on the parent batch
        related_stmt = select(InventoryMovement).where(
            InventoryMovement.project_id == project.id,
            (InventoryMovement.batch_id == batch.id)
            | (InventoryMovement.produced_batch_id == batch.id)
            | (InventoryMovement.usage_record_id == creation.usage_record_id),
        )
    related = list(
        db.scalars(
            related_stmt.order_by(InventoryMovement.created_at.asc(), InventoryMovement.sequence.asc())
        ).all()
    )

    original = {
        "label": "原砖",
        "batch_id": root.id,
        "batch_no": root.batch_no,
        "width_mm": root.width_mm,
        "height_mm": root.height_mm,
        "area_mm2": root.area_mm2,
        "shape_type": root.shape_type,
        "quantity": root.initial_quantity,
        "geometry": root.geometry,
    }

    demand = None
    if creation is not None:
        demand = {
            "label": "本次需求",
            "length_mm": creation.used_length_mm,
            "width_mm": creation.used_width_mm,
            "area_mm2": (creation.used_length_mm or 0) * (creation.used_width_mm or 0),
            "quantity": usage.demand_quantity if usage else batch.initial_quantity,
            "cut_option": creation.cut_option,
            "cut_option_label": CUT_LABELS.get(creation.cut_option or "", None),
            "remnant_action": creation.remnant_action,
            "remnant_action_label": REMNANT_LABELS.get(creation.remnant_action or "", None),
            "usage_id": creation.usage_record_id,
            "at": iso(creation.created_at),
        }

    remnant = {
        "label": "切后余料",
        "batch_id": batch.id,
        "width_mm": batch.width_mm,
        "height_mm": batch.height_mm,
        "area_mm2": batch.area_mm2,
        "shape_type": batch.shape_type,
        "notch": batch.geometry.get("notch"),
        "notch_corner": batch.geometry.get("notch_corner"),
        "rects": batch.geometry.get("rects", []),
        "below_min_usable": min(batch.width_mm, batch.height_mm) < project.min_usable_mm,
    } if batch.source_type == "cut" else None

    if remnant is not None and demand is not None:
        demand_area = demand["area_mm2"] or 1
        remnant["utilization"] = round(demand_area / original["area_mm2"], 4) if original["area_mm2"] else None
        remnant["area_ratio"] = round(batch.area_mm2 / original["area_mm2"], 4) if original["area_mm2"] else None

    chain_nodes = [_node(b) for b in ancestors] + [_node(batch, True)] + [_node(c) for c in children]

    return {
        "batch": batch_payload(batch, project.min_usable_mm),
        "root": _node(root),
        "ancestors": [_node(b) for b in ancestors],
        "children": [_node(c) for c in children],
        "chain": {
            "nodes": chain_nodes,
            "current_index": len(ancestors),
            "edges": [
                {"from": ancestors[i].id, "to": (ancestors[i + 1] if i + 1 < len(ancestors) else batch).id}
                for i in range(len(ancestors))
            ]
            + [{"from": batch.id, "to": c.id} for c in children],
        },
        "comparison": {"original": original, "demand": demand, "remnant": remnant},
        "usage": {
            "id": usage.id,
            "quantity": usage.demand_quantity,
            "length_mm": usage.demand_length_mm,
            "width_mm": usage.demand_width_mm,
            "total_waste_mm2": usage.total_waste_mm2,
            "created_at": iso(usage.created_at),
            "device_id": usage.device_id,
        }
        if usage
        else None,
        "movements": [movement_payload(m) for m in related],
        "links": {
            "self": f"{settings.api_prefix}/projects/{project.id}/trace/{batch.id}",
            "inventory": f"{settings.api_prefix}/projects/{project.id}/inventory?batch_id={batch.id}",
            "movements": f"{settings.api_prefix}/projects/{project.id}/movements?batch_id={batch.id}",
        },
    }
