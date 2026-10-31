"""Device credentials, password hashing and project token helpers."""

from __future__ import annotations

import hashlib
import hmac
import secrets

import bcrypt

from .config import settings


def hash_device_secret(secret: str, rounds: int | None = None) -> str:
    """bcrypt hash of the device secret (never stored in clear)."""
    # bcrypt only considers the first 72 bytes; our secrets are 43 chars.
    payload = secret.encode("utf-8")[:72]
    return bcrypt.hashpw(payload, bcrypt.gensalt(rounds=rounds or settings.bcrypt_rounds)).decode("utf-8")


def verify_device_secret(secret: str, hashed: str) -> bool:
    if not secret or not hashed:
        return False
    try:
        return bcrypt.checkpw(secret.encode("utf-8")[:72], hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def new_device_secret() -> str:
    return secrets.token_urlsafe(settings.device_secret_bytes)


def new_project_token() -> str:
    return secrets.token_urlsafe(settings.project_token_bytes)


def token_fingerprint(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def safe_compare(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))
