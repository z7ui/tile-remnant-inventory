# API 文档

Base URL：`https://<你的域名>/api`
交互式文档：`https://<你的域名>/docs`（OpenAPI：`/api/openapi.json`）

所有响应 `Content-Type: application/json; charset=utf-8`，时间均为 ISO8601 UTC（`...Z`）。

---

## 0. 认证模型

无账号体系，两层凭证：

| 场景 | 请求头 |
|---|---|
| 设备级（注册后用） | `X-Device-Id` + `X-Device-Secret` |
| 项目级（加入项目后） | `X-Device-Id` + `X-Project-Token` |

项目级接口**必须**同时带设备 ID 与项目令牌。服务端校验：

1. 设备存在且未停用；
2. 令牌哈希匹配，且 `token.project_id == 路径 project_id`，`token.device_id == 请求设备`；
3. 项目 `status == active`；
4. 成员关系存在且 `removed_at is null`。

任一不满足：`403`。缺少设备头：`401`。**仅凭 `project_id` 无法取数。**

统一错误体：

```json
{
  "error": {
    "code": "project_name_taken",
    "message": "项目名称「金域蓝湾」已被占用（不区分大小写、忽略首尾空格），请换一个名称。",
    "details": {"conflict_project_id": "…"},
    "request_id": "6f1c…",
    "timestamp": "2026-10-31T12:00:00Z"
  }
}
```

| HTTP | code 示例 | 含义 |
|---|---|---|
| 401 | `device_credentials_missing` / `device_secret_invalid` | 设备凭证问题 |
| 403 | `project_access_denied` / `not_a_member` / `owner_only` | 越权 |
| 404 | `invite_invalid` / `batch_not_found` | 资源不存在 |
| 409 | `project_name_taken` / `insufficient_quantity` / `cut_option_infeasible` / `concurrent_update` | 业务冲突 |
| 422 | `validation_error` / `invalid_dimension` / `remnant_action_required` | 参数问题 |
| 429 | `rate_limited` | 限流（带 `Retry-After`） |

---

## 1. 设备

### POST /devices/register

```json
{"name": "工头手机", "platform": "android", "app_version": "0.1.0"}
```

```json
{
  "device_id": "9f2c…",
  "device_secret": "…43 chars…",
  "name": "工头手机",
  "created_at": "2026-10-31T12:00:00Z",
  "notice": "设备密钥只返回一次…"
}
```

密钥仅此一次返回，服务端只存 bcrypt 哈希。

### POST /devices/heartbeat

需设备头。`{"app_version": "0.1.0"}` → `{"ok": true, "server_time": "…"}`

---

## 2. 项目

### GET /projects/name-available?name=…

设备级。返回 `{"name","key","available","conflict_project"}`。用于新建页失焦即时查重。

### POST /projects

```json
{"name": "金域蓝湾 3 栋 1802", "default_unit": "mm", "min_usable_mm": 50}
```

`201`：

```json
{
  "project": {"id": "…", "name": "…", "role": "owner", "default_unit": "mm", "min_usable_mm": 50, "stats": {}},
  "project_token": "…",
  "invite": {
    "code": "ABCD2345EF",
    "status": "active",
    "qr_payload": "tileremnant://join?server=https://tiles.example.com&code=ABCD2345EF",
    "join_url": "https://tiles.example.com/join?code=ABCD2345EF",
    "never_expires": true,
    "generation": 1
  }
}
```

名称重复：`409 project_name_taken`。

### GET /projects

设备级。返回已加入项目及统计：

```json
{"items": [{"id": "…", "name": "…", "role": "owner",
  "stats": {"total_pieces": 12, "batch_count": 5, "l_shape_batches": 1,
            "total_area_mm2": 4320000, "last_activity_at": "…"}}], "total": 1}
```

### POST /projects/join

```json
{"invite_code": "abcd2345ef"}
```

成功返回与创建相同的结构（`role` 为 `member`）。邀请码无效/已撤销：`404 invite_invalid`。

### GET /projects/{id}

返回项目详情 + 当前设备成员信息。

### PATCH /projects/{id}

拥有者。可改 `name`、`default_unit`、`min_usable_mm`。

### DELETE /projects/{id}

拥有者。软删除：`status=deleted`，所有令牌立即失效。

### GET /projects/{id}/summary

```json
{
  "project": {"id": "…", "role": "owner", "default_unit": "mm", "min_usable_mm": 50},
  "stats": {"total_pieces": 12, "batch_count": 5, "l_shape_batches": 1, "available_batches": 5, "total_area_mm2": 4320000},
  "recent_movements": [ …最多 3 条… ],
  "known_locations": ["阳台", "储物间"]
}
```

---

## 3. 邀请码与成员

| 接口 | 权限 | 说明 |
|---|---|---|
| `GET /projects/{id}/invite` | 拥有者 | 无有效码时自动生成 |
| `POST /projects/{id}/invite/revoke` | 拥有者 | 旧码立即失效，`code` 变 `null` |
| `POST /projects/{id}/invite/reset` | 拥有者 | 生成新码，`generation + 1` |
| `GET /projects/{id}/members` | 拥有者 | 成员设备列表 |
| `DELETE /projects/{id}/membership` | 任意成员 | 移除自己 |
| `DELETE /projects/{id}/members/{deviceId}` | 拥有者 | 移除他人 |

