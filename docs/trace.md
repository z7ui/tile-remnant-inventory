# 溯源对比说明

目标是回答三个问题：

1. 这块余料是从哪块原砖来的？
2. 当时切的是多大的需求？
3. 切完剩了多少、有哪些后续使用？

## 数据结构

`GET /api/projects/{id}/trace/{batchId}` 返回：

```
batch          当前批次（含 geometry / rects / 余料缺口）
root           根批次（最初录入的那块原砖）
ancestors      根 → … → 直接父批次
children       直接子批次
chain          可视化节点序列 + 当前下标 + 边
comparison     三列对比：original / demand / remnant
usage          产生当前批次的那次使用记录
movements      与该批次相关的全部流水
```

## 三列对比

| 列 | 数据来源 | 说明 |
|---|---|---|
| 原砖 `original` | 根批次的 `width_mm/height_mm/area_mm2/geometry` | 整棵树的起点，与当前切了多少刀无关 |
| 本次需求 `demand` | 生成当前批次的 `cut_remnant` 流水：`used_length_mm` × `used_width_mm`、`usage_record.demand_quantity` | 没有父批次时为 `null` |
| 切后余料 `remnant` | 当前批次的尺寸/面积/geometry | 原砖批次（非切割产出）为 `null` |

派生指标：

- `remnant.utilization = 需求面积 / 原砖面积`（这一刀用掉了原砖的百分之多少）
- `remnant.area_ratio = 余料面积 / 原砖面积`
- `below_min_usable`：余料最小边是否低于项目阈值

## 图示

App 的 `TileShapePreview` 用 Canvas 画俯视图：

- 外框 = 批次外接矩形；
- 实心块 = 需求矩形（来自 `placement`），带 2px 描边；
- 剩余区域 = 余料色；
- 缺口 = 先用斜线填充外接矩形，再用区域矩形覆盖 → 未被覆盖的部分自然呈现为斜线缺口（L 形/复合形都适用，不依赖缺口坐标）；
- 虚线 = 刀路（需求矩形的右边与上边贯穿到外框）；
- 尺寸标注 = 外框底线与左边线，数字用等宽数字；
- 图形按真实长宽比缩放，不拉伸。

## 父子链

```
#0001 原砖 800×900
  └─ #0004 L形 800×900（切掉 500×600）
       └─ #0007 L形 600×700（再切掉 200×500）
```

- `chain.nodes` 按根 → 当前 → 子 排列，`current_index` 指向当前批次；
- 点击任意节点跳转到该批次的溯源页（App 内是 push 新页面，返回保留上一个页面的滚动位置）；
- 库存列表卡片、流水详情、确认成功弹窗都能一键进入。

## 丢弃也留痕

选择「丢弃」时不生成新批次，但会写一条 `remnant_discard` 流水：

```json
{"type": "remnant_discard", "remnant_action": "discard",
 "remnant_shape": "l_shape", "remnant_area_mm2": 420000,
 "used_length_mm": 600, "used_width_mm": 500,
 "cut_option": "long_side_cut", "quantity_delta": 0}
```

因此「这块砖当时切了什么、剩了什么、被丢了」在流水和溯源页里都能查到，只是不再出现在库存中。

## 为什么用矩形并集而不是多边形

- 规则简单：所有切割都是轴对齐、从一个角直线切到底；
- 计算便宜：`region - rect` 最多产生 4 个子矩形，无需通用多边形布尔运算；
- 不会算错：面积守恒可用「各矩形面积之和」直接断言，测试里就是这么验的；
- 渲染直接：客户端遍历 `rects` 即可，不需要路径求解。

代价是极端情况（多次异形切割后）余料会被标记为 `composite: true`，此时仍保留完整 `rects`，图示依然正确，只是不再具备「外接矩形 + 单个缺口」的简写形式。
