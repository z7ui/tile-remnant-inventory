# 部署说明

目标：把 API 跑在**你自己的云主机**上，手机通过 HTTPS 访问。

两条路，先按场景选：

| 你的机器 | 用哪个 |
|---|---|
| 已经跑着 nginx（博客、其它站点、有现成证书） | **A. systemd + 现有 nginx** ← 推荐 |
| 全新机器，想整套容器化 | B. Docker Compose（见文末） |

> **为什么默认不是 Docker**：这台机器上大概已经有一个 nginx 占着 80/443。
> compose 里那套 nginx 会去抢端口，跟现有站点正面冲突（博客立刻 502）。
> 而这个项目本身只是一个 uvicorn 进程 + 一个 SQLite 文件，没必要为它再套一层。

---

## A. systemd + 现有 nginx（推荐）

### A0. 前置

- 一台 Linux 主机（1C1G 起），Python **3.11+**
- 已解析到该主机的域名，例如 `tiles.example.com`
- 宿主机上已有 nginx 和有效证书（certbot / acme.sh 签的都行）
- 一个专用系统用户，下面用 `tile`

```bash
useradd --system --home /opt/tile --shell /usr/sbin/nologin tile
mkdir -p /opt/tile /var/lib/tile
chown -R tile:tile /opt/tile /var/lib/tile
```

### A1. 放代码

```bash
git clone https://github.com/z7ui/tile-remnant-inventory.git /opt/tile/app
chown -R tile:tile /opt/tile/app
```

### A2. 虚拟环境与依赖

```bash
sudo -u tile python3 -m venv /opt/tile/venv
sudo -u tile /opt/tile/venv/bin/pip install -U pip
sudo -u tile /opt/tile/venv/bin/pip install -r /opt/tile/app/backend/requirements.txt
```

> 国内装不动时加 `-i https://pypi.tuna.tsinghua.edu.cn/simple`；反过来，如果镜像报
> `No matching distribution found`（`from versions: none`），换官方源
> `--index-url https://pypi.org/simple` 再来一次。

### A3. 配置 `.env`

```bash
cp /opt/tile/app/.env.example /opt/tile/app/.env
chown tile:tile /opt/tile/app/.env
chmod 600 /opt/tile/app/.env
```

至少改这几项：

```ini
PUBLIC_BASE_URL=https://tiles.example.com
DATABASE_URL=sqlite:////var/lib/tile/tile_remnant.db
DATA_DIR=/var/lib/tile
ENVIRONMENT=production
AUTO_CREATE_TABLES=false
BCRYPT_ROUNDS=12
```

两个容易错的地方：

- **SQLite 路径是四条斜杠**：`sqlite:////var/lib/tile/...`（`sqlite://` + 绝对路径 `/var/...`）。
  容器里的 `/data/...` 在宿主机上不存在，照抄会启动失败。
- **`.env` 里不要给值加引号**。systemd 的 `EnvironmentFile` 会把引号当成值的一部分，
  `PUBLIC_BASE_URL="https://..."` 会变成带引号的字符串，二维码里的地址就是错的。

### A4. 先手动跑一次迁移

容器方案里 `docker-entrypoint.sh` 会自动迁移，systemd 不会。**部署时必须手动跑一次**，
以后升级也要跑：

```bash
cd /opt/tile/app/backend
sudo -u tile env $(grep -v '^#' /opt/tile/app/.env | xargs) \
  /opt/tile/venv/bin/alembic upgrade head
```

预期看到 `Running upgrade -> 9eb0dc91e867, initial schema`，随后建出 9 张表。

> 为什么不在 unit 里自动跑：迁移失败时你希望服务**不要**起来，而不是带着半新半旧的表结构
> 对外服务。手动一步比在 `ExecStartPre` 里藏着错误安全。

### A5. systemd unit

```ini
# /etc/systemd/system/tile-api.service
[Unit]
Description=Tile Remnant API
After=network.target

[Service]
Type=simple
User=tile
Group=tile
WorkingDirectory=/opt/tile/app/backend
EnvironmentFile=/opt/tile/app/.env
ExecStart=/opt/tile/venv/bin/uvicorn app.main:app \
          --host 127.0.0.1 --port 8000 \
          --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=always
RestartSec=3

# 基本加固：禁止提权、私有 /tmp、系统目录只读
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now tile-api
systemctl status tile-api --no-pager
curl -s http://127.0.0.1:8000/healthz     # {"status":"ok","version":"0.1.0"}
```

**只监听 `127.0.0.1`**：8000 不对外，外部一律走 nginx。

### A6. nginx server block

```nginx
# /etc/nginx/conf.d/tiles.conf
server {
    listen 80;
    server_name tiles.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name tiles.example.com;

    ssl_certificate     /etc/letsencrypt/live/tiles.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tiles.example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff always;

    client_max_body_size 1m;

    location / {
        proxy_pass         http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }
}
```

```bash
nginx -t && systemctl reload nginx
```

> 三个 `X-Forwarded-*` 别省：unit 里开了 `--proxy-headers`，后端的限流和来源校验都依赖真实 IP；
> 少了 `X-Forwarded-Proto`，后端可能以为自己收到的是 HTTP。

### A7. 验证

