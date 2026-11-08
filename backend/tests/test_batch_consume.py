"""整砖批量使用 + 手动调整片数。"""

from __future__ import annotations

from fastapi.testclient import TestClient

from tests.conftest import add_inventory


def test_consume_whole_deducts_and_logs_usage(client: TestClient, project: dict) -> None:
    """100 片 715，贴地板用掉 50 片完整的。"""
    batch = add_inventory(client, project, 715, 715, quantity=100)

    response = client.post(
        f"/api/projects/{project['id']}/inventory/{batch['id']}/consume",
        json={"quantity": 50, "note": "贴地板"},
        headers=project["headers"],
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["batch"]["quantity"] == 50
    assert body["used_quantity"] == 50

    movements = client.get(
        f"/api/projects/{project['id']}/movements", headers=project["headers"]
    ).json()
    usage = [m for m in movements["items"] if m["type"] == "usage"]
    assert usage
    assert usage[0]["quantity_delta"] == -50


def test_consume_whole_rejects_overdraw(client: TestClient, project: dict) -> None:
    batch = add_inventory(client, project, 715, 715, quantity=10)

    response = client.post(
        f"/api/projects/{project['id']}/inventory/{batch['id']}/consume",
        json={"quantity": 20},
        headers=project["headers"],
    )
    assert response.status_code == 409


def test_consume_whole_marks_depleted(client: TestClient, project: dict) -> None:
    batch = add_inventory(client, project, 715, 715, quantity=3)

    response = client.post(
        f"/api/projects/{project['id']}/inventory/{batch['id']}/consume",
        json={"quantity": 3},
        headers=project["headers"],
    )
    assert response.status_code == 200
    assert response.json()["batch"]["quantity"] == 0
    assert response.json()["batch"]["status"] == "depleted"


def test_patch_quantity_reduces_stock(client: TestClient, project: dict) -> None:
    """手动把 100 改成 80，写一条 adjust 流水。"""
    batch = add_inventory(client, project, 715, 715, quantity=100)

    response = client.patch(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        json={"quantity": 80, "adjust_reason": "盘点少 20"},
        headers=project["headers"],
    )
    assert response.status_code == 200, response.text
    assert response.json()["batch"]["quantity"] == 80

    movements = client.get(
        f"/api/projects/{project['id']}/movements", headers=project["headers"]
    ).json()
    adjust = [m for m in movements["items"] if m["type"] == "adjust"]
    assert adjust
    assert adjust[0]["quantity_delta"] == -20
