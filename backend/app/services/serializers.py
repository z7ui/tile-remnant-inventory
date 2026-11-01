"""Uniform JSON serialisers shared by all routers."""

from __future__ import annotations

from typing import Any

from ..config import settings
from ..models import InventoryBatch, InventoryMovement, Project
from ..utils import iso


def batch_payload(batch: InventoryBatch, min_usable_mm: int = 50) -> dict[str, Any]:
    geom = batch.geometry or {}
    return {
        "id": batch.id,
        "batch_no": batch.batch_no,
        "code": f"#{batch.batch_no:04d}",
        "shape_type": batch.shape_type,
        "width_mm": batch.width_mm,
        "height_mm": batch.height_mm,
        "short_mm": min(batch.width_mm, batch.height_mm),
        "long_mm": max(batch.width_mm, batch.height_mm),
        "area_mm2": batch.area_mm2,
        "geometry": geom,
        "rects": geom.get("rects", []),
        "notch": {
            "w": batch.notch_w_mm,
            "h": batch.notch_h_mm,
            "corner": batch.notch_corner,
        }
        if batch.shape_type == "l_shape" and batch.notch_w_mm
        else None,
        "composite": bool(geom.get("composite")),
        "quantity": batch.quantity,
        "initial_quantity": batch.initial_quantity,
        "quantity_used": max(0, batch.initial_quantity - batch.quantity),
        "source_type": batch.source_type,
        "parent_batch_id": batch.parent_batch_id,
        "root_batch_id": batch.root_batch_id,
        "cut_option": batch.cut_option,
        "used_length_mm": batch.used_length_mm,
        "used_width_mm": batch.used_width_mm,
        "location": batch.location,
        "note": batch.note,
        "status": batch.status,
        "is_available": batch.status == "available" and batch.quantity > 0,
        "below_min_usable": min(batch.width_mm, batch.height_mm) < min_usable_mm,
        "created_by_device_id": batch.created_by_device_id,
        "created_at": iso(batch.created_at),
        "updated_at": iso(batch.updated_at),
        "version": batch.version,
        "trace_url": f"{settings.api_prefix}/projects/{batch.project_id}/trace/{batch.id}",
    }


def movement_payload(m: InventoryMovement) -> dict[str, Any]:
    return {
        "id": m.id,
        "batch_id": m.batch_id,
        "batch_no": m.batch_no,
        "batch_code": f"#{m.batch_no:04d}",
        "root_batch_id": m.root_batch_id,
        "sequence": m.sequence,
        "type": m.type,
        "type_label": MOVEMENT_LABELS.get(m.type, m.type),
        "quantity_delta": m.quantity_delta,
        "quantity_before": m.quantity_before,
        "quantity_after": m.quantity_after,
        "width_before_mm": m.width_before_mm,
        "height_before_mm": m.height_before_mm,
        "width_after_mm": m.width_after_mm,
        "height_after_mm": m.height_after_mm,
        "area_before_mm2": m.area_before_mm2,
        "area_after_mm2": m.area_after_mm2,
        "used_length_mm": m.used_length_mm,
        "used_width_mm": m.used_width_mm,
        "cut_option": m.cut_option,
        "cut_option_label": CUT_LABELS.get(m.cut_option or "", None),
        "remnant_action": m.remnant_action,
        "remnant_action_label": REMNANT_LABELS.get(m.remnant_action or "", None),
        "remnant_shape": m.remnant_shape,
        "remnant_area_mm2": m.remnant_area_mm2,
        "produced_batch_id": m.produced_batch_id,
        "usage_record_id": m.usage_record_id,
        "device_id": m.device_id,
        "note": m.note,
        "created_at": iso(m.created_at),
        "trace_url": f"{settings.api_prefix}/projects/{m.project_id}/trace/{m.batch_id}",
    }


MOVEMENT_LABELS = {
    "stock_in": "入库",
    "usage": "使用扣减",
    "cut_remnant": "切割生成余料",
    "remnant_discard": "余料丢弃",
    "adjust": "人工调整",
    "void": "作废",
}

CUT_LABELS = {"long_side_cut": "长边切到底", "short_side_cut": "短边切到底"}
REMNANT_LABELS = {"store": "直接入库", "discard": "丢弃"}


def project_payload(project: Project, role: str, stats: dict | None = None) -> dict[str, Any]:
    return {
        "id": project.id,
        "name": project.name,
        # 特征码：名字允许重复，界面上靠它区分同名项目
        "code": project.short_code,
        "default_unit": project.default_unit,
        "min_usable_mm": project.min_usable_mm,
        "role": role,
        "status": project.status,
        "created_at": iso(project.created_at),
        "deleted_at": iso(project.deleted_at),
        "stats": stats or {},
    }
