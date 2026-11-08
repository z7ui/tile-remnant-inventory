"""服务端公告：读 JSON 文件，按版本/时间筛选后下发给客户端。

文件格式（`ANNOUNCEMENT_PATH`，默认 /opt/tile/announcements.json）：

{
  "announcements": [
    {
      "id": "2026-11-08-upgrade",
      "enabled": true,
      "title": "需要更新",
      "body": "0.1.30 以下版本即将停止服务。",
      "dismissible": true,
      "min_version": "0.0.0",
      "max_version": "0.1.29",
      "starts_at": null,
      "ends_at": null,
      "buttons": [
        {"label": "去下载", "action": "open_url", "target": "https://www.z7ui.cn/apps/"},
        {"label": "稍后", "action": "dismiss"},
        {"label": "", "action": "none"},
        {"label": "", "action": "none"}
      ]
    }
  ]
}

按钮 action 白名单：
  open_url  打开链接（target 是 URL）
  dismiss   关闭公告
  reload    重载本地配置/刷新
  open_about 打开「关于」页
  copy      复制 target 文本
  none      不显示（空槽位）
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..config import settings

logger = logging.getLogger("tile.announcement")

ALLOWED_ACTIONS = {"open_url", "dismiss", "reload", "open_about", "copy", "none"}


def _ver_tuple(value: str) -> tuple[int, ...]:
    """把 "0.1.23" 变成 (0, 1, 23)，避免字符串比较把 0.1.9 当成比 0.1.10 大。"""
    parts: list[int] = []
    for chunk in (value or "").strip().split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(0)
    return tuple(parts)


def _in_range(app_version: str, min_v: str | None, max_v: str | None) -> bool:
    version = _ver_tuple(app_version)
    if min_v and version < _ver_tuple(min_v):
        return False
    if max_v and version > _ver_tuple(max_v):
        return False
    return True


def _parse_time(value: Any) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _in_time(start: Any, end: Any) -> bool:
    now = datetime.now(timezone.utc)
    begin = _parse_time(start)
    finish = _parse_time(end)
    if begin and now < begin:
        return False
    if finish and now > finish:
        return False
    return True


def load_raw() -> list[dict[str, Any]]:
    path = Path(settings.announcement_path)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - 文件写坏了不能拖垮接口
        logger.warning("公告文件解析失败: %s", exc)
        return []
    items = data.get("announcements") if isinstance(data, dict) else data
    return items if isinstance(items, list) else []


def pick(app_version: str) -> dict | None:
    """返回第一条对当前版本生效的公告；没有就返回 None。"""
    for item in load_raw():
        if not isinstance(item, dict) or not item.get("enabled", True):
            continue
        if not _in_range(app_version, item.get("min_version"), item.get("max_version")):
            continue
        if not _in_time(item.get("starts_at"), item.get("ends_at")):
            continue

        buttons: list[dict[str, str]] = []
        for raw in (item.get("buttons") or [])[:4]:
            if not isinstance(raw, dict):
                continue
            action = str(raw.get("action") or "none")
            if action not in ALLOWED_ACTIONS:
                action = "none"
            buttons.append(
                {
                    "label": str(raw.get("label") or ""),
                    "action": action,
                    "target": str(raw.get("target") or ""),
                }
            )

        return {
            "id": str(item.get("id") or ""),
            "title": str(item.get("title") or ""),
            "body": str(item.get("body") or ""),
            "dismissible": bool(item.get("dismissible", True)),
            "buttons": buttons,
        }
    return None
