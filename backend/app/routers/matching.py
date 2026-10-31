"""Matching, usage confirmation, movements and trace endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..deps import ProjectContext, client_ip, get_project_context
from ..ratelimit import enforce
from ..schemas import MatchIn, UsageConfirmIn
from ..services import matching as matching_service
from ..services import movements as movement_service
from ..services import trace as trace_service
from ..services import usage as usage_service
from ..utils import iso, utcnow

router = APIRouter(prefix="/projects/{project_id}", tags=["matching"])


@router.post("/match", summary="按需求尺寸匹配最合适的余砖")
def match(
    payload: MatchIn,
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "match")
    short, long, qty = matching_service.resolve_demand(
        ctx.project, payload.length, payload.width, payload.quantity, payload.unit
    )
    result = matching_service.match(db, ctx.project, short, long, qty, limit=payload.limit)
    result["project"] = {"id": ctx.project.id, "min_usable_mm": ctx.project.min_usable_mm}
    return result


@router.post("/usage/confirm", summary="确认使用：事务扣减 + 余料入库/丢弃 + 流水")
def confirm_usage(
    payload: UsageConfirmIn,
    request: Request,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    enforce(client_ip(request), "usage.confirm", write=True)
    return usage_service.confirm_usage(db, ctx, payload, ip=client_ip(request))


@router.get("/movements", summary="变动流水（筛选 + 分页）")
def list_movements(
    batch_id: str | None = Query(default=None),
    root_batch_id: str | None = Query(default=None),
    type: str | None = Query(default=None, description="逗号分隔，如 usage,cut_remnant"),
    device_id: str | None = Query(default=None),
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    q: str | None = Query(default=None, max_length=80),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=settings.default_page_size, ge=1, le=settings.max_page_size),
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    filters = {
        "batch_id": batch_id,
        "root_batch_id": root_batch_id,
        "type": type,
        "device_id": device_id,
        "date_from": movement_service.parse_datetime(date_from),
        "date_to": movement_service.parse_datetime(date_to),
        "q": q,
    }
    return movement_service.list_movements(db, ctx.project, filters, page=page, page_size=page_size)


@router.get("/movements/export", summary="导出流水 CSV")
def export_movements(
    batch_id: str | None = Query(default=None),
    type: str | None = Query(default=None),
    date_from: str | None = Query(default=None),
    date_to: str | None = Query(default=None),
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> Response:
    filters = {
        "batch_id": batch_id,
        "type": type,
        "date_from": movement_service.parse_datetime(date_from),
        "date_to": movement_service.parse_datetime(date_to),
    }
    csv_text = movement_service.export_csv(db, ctx.project, filters)
    stamp = utcnow().strftime("%Y%m%d-%H%M")
    filename = f"movements-{ctx.project.id[:8]}-{stamp}.csv"
    return Response(
        content="\ufeff" + csv_text,  # BOM so Excel opens Chinese headers correctly
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/trace/{batch_id}", summary="溯源对比：原砖 vs 需求 vs 余料 + 父子链 + 关联流水")
def trace(
    batch_id: str,
    ctx: ProjectContext = Depends(get_project_context),
    db: Session = Depends(get_db),
) -> dict:
    result = trace_service.build_trace(db, ctx.project, batch_id)
    result["generated_at"] = iso(utcnow())
    return result
