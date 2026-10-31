# 备份与恢复

数据是工地的实际库存记录，丢了就得重新盘点——请把备份当成必做项。

## 一、备份

### 1. 一键脚本

```bash
# SQLite（默认，读 .env 的 DATABASE_URL 或 DB_PATH）
bash scripts/backup.sh

# 指定路径
DB_PATH=/var/lib/docker/volumes/tile-remnant_tile_data/_data/tile_remnant.db \
  bash scripts/backup.sh

# PostgreSQL
DATABASE_URL=postgresql://tile:***@127.0.0.1:5432/tile bash scripts/backup.sh
```

产出：`backups/YYYYmmdd-HHMM/tile_remnant.db`（或 `.sql.gz`），自动保留最近 14 份。

### 2. 容器内备份（SQLite）

```bash
docker compose exec api python - <<'PY'
import sqlite3
src = sqlite3.connect('/data/tile_remnant.db')
dst = sqlite3.connect('/data/backup-copy.db')
src.backup(dst)
dst.close(); src.close()
print('ok')
PY
docker compose cp api:/data/backup-copy.db ./backups/manual-$(date +%Y%m%d).db
docker compose exec api rm /data/backup-copy.db
```

### 3. 为什么不能直接 `cp` 正在写入的 SQLite

WAL 模式下主库文件可能缺少最新事务。用 `.backup` / `VACUUM INTO` / `Connection.backup()` 才能拿到一致快照。

### 4. 异地保存

```bash
# rclone 到对象存储
rclone copy backups/ remote:tile-backup/ --max-age 30d

# 或 rsync 到另一台机器
rsync -az backups/ backup-host:/srv/tile-backup/
```

建议：本机留 14 天，异地留 30 天，每月做一次恢复演练。

### 5. 定时任务

```cron
# 每天 03:10 备份并同步
10 3 * * * cd /opt/tile-remnant-inventory && /usr/bin/bash scripts/backup.sh >> /var/log/tile-backup.log 2>&1
30 3 * * * rclone copy /opt/tile-remnant-inventory/backups/ remote:tile-backup/ --max-age 35d
```

## 二、恢复

```bash
# 1. 停写入
docker compose stop api

# 2. 恢复（脚本会要求输入 RESTORE 确认）
bash scripts/restore.sh backups/20261031-2100/tile_remnant.db

# 3. 启动（entrypoint 会跑 alembic upgrade head）
docker compose start api

# 4. 校验
curl -s https://你的域名/healthz
```

PostgreSQL：

```bash
gunzip -c backups/20261031-2100/tile_remnant.sql.gz | \
  docker compose exec -T db psql -U tile -d tile
```

## 三、恢复后校验清单

```bash
# 项目数、批次数、流水数
docker compose exec api python - <<'PY'
import sqlite3
c = sqlite3.connect('/data/tile_remnant.db')
for table in ('projects','inventory_batches','inventory_movements','usage_records'):
    print(table, c.execute(f'select count(*) from {table}').fetchone()[0])
PY
```

再用 App 抽查一个项目：

1. 库存总片数与备份前一致；
2. 最近一条流水时间正确；
3. 随机点开一个 L 形批次的溯源页，父子链完整。

## 四、迁移到新主机

```bash
# 旧机
bash scripts/backup.sh
scp backups/20261031-2100/tile_remnant.db new-host:/tmp/

# 新机
git clone … && cd tile-remnant-inventory
cp .env.example .env && vi .env
mkdir -p deploy/certs && scp 证书…
docker compose up -d --build
docker compose stop api
docker run --rm -v tile-remnant_tile_data:/data -v /tmp:/backup alpine \
  cp /backup/tile_remnant.db /data/tile_remnant.db
docker compose start api
```

域名不变时，手机端无需任何操作；域名变了需要在 App 设置里改服务器地址（会清空本机项目关联，需重新扫码）。

## 五、故障演练建议

| 场景 | 做法 | 期望 |
|---|---|---|
| 误删项目 | 恢复前一天备份到临时库，手工导出该项目 | 数据可回捞 |
| 磁盘写满 | 限制备份保留数、日志轮转 | API 仍可只读 |
| 数据库损坏 | 用最新备份 + 当日流水核对 | 最多丢一天 |
