"""add project short_code and make name_key unique per code

项目名从「全局唯一」改为「允许重名，靠 4 位特征码区分」。
name_key 从「归一化名」改成「归一化名#码」，这样既保住原有的唯一约束，
又不需要重建表（SQLite 改约束要整表重建）。

Revision ID: 7c1f4a9b2d30
Revises: 9eb0dc91e867
"""

from __future__ import annotations

import secrets

import sqlalchemy as sa
from alembic import op

revision = "7c1f4a9b2d30"
down_revision = "9eb0dc91e867"
branch_labels = None
depends_on = None

ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def _new_code(used: set[str]) -> str:
    while True:
        code = "".join(secrets.choice(ALPHABET) for _ in range(4))
        if code not in used:
            used.add(code)
            return code


def upgrade() -> None:
    op.add_column("projects", sa.Column("short_code", sa.String(length=8), nullable=True))
    op.create_index("ix_projects_short_code", "projects", ["short_code"])

    conn = op.get_bind()
    rows = conn.execute(sa.text("SELECT id, name_key FROM projects")).fetchall()
    used: set[str] = set()
    for project_id, key in rows:
        if key and "#" in key:
            used.add(key.rsplit("#", 1)[-1])
            continue
        code = _new_code(used)
        conn.execute(
            sa.text("UPDATE projects SET short_code = :code, name_key = :key WHERE id = :id"),
            {"code": code, "key": f"{key}#{code}", "id": project_id},
        )


def downgrade() -> None:
    conn = op.get_bind()
    rows = conn.execute(sa.text("SELECT id, name_key FROM projects")).fetchall()
    for project_id, key in rows:
        if key and "#" in key:
            conn.execute(
                sa.text("UPDATE projects SET name_key = :key WHERE id = :id"),
                {"key": key.rsplit("#", 1)[0], "id": project_id},
            )
    op.drop_index("ix_projects_short_code", table_name="projects")
    op.drop_column("projects", "short_code")
