# 数据库设计

默认 SQLite（WAL），可切 PostgreSQL 16。所有项目级表带 `project_id` 与索引；所有时间字段为 UTC `DATETIME`。

```
devices ─┬─< project_members >─ projects ─┬─< project_invites
         │                                ├─< project_access_tokens
         │                                ├─< inventory_batches ──< (self) parent/children
         │                                ├─< usage_records
         │                                └─< inventory_movements
         └─< audit_logs (可空 project_id)
```

## devices

| 字段 | 类型 | 说明 |
|---|---|---|
| id | varchar(32) PK | 16 字节 hex |
| name / platform / app_version | varchar | 展示用 |
| secret_hash | varchar(255) | bcrypt(cost 12)，绝不存明文 |
| created_at / last_seen_at / revoked_at | datetime | 心跳超过 5 分钟才写库 |

## projects

| 字段 | 类型 | 说明 |
|---|---|---|
| id | varchar(32) PK | |
| name | varchar(120) | 展示名（已去首尾空白、压缩内部空白） |
| name_key | varchar(160) UNIQUE | NFKC + casefold 后的唯一键 |
| default_unit | varchar(4) | `mm` / `cm` |
| min_usable_mm | int | 余料最小可用阈值，默认 50 |
| owner_device_id | varchar(32) | 拥有者设备 |
| status | varchar(16) | `active` / `deleted` |
| created_at / updated_at / deleted_at | datetime | 软删除 |

索引：`ix_projects_status`、`ix_projects_owner`、`ix_projects_short_code`。`name_key` 存成 `归一化名#特征码`，唯一约束由它兜底——但唯一性的**来源**已经变成 `short_code`，名字本身允许重复。

## project_members

`id`, `project_id`, `device_id`, `role`(`owner`/`member`), `joined_at`, `removed_at`
唯一约束 `(project_id, device_id)`；索引 `ix_members_device`。移除成员只置 `removed_at`，历史数据不动。

## project_invites

`id`, `project_id`, `code`(UNIQUE), `status`(`active`/`revoked`), `generation`, `created_by_device_id`, `created_at`, `revoked_at`
无过期字段——邀请码长期有效，只能撤销或重置。

## project_access_tokens

`id`, `project_id`, `device_id`, `token_hash`(sha256, UNIQUE), `token_hint`(前 6 位), `created_at`, `last_used_at`, `revoked_at`, `expires_at`(可空，默认永不过期)
索引 `(project_id, device_id)`。同一设备同一项目只保留一个有效令牌，重新加入会轮换旧令牌。

## inventory_batches

| 字段 | 说明 |
|---|---|
| project_id, batch_no | 项目内自增批次号，唯一约束 `(project_id, batch_no)` |
| shape_type | `rectangle` / `l_shape` |
| width_mm, height_mm | 当前外接矩形，**恒有 width ≤ height** |
| geometry | JSON：`type`/`outer`/`notch`/`notch_corner`/`rects`/`area_mm2` |
| area_mm2 | 实际可用面积（L 形已扣除缺口），BIGINT |
| notch_w_mm, notch_h_mm, notch_corner | 便于筛选/展示的冗余列 |
| quantity, initial_quantity | 当前 / 初始片数 |
| source_type | `manual`（主动录入）/ `cut`（切割余料） |
| parent_batch_id | 父批次（切出它的那块） |
| root_batch_id | 根批次（最初的原砖），自身即根时等于 id |
| cut_option, used_length_mm, used_width_mm | 生成该余料时的切法与本次需求 |
| location, note | 存放位置 / 备注 |
| status | `available` / `depleted` / `void` |
| created_by_device_id, created_at, updated_at | |
| version | 乐观锁版本号，扣减时 `WHERE version = ?` |

索引：`(project_id,status)`、`(project_id,created_at)`、`parent_batch_id`、`root_batch_id`、`(project_id,location)`。

## usage_records

`id`, `project_id`, `device_id`, `idempotency_key`, `request_hash`, `demand_length_mm`, `demand_width_mm`, `demand_quantity`, `total_waste_mm2`, `cut_option`, `remnant_action`, `note`, `created_at`
唯一约束 `(project_id, idempotency_key)`——重复提交的唯一防线。

## inventory_movements（只追加）

| 字段 | 说明 |
|---|---|
| project_id, batch_id, batch_no, root_batch_id | 归属 |
| sequence | 同一次使用内的顺序 |
| type | `stock_in`/`usage`/`cut_remnant`/`remnant_discard`/`adjust`/`void` |
| quantity_delta, quantity_before, quantity_after | 片数变化 |
| width_before_mm / height_before_mm / width_after_mm / height_after_mm | 尺寸变化 |
| area_before_mm2 / area_after_mm2 | 面积变化 |
| used_length_mm / used_width_mm | 本次使用尺寸（长 × 宽） |
| cut_option / remnant_action / remnant_shape / remnant_area_mm2 | 切法与余料 |
| produced_batch_id | 生成的余料批次 |
| usage_record_id | 关联使用记录 |
| device_id, note, created_at | 操作者与备注 |

索引：`(project_id,created_at)`、`(project_id,type)`、`batch_id`、`usage_record_id`。

**为什么「每片一条 usage 流水」**：需求 3 片时写 3 条 `usage`（各 -1），配合 `sequence` 可精确还原「第几片从多少片扣到多少片」，也满足「每片扣减都写流水」。

## audit_logs

`id`, `project_id`(可空), `device_id`, `action`, `target_type`, `target_id`, `detail`(JSON), `ip`, `ok`, `created_at`
记录注册、建项目、加入、邀请撤销/重置、成员移除、删除项目、确认使用。

## 迁移

```bash
cd backend
DATABASE_URL=sqlite:///./data/tile.db alembic upgrade head
DATABASE_URL=postgresql+psycopg://... alembic upgrade head
```

初始迁移：`backend/alembic/versions/9eb0dc91e867_initial_schema.py`（已在本机实际执行验证）。

## 并发与一致性

1. 读批次 → 2. 计算切割方案 → 3. `UPDATE inventory_batches SET quantity=?, version=version+1 WHERE id=? AND version=? AND quantity>=?` → 4. 写流水/余料批次 → 5. 提交。

- PostgreSQL：第 1 步用 `SELECT … FOR UPDATE` 占行锁；
- SQLite：WAL + `busy_timeout=30s`，写串行；
- 版本号不匹配或 `rowcount != 1` → 抛冲突 → 整个事务回滚 → 自动重试（最多 4 次）→ 仍失败返回 409；
- 幂等键命中 → 直接回放原结果（`replayed: true`），不再扣减。
