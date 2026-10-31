#!/usr/bin/env bash
# Backup SQLite (default) or PostgreSQL (DATABASE_URL=postgresql://...) data.
#
#   bash scripts/backup.sh                  # -> backups/YYYYmmdd-HHMM/
#   DB_PATH=/data/tile_remnant.db bash scripts/backup.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M)"
OUT_DIR="${OUT_DIR:-$ROOT/backups/$STAMP}"
mkdir -p "$OUT_DIR"

DATABASE_URL="${DATABASE_URL:-sqlite:///./data/tile_remnant.db}"

if [[ "$DATABASE_URL" == sqlite* ]]; then
  DB_PATH="${DB_PATH:-${DATABASE_URL#sqlite:///}}"
  if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: 找不到数据库文件: $DB_PATH" >&2
    exit 1
  fi
  TARGET="$OUT_DIR/tile_remnant.db"
  # VACUUM INTO creates a consistent copy even while WAL is active
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$DB_PATH" ".backup '$TARGET'"
  else
    python - "$DB_PATH" "$TARGET" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
with sqlite3.connect(src) as conn, sqlite3.connect(dst) as out:
    conn.backup(out)
PY
  fi
  echo "==> SQLite 备份: $TARGET"
else
  if ! command -v pg_dump >/dev/null 2>&1; then
    echo "ERROR: 需要 pg_dump（或通过 docker compose exec db pg_dump 备份）" >&2
    exit 1
  fi
  TARGET="$OUT_DIR/tile_remnant.sql.gz"
  pg_dump "$DATABASE_URL" | gzip -9 > "$TARGET"
  echo "==> PostgreSQL 备份: $TARGET"
fi

# keep the 14 most recent backups
ls -1dt "$ROOT"/backups/*/ 2>/dev/null | tail -n +15 | xargs -r rm -rf
echo "==> 完成。恢复方式见 docs/backup-restore.md"
