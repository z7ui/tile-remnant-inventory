"""Very small in-process rate limiter.

Good enough for a single-container deployment; swap for Redis when scaling out
(see docs/security.md).  The limiter is deliberately dependency free so the
API can boot on a cheap shared host.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from .config import settings
from .errors import ApiError


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: float = 60.0) -> None:
        self.limit = limit
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()
        self._last_sweep = time.monotonic()

    def check(self, key: str, cost: int = 1) -> None:
        if not settings.rate_limit_enabled or self.limit <= 0:
            return
        now = time.monotonic()
        with self._lock:
            bucket = self._hits[key]
            while bucket and now - bucket[0] > self.window:
                bucket.popleft()
            if len(bucket) + cost > self.limit:
                retry_after = max(1, int(self.window - (now - bucket[0])) + 1) if bucket else 1
                raise ApiError(429, "rate_limited", "请求过于频繁，请稍后再试。", {"retry_after_seconds": retry_after})
            for _ in range(cost):
                bucket.append(now)
            self._sweep(now)

    def _sweep(self, now: float) -> None:
        if now - self._last_sweep < self.window:
            return
        self._last_sweep = now
        stale = [k for k, v in self._hits.items() if not v or now - v[-1] > self.window]
        for key in stale:
            self._hits.pop(key, None)


read_limiter = SlidingWindowLimiter(settings.rate_limit_per_minute)
write_limiter = SlidingWindowLimiter(settings.rate_limit_write_per_minute)
# 名字预检单独一档：每分钟 12 次。正常建项目一个人一分钟用不到 12 次，
# 但枚举项目名需要成千上万次，这个额度让对方基本无从下手。
name_limiter = SlidingWindowLimiter(settings.rate_limit_name_check_per_minute)


def enforce(client_ip: str, scope: str, write: bool = False, name_check: bool = False) -> None:
    if name_check:
        limiter = name_limiter
    else:
        limiter = write_limiter if write else read_limiter
    limiter.check(f"{scope}:{client_ip}")
