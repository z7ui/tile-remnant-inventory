"""Device credentials, password hashing and project token helpers."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import time

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


# bcrypt costs ~250 ms at the default cost factor. Device-level endpoints
# (project list / create / join) are called on every app start, so reusing a
# recent *success* keeps that off the hot path.
#
# Why this is safe:
#   * only successes are cached (a wrong secret always pays the full cost);
#   * the key is a sha256 of (device_id, secret) — the secret is never stored;
#   * revocation is still immediate, because callers check ``device.revoked_at``
#     in the database *before* reaching this function.
_VERIFY_CACHE: dict[str, float] = {}
_VERIFY_TTL_SECONDS = 300.0
_VERIFY_MAX_ENTRIES = 2048


def verify_device_secret_cached(device_id: str, secret: str, hashed: str) -> bool:
    """verify_device_secret with a short-lived cache for successful checks."""
    if not secret or not hashed:
        return False
    key = hashlib.sha256(f"{device_id}\x00{secret}".encode("utf-8")).hexdigest()
    now = time.monotonic()
    seen_at = _VERIFY_CACHE.get(key)
    if seen_at is not None and now - seen_at < _VERIFY_TTL_SECONDS:
        return True
    if not verify_device_secret(secret, hashed):
        _VERIFY_CACHE.pop(key, None)
        return False
    if len(_VERIFY_CACHE) >= _VERIFY_MAX_ENTRIES:
        _VERIFY_CACHE.clear()
    _VERIFY_CACHE[key] = now
    return True


def new_device_secret() -> str:
    return secrets.token_urlsafe(settings.device_secret_bytes)


def new_project_token() -> str:
    return secrets.token_urlsafe(settings.project_token_bytes)


def token_fingerprint(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def safe_compare(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))
