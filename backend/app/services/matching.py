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

    # 单块余料最多能切多少片需求，只需精确到需求数量即可。
    # 之前这里混入 batch.quantity（那是「块数」，与单块切割片数无关）和硬编码 20，
    # 导致大余料（如 1500×7490 切 600×600 实际能切 24 片）被低估成 20 片，匹配凑不满。
    cap = max(1, want_pieces)
    # 用 best 的单一方向估算可切片数，保证和分配的 cut_option 一致；
    # 否则混合方向能切 10 片、单一方向只切得出 8 片，确认时就会报「切不出」。
    max_pieces = geometry.pieces_available(region, w, h, demand_short, demand_long, cap, best["cut_option"])
    stock_area = batch.area_mm2
    demand_area = demand_short * demand_long
    # 按「切满 max_pieces 片」算浪费，而不是只算 1 片：
    # 600×1200 切 600×600 能切 2 片正好用完，利用率应 100%、浪费 0；
    # 之前按单片算会显示利用率 50%、浪费半块。
    used_area = max_pieces * demand_area
    waste = max(0, stock_area - used_area)

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
            "utilization": round(min(1.0, used_area / stock_area), 4) if stock_area else 0.0,
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

    # 按「每片浪费面积」排序（总浪费 / 能切几片），让利用率高的余料优先。
    # 之前按单块浪费（切 1 片的浪费）排，把「单块小但利用率低」的余料排前面，
    # 导致一块能切多片的大余料（利用率高）反而用不上。
    demand_area = demand_short * demand_long
    candidates.sort(
        key=lambda c: (
            max(0, c["stock"]["area_mm2"] - c["match"]["max_pieces"] * demand_area) / c["match"]["max_pieces"],
            -c["match"]["remnant_value"],
            c["batch"]["created_at"],
            c["batch"]["batch_no"],
        )
    )

    allocation: list[dict] = []
    remaining = quantity
    for cand in candidates:
        if remaining <= 0:
            break
        max_pieces = cand["match"]["max_pieces"]
        blocks = cand["batch"]["quantity"]
        # 一块余料能切 max_pieces 片需求，这个批次有 blocks 块，逐块分配。
        # 之前这里 `min(remaining, max_pieces, quantity)` 把「块数」当「片数」用，
        # 导致一块能切多片时要么少取、要么把片数当块数扣减，库存账对不上。
        while remaining > 0 and blocks > 0:
            take = min(remaining, max_pieces)
            if take <= 0:
                break
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
            blocks -= 1

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


def match_multi(
    db: Session,
    project: Project,
    demands: list[tuple[int, int, int]],
    limit_blocks: int = 200,
) -> dict:
    """
    多个尺寸一起匹配：大件优先，一块砖内递归切割（一刀切到底），余料当场给小块用。

    demands: [(短边, 长边, 数量), ...]
    limit_blocks: 单次最多排多少块砖（防止超大需求把接口拖死）。

    返回每块砖的混排计划，以及「满足 / 缺口 / 利用率」汇总。
    """
    from . import nesting

    # 合并同尺寸，并按面积降序（大件优先）
    merged: dict[tuple[int, int], int] = {}
    for short, long, qty in demands:
        key = (short, long) if short <= long else (long, short)
        merged[key] = merged.get(key, 0) + max(0, qty)
    remaining: dict[tuple[int, int], int] = {k: v for k, v in merged.items() if v > 0}
    ordered = sorted(remaining.keys(), key=lambda k: k[0] * k[1], reverse=True)

    batches = load_available_batches(db, project)
    blocks: list[dict] = []
    skipped: list[dict] = []

    for batch in batches:
        if len(blocks) >= limit_blocks:
            break
        if not any(v > 0 for v in remaining.values()):
            break

        _, _, region = geometry.region_from_geometry(batch.geometry)
        if len(region) != 1:
            # L 形/复合余料暂不参与混排：切法不唯一，先只做矩形，避免算出切不出来的方案
            skipped.append(
                {
                    "batch_id": batch.id,
                    "batch_no": batch.batch_no,
                    "reason": "非矩形余料，暂不参与多尺寸混排",
                }
            )
            continue

        w, h = batch.width_mm, batch.height_mm
        left = batch.quantity
        while left > 0 and any(v > 0 for v in remaining.values()):
            live = [(sw, sl, n) for (sw, sl), n in remaining.items() if n > 0]
            plan = nesting.fill_block(w, h, live)
            if not plan.placed:
                break
            for (pw, ph), n in plan.placed.items():
                remaining[(pw, ph)] = max(0, remaining[(pw, ph)] - n)
            blocks.append(
                {
                    "batch_id": batch.id,
                    "batch_no": batch.batch_no,
                    "width_mm": w,
                    "height_mm": h,
                    "cut_option": "nesting",
                    "plan": plan.as_dict(),
                }
            )
            left -= 1

    total_pieces = sum(merged.values())
    missing = sum(remaining.values())
    used_area = sum(b["plan"]["used_area_mm2"] for b in blocks)
    stock_area = sum(b["width_mm"] * b["height_mm"] for b in blocks)

    return {
        "demands": [
            {
                "short_mm": short,
                "long_mm": long,
                "length_mm": long,
                "width_mm": short,
                "quantity": merged[(short, long)],
                "fulfilled": merged[(short, long)] - remaining.get((short, long), 0),
                "missing": remaining.get((short, long), 0),
                "area_mm2": short * long,
            }
            for (short, long) in ordered
        ],
        "blocks": blocks,
        "summary": {
            "blocks_used": len(blocks),
            "demand_pieces": total_pieces,
            "fulfilled_pieces": total_pieces - missing,
            "missing_pieces": missing,
            "used_area_mm2": used_area,
            "waste_area_mm2": stock_area - used_area,
            "utilization": (used_area / stock_area) if stock_area else 0.0,
        },
        "skipped": skipped[:10],
        "sorting": "大件优先（面积降序）→ 每块砖递归切割（一刀切到底）→ 余料当场切小块",
    }
