#!/usr/bin/env bash
# Start the API locally (SQLite, auto-migrated) for development.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d .venv ]; then
  echo "==> 创建虚拟环境"
  python -m venv .venv
fi

if [ -f .venv/Scripts/python.exe ]; then
  PY=".venv/Scripts/python.exe"
else
  PY=".venv/bin/python"
fi

echo "==> 安装依赖"
"$PY" -m pip install --quiet --upgrade pip
"$PY" -m pip install --quiet -r backend/requirements-dev.txt

cd backend
export DATABASE_URL="${DATABASE_URL:-sqlite:///./data/tile_remnant.db}"
export AUTO_CREATE_TABLES="${AUTO_CREATE_TABLES:-true}"
export PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-http://127.0.0.1:8000}"

echo "==> 数据库: $DATABASE_URL"
"$PY" -m alembic upgrade head || echo "(alembic 失败时可忽略：AUTO_CREATE_TABLES=true 会建表)"

echo "==> API: http://127.0.0.1:8000/docs"
"$PY" -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
