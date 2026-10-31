"""HTTP middleware: request id, security headers, rate limiting."""

from __future__ import annotations

import time
import uuid
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from .config import settings
from .errors import error_body
from .ratelimit import read_limiter, write_limiter

MAX_BODY_BYTES = 1_048_576


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        request.state.request_id = request_id
        started = time.perf_counter()

        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            length = request.headers.get("content-length")
            if length and length.isdigit() and int(length) > MAX_BODY_BYTES:
                return JSONResponse(
                    status_code=413,
                    content=error_body("payload_too_large", "请求体过大（上限 1MB）。", None, request_id),
                )

        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        if request.url.path.startswith(settings.api_prefix):
            response.headers["Cache-Control"] = "no-store"
        response.headers["Server-Timing"] = f"app;dur={(time.perf_counter() - started) * 1000:.1f}"
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Cheap per-IP limiting in front of the API (nginx also limits)."""

    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        path = request.url.path
        if not path.startswith(settings.api_prefix) or not settings.rate_limit_enabled:
            return await call_next(request)

        forwarded = request.headers.get("x-forwarded-for", "")
        ip = (forwarded.split(",")[0].strip() if forwarded else "") or (
            request.client.host if request.client else "unknown"
        )
        is_write = request.method in ("POST", "PUT", "PATCH", "DELETE")
        limiter = write_limiter if is_write else read_limiter
        try:
            limiter.check(f"{'w' if is_write else 'r'}:{ip}")
        except Exception as exc:  # ApiError(429)
            retry_after = "60"
            details = getattr(exc, "details", {}) or {}
            if details.get("retry_after_seconds"):
                retry_after = str(details["retry_after_seconds"])
            return JSONResponse(
                status_code=429,
                content=error_body("rate_limited", "请求过于频繁，请稍后再试。", details, getattr(request.state, "request_id", "")),
                headers={"Retry-After": retry_after},
            )
        return await call_next(request)
