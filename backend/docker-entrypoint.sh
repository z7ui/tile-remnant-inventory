#!/bin/sh
# Wait for the database, run migrations, then start the API.
set -eu

echo "[entrypoint] environment=${ENVIRONMENT:-production}"
echo "[entrypoint] database=${DATABASE_URL%%:*}://…"

if [ "${AUTO_CREATE_TABLES:-false}" = "true" ]; then
  echo "[entrypoint] AUTO_CREATE_TABLES=true (dev mode, skipping alembic)"
else
  echo "[entrypoint] running alembic upgrade head"
  alembic upgrade head
fi

exec "$@"
