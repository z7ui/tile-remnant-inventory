"""Small shared helpers."""

from __future__ import annotations

import secrets
import string
from datetime import datetime, timezone

# Ambiguous characters (0/O, 1/I/L) are removed so codes can be read aloud on
# a building site and typed with gloves on.
INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def utcnow() -> datetime:
    """Naive UTC timestamp (stored uniformly across SQLite and PostgreSQL)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def new_id() -> str:
    return secrets.token_hex(16)


def new_secret(nbytes: int) -> str:
    return secrets.token_urlsafe(nbytes)


PROJECT_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def new_project_code(length: int = 4) -> str:
    """项目特征码。4 位是 31^4 ≈ 92 万种，项目数远小于这个量级。"""
    return "".join(secrets.choice(PROJECT_CODE_ALPHABET) for _ in range(length))


def new_invite_code(length: int) -> str:
    return "".join(secrets.choice(INVITE_ALPHABET) for _ in range(length))


def normalise_project_name(name: str) -> str:
    """Trim + collapse inner whitespace; used for display."""
    return " ".join((name or "").split())


def project_name_key(name: str) -> str:
    """Case/space insensitive uniqueness key (Unicode aware)."""
    import unicodedata

    collapsed = normalise_project_name(unicodedata.normalize("NFKC", name or ""))
    return collapsed.casefold()
