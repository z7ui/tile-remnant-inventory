"""Inventory endpoints (manual rectangle stock-in, filtering, adjustments)."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..deps import ProjectContext, client_ip, get_project_context
from ..ratelimit import enforce
from ..schemas import InventoryCreateIn, InventoryPatchIn
from ..services import inventory as inventory_service
from ..services.serializers import batch_payload

router = APIRouter(prefix="/projects/{project_id}/inventory", tags=["inventory"])


def inventory_filters(
    q: str | None = Query(default=None, max_length=80),
    batch_id: str | None = Query(default=None, max_length=40),
    shape_type: Literal["rectangle", "l_shape", "irregular"] | None = None,
    source_type: Literal["manual", "cut"] | None = None,
    location: str | None = Query(default=None, max_length=120),
    status: Literal["available", "depleted", "void"] | None = None,
    min_quantity: int | None = Query(default=None, ge=0),
    max_quantity: int | None = Query(default=None, ge=0),
    min_short_mm: int | None = Query(default=None, ge=0),
    max_short_mm: int | None = Query(default=None, ge=0),
    min_long_mm: int | None = Query(default=None, ge=0),
    max_long_mm: int | None = Query(default=None, ge=0),
    created_from: str | None = Query(default=None),
    created_to: str | None = Query(default=None),
    only_available: bool = Query(default=True),
) -> dict:
    return {
        "q": q,
        "batch_id": batch_id,
        "shape_type": shape_type,
        "source_type": source_type,
        "location": location,
        "status": status,
        "min_quantity": min_quantity,
        "max_quantity": max_quantity,
        "min_short_mm": min_short_mm,
        "max_short_mm": max_short_mm,
        "min_long_mm": min_long_mm,
        "max_long_mm": max_long_mm,
        "created_from": inventory_service.parse_date(created_from),
        "created_to": inventory_service.parse_date(created_to),
        "only_available": only_available,
    }


@router.post("", summary="录入矩形余砖（仅矩形）", status_code=201)
def create_inventory(
    payload: InventoryCreateIn,
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "inventory.create", write=True)
    return inventory_service.create_batch(db, ctx, payload, ip=client_ip(request))


@router.get("", summary="库存列表（筛选 + 分页）")
def list_inventory(
    filters: dict = Depends(inventory_filters),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=settings.default_page_size, ge=1, le=settings.max_page_size),
    sort: Literal["created_desc", "created_asc", "area_desc", "quantity_desc", "batch_no_desc"] = "created_desc",
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    return inventory_service.list_batches(db, ctx.project, filters, page=page, page_size=page_size, sort=sort)


@router.get("/{batch_id}", summary="批次详情")
def get_inventory(
    batch_id: str,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    batch = inventory_service.get_batch(db, ctx.project, batch_id)
    return {"batch": batch_payload(batch, ctx.project.min_usable_mm)}


@router.patch("/{batch_id}", summary="修改存放位置/备注/片数/状态")
def patch_inventory(
    batch_id: str,
    payload: InventoryPatchIn,
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "inventory.patch", write=True)
    return inventory_service.update_batch(db, ctx, batch_id, payload, ip=client_ip(request))
