"""Inventory movements (append-only ledger) and CSV export."""

from __future__ import annotations

import csv
import io
import re
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import InventoryMovement, Project

# Excel / Numbers / WPS 打开 CSV 时，会把以 = + - @ 开头的单元格当公式执行
# （CSV injection：`=HYPERLINK("http://x","点我")` 或 `=cmd|'/C calc'!A0`）。
# 这里的「项目」和「备注」两列直接来自用户输入，所以要中和掉。
# 但 `-5` 这种负数不能被误伤，所以 `-` 只在「不像数字」时才加前缀。
_NUMERIC = re.compile(r"^-?\d+(?:\.\d+)?$")
_FORMULA_HEADS = ("=", "+", "@", "\t", "\r")


def _csv_safe(value: object) -> object:
    """Neutralise formula-looking strings so spreadsheet apps treat them as text."""
    if not isinstance(value, str) or not value:
        return value
    head = value[0]
    if head in _FORMULA_HEADS:
        return "'" + value
    if head == "-" and not _NUMERIC.match(value):
        return "'" + value
    return value
from ..utils import iso
from .serializers import MOVEMENT_LABELS, movement_payload


def list_movements(
    db: Session,
    project: Project,
    filters: dict,
    page: int = 1,
    page_size: int = 20,
) -> dict:
    stmt = select(InventoryMovement).where(InventoryMovement.project_id == project.id)
    if filters.get("type"):
        types = [t.strip() for t in str(filters["type"]).split(",") if t.strip()]
        stmt = stmt.where(InventoryMovement.type.in_(types))
    if filters.get("batch_id"):
        stmt = stmt.where(InventoryMovement.batch_id == filters["batch_id"])
    if filters.get("root_batch_id"):
        stmt = stmt.where(InventoryMovement.root_batch_id == filters["root_batch_id"])
    if filters.get("device_id"):
        stmt = stmt.where(InventoryMovement.device_id == filters["device_id"])
    if filters.get("date_from"):
        stmt = stmt.where(InventoryMovement.created_at >= filters["date_from"])
    if filters.get("date_to"):
        stmt = stmt.where(InventoryMovement.created_at <= filters["date_to"])
    if filters.get("q"):
        needle = f"%{filters['q'].strip()}%"
        stmt = stmt.where(InventoryMovement.note.ilike(needle))

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(
        stmt.order_by(InventoryMovement.created_at.desc(), InventoryMovement.sequence.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()

    return {
        "items": [movement_payload(m) for m in rows],
        "page": page,
        "page_size": page_size,
        "total": int(total),
        "has_more": page * page_size < int(total),
    }


CSV_HEADERS = [
    ("时间", "created_at"),
    ("项目", "project"),
    ("设备", "device_id"),
    ("批次", "batch_code"),
    ("根批次", "root_batch_id"),
    ("类型", "type_label"),
    ("变动前尺寸(mm)", "before_size"),
    ("变动后尺寸(mm)", "after_size"),
    ("变动前片数", "quantity_before"),
    ("变动后片数", "quantity_after"),
    ("数量变化", "quantity_delta"),
    ("使用尺寸(mm)", "used_size"),
    ("切割方式", "cut_option_label"),
    ("余料处置", "remnant_action_label"),
    ("余料形状", "remnant_shape"),
    ("余料面积(mm2)", "remnant_area_mm2"),
    ("关联使用记录", "usage_record_id"),
    ("备注", "note"),
]


def _row(m: InventoryMovement, project: Project) -> dict:
    payload = movement_payload(m)
    before = (
        f"{m.width_before_mm}x{m.height_before_mm}" if m.width_before_mm and m.height_before_mm else ""
    )
    after = f"{m.width_after_mm}x{m.height_after_mm}" if m.width_after_mm and m.height_after_mm else ""
    used = f"{m.used_length_mm}x{m.used_width_mm}" if m.used_length_mm and m.used_width_mm else ""
    row = dict(payload)
    row.update(
        {
            "project": project.name,
            "before_size": before,
            "after_size": after,
            "used_size": used,
            "type_label": MOVEMENT_LABELS.get(m.type, m.type),
        }
    )
    return row


def export_csv(db: Session, project: Project, filters: dict, limit: int = 20000) -> str:
    stmt = select(InventoryMovement).where(InventoryMovement.project_id == project.id)
    if filters.get("type"):
        types = [t.strip() for t in str(filters["type"]).split(",") if t.strip()]
        stmt = stmt.where(InventoryMovement.type.in_(types))
    if filters.get("batch_id"):
        stmt = stmt.where(InventoryMovement.batch_id == filters["batch_id"])
    if filters.get("date_from"):
        stmt = stmt.where(InventoryMovement.created_at >= filters["date_from"])
    if filters.get("date_to"):
        stmt = stmt.where(InventoryMovement.created_at <= filters["date_to"])

    rows = db.scalars(stmt.order_by(InventoryMovement.created_at.asc(), InventoryMovement.sequence.asc()).limit(limit)).all()
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\r\n")
    writer.writerow([h for h, _ in CSV_HEADERS])
    for m in rows:
        data = _row(m, project)
        writer.writerow([_csv_safe(data.get(key, "")) for _, key in CSV_HEADERS])
    return buffer.getvalue()


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    return parsed.replace(tzinfo=None) if parsed.tzinfo else parsed


__all__ = ["list_movements", "export_csv", "parse_datetime", "iso"]
