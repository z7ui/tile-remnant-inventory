"""递归切割（guillotine）：在一块矩形砖里按「大件优先」切出多种尺寸。

约束和工地一致——每一刀都贯穿当前矩形（一刀切到底），
所以每次切割就是把一个矩形一分为二，递归到放不下为止。
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Rect:
    x: int
    y: int
    w: int
    h: int

    @property
    def area(self) -> int:
        return self.w * self.h

    def as_dict(self) -> dict[str, int]:
        return {"x": self.x, "y": self.y, "w": self.w, "h": self.h}


@dataclass
class BlockPlan:
    """一块砖的混排结果。"""

    width_mm: int
    height_mm: int
    # (宽, 高) -> 片数
    placed: dict[tuple[int, int], int] = field(default_factory=dict)
    # 切完剩下的矩形（可能多块）
    leftovers: list[Rect] = field(default_factory=list)
    # 每次下刀的记录：{"w": 切成两半的那条线长度, ...} 这里只留矩形，够画图用
    pieces_rects: list[Rect] = field(default_factory=list)

    @property
    def used_area(self) -> int:
        return sum(w * h * n for (w, h), n in self.placed.items())

    @property
    def waste_area(self) -> int:
        return self.width_mm * self.height_mm - self.used_area

    @property
    def total_pieces(self) -> int:
        return sum(self.placed.values())

    def as_dict(self) -> dict:
        return {
            "width_mm": self.width_mm,
            "height_mm": self.height_mm,
            "placed": [
                {"width_mm": w, "height_mm": h, "quantity": n, "area_mm2": w * h * n}
                for (w, h), n in sorted(self.placed.items(), key=lambda kv: kv[0][0] * kv[0][1], reverse=True)
            ],
            "pieces_rects": [r.as_dict() for r in self.pieces_rects],
            "leftovers": [r.as_dict() for r in self.leftovers],
            "used_area_mm2": self.used_area,
            "waste_area_mm2": self.waste_area,
            "total_pieces": self.total_pieces,
        }


def fill_block(
    width_mm: int,
    height_mm: int,
    demands: list[tuple[int, int, int]],
) -> BlockPlan:
    """
    在一块 width_mm × height_mm 的砖里递归切割。

    demands: [(w, h, count), ...] —— 当前「还缺多少」的需求。
    内部按面积降序（大件优先），每放一片就把剩余区域一分为二。
    """
    plan = BlockPlan(width_mm=width_mm, height_mm=height_mm)
    rects: list[Rect] = [Rect(0, 0, width_mm, height_mm)]
    ordered = sorted(demands, key=lambda d: d[0] * d[1], reverse=True)

    for dw, dh, count in ordered:
        if dw <= 0 or dh <= 0 or count <= 0:
            continue
        for _ in range(count):
            # best fit：能放下且面积最小的空矩形；允许把砖转 90°（两种朝向都试）
            best_idx = -1
            best_area: int | None = None
            best_w, best_h = dw, dh
            for i, r in enumerate(rects):
                for pw, ph in ((dw, dh), (dh, dw)):
                    if r.w >= pw and r.h >= ph:
                        if best_area is None or r.area < best_area:
                            best_area = r.area
                            best_idx = i
                            best_w, best_h = pw, ph
            if best_idx < 0:
                break

            r = rects.pop(best_idx)
            # 计数按需求的「标准朝向」记，避免 (300,900) 和 (900,300) 被当成两种尺寸
            plan.placed[(dw, dh)] = plan.placed.get((dw, dh), 0) + 1
            plan.pieces_rects.append(Rect(r.x, r.y, best_w, best_h))

            # 一刀切到底：右侧一条 + 下方一整块，两者不重叠、合起来正好是剩余面积
            if r.w > best_w:
                rects.append(Rect(r.x + best_w, r.y, r.w - best_w, best_h))
            if r.h > best_h:
                rects.append(Rect(r.x, r.y + best_h, r.w, r.h - best_h))

    plan.leftovers = rects
    return plan
