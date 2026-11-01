"""Rectilinear geometry engine for tile remnants.

Coordinate space
----------------
A batch is described by a set of disjoint axis-aligned rectangles ("region")
inside a bounding box of ``width_mm`` x ``height_mm``.  The origin is the
bottom-left corner, ``x`` runs along the *width* axis and ``y`` along the
*height* axis.  Regions are always canonicalised so that
``width_mm <= height_mm`` (the short side is the horizontal axis).  Because a
tile can be rotated freely on the floor, restricting the canonical form to
``short x long`` loses no information.

Shapes
------
* ``rectangle``  - a single rectangle.
* ``l_shape``    - a rectangle with one rectangular notch removed from a
  corner (a true L), or - in rare cases after several cuts - a rectilinear
  region that cannot be written as a single L.  Those are still stored as
  ``l_shape`` with ``composite = true`` and an explicit rectangle list so
  that no geometry is ever lost.  Clients always render ``rects``.

Cutting
-------
A cut always removes one axis-aligned rectangle from a corner of one of the
region's rectangles.  That models a straight cut that runs "all the way"
(``切到底``): one blade line parallel to the long side, one parallel to the
short side, both starting from an edge of the tile.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Literal, Sequence

Rect = tuple[int, int, int, int]
CutOption = Literal["long_side_cut", "short_side_cut"]
ShapeType = Literal["rectangle", "l_shape"]

CORNERS = ("bottom_left", "bottom_right", "top_left", "top_right")


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------
def rect_area(r: Rect) -> int:
    return max(0, r[2]) * max(0, r[3])


def region_area(region: Sequence[Rect]) -> int:
    return sum(rect_area(r) for r in region)


def normalize_pair(a: int, b: int) -> tuple[int, int]:
    """Return (short, long)."""
    return (a, b) if a <= b else (b, a)


def bbox(region: Sequence[Rect]) -> tuple[int, int, int, int]:
    min_x = min(r[0] for r in region)
    min_y = min(r[1] for r in region)
    max_x = max(r[0] + r[2] for r in region)
    max_y = max(r[1] + r[3] for r in region)
    return min_x, min_y, max_x - min_x, max_y - min_y


def canonicalise(region: Iterable[Rect]) -> tuple[int, int, list[Rect]]:
    """Rotate/translate a region so that the bbox starts at (0, 0) and W <= H."""
    rects = [(int(r[0]), int(r[1]), int(r[2]), int(r[3])) for r in region if r[2] > 0 and r[3] > 0]
    if not rects:
        raise ValueError("empty region")
    min_x, min_y, w, h = bbox(rects)
    rects = [(x - min_x, y - min_y, rw, rh) for (x, y, rw, rh) in rects]
    if w > h:
        # pure 90 degree rotation (counter clockwise): (x, y) -> (h - y - rh, x)
        rects = [(h - y - rh, x, rh, rw) for (x, y, rw, rh) in rects]
        w, h = h, w
        min_x, min_y, _, _ = bbox(rects)
        rects = [(x - min_x, y - min_y, rw, rh) for (x, y, rw, rh) in rects]
    rects.sort(key=lambda r: (r[1], r[0]))
    return w, h, rects


def subtract_rect(region: Sequence[Rect], cut: Rect) -> list[Rect]:
    """Return ``region - cut`` as a list of disjoint rectangles."""
    cx, cy, cw, ch = cut
    out: list[Rect] = []
    for (x, y, w, h) in region:
        ix = max(x, cx)
        iy = max(y, cy)
        iw = min(x + w, cx + cw) - ix
        ih = min(y + h, cy + ch) - iy
        if iw <= 0 or ih <= 0:
            out.append((x, y, w, h))
            continue
        # below
        if iy > y:
            out.append((x, y, w, iy - y))
        # above
        if iy + ih < y + h:
            out.append((x, iy + ih, w, y + h - (iy + ih)))
        # left
        if ix > x:
            out.append((x, iy, ix - x, ih))
        # right
        if ix + iw < x + w:
            out.append((ix + iw, iy, x + w - (ix + iw), ih))
    return [r for r in out if r[2] > 0 and r[3] > 0]


def _contains(r: Rect, px: int, py: int) -> bool:
    return r[0] <= px < r[0] + r[2] and r[1] <= py < r[1] + r[3]


def complement(region: Sequence[Rect], width: int, height: int) -> list[Rect]:
    """Rectangles covering ``box - region`` (used to describe L notches)."""
    xs = sorted({0, width, *[r[0] for r in region], *[r[0] + r[2] for r in region]})
    ys = sorted({0, height, *[r[1] for r in region], *[r[1] + r[3] for r in region]})
    xs = [v for v in xs if 0 <= v <= width]
    ys = [v for v in ys if 0 <= v <= height]

    cells: set[tuple[int, int]] = set()
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cw = xs[i + 1] - xs[i]
            ch = ys[j + 1] - ys[j]
            if cw <= 0 or ch <= 0:
                continue
            px = xs[i] + cw / 2
            py = ys[j] + ch / 2
            if not any(_contains(r, int(px), int(py)) for r in region):
                cells.add((i, j))

    # merge horizontally, then vertically
    rows: dict[int, list[tuple[int, int]]] = {}
    for (i, j) in sorted(cells, key=lambda c: (c[1], c[0])):
        rows.setdefault(j, []).append((i, i))

    h_merged: list[tuple[int, int, int]] = []  # i0, i1, j
    for j, spans in rows.items():
        spans.sort()
        cur_i0, cur_i1 = spans[0]
        for i0, _ in spans[1:]:
            if i0 == cur_i1 + 1:
                cur_i1 = i0
            else:
                h_merged.append((cur_i0, cur_i1, j))
                cur_i0 = cur_i1 = i0
        h_merged.append((cur_i0, cur_i1, j))

    h_merged.sort(key=lambda t: (t[0], t[1], t[2]))

    out: list[Rect] = []
    used = [False] * len(h_merged)
    for idx, (i0, i1, j) in enumerate(h_merged):
        if used[idx]:
            continue
        j2 = j
        while True:
            nxt = next(
                (k for k in range(idx + 1, len(h_merged))
                 if not used[k] and h_merged[k][0] == i0 and h_merged[k][1] == i1 and h_merged[k][2] == j2 + 1),
                None,
            )
            if nxt is None:
                break
            used[nxt] = True
            j2 += 1
        used[idx] = True
        x = xs[i0]
        y = ys[j]
        w = xs[i1 + 1] - xs[i0]
        h = ys[j2 + 1] - ys[j]
        if w > 0 and h > 0:
            out.append((x, y, w, h))

    # drop slivers fully covered (defensive)
    out = [r for r in out if rect_area(r) > 0]
    out.sort(key=lambda r: (r[1], r[0]))
    return out


def _touch_corner(r: Rect, width: int, height: int) -> str | None:
    x, y, w, h = r
    if x not in (0, width - w) or y not in (0, height - h):
        return None
    if x == 0 and y == 0:
        return "bottom_left"
    if x > 0 and y == 0:
        return "bottom_right"
    if x == 0 and y > 0:
        return "top_left"
    return "top_right"


def describe(region: Sequence[Rect], width: int, height: int) -> dict:
    """Describe a canonical region as a JSON-friendly geometry dict."""
    rects = [{"x": r[0], "y": r[1], "w": r[2], "h": r[3]} for r in region]
    comp = complement(region, width, height)
    if len(region) == 1 and region[0] == (0, 0, width, height):
        return {
            "type": "rectangle",
            "width_mm": width,
            "height_mm": height,
            "rects": rects,
            "area_mm2": rect_area(region[0]),
        }
    if len(comp) == 1:
        corner = _touch_corner(comp[0], width, height)
        if corner is not None:
            nx, ny, nw, nh = comp[0]
            return {
                "type": "l_shape",
                "composite": False,
                "width_mm": width,
                "height_mm": height,
                "outer": {"w": width, "h": height},
                "notch": {"x": nx, "y": ny, "w": nw, "h": nh},
                "notch_corner": corner,
                "rects": rects,
                "area_mm2": region_area(region),
            }
    # 三块及以上拼出来的不是 L 形：比如 710×1500 连切 10 片 230×220，
    # 剩下的是 5 块矩形拼成的不规则形状。以前这里硬标 l_shape，
    # 界面上全是"L 形"，和实际对不上。
    return {
        "type": "irregular" if len(region) >= 3 else "l_shape",
        "composite": True,
        "width_mm": width,
        "height_mm": height,
        "outer": {"w": width, "h": height},
        "notch": None,
        "notch_corner": None,
        "rects": rects,
        "area_mm2": region_area(region),
    }


def region_from_geometry(geometry: dict) -> tuple[int, int, list[Rect]]:
    """Rebuild a canonical region from a stored geometry dict."""
    rects = [(int(r["x"]), int(r["y"]), int(r["w"]), int(r["h"])) for r in geometry.get("rects") or []]
    if not rects:
        raise ValueError("geometry has no rects")
    w = int(geometry.get("width_mm") or geometry.get("outer", {}).get("w"))
    h = int(geometry.get("height_mm") or geometry.get("outer", {}).get("h"))
    return canonicalise(rects)


# --------------------------------------------------------------------------
# placement / cutting plans
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class Plan:
    option: CutOption
    rotation: int
    x: int
    y: int
    w: int
    h: int
    remainder: tuple[Rect, ...] = field(default_factory=tuple)

    @property
    def piece_dims(self) -> tuple[int, int]:
        return normalize_pair(self.w, self.h)


def _corner_positions(r: Rect, dw: int, dh: int) -> list[tuple[int, int]]:
    x, y, w, h = r
    xs = {x, x + w - dw}
    ys = {y, y + h - dh}
    out = []
    for px in xs:
        for py in ys:
            if x <= px <= x + w - dw and y <= py <= y + h - dh:
                out.append((px, py))
    return out


def cut_options_for(batch_width: int, batch_height: int) -> list[CutOption]:
    return ["long_side_cut", "short_side_cut"]


def _dims_for(option: CutOption, short: int, long: int) -> tuple[int, int]:
    """Return (w along x, h along y) for the demand under a cut option.

    ``long_side_cut`` keeps the demand's long edge parallel to the tile's long
    edge (the y axis); ``short_side_cut`` rotates it by 90 degrees.
    """
    if option == "long_side_cut":
        return short, long
    return long, short


def _score(remainder: Sequence[Rect], demand_area: int) -> tuple:
    pieces = len(remainder)
    largest = max((rect_area(r) for r in remainder), default=0)
    # fewer leftover pieces first, then the biggest reusable piece, then total
    return (pieces, -largest, region_area(remainder) - demand_area)


def plan_cut(
    region: Sequence[Rect],
    width: int,
    height: int,
    demand_short: int,
    demand_long: int,
    option: CutOption,
) -> Plan | None:
    """Best straight-cut placement of a demand rectangle for one cut option."""
    dw, dh = _dims_for(option, demand_short, demand_long)
    best: Plan | None = None
    best_score: tuple | None = None
    for r in region:
        if dw > r[2] or dh > r[3]:
            continue
        for (px, py) in _corner_positions(r, dw, dh):
            remainder = subtract_rect(region, (px, py, dw, dh))
            remainder = tuple(canonicalise(remainder)[2]) if remainder else tuple()
            score = _score(remainder, dw * dh)
            if best_score is None or score < best_score:
                best_score = score
                rotation = 0 if option == "long_side_cut" else 90
                best = Plan(option=option, rotation=rotation, x=px, y=py, w=dw, h=dh, remainder=remainder)
    return best


def plan_demand(region: Sequence[Rect], width: int, height: int, demand_short: int, demand_long: int) -> dict[str, Plan | None]:
    return {
        "long_side_cut": plan_cut(region, width, height, demand_short, demand_long, "long_side_cut"),
        "short_side_cut": plan_cut(region, width, height, demand_short, demand_long, "short_side_cut"),
    }


def fits(region: Sequence[Rect], demand_short: int, demand_long: int) -> bool:
    for r in region:
        if (demand_short <= r[2] and demand_long <= r[3]) or (demand_long <= r[2] and demand_short <= r[3]):
            return True
    return False


def fits_any(region: Sequence[Rect], demand_short: int, demand_long: int) -> bool:
    return fits(region, demand_short, demand_long)


def remnant_payload(remainder: Sequence[Rect], min_usable_mm: int) -> dict | None:
    """Describe the leftover of a cut, or ``None`` when nothing is left."""
    if not remainder:
        return None
    w, h, rects = canonicalise(remainder)
    geom = describe(rects, w, h)
    # 判「是否低于可再用阈值」要看最窄的那一段，不能看外框短边：
    # 900×800 的砖切走 880×780，余料是两条 20mm 的边，外框 900×800 却会
    # 被 min(w, h)=800 判成「够大」，提示就永远不出现。
    narrowest = min(min(r[2], r[3]) for r in rects)
    return {
        "exists": True,
        "shape_type": geom["type"],
        "composite": bool(geom.get("composite")),
        "width_mm": w,
        "height_mm": h,
        "area_mm2": region_area(rects),
        "outer": {"w": w, "h": h},
        "notch": geom.get("notch"),
        "notch_corner": geom.get("notch_corner"),
        "rects": geom["rects"],
        "min_side_mm": narrowest,
        "below_threshold": narrowest < min_usable_mm,
        "geometry": geom,
    }


def usage_preview(
    region: Sequence[Rect],
    width: int,
    height: int,
    demand_short: int,
    demand_long: int,
    option: CutOption,
    min_usable_mm: int = 50,
) -> dict:
    """Full preview (placement, remnant, waste) for one cut option."""
    plan = plan_cut(region, width, height, demand_short, demand_long, option)
    if plan is None:
        return {
            "cut_option": option,
            "feasible": False,
            "reason": "该切法放不下：需求尺寸超出余砖可用区域，请换一种切法或换一块砖。",
            "rotation": None,
            "placement": None,
            "demand_dims": None,
            "waste_mm2": None,
            "utilization": None,
            "remnant": None,
        }
    demand_area = demand_short * demand_long
    total = region_area(region)
    remnant = remnant_payload(plan.remainder, min_usable_mm)
    return {
        "cut_option": option,
        "feasible": True,
        "reason": None,
        "rotation": plan.rotation,
        "placement": {"x": plan.x, "y": plan.y, "w": plan.w, "h": plan.h},
        "demand_dims": {"width_mm": plan.w, "height_mm": plan.h},
        "waste_mm2": max(0, total - demand_area),
        "utilization": round(demand_area / total, 4) if total else 0.0,
        "remnant": remnant,
        "stock_area_mm2": total,
    }


def best_option(
    region: Sequence[Rect],
    width: int,
    height: int,
    demand_short: int,
    demand_long: int,
    min_usable_mm: int = 50,
) -> dict | None:
    """Pick the cut option that leaves the most reusable remnant."""
    previews = [
        usage_preview(region, width, height, demand_short, demand_long, opt, min_usable_mm)
        for opt in ("long_side_cut", "short_side_cut")
    ]
    feasible = [p for p in previews if p["feasible"]]
    if not feasible:
        return None
    feasible.sort(key=lambda p: (p["remnant"] is None, -(p["remnant"]["area_mm2"] if p["remnant"] else 0), p["cut_option"] != "long_side_cut"))
    return feasible[0]


def pieces_available(
    region: Sequence[Rect],
    width: int,
    height: int,
    demand_short: int,
    demand_long: int,
    cap: int,
    option: CutOption | None = None,
) -> int:
    """How many demand pieces can be cut out of one physical tile (simulated).

    ``option`` 固定为单一方向时，模拟只沿该方向连切；为 ``None`` 时 long 优先、
    short 兜底（用于估算上限）。分配时的 ``cut_option`` 是单一方向，所以估算可用
    片数必须用同一个方向，否则会出现「说能切 10 片、实际某方向只切得出 8 片」。
    """
    count = 0
    cur: list[Rect] = list(region)
    cw, ch = width, height
    while count < cap:
        if option is not None:
            plan = plan_cut(cur, cw, ch, demand_short, demand_long, option)
        else:
            plan = plan_cut(cur, cw, ch, demand_short, demand_long, "long_side_cut") or plan_cut(
                cur, cw, ch, demand_short, demand_long, "short_side_cut"
            )
        if plan is None:
            break
        count += 1
        if not plan.remainder:
            break
        cw, ch, cur = canonicalise(plan.remainder)
    return count


def build_rectangle_region(width: int, height: int) -> tuple[int, int, list[Rect]]:
    w, h = normalize_pair(width, height)
    return w, h, [(0, 0, w, h)]


def build_l_region(outer_w: int, outer_h: int, notch_w: int, notch_h: int, corner: str) -> tuple[int, int, list[Rect]]:
    """Build an L shape: outer rectangle minus a corner notch."""
    W, H = normalize_pair(outer_w, outer_h)
    nw, nh = abs(notch_w), abs(notch_h)
    if nw >= W or nh >= H or nw <= 0 or nh <= 0:
        raise ValueError("notch must be smaller than the outer rectangle")
    if corner == "bottom_left":
        # notch at x:[0,nw], y:[0,nh]
        rects = [(0, nh, W, H - nh), (nw, 0, W - nw, nh)]
    elif corner == "bottom_right":
        # notch at x:[W-nw,W], y:[0,nh]
        rects = [(0, nh, W, H - nh), (0, 0, W - nw, nh)]
    elif corner == "top_left":
        # notch at x:[0,nw], y:[H-nh,H]
        rects = [(0, 0, W, H - nh), (nw, H - nh, W - nw, nh)]
    elif corner == "top_right":
        # notch at x:[W-nw,W], y:[H-nh,H]
        rects = [(0, 0, W, H - nh), (0, H - nh, W - nw, nh)]
    else:  # pragma: no cover - guarded by callers
        raise ValueError(f"unknown corner {corner}")
    W, H, rects = canonicalise(rects)
    return W, H, rects
