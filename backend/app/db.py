"""Database engine, session factory and declarative base."""

from __future__ import annotations

import os
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import settings


def _ensure_sqlite_dir(url: str) -> None:
    if not url.startswith("sqlite"):
        return
    path = url.split("sqlite:///")[-1]
    if path in ("", ":memory:") or path.startswith("file:"):
        return
    directory = os.path.dirname(os.path.abspath(path))
    if directory:
        os.makedirs(directory, exist_ok=True)


_ensure_sqlite_dir(settings.database_url)

_is_sqlite = settings.database_url.startswith("sqlite")

engine_kwargs: dict = {
    "echo": settings.sql_echo,
    "future": True,
    "pool_pre_ping": not _is_sqlite,
}
if _is_sqlite:
    engine_kwargs["connect_args"] = {
        "timeout": settings.sqlite_busy_timeout_ms / 1000,
        "check_same_thread": False,
    }
else:
    engine_kwargs["pool_size"] = settings.db_pool_size
    engine_kwargs["max_overflow"] = settings.db_max_overflow

engine: Engine = create_engine(settings.database_url, **engine_kwargs)


@event.listens_for(engine, "connect")
def _set_sqlite_pragma(dbapi_connection, _connection_record):  # noqa: ANN001
    if not _is_sqlite:
        return
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA synchronous=NORMAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.execute(f"PRAGMA busy_timeout={settings.sqlite_busy_timeout_ms}")
    cursor.close()


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def session_scope() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
