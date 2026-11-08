"""多尺寸一次确认。"""

from __future__ import annotations

from fastapi.testclient import TestClient

from tests.conftest import add_inventory


def _confirm(client: TestClient, project: dict, payload: dict) -> dict:
    response = client.post(
        f"/api/projects/{project['id']}/usage/confirm-multi",
        json=payload,
        headers=project["headers"],
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_confirm_multi_deducts_one_block_per_block(
    client: TestClient, project: dict
) -> None:
    """一块砖切了 70×70 + 15 个 10×10，只扣 1 块库存。"""
    batch = add_inventory(client, project, 800, 800, quantity=2)

    body = _confirm(
        client,
        project,
        {
            "idempotency_key": "multi-confirm-0001",
            "blocks": [
                {
                    "batch_id": batch["id"],
                    "pieces": [
                        {"width_mm": 700, "height_mm": 700, "quantity": 1},
                        {"width_mm": 100, "height_mm": 100, "quantity": 15},
                    ],
                }
            ],
        },
    )

    assert body["total_pieces"] == 16
    detail = client.get(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        headers=project["headers"],
    ).json()
    assert detail["batch"]["quantity"] == 1


def test_confirm_multi_rejects_over_capacity(client: TestClient, project: dict) -> None:
    batch = add_inventory(client, project, 800, 800, quantity=1)

    response = client.post(
        f"/api/projects/{project['id']}/usage/confirm-multi",
        json={
            "idempotency_key": "multi-confirm-0002",
            "blocks": [
                {
                    "batch_id": batch["id"],
                    "pieces": [
                        {"width_mm": 700, "height_mm": 700, "quantity": 5},
                    ],
                }
            ],
        },
        headers=project["headers"],
    )
    assert response.status_code == 409


def test_confirm_multi_marks_depleted(client: TestClient, project: dict) -> None:
    batch = add_inventory(client, project, 800, 800, quantity=1)

    _confirm(
        client,
        project,
        {
            "idempotency_key": "multi-confirm-0003",
            "blocks": [
                {
                    "batch_id": batch["id"],
                    "pieces": [{"width_mm": 300, "height_mm": 300, "quantity": 4}],
                }
            ],
        },
    )

    detail = client.get(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        headers=project["headers"],
    ).json()
    assert detail["batch"]["quantity"] == 0
    assert detail["batch"]["status"] == "depleted"
