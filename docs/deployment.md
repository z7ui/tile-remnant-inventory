# 部署说明（Docker Compose + Nginx + HTTPS）

目标：把 API 跑在**你自己的博客云主机**上，手机通过 HTTPS 访问。

## 0. 前置

- 一台有公网 IP 的 Linux 主机（1C1G 起）
- 已解析到该主机的域名，例如 `tiles.example.com`
- Docker 24+、Docker Compose v2
- 80/443 端口可访问（签证书 + 跳转用）

## 1. 准备代码与配置

```bash
git clone https://github.com/<you>/tile-remnant-inventory.git
cd tile-remnant-inventory
cp .env.example .env
```

编辑 `.env`，至少改这三项：

```ini
PUBLIC_BASE_URL=https://tiles.example.com
DATABASE_URL=sqlite:////data/tile_remnant.db
BCRYPT_ROUNDS=12
```

`.env` 权限：

```bash
chmod 600 .env
```

## 2. 证书

### 方式 A：已有证书

```bash
mkdir -p deploy/certs
cp /path/fullchain.pem deploy/certs/fullchain.pem
cp /path/privkey.pem   deploy/certs/privkey.pem
```

### 方式 B：acme.sh webroot（推荐）

先用 HTTP 起一个只做 ACME 校验的 Nginx（或临时把 80 端口让给 acme.sh）：

```bash
mkdir -p deploy/acme
docker run --rm -v "$PWD/deploy/acme:/acme" -v "$PWD/deploy/certs:/certs" \
  neilpang/acme.sh --issue -d tiles.example.com --standalone
```

拿到证书后放到 `deploy/certs/fullchain.pem` 与 `privkey.pem`，并在宿主机加 cron 续期。

## 3. 改域名

```bash
sed -i 's/tiles.example.com/你的域名/g' deploy/nginx/tile-api.conf
```

## 4. 启动

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f api
```

预期：

- `tile-api` 状态 healthy；
- 日志出现 `Running upgrade -> 9eb0dc91e867, initial schema`（首次）；
- `curl https://你的域名/healthz` 返回 `{"status":"ok",...}`。

## 5. 验证

```bash
# HTTPS 跳转
curl -I http://你的域名            # 301 → https
# 证书与 HSTS
curl -sI https://你的域名/healthz | grep -i strict-transport
# 数据库没有对外端口
docker compose ps                  # api 只有 8000/tcp，无 0.0.0.0:8000
ss -lntp | grep -E '5432|3306'     # 应为空
# 未授权访问
curl -s -o /dev/null -w '%{http_code}\n' https://你的域名/api/projects   # 401
```

## 6. 切到 PostgreSQL（可选）

```bash
# .env
POSTGRES_PASSWORD=<长随机>
DATABASE_URL=postgresql+psycopg://tile:<长随机>@db:5432/tile

docker compose --profile postgres up -d
docker compose exec api alembic upgrade head
```

需要在镜像里装驱动：把 `backend/requirements-postgres.txt` 的内容并入 `requirements.txt` 后重新 build。

## 7. 升级

```bash
git pull
docker compose build api
docker compose up -d api       # entrypoint 自动 alembic upgrade head
```

回滚：`git checkout <tag> && docker compose up -d --build`，数据库迁移需自行 `alembic downgrade`（初始版本 `downgrade` 会删表，谨慎）。

## 8. 常见问题

| 现象 | 排查 |
|---|---|
| 502 Bad Gateway | `docker compose logs api`，多为迁移失败或端口未起 |
| 手机提示「必须使用 HTTPS」 | App 只接受 https（除 localhost/10.0.2.2），检查 `PUBLIC_BASE_URL` |
| 扫码后加入失败 | 二维码里的 `server` 与 API 实际域名不一致，重建项目或改 `.env` 后重新生成邀请码 |
| 上传 413 | Nginx `client_max_body_size` 与 `MAX_BODY_BYTES`，本期只需 JSON，正常不会触发 |
| 429 频繁 | 调 `.env` 的 `RATE_LIMIT_*` 与 Nginx `limit_req` |
| SQLite `database is locked` | 提高 `SQLITE_BUSY_TIMEOUT_MS`；并发高的工地建议换 PostgreSQL |

## 9. 资源占用

| 组件 | 内存 | 磁盘 |
|---|---|---|
| api（uvicorn 单进程） | ~120MB | 镜像 ~180MB |
| nginx | ~10MB | — |
| SQLite 数据 | — | 每万条流水约 5–10MB |

1C1G 主机足够十几个项目、几十台设备日常使用。
