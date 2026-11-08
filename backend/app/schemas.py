"""Pydantic request models (strictly validated, Chinese error copy)."""

from __future__ import annotations

import unicodedata
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .units import ALLOWED_PROJECT_UNITS

Unit = Literal["mm", "cm"]
CutOption = Literal["long_side_cut", "short_side_cut"]
RemnantAction = Literal["store", "discard"]
ShapeType = Literal["rectangle", "l_shape", "irregular"]

# 项目名里不允许出现的 Unicode 类别：
#   Cc 控制字符（\x00、\n、\r、\x1b…）—— 会撑断日志行、把 JSON/CSV 结构搞乱
#   Cf 格式字符（零宽空格 U+200B、RTL 覆写 U+202E、BOM U+FEFF…）—— 肉眼不可见，
#      可以造出两个「看起来一样」的项目名，也能让界面文字倒着显示
#   Cs 代理项、Co 私用区、Cn 未分配 —— 不是正常输入
_FORBIDDEN_CATEGORIES = frozenset({"Cc", "Cf", "Cs", "Co", "Cn"})


def _reject_invisible_chars(value: str, field: str = "项目名称") -> str:
    for index, char in enumerate(value):
        if unicodedata.category(char) in _FORBIDDEN_CATEGORIES:
            raise ValueError(
                f"{field}第 {index + 1} 个字符是控制字符或不可见格式字符（U+{ord(char):04X}），请删掉后重试"
            )
    return value

DimensionValue = Annotated[str | int | float, Field(description="尺寸，支持 800 / 80cm / 800mm")]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class DeviceRegisterIn(StrictModel):
    name: str = Field(default="", max_length=120)
    platform: str = Field(default="android", max_length=40)
    app_version: str = Field(default="", max_length=40)


class DeviceHeartbeatIn(StrictModel):
    app_version: str = Field(default="", max_length=40)


class ProjectCreateIn(StrictModel):
    name: str = Field(min_length=1, max_length=120)
    default_unit: Unit = "mm"
    min_usable_mm: int = Field(default=50, ge=0, le=5000)

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("项目名称不能为空")
        return _reject_invisible_chars(value)


class ProjectPatchIn(StrictModel):
    default_unit: Unit | None = None
    min_usable_mm: int | None = Field(default=None, ge=0, le=5000)
    name: str | None = Field(default=None, min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def _name_clean(cls, value: str | None) -> str | None:
        # 改名和新建必须走同一套字符检查，否则绕一下就能塞进控制字符。
        if value is None:
            return None
        if not value.strip():
            raise ValueError("项目名称不能为空")
        return _reject_invisible_chars(value)


class ProjectJoinIn(StrictModel):
    invite_code: str = Field(min_length=4, max_length=32)
    device_label: str = Field(default="", max_length=120)

    @field_validator("invite_code")
    @classmethod
    def _upper(cls, value: str) -> str:
        return value.replace(" ", "").replace("-", "").upper()


class InventoryCreateIn(StrictModel):
    length: DimensionValue
    width: DimensionValue
    quantity: int = Field(default=1, ge=1, le=20000)
    unit: Unit | None = None
    location: str = Field(default="", max_length=120)
    note: str = Field(default="", max_length=500)


class BatchConsumeIn(StrictModel):
    """整砖批量使用（不切割）：一次扣掉 N 片。"""

    quantity: int = Field(ge=1, le=20000)
    note: str = Field(default="", max_length=200)


class InventoryPatchIn(StrictModel):
    location: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=500)
    quantity: int | None = Field(default=None, ge=0, le=20000)
    status: Literal["available", "void", "depleted"] | None = None
    adjust_reason: str = Field(default="", max_length=200)


class DemandIn(StrictModel):
    length: DimensionValue
    width: DimensionValue
    quantity: int = Field(default=1, ge=1, le=2000)
    unit: Unit | None = None


class MatchIn(DemandIn):
    limit: int = Field(default=10, ge=1, le=50)
    include_exhausted: bool = False


class DemandItemIn(StrictModel):
    length: DimensionValue
    width: DimensionValue
    quantity: int = Field(default=1, ge=1, le=2000)


class MatchMultiIn(StrictModel):
    """多尺寸一起匹配：每行一个尺寸 + 数量，服务端按大件优先混排。"""

    unit: Unit | None = None
    demands: list[DemandItemIn] = Field(min_length=1, max_length=50)


class AllocationIn(StrictModel):
    batch_id: str = Field(min_length=8, max_length=40)
    quantity: int = Field(ge=1, le=2000)
    cut_option: CutOption | None = None
    remnant_action: RemnantAction | None = None
    location: str | None = Field(default=None, max_length=120)


class UsageConfirmIn(DemandIn):
    idempotency_key: str = Field(min_length=8, max_length=80)
    allocations: list[AllocationIn] | None = None
    default_remnant_action: RemnantAction = "store"
    location: str | None = Field(default=None, max_length=120)
    note: str = Field(default="", max_length=500)

    @field_validator("idempotency_key")
    @classmethod
    def _key_ok(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("幂等键不能为空")
        return value

    @model_validator(mode="after")
    def _check_allocations(self) -> "UsageConfirmIn":
        if self.allocations is not None:
            if not self.allocations:
                raise ValueError("allocations 不能为空数组")
            ids = [a.batch_id for a in self.allocations]
            if len(ids) != len(set(ids)):
                raise ValueError("同一批次不能重复出现，请合并数量")
            total = sum(a.quantity for a in self.allocations)
            if total != self.quantity:
                raise ValueError(f"分配数量之和（{total}）必须等于需求数量（{self.quantity}）")
        return self


class InviteResetIn(StrictModel):
    reason: str = Field(default="", max_length=200)


class MembershipRemoveIn(StrictModel):
    reason: str = Field(default="", max_length=200)


__all__ = [
    "ALLOWED_PROJECT_UNITS",
    "AllocationIn",
    "CutOption",
    "DemandIn",
    "DeviceHeartbeatIn",
    "DeviceRegisterIn",
    "InventoryCreateIn",
    "InventoryPatchIn",
    "InviteResetIn",
    "MatchIn",
    "MembershipRemoveIn",
    "ProjectCreateIn",
    "ProjectJoinIn",
    "ProjectPatchIn",
    "RemnantAction",
    "ShapeType",
    "Unit",
    "UsageConfirmIn",
]
