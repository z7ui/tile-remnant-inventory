#!/usr/bin/env bash
# Restore a backup created by scripts/backup.sh.
#   bash scripts/restore.sh backups/20261031-2100/tile_remnant.db
#   bash scripts/restore.sh backups/20261031-2100/tile_remnant.sql.gz
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "用法: bash scripts/restore.sh <备份文件>" >&2
  exit 1
fi

DATABASE_URL="${DATABASE_URL:-sqlite:///./data/tile_remnant.db}"

echo "!!! 恢复会覆盖现有数据，请确认所有设备已停止写入。"
read -r -p "输入 RESTORE 继续: " answer
[ "$answer" = "RESTORE" ] || { echo "已取消"; exit 1; }

if [[ "$SRC" == *.db ]]; then
  DB_PATH="${DB_PATH:-${DATABASE_URL#sqlite:///}}"
  mkdir -p "$(dirname "$DB_PATH")"
  if [ -f "$DB_PATH" ]; then
    cp "$DB_PATH" "$DB_PATH.before-restore.$(date +%s)"
  fi
  cp "$SRC" "$DB_PATH"
  rm -f "$DB_PATH-wal" "$DB_PATH-shm"
  echo "==> 已恢复 SQLite: $DB_PATH"
elif [[ "$SRC" == *.sql.gz ]]; then
  if ! command -v psql >/dev/null 2>&1; then
    echo "ERROR: 需要 psql 客户端" >&2
    exit 1
  fi
  gunzip -c "$SRC" | psql "$DATABASE_URL"
  echo "==> 已恢复 PostgreSQL"
else
  echo "ERROR: 不认识的备份格式" >&2
  exit 1
fi

echo "==> 重启 API 后生效: docker compose restart api"