```bash
curl -I http://tiles.example.com                     # 301 → https
curl -s https://tiles.example.com/healthz | head -1  # {"status":"ok",...}
curl -sI https://tiles.example.com/healthz | grep -i strict-transport
curl -s -o /dev/null -w '%{http_code}\n' https://tiles.example.com/api/projects   # 401
ss -lntp | grep 8000                                 # 只应看到 127.0.0.1:8000
```

最后一条很关键：如果 `ss` 显示 `0.0.0.0:8000`，说明 `--host` 写成了 `0.0.0.0`，API 直接暴露在公网。

### A8. 升级与回滚

```bash
cd /opt/tile/app
sudo -u tile git pull
sudo -u tile /opt/tile/venv/bin/pip install -r backend/requirements.txt
# 有迁移就先迁
cd backend && sudo -u tile env $(grep -v '^#' /opt/tile/app/.env | xargs) \
  /opt/tile/venv/bin/alembic upgrade head
systemctl restart tile-api
```

回滚：`git checkout <tag>` → 重装依赖 → 重启。数据库迁移要自己 `alembic downgrade`，
**初始版本 downgrade 会删表**，先备份 `/var/lib/tile/tile_remnant.db`。

### A9. 备份

SQLite 用 WAL，别直接 `cp` 正在写的库：

```bash
sqlite3 /var/lib/tile/tile_remnant.db ".backup '/var/backups/tile-$(date +%F).db'"
```

详见 [`backup-restore.md`](backup-restore.md)。

---

## B. Docker Compose（可选）

只有两种情况值得用：**全新机器**，或者你就是要容器化。

### B1. 只跑 api（复用宿主机 nginx）—— 默认行为

`docker-compose.yml` 里 api 只绑 `127.0.0.1:8000`，nginx 服务挂在 `standalone` profile 下
**默认不启动**，所以不会跟宿主机 nginx 抢 80/443。此时按 A6 配反向代理即可，
`proxy_pass http://127.0.0.1:8000`。

```bash
cp .env.example .env && chmod 600 .env
# 必改：PUBLIC_BASE_URL、DATABASE_URL、BCRYPT_ROUNDS
docker compose up -d --build
docker compose ps                     # tile-api 应为 healthy
curl -s http://127.0.0.1:8000/healthz # {"status":"ok",...}
```

容器内的 `DATABASE_URL` 用 `sqlite:////data/tile_remnant.db`（`/data` 是命名卷），
这一点和 A3 的宿主机路径不同，别混。

### B2. 整套容器化（含 nginx）

仅当机器上**没有**别的 nginx 占着 80/443：

```bash
mkdir -p deploy/certs
# 放入 fullchain.pem / privkey.pem
sed -i 's/tiles.example.com/你的域名/g' deploy/nginx/tile-api.conf
docker compose --profile standalone up -d --build
```

启动时 `docker-entrypoint.sh` 会自动 `alembic upgrade head`。

### B3. PostgreSQL

```ini
# .env
POSTGRES_PASSWORD=<长随机>
DATABASE_URL=postgresql+psycopg://tile:<长随机>@db:5432/tile
```

```bash
docker compose --profile postgres up -d
docker compose exec api alembic upgrade head
```

需要驱动：把 `backend/requirements-postgres.txt` 并入 `requirements.txt` 后重建镜像。
数据库不映射宿主机端口，只能从 `edge` 网络访问。

---

## 常见问题

| 现象 | 排查 |
|---|---|
| `502 Bad Gateway` | `systemctl status tile-api` / `journalctl -u tile-api -n 50`；多为迁移没跑或端口没起 |
| 服务起来就退 | 多半是 `.env` 的 `DATABASE_URL` 路径不对（容器路径 vs 宿主机路径），或目录没有写权限 |
| 手机提示「必须使用 HTTPS」 | App 只接受 https（除 localhost）。检查 `PUBLIC_BASE_URL` 与证书 |
| 扫码后加入失败 | 二维码里的 `server` 和 API 实际域名不一致；改 `.env` 后重新生成邀请码 |
| 二维码里域名带引号 | `.env` 里给值加了引号，systemd 把它当成了值的一部分 |
| `413` 上传失败 | nginx `client_max_body_size` 与后端 `MAX_BODY_BYTES`；本期只传 JSON，正常不触发 |
| `429` 频繁 | 调 `.env` 的 `RATE_LIMIT_*` 与 nginx `limit_req` |
| SQLite `database is locked` | 调大 `SQLITE_BUSY_TIMEOUT_MS`；并发高的工地换 PostgreSQL |
| `ss` 看到 `0.0.0.0:8000` | `--host` 写成了 `0.0.0.0`，API 已暴露公网，改成 `127.0.0.1` |

## 资源占用

| 组件 | 内存 | 磁盘 |
|---|---|---|
| uvicorn 单进程（systemd） | ~120 MB | 依赖 ~150 MB |
| api 容器 | ~120 MB | 镜像 ~180 MB |
| nginx（复用宿主机） | 已有 | — |
| SQLite 数据 | — | 每万条流水约 5–10 MB |

1C1G 主机足够十几个项目、几十台设备日常使用。Docker 自身在 1C1G 上还要额外吃 100–200 MB，
这也是优先选 systemd 的原因之一。
