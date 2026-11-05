"""设备统计与「第 N 位用户」里程碑。"""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.services.devices import MILESTONES


def _register(client: TestClient, name: str) -> dict:
    response = client.post("/api/devices/register", json={"name": name, "platform": "android"})
    assert response.status_code == 200, response.text
    return response.json()


def test_stats_counts_devices_and_projects(client: TestClient) -> None:
    assert client.get("/api/devices/stats").json()["devices"] == 0

    _register(client, "a")
    _register(client, "b")

    body = client.get("/api/devices/stats").json()
    assert body["devices"] == 2
    assert body["projects"] == 0
    assert body["milestones"] == list(MILESTONES)


def test_register_reports_ordinal_but_no_milestone_for_early_devices(client: TestClient) -> None:
    first = _register(client, "a")
    second = _register(client, "b")
    assert first["device_ordinal"] == 1
    assert second["device_ordinal"] == 2
    assert "milestone" not in first
    assert "milestone" not in second


def test_tenth_device_gets_milestone(client: TestClient) -> None:
    for i in range(MILESTONES[0] - 1):
        body = _register(client, f"d{i}")
        assert "milestone" not in body, f"第 {i + 1} 台不该庆祝"

    tenth = _register(client, "d10")
    assert tenth["device_ordinal"] == MILESTONES[0]
    assert tenth["milestone"] == MILESTONES[0]