拥有者不能退出（`409 owner_cannot_leave`），只能删除项目。

---

## 4. 库存

### POST /projects/{id}/inventory

只接受矩形，**不接受** `shape_type` 字段（传了会 422）：

```json
{"length": "90cm", "width": "80cm", "quantity": 3, "unit": "cm", "location": "阳台", "note": "客厅剩料"}
```

`201` 返回 `{"batch": {…}}`，字段含：

```json
{
  "id": "…", "batch_no": 3, "code": "#0003",
  "shape_type": "rectangle", "width_mm": 800, "height_mm": 900,
  "short_mm": 800, "long_mm": 900, "area_mm2": 720000,
  "geometry": {"type": "rectangle", "rects": [{"x":0,"y":0,"w":800,"h":900}]},
  "rects": [{"x":0,"y":0,"w":800,"h":900}],
  "quantity": 3, "initial_quantity": 3, "quantity_used": 0,
  "source_type": "manual", "parent_batch_id": null, "root_batch_id": "…",
  "location": "阳台", "note": "客厅剩料", "status": "available",
  "is_available": true, "below_min_usable": false,
  "created_at": "…", "trace_url": "/api/projects/…/trace/…"
}
```

### GET /projects/{id}/inventory

查询参数：

| 参数 | 说明 |
|---|---|
| `q` | 批次号 / 位置 / 备注 模糊搜索 |
| `shape_type` | `rectangle` / `l_shape` |
| `source_type` | `manual` / `cut` |
| `location` | 精确匹配 |
| `status` | `available` / `depleted` / `void` |
| `min_quantity` `max_quantity` | 片数范围 |
| `min_short_mm` `max_short_mm` `min_long_mm` `max_long_mm` | 尺寸范围 |
| `created_from` `created_to` | ISO 时间 |
| `only_available` | 默认 `true` |
| `page` `page_size` `sort` | 排序：`created_desc`/`created_asc`/`area_desc`/`quantity_desc`/`batch_no_desc` |

响应含 `summary: {pieces, area_mm2, batches}` 与 `filters.locations`（供筛选 Chip 用）。

### PATCH /projects/{id}/inventory/{batchId}

```json
{"location": "储物间", "note": "靠墙第二排", "quantity": 2, "adjust_reason": "现场盘点"}
```

片数变化写 `adjust` 流水；`status: "void"` 写作废流水并停止参与匹配。

---

## 5. 匹配

### POST /projects/{id}/match

```json
{"length": 800, "width": 900, "quantity": 2, "unit": "mm", "limit": 20}
```

```json
{
  "demand": {"length_mm": 900, "width_mm": 800, "short_mm": 800, "long_mm": 900, "quantity": 2, "area_mm2": 720000},
  "candidates": [
    {
      "batch": { …批次对象… },
      "stock": {"shape_type": "l_shape", "width_mm": 800, "height_mm": 900, "rects": [ … ], "notch": {…}},
      "match": {
        "waste_mm2": 240000, "waste_ratio": 0.2667, "utilization": 0.7333,
        "rotation": 90, "cut_option": "short_side_cut", "cut_option_label": "短边切到底",
        "placement": {"x": 0, "y": 0, "w": 700, "h": 600},
        "remnant": {
          "exists": true, "shape_type": "l_shape", "composite": false,
          "width_mm": 400, "height_mm": 800, "area_mm2": 240000,
          "notch": {"x": 300, "y": 0, "w": 100, "h": 600}, "notch_corner": "bottom_right",
          "rects": [ … ], "min_side_mm": 400, "below_threshold": false
        },
        "remnant_value": 240000, "max_pieces": 1
      },
      "cut_options": [
        {"cut_option": "long_side_cut", "feasible": false, "reason": "该切法放不下…", "remnant": null},
        {"cut_option": "short_side_cut", "feasible": true, "rotation": 90, "placement": {…}, "waste_mm2": 240000, "remnant": {…}}
      ]
    }
  ],
  "total_candidates": 1,
  "rejected": [],
  "allocation": [{"batch_id": "…", "batch_no": 3, "quantity": 1, "cut_option": "short_side_cut", "remnant_action": "store"}],
  "unfulfilled_quantity": 1,
  "sorting": "浪费面积 → 余料可再利用价值 → 可用片数 → 录入时间/批次"
}
```

`cut_options` 两种切法都会返回，不可行的带 `reason`，客户端据此禁用图示卡。

---

## 6. 确认使用

### POST /projects/{id}/usage/confirm

```json
{
  "idempotency_key": "0f8a…32 hex…",
  "length": 800,
  "width": 600,
  "quantity": 2,
  "unit": "mm",
  "allocations": [
    {"batch_id": "…", "quantity": 1, "cut_option": "long_side_cut", "remnant_action": "store"},
    {"batch_id": "…", "quantity": 1, "cut_option": "short_side_cut", "remnant_action": "discard"}
  ],
  "note": "主卫墙砖"
}
```

