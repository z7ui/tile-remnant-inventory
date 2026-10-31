# 余砖管家 · 装修瓷砖余料库存与匹配管理

把工地剩下的瓷砖拍平成一张可检索的库存表：按尺寸匹配需求、按真实切割扣减、把切下来的余料（包括 L 形异形）继续入库，并且每一片砖的来龙去脉都能追溯到原砖。

- 移动端：Flutter（Android APK，不上架应用商店）
- 后端：Python FastAPI + SQLAlchemy 2 + Alembic
- 数据库：SQLite（WAL，默认）或 PostgreSQL（`docker compose --profile postgres`）
- 部署：Docker Compose + Nginx + HTTPS
- 许可证：GPL-3.0

> 当前版本 **v0.1.0**。后端 104 个 pytest 用例全部通过；移动端已用 Flutter 3.47.9 + JDK 17 实际跑通 `pub get` / `analyze`（0 error）/ `test`（14 passed），并构建出 release APK。
>
> **只想用，不想看代码？** → [`docs/how-to-use.md`](docs/how-to-use.md)（装包、建项目、入库、匹配、切割、溯源，以及构建与部署的坑）

---

## 目录

- [一、它解决什么问题](#一它解决什么问题)
- [二、功能清单](#二功能清单)
- [三、目录结构](#三目录结构)
- [四、数据模型](#四数据模型)
- [五、匹配与切割算法](#五匹配与切割算法)
- [六、L 形余料规则](#六l-形余料规则)
- [七、API 一览](#七api-一览)
- [八、本地开发与测试](#八本地开发与测试)
- [九、部署（Docker + Nginx + HTTPS）](#九部署docker--nginx--https)
- [十、构建 APK](#十构建-apk)
- [十一、备份与恢复](#十一备份与恢复)
- [十二、安全说明](#十二安全说明)
- [十三、假设与可配置项](#十三假设与可配置项)
- [十四、换机 / 清缓存说明](#十四换机--清缓存说明)
- [十五、本次交付的实际状态](#十五本次交付的实际状态)

---

## 一、它解决什么问题

工地上的余砖散落在阳台、储物间、车库，尺寸各异。要补 3 片 600×300 的砖时，师傅只能凭记忆翻找，最后往往切新砖、把旧余料继续堆着。

这个 App 做三件事：

1. **记得住**：按项目录入每块余砖的长、宽、片数和存放位置，统一存成整数毫米。
2. **找得到**：输入需求尺寸，按「浪费面积最小 → 余料更可再利用」排序给出候选，并告诉你这块砖怎么切、切完剩什么形状。
3. **追得回**：每次使用都写流水；切下来的余料自动成为新批次，带父批次、根批次、切割方式、余料 geometry，能一路点回原砖。

## 二、功能清单

| 能力 | 说明 |
|---|---|
| 项目隔离 | 以项目为数据单位，所有表带 `project_id`；跨项目访问一律 404/403 |
| 项目名唯一 | 去首尾空格 + 忽略大小写 + Unicode NFKC 归一化后全局唯一，重复返回 `409 project_name_taken` |
| 无账号 | 首次启动注册设备（设备 ID + 设备密钥，密钥只返回一次）；加入项目后签发长期项目令牌 |
| 邀请码 | 10 位高熵、长期有效（不自动过期），可撤销 / 重置；二维码只含邀请码与服务器地址 |
| 库存录入 | **只允许矩形**：长、宽、片数；支持 `800` / `80cm` / `800mm`，统一存毫米 |
| 匹配 | 允许旋转 90°，长短边自动规范化；需求必须被完全覆盖，否则不给候选 |
| 切割 | 二选一：长边切到底 / 短边切到底；实时图示预览原砖、需求、余料 |
| 余料 | 二选一：直接入库（矩形或 L 形）/ 丢弃；丢弃也写流水与溯源 |
| 流水 | 只追加；含变动前后尺寸片数、使用尺寸、切法、余料处置、设备、关联使用记录 |
| 溯源 | 原砖 / 需求 / 余料三列对比 + 父子链 + 关联流水；库存卡片与流水详情都能进入 |
| 并发 | 事务 + 乐观锁（`version`）+ 幂等键；并发确认不会超扣，重复提交不会重复扣减 |
| 导出 | 流水 CSV（带 BOM，Excel 直接打开中文表头） |

## 三、目录结构

```
tile-remnant-inventory/
├── backend/
│   ├── app/
│   │   ├── main.py               # FastAPI 应用、路由挂载、错误处理
│   │   ├── config.py             # 全部可配置项（env）
│   │   ├── db.py                 # engine / Session / SQLite WAL
│   │   ├── models.py             # 9 张表的 ORM 定义
│   │   ├── schemas.py            # 请求体校验（Pydantic v2）
│   │   ├── geometry.py           # ★ 矩形/异形几何引擎（切、余料、L 形）
│   │   ├── units.py              # cm/mm 解析
│   │   ├── deps.py               # 设备凭证 + 项目成员鉴权
│   │   ├── security.py           # bcrypt / 令牌哈希
│   │   ├── errors.py             # 统一错误码
│   │   ├── middleware.py         # 请求 ID、速率限制、安全响应头
│   │   ├── routers/              # devices / projects / inventory / matching
│   │   └── services/             # projects / inventory / matching / usage / movements / trace
│   ├── alembic/                  # 迁移（初始版本已生成并验证）
│   ├── tests/                    # 104 个 pytest 用例
│   ├── Dockerfile
│   └── docker-entrypoint.sh
├── mobile/
│   ├── lib/
│   │   ├── core/                 # 主题、API 客户端、会话、模型、单位格式化
│   │   ├── widgets/              # ★ TileShapePreview（Canvas 俯视图）、库存卡、尺寸输入
│   │   └── features/             # 项目列表/新建/加入/扫码、库存、匹配、确认、流水、溯源、设置
│   ├── android/                  # Gradle 工程、清单、网络安全配置、图标
│   ├── test/                     # formatters / invite payload / 图形组件
│   └── tool/generate_icons.py    # 无依赖生成 launcher 图标
├── deploy/nginx/tile-api.conf    # HTTPS、HSTS、限流、反代
├── docs/                         # API、数据库、溯源、安全、部署、备份、博客文章
├── scripts/                      # build_apk / publish_github / backup / restore / dev / wp_publish
├── docker-compose.yml
├── .env.example
└── LICENSE                       # GPL-3.0
```

## 四、数据模型

9 张表，项目级表全部带 `project_id` 索引：

| 表 | 作用 | 关键字段 |
|---|---|---|
| `devices` | 设备身份 | `secret_hash`（bcrypt）、`last_seen_at` |
| `projects` | 项目 | `name_key`（唯一）、`default_unit`、`min_usable_mm`、`status`（软删除） |
| `project_members` | 成员关系 | `role`（owner/member）、`removed_at` |
| `project_invites` | 邀请码 | `code`（唯一）、`status`、`generation` |
| `project_access_tokens` | 项目令牌 | `token_hash`（sha256）、`revoked_at` |
| `inventory_batches` | 余砖批次 | `shape_type`、`width_mm/height_mm`、`geometry`(JSON)、`area_mm2`、`quantity`、`source_type`、`parent_batch_id`、`root_batch_id`、`cut_option`、`version` |
| `usage_records` | 使用记录 | `idempotency_key`（项目内唯一）、需求尺寸/数量、`total_waste_mm2` |
| `inventory_movements` | 流水（只追加） | `type`、`quantity_before/after`、`width/height_before/after`、`used_*`、`cut_option`、`remnant_action`、`remnant_shape/area`、`produced_batch_id` |
| `audit_logs` | 审计 | `action`、`target_*`、`ip`、`detail` |

完整字段与索引见 [`docs/database.md`](docs/database.md)。

## 五、匹配与切割算法

### 5.1 尺寸规范化

- 输入 `80cm` / `800mm` / `80`（按项目默认单位）→ 整数毫米。
- 库存和需求都转成 `(short, long)`，不要求用户先输长边。
- 库存批次的坐标空间固定为 `x = 短边`、`y = 长边`；任何时刻都保持 `width_mm <= height_mm`。

### 5.2 覆盖判定（不许有缝）

矩形库存：`需求短边 <= 库存短边 且 需求长边 <= 库存长边`，允许旋转 90°。
异形库存：把 L 形拆成若干「最大矩形子区域」，需求必须完整落在其中一个子区域内。

> 900×800 的余砖可以匹配 800×900、90cm×80cm、800mm×900mm；801×901 直接没有候选。

### 5.3 排序

```
浪费面积升序
  → 余料可再利用价值降序（余料面积，异形 ×0.75，低于阈值 ×0.4）
  → 单块可切片数降序
  → 录入时间 / 批次号升序
```

面积相同的情况下优先留下更大的整块余料——这比「先切碎」更贴近师傅的实际习惯。

### 5.4 切割模型

需求矩形永远从某个角的**直线切到底**取出，因此一次切割最多产生一个连通的余料：

- 需求宽 = 库存宽 → 余料是矩形条；
- 需求高 = 库存高 → 余料是矩形条；
- 都不相等 → 余料是 **L 形**（一个角被切掉）；
- 需求 = 整砖 → **无余料**，跳过余料处置。

「长边切到底」= 需求长边与原砖长边平行；「短边切到底」= 旋转 90°，切割线沿短边方向贯穿。

## 六、L 形余料规则

```json
{
  "type": "l_shape",
  "width_mm": 800, "height_mm": 900,
  "outer": {"w": 800, "h": 900},
  "notch": {"x": 600, "y": 600, "w": 200, "h": 300},
  "notch_corner": "top_right",
  "rects": [{"x":0,"y":0,"w":800,"h":600}, {"x":0,"y":600,"w":600,"h":300}]
}
```

- 用「外接矩形 + 缺口矩形 + 缺口角位置」描述，同时给出 `rects`（可绘制的矩形并集），客户端永远画 `rects`，不会画错。
- 多次切割后若余料不再是一个标准 L（缺口不在角上），仍标记为 `l_shape` 并置 `composite: true`，几何信息完整保留，不做假简化。
- 入库时若最小边 < `min_usable_mm`（默认 50mm），接口返回 `below_threshold: true`，App 提示但允许强制入库。
- 图示：外框为原砖，实心块为需求，剩余为余料，缺口用斜线填充，虚线为刀路。

## 七、API 一览

所有项目级接口都需要两个请求头：

```
X-Device-Id: <设备 ID>
X-Project-Token: <项目令牌>
```

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/devices/register` | 注册设备，返回设备 ID + 密钥（仅一次） |
| POST | `/api/devices/heartbeat` | 心跳 |
| GET | `/api/projects/name-available` | 项目名实时查重 |
| POST | `/api/projects` | 新建项目（唯一名校验），返回令牌 + 邀请码 |
| GET | `/api/projects` | 本机已加入的项目 |
| POST | `/api/projects/join` | 邀请码加入 |
| GET/PATCH/DELETE | `/api/projects/{id}` | 详情 / 设置 / 软删除 |
| GET | `/api/projects/{id}/summary` | 概览 + 最近 3 条流水 |
| GET | `/api/projects/{id}/invite` | 查看邀请码（拥有者） |
| POST | `/api/projects/{id}/invite/revoke`、`/reset` | 撤销 / 重置 |
| GET | `/api/projects/{id}/members` | 成员设备（拥有者） |
| DELETE | `/api/projects/{id}/membership` | 移除本设备关联 |
| DELETE | `/api/projects/{id}/members/{deviceId}` | 移除指定设备（拥有者） |
| POST/GET | `/api/projects/{id}/inventory` | 录入 / 列表（筛选分页） |
| PATCH | `/api/projects/{id}/inventory/{batchId}` | 位置 / 备注 / 片数 / 状态 |
| POST | `/api/projects/{id}/match` | 匹配，返回候选、旋转、切法、余料预览 |
| POST | `/api/projects/{id}/usage/confirm` | 确认使用（事务 + 幂等） |
| GET | `/api/projects/{id}/movements` | 流水（筛选分页） |
| GET | `/api/projects/{id}/movements/export` | 导出 CSV |
| GET | `/api/projects/{id}/trace/{batchId}` | 溯源对比 |

统一错误体：

```json
{"error": {"code": "project_name_taken", "message": "项目名称已被占用", "details": {}, "request_id": "...", "timestamp": "..."}}
```

完整参数、示例与错误码见 [`docs/api.md`](docs/api.md)；交互式文档：`https://你的域名/docs`。

## 八、本地开发与测试

```bash
# 后端（默认 SQLite，自动建表）
bash scripts/dev_backend.sh
# → http://127.0.0.1:8000/docs

# 只跑测试
cd backend
python -m pytest -q
```

当前结果：

```
104 passed
```

覆盖点：cm/mm 解析、旋转、覆盖校验、L 形几何、余料面积守恒、异形入库/丢弃、三种切割结果、多片扣减、多批次拆分、幂等、并发不超扣、项目名唯一、越权 403、邀请码撤销/重置、软删除、CSV 导出、溯源链。

## 九、部署（Docker + Nginx + HTTPS）

```bash
cp .env.example .env
# 必改：PUBLIC_BASE_URL=https://你的域名  DATABASE_URL  POSTGRES_PASSWORD
mkdir -p deploy/certs
# 放入 fullchain.pem / privkey.pem（或先用 acme.sh webroot 签发）
sed -i 's/tiles.example.com/你的域名/g' deploy/nginx/tile-api.conf
docker compose up -d --build
docker compose logs -f api
```

- API 只监听容器内 `8000`，**不映射到宿主机**；对外只有 Nginx 的 80/443。
- Nginx：HTTP→HTTPS 301、TLS1.2/1.3、HSTS、`X-Content-Type-Options`、请求体 1MB 上限、读写分离限流。
- 启动时 `docker-entrypoint.sh` 自动执行 `alembic upgrade head`。
- PostgreSQL 可选：`docker compose --profile postgres up -d`，并把 `DATABASE_URL` 改为 `postgresql+psycopg://tile:密码@db:5432/tile`；数据库同样不暴露端口。

细节与排错见 [`docs/deployment.md`](docs/deployment.md)。

## 十、构建 APK

前置：Flutter 3.22+、Android SDK（platform 35 + build-tools）、JDK 17。

```bash
API_BASE_URL=https://你的域名 bash scripts/build_apk.sh
# 产物：dist/tile-remnant-0.1.0.apk
```

脚本会：生成 `android/local.properties` → 必要时补 Gradle wrapper → `pub get` → `analyze` → `test` → `build apk --release`。

签名（推荐，私发也需要）：

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cat > mobile/android/key.properties <<'EOF'
storePassword=你的密码
keyPassword=你的密码
keyAlias=upload
storeFile=/绝对路径/upload-keystore.jks
EOF
```

没有 `key.properties` 时 Release 会退化为 debug 签名（可安装，但不适合长期分发）。

### 常见报错

| 报错 | 原因 / 解决 |
|---|---|
| `Java/Gradle incompatibility`，提示 Java 25 | Flutter 默认用 Android Studio 自带的 JDK（可能是 25），而 Gradle 8.7 只支持到 21。必须 `flutter config --jdk-dir="<JDK17 路径>"`——**只设 `JAVA_HOME` 不生效**，Flutter 有自己的 jdk 配置 |
| `Downloading ... gradle-8.7-all.zip failed: timeout` | `services.gradle.org` 国内经常连不上。下腾讯镜像（`https://mirrors.cloud.tencent.com/gradle/gradle-8.7-all.zip`），把 `gradle-wrapper.properties` 的 `distributionUrl` 临时指向本地文件：`file\:///D\:/路径/gradle-8.7-all.zip` |
| `Invalid WebSocket upgrade request`（跑 `flutter test` 时） | 系统代理拦了 localhost 的 WebSocket。清掉 `http_proxy` / `https_proxy`，并设 `NO_PROXY=localhost,127.0.0.1,::1` |

SDK 缺 `.git`、`dart-sdk.old1` 这类更少见的问题，排查过程记在 [`docs/how-to-use.md`](docs/how-to-use.md) 第 3.3 节。

## 十一、备份与恢复

```bash
bash scripts/backup.sh                 # → backups/20261031-2100/tile_remnant.db
bash scripts/restore.sh backups/20261031-2100/tile_remnant.db
```

- SQLite 用 `.backup` / `VACUUM INTO`，WAL 模式下也能得到一致副本；
- PostgreSQL 用 `pg_dump | gzip`；
- 保留最近 14 份；
- 恢复前会把现有库改名为 `*.before-restore.<ts>`。

完整演练步骤（含容器内备份、异地保存、恢复后校验）见 [`docs/backup-restore.md`](docs/backup-restore.md)。

## 十二、安全说明

- 全链路 HTTPS：Nginx 强制 301，App 端拒绝非 HTTPS（仅允许 `localhost`/`10.0.2.2` 调试），Android `cleartextTrafficPermitted=false`。
- 客户端不直连数据库：数据库仅存在于容器网络，不映射端口。
- 设备密钥 bcrypt（cost 12）哈希存储，仅在注册时返回一次；项目令牌 sha256 哈希存储，可撤销。
- 项目级接口逐次校验「设备 ∈ 项目成员 且 令牌属于该设备」，仅凭 `project_id` 无法访问（401/403）。
- 日志脱敏：不打印密钥、令牌、完整请求体。
- 速率限制：应用层滑动窗口 + Nginx `limit_req` 双层。
- 审计：项目创建/加入/邀请变更/成员移除/使用确认全部落 `audit_logs`。

详见 [`docs/security.md`](docs/security.md)。

## 十三、假设与可配置项

| # | 假设 | 可配置 |
|---|---|---|
| 1 | 项目名唯一性**包含已软删除的项目**（避免历史批次指向同名新项目） | 需改代码 `projects.check_name_available` |
| 2 | 库存尺寸按 `(短边, 长边)` 规范化存储，`width_mm <= height_mm` | 固定约定 |
| 3 | 一次切割只从一个角直线切到底，最多产生一块连通余料 | 固定算法 |
| 4 | 多片需求可从同一批次切多片，余料按「同批次同切法」合并为一个批次（数量 = 片数） | 固定 |
| 5 | 最小可用阈值默认 50mm，入库仅提示不阻止 | 项目级 `min_usable_mm` / `.env` `MIN_USABLE_MM` |
| 6 | 邀请码 10 位，字符集剔除 `0/O/1/I/L`，便于口述 | `.env` `INVITE_CODE_LENGTH` |
| 7 | 项目令牌默认永不过期（`TOKEN_TTL_DAYS=0`） | `.env` |
| 8 | 设备密钥 bcrypt cost 12（约 250ms/次） | `.env` `BCRYPT_ROUNDS` |
| 9 | 时间统一以 UTC 存库，接口返回 ISO8601（`Z`） | 固定 |
| 10 | 速率限制为单进程内存实现，多副本需换 Redis | 代码 `ratelimit.py` |
| 11 | 服务端不生成二维码图片，只返回 payload，由 App 用 `qr_flutter` 渲染 | 固定 |
| 12 | 单张照片/附件上传不在本期范围 | — |
| 13 | CSV 导出上限 20000 行 | 代码 `movements.export_csv` |
| 14 | `AUTO_CREATE_TABLES` 仅供本地，生产走 Alembic | `.env` |

## 十四、换机 / 清缓存说明

**没有项目恢复码。**

- 设备身份（设备 ID + 密钥）与项目令牌保存在系统安全存储（Android Keystore 支持的 EncryptedSharedPreferences）。
- 同一台手机可以加入多个项目，加入后长期保留，下次打开自动加载，无需再次扫码。
- 换手机、卸载重装、清除应用数据、恢复出厂设置后，本机身份丢失 → **需要用邀请码/二维码重新加入**。项目库存、流水、溯源记录都还在服务器上，不受影响。
- 成员可以随时「移除本项目关联」；拥有者不能退出，只能删除项目（软删除）。

## 十五、本次交付的实际状态

| 项 | 状态 |
|---|---|
| 后端代码 + 迁移 + 测试 | ✅ 完成，`pytest` 104 passed |
| Alembic 初始迁移 | ✅ 已生成并实际 `upgrade head` 验证 |
| Flutter 源码（10 个页面 + 图示组件） | ✅ 完整提交 |
| Flutter `analyze` / `test` | ✅ `analyze` **0 error / 0 warning**；`test` **14 passed**（修了 5 个真实 bug：3 处漏 import、`post()` 缺参数、`formatArea` 阈值与 `parseLengthToMm` 吞空格） |
| APK 构建 | ✅ `app-release.apk` **36.5 MB**（Flutter 3.47.9 + JDK 17 + Gradle 8.14.3，debug 签名） |
| Docker Compose / Nginx 配置 | ⚠️ **未实跑**：本机无 Docker，`wsl.exe` 被安全策略拦截。已用 `uvicorn` 起真实服务验证 `/healthz` 返回 200（compose 的健康检查就是这条） |
| GitHub 仓库 / Release | ✅ <https://github.com/z7ui/tile-remnant-inventory>（PUBLIC），Release v0.1.0 **已附 APK**，digest 与本地一致 |
| WordPress 博客 | ✅ <https://www.z7ui.cn/tile-remnant-inventory/>（post 89） |

环境搭建与踩坑的完整记录见 [`docs/DELIVERY-STATUS.md`](docs/DELIVERY-STATUS.md)，
面向使用者的操作说明见 [`docs/how-to-use.md`](docs/how-to-use.md)。
