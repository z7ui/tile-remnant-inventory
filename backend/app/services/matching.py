"""Matching engine: pick the best remnant batch for a demand rectangle."""

from __future__ import annotations

from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import geometry
from ..errors import ApiError
from ..models import InventoryBatch, Project
from ..units import DimensionError, parse_length_mm, parse_quantity
from .serializers import batch_payload


def resolve_demand(project: Project, length: Any, width: Any, quantity: Any, unit: str | None) -> tuple[int, int, int]:
    use_unit = unit or project.default_unit
    try:
        length_mm = parse_length_mm(length, use_unit, "需求长度")
        width_mm = parse_length_mm(width, use_unit, "需求宽度")
        qty = parse_quantity(quantity, "需求数量")
    except DimensionError as exc:
        raise ApiError(422, "invalid_dimension", str(exc)) from exc
    short, long = geometry.normalize_pair(length_mm, width_mm)
    return short, long, qty


def _remnant_value(remnant: dict | None, min_usable_mm: int) -> float:
    if not remnant:
        return 0.0
    value = float(remnant["area_mm2"])
    if remnant.get("composite"):
        value *= 0.75
    if remnant.get("below_threshold"):
        value *= 0.4
    return value


def evaluate_batch(
    batch: InventoryBatch,
    demand_short: int,
    demand_long: int,
    min_usable_mm: int,
    want_pieces: int = 1,
) -> dict[str, Any] | None:
    w, h, region = geometry.region_from_geometry(batch.geometry)
    if not geometry.fits(region, demand_short, demand_long):
        return None

    previews = [
        geometry.usage_preview(region, w, h, demand_short, demand_long, option, min_usable_mm)
        for option in ("long_side_cut", "short_side_cut")
    ]
    feasible = [p for p in previews if p["feasible"]]
    if not feasible:
        return None

    # prefer the option that leaves the most reusable remnant; ties -> long side
    feasible.sort(
        key=lambda p: (
            p["remnant"] is None,
            -_remnant_value(p["remnant"], min_usable_mm),
            p["cut_option"] != "long_side_cut",
        )
    )
    best = feasible[0]

    cap = max(1, min(want_pieces, max(1, batch.quantity), 20))
    max_pieces = geometry.pieces_available(region, w, h, demand_short, demand_long, cap)
    stock_area = batch.area_mm2
    demand_area = demand_short * demand_long
    waste = max(0, stock_area - demand_area)

    return {
        "batch": batch_payload(batch, min_usable_mm),
        "stock": {
            "shape_type": batch.shape_type,
            "width_mm": w,
            "height_mm": h,
            "area_mm2": stock_area,
            "rects": batch.geometry.get("rects", []),
            "notch": batch.geometry.get("notch"),
            "notch_corner": batch.geometry.get("notch_corner"),
        },
        "match": {
            "waste_mm2": waste,
            "waste_ratio": round(waste / stock_area, 4) if stock_area else 0.0,
            "utilization": round(demand_area / stock_area, 4) if stock_area else 0.0,
            "rotation": best["rotation"],
            "cut_option": best["cut_option"],
            "cut_option_label": "长边切到底" if best["cut_option"] == "long_side_cut" else "短边切到底",
            "placement": best["placement"],
            "remnant": best["remnant"],
            "remnant_value": round(_remnant_value(best["remnant"], min_usable_mm)),
            "max_pieces": max_pieces,
        },
        "cut_options": previews,
    }


def load_available_batches(db: Session, project: Project) -> list[InventoryBatch]:
    return list(
        db.scalars(
            select(InventoryBatch)
            .where(
                InventoryBatch.project_id == project.id,
                InventoryBatch.status == "available",
                InventoryBatch.quantity > 0,
            )
            .order_by(InventoryBatch.created_at.asc(), InventoryBatch.batch_no.asc())
        ).all()
    )


def match(
    db: Session,
    project: Project,
    demand_short: int,
    demand_long: int,
    quantity: int,
    limit: int = 10,
) -> dict:
    candidates: list[dict] = []
    rejected: list[dict] = []
    for batch in load_available_batches(db, project):
        evaluated = evaluate_batch(batch, demand_short, demand_long, project.min_usable_mm, quantity)
        if evaluated is None:
            w, h, _ = geometry.region_from_geometry(batch.geometry)
            if geometry.fits([(0, 0, w, h)], demand_short, demand_long):
                rejected.append({"batch_id": batch.id, "batch_no": batch.batch_no, "reason": "几何形状不满足，无法直切"})
            continue
        candidates.append(evaluated)

    # waste first, then the more reusable remnant, then more pieces / older batch
    candidates.sort(
        key=lambda c: (
            c["match"]["waste_mm2"],
            -c["match"]["remnant_value"],
            -c["match"]["max_pieces"],
            c["batch"]["created_at"],
            c["batch"]["batch_no"],
        )
    )

    allocation: list[dict] = []
    remaining = quantity
    for cand in candidates:
        if remaining <= 0:
            break
        take = min(remaining, cand["match"]["max_pieces"], cand["batch"]["quantity"])
        if take <= 0:
            continue
        allocation.append(
            {
                "batch_id": cand["batch"]["id"],
                "batch_no": cand["batch"]["batch_no"],
                "quantity": take,
                "cut_option": cand["match"]["cut_option"],
                "remnant_action": "store" if cand["match"]["remnant"] else None,
            }
        )
        remaining -= take

    return {
        "demand": {
            "length_mm": demand_long,
            "width_mm": demand_short,
            "short_mm": demand_short,
            "long_mm": demand_long,
            "quantity": quantity,
            "area_mm2": demand_short * demand_long,
        },
        "candidates": candidates[:limit],
        "total_candidates": len(candidates),
        "rejected": rejected[:10],
        "allocation": allocation,
        "unfulfilled_quantity": max(0, remaining),
        "sorting": "浪费面积 → 余料可再利用价值 → 可用片数 → 录入时间/批次",
    }
