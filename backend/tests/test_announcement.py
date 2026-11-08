"""服务端公告：版本/时间筛选、按钮动作白名单。"""

from __future__ import annotations

import json
import os
import tempfile
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from app.services import announcement as announcement_service


@pytest.fixture()
def announcement_file(monkeypatch: pytest.MonkeyPatch) -> Iterator[str]:
    path = os.path.join(tempfile.mkdtemp(prefix="tile-announce-"), "announcements.json")
    monkeypatch.setattr(announcement_service.settings, "announcement_path", path)
    yield path


def _write(path: str, payload: dict) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False)


def test_none_when_file_missing(client: TestClient, announcement_file: str) -> None:
    response = client.get("/api/announcement")
    assert response.status_code == 200
    assert response.json()["announcement"] is None


def test_version_filter(client: TestClient, announcement_file: str) -> None:
    _write(
        announcement_file,
        {
            "announcements": [
                {
                    "id": "upgrade",
                    "enabled": True,
                    "title": "需要更新",
                    "body": "0.1.30 以下版本即将停止服务。",
                    "max_version": "0.1.29",
                    "buttons": [
                        {"label": "去下载", "action": "open_url", "target": "https://example.com"}
                    ],
                }
            ]
        },
    )

    hit = client.get("/api/announcement?app_version=0.1.28").json()["announcement"]
    assert hit is not None and hit["id"] == "upgrade"

    miss = client.get("/api/announcement?app_version=0.1.30").json()["announcement"]
    assert miss is None


def test_version_compare_is_numeric(client: TestClient, announcement_file: str) -> None:
    """0.1.9 要小于 0.1.10（字符串比较会出错）。"""
    _write(
        announcement_file,
        {"announcements": [{"id": "x", "enabled": True, "title": "t", "min_version": "0.1.10"}]},
    )
    assert client.get("/api/announcement?app_version=0.1.9").json()["announcement"] is None
    assert (
        client.get("/api/announcement?app_version=0.1.10").json()["announcement"] is not None
    )


def test_button_action_whitelist(client: TestClient, announcement_file: str) -> None:
    _write(
        announcement_file,
        {
            "announcements": [
                {
                    "id": "x",
                    "enabled": True,
                    "title": "t",
                    "buttons": [
                        {"label": "去下载", "action": "open_url", "target": "https://example.com"},
                        {"label": "删库", "action": "rm_rf", "target": "/"},
                        {"label": "", "action": "none"},
                    ],
                }
            ]
        },
    )
    item = client.get("/api/announcement?app_version=0.1.35").json()["announcement"]
    assert [b["action"] for b in item["buttons"]] == ["open_url", "none", "none"]


def test_disabled_is_skipped(client: TestClient, announcement_file: str) -> None:
    _write(announcement_file, {"announcements": [{"id": "off", "enabled": False, "title": "t"}]})
    assert client.get("/api/announcement").json()["announcement"] is None


def test_expired_window_is_skipped(client: TestClient, announcement_file: str) -> None:
    _write(
        announcement_file,
        {
            "announcements": [
                {
                    "id": "past",
                    "enabled": True,
                    "title": "t",
                    "starts_at": "2020-01-01T00:00:00",
                    "ends_at": "2020-01-02T00:00:00",
                }
            ]
        },
    )
    assert client.get("/api/announcement").json()["announcement"] is None


def test_broken_file_does_not_break_api(client: TestClient, announcement_file: str) -> None:
    with open(announcement_file, "w", encoding="utf-8") as fh:
        fh.write("{ not json")
    response = client.get("/api/announcement")
    assert response.status_code == 200
    assert response.json()["announcement"] is None
