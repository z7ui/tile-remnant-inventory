"""Dimension parsing: ``80cm`` / ``800mm`` / ``80`` -> integer millimetres."""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation

from .config import settings

_LENGTH_RE = re.compile(r"^\s*(?P<num>\d+(?:[.,]\d+)?)\s*(?P<unit>mm|cm|m)?\s*$", re.IGNORECASE)

UNIT_FACTOR = {"mm": Decimal(1), "cm": Decimal(10), "m": Decimal(1000)}
ALLOWED_PROJECT_UNITS = ("mm", "cm")


class DimensionError(ValueError):
    """Raised with a user facing Chinese message."""


def normalise_unit(unit: str | None, default: str = "mm") -> str:
    value = (unit or default or "mm").strip().lower()
    if value not in ALLOWED_PROJECT_UNITS:
        raise DimensionError(f"单位只支持 mm 或 cm，收到：{unit}")
    return value


def parse_length_mm(
    raw: object,
    default_unit: str = "mm",
    field: str = "尺寸",
    max_mm: int | None = None,
) -> int:
    """Parse a length into integer millimetres.

    ``raw`` may be ``800`` (uses ``default_unit``), ``"800"``, ``"80cm"``,
    ``"800 mm"`` or ``"80.5cm"``.
    """
    max_value = max_mm or settings.max_dimension_mm
    unit = default_unit or "mm"
    if unit not in UNIT_FACTOR:
        unit = "mm"

    if isinstance(raw, bool) or raw is None:
        raise DimensionError(f"{field}必须是数字，例如 800 或 80cm。")

    if isinstance(raw, (int, float, Decimal)):
        try:
            value = Decimal(str(raw))
        except InvalidOperation as exc:  # pragma: no cover - defensive
            raise DimensionError(f"{field}不是有效数字。") from exc
        unit_factor = UNIT_FACTOR[unit]
    else:
        text = str(raw).strip()
        if not text:
            raise DimensionError(f"{field}不能为空。")
        match = _LENGTH_RE.match(text)
        if not match:
            raise DimensionError(f"{field}格式不正确，请输入如 800、80cm、800mm。")
        value = Decimal(match.group("num").replace(",", "."))
        unit_token = (match.group("unit") or unit).lower()
        unit_factor = UNIT_FACTOR.get(unit_token)
        if unit_factor is None:
            raise DimensionError(f"{field}单位只支持 mm 或 cm。")

    if value <= 0:
        raise DimensionError(f"{field}必须大于 0。")
    mm = int((value * unit_factor).to_integral_value(rounding="ROUND_HALF_UP"))
    if mm <= 0:
        raise DimensionError(f"{field}必须大于 0。")
    if mm > max_value:
        raise DimensionError(f"{field}超出上限（最大 {max_value} mm）。")
    return mm


def parse_quantity(raw: object, field: str = "片数") -> int:
    if isinstance(raw, bool) or raw is None:
        raise DimensionError(f"{field}必须是整数。")
    try:
        value = int(str(raw).strip())
    except (TypeError, ValueError) as exc:
        raise DimensionError(f"{field}必须是整数。") from exc
    if value < 1:
        raise DimensionError(f"{field}至少为 1。")
    if value > settings.max_quantity:
        raise DimensionError(f"{field}超出上限（最大 {settings.max_quantity}）。")
    return value


def mm_to_display(mm: int, unit: str = "cm") -> str:
    """Human readable dimension, e.g. 800 -> ``80cm``."""
    if unit == "cm":
        text = f"{Decimal(mm) / Decimal(10):.2f}".rstrip("0").rstrip(".")
        return f"{text}cm"
    return f"{mm}mm"