- `allocations` 省略时由服务端按匹配结果自动分配（仍会按默认策略入库余料）。
- `sum(quantity)` 必须等于 `quantity`，否则 422。
- 产生余料时 `remnant_action` 必填，否则 422 `remnant_action_required`。
- 选定的 `cut_option` 放不下 → 409 `cut_option_infeasible`。

响应：

```json
{
  "usage_id": "…",
  "replayed": false,
  "created_at": "…",
  "demand": {"length_mm": 800, "width_mm": 600, "quantity": 2, "area_mm2": 480000},
  "results": [
    {
      "batch_id": "…", "batch_no": 3, "quantity": 1,
      "cut_option": "long_side_cut", "cut_option_label": "长边切到底",
      "remnant_action": "store", "remnant_action_label": "直接入库",
      "remnant": { …余料 geometry… },
      "remnant_batch": { …新批次，parent_batch_id 指向原批次… },
      "waste_mm2": 240000, "placement": {…}, "rotation": 0, "utilization": 0.6667,
      "quantity_before": 5, "quantity_after": 4,
      "trace_url": "/api/projects/…/trace/…"
    }
  ],
  "total_waste_mm2": 480000,
  "inventory_after": {"pieces": 7},
  "movements": [ …本次产生的全部流水… ]
}
```

同一 `idempotency_key` 重复提交：`200`，`replayed: true`，库存不再变化。

并发：事务内 `SELECT … FOR UPDATE`（PostgreSQL）+ 原子 `UPDATE … WHERE version = ?`（双库），冲突时自动重试 4 次，仍冲突返回 `409 concurrent_update`。

---

## 7. 流水

### GET /projects/{id}/movements

参数：`batch_id`、`root_batch_id`、`type`（逗号分隔）、`device_id`、`date_from`、`date_to`、`q`、`page`、`page_size`。

```json
{
  "items": [{
    "id": "…", "type": "usage", "type_label": "使用扣减",
    "batch_id": "…", "batch_code": "#0003",
    "quantity_delta": -1, "quantity_before": 5, "quantity_after": 4,
    "width_before_mm": 800, "height_before_mm": 900,
    "used_length_mm": 600, "used_width_mm": 500,
    "cut_option": "long_side_cut", "cut_option_label": "长边切到底",
    "remnant_action": "store", "remnant_action_label": "直接入库",
    "remnant_shape": "l_shape", "remnant_area_mm2": 420000,
    "produced_batch_id": "…", "usage_record_id": "…",
    "device_id": "…", "note": "使用 600×500mm", "created_at": "…"
  }],
  "page": 1, "page_size": 20, "total": 12, "has_more": false
}
```

`type` 取值：`stock_in` / `usage` / `cut_remnant` / `remnant_discard` / `adjust` / `void`。

### GET /projects/{id}/movements/export

`text/csv`，UTF-8 带 BOM。列：时间、项目、设备、批次、根批次、类型、变动前/后尺寸、变动前/后片数、数量变化、使用尺寸、切割方式、余料处置、余料形状、余料面积、关联使用记录、备注。

---

## 8. 溯源

### GET /projects/{id}/trace/{batchId}

```json
{
  "batch": { …批次对象… },
  "root": {"id": "…", "code": "#0001", …},
  "ancestors": [ …父批次，从根到直接父… ],
  "children": [ …子批次… ],
  "chain": {
    "nodes": [ …根 → … → 当前 → 子… ],
    "current_index": 2,
    "edges": [{"from": "…", "to": "…"}]
  },
  "comparison": {
    "original": {"label": "原砖", "width_mm": 800, "height_mm": 900, "area_mm2": 720000, "geometry": {…}},
    "demand": {"label": "本次需求", "length_mm": 600, "width_mm": 500, "area_mm2": 300000,
               "quantity": 1, "cut_option_label": "长边切到底", "remnant_action_label": "直接入库", "at": "…"},
    "remnant": {"label": "切后余料", "width_mm": 800, "height_mm": 900, "area_mm2": 420000,
                "shape_type": "l_shape", "notch": {…}, "rects": [ … ], "utilization": 0.4167, "area_ratio": 0.5833}
  },
  "usage": {"id": "…", "quantity": 1, "length_mm": 600, "width_mm": 500, "total_waste_mm2": 420000},
  "movements": [ … ],
  "links": {"self": "…", "inventory": "…", "movements": "…"}
}
```

原砖批次（`source_type=manual`）的 `comparison.remnant` 为 `null`，`children` 里能看到它切出的余料。

---

## 9. 系统

| 接口 | 说明 |
|---|---|
| `GET /healthz` | 健康检查（容器 healthcheck 用） |
| `GET /api/health` | 版本与环境 |
| `GET /api/config` | 客户端启动配置：单位、切法枚举、余料处置枚举、上限、换机提示 |

### 限流

默认读 240 次/分钟/IP，写 60 次/分钟/IP（`.env` 可调），超限 `429` + `Retry-After`。Nginx 侧另有 8r/s、2r/s 的 `limit_req`。
