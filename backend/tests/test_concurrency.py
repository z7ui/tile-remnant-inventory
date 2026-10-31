"""Concurrency: no over-deduction, idempotent retries."""

from __future__ import annotations

import concurrent.futures
import uuid

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import add_inventory


def _post_confirm(project_id: str, headers: dict, payload: dict) -> tuple[int, dict]:
    # a fresh client per thread: each request gets its own portal + DB session
    client = TestClient(app)
    response = client.post(f"/api/projects/{project_id}/usage/confirm", json=payload, headers=headers)
    return response.status_code, response.json()


def _payload(batch_id: str, key: str, length=800, width=900) -> dict:
    return {
        "idempotency_key": key,
        "length": length,
        "width": width,
        "quantity": 1,
        "allocations": [
            {
                "batch_id": batch_id,
                "quantity": 1,
                "cut_option": "long_side_cut",
                "remnant_action": "store",
            }
        ],
    }


def test_concurrent_confirms_never_oversell(client, project):
    batch = add_inventory(client, project, 900, 800, 5)

    def worker(_i: int):
        return _post_confirm(project["id"], project["headers"], _payload(batch["id"], uuid.uuid4().hex))

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(worker, range(10)))

    successes = [body for status, body in results if status == 200]
    failures = [body for status, body in results if status != 200]
    assert len(successes) == 5, [s for s, _ in results]
    assert all(body["error"]["code"] in ("insufficient_quantity", "batch_unavailable", "concurrent_update") for body in failures)

    inventory = client.get(
        f"/api/projects/{project['id']}/inventory",
        params={"only_available": "false"},
        headers=project["headers"],
    ).json()
    quantities = {item["id"]: item["quantity"] for item in inventory["items"]}
    assert quantities[batch["id"]] == 0, "inventory must never go negative"

    movements = client.get(
        f"/api/projects/{project['id']}/movements", params={"type": "usage", "page_size": 100}, headers=project["headers"]
    ).json()
    assert movements["total"] == 5


def test_concurrent_duplicate_idempotency_key_deducts_once(client, project):
    batch = add_inventory(client, project, 900, 800, 5)
    key = "same-key-concurrent"

    def worker(_i: int):
        return _post_confirm(project["id"], project["headers"], _payload(batch["id"], key))

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(worker, range(6)))

    successes = [body for status, body in results if status == 200]
    assert successes, [s for s, _ in results]
    assert len({body["usage_id"] for body in successes}) == 1
    assert all(
        status == 200 or body["error"]["code"] == "concurrent_update" for status, body in results
    )

    inventory = client.get(
        f"/api/projects/{project['id']}/inventory",
        params={"only_available": "false"},
        headers=project["headers"],
    ).json()
    quantities = {item["id"]: item["quantity"] for item in inventory["items"]}
    assert quantities[batch["id"]] == 4

    movements = client.get(
        f"/api/projects/{project['id']}/movements", params={"type": "usage", "page_size": 100}, headers=project["headers"]
    ).json()
    assert movements["total"] == 1


def test_concurrent_multi_piece_confirms(client, project):
    batch = add_inventory(client, project, 900, 800, 20)

    def worker(i: int):
        payload = _payload(batch["id"], f"multi-piece-{uuid.uuid4().hex}", length=400, width=400)
        return _post_confirm(project["id"], project["headers"], payload)

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(worker, range(12)))

    assert sum(1 for status, _ in results if status == 200) == 12
    inventory = client.get(
        f"/api/projects/{project['id']}/inventory",
        params={"only_available": "false"},
        headers=project["headers"],
    ).json()
    quantities = {item["id"]: item["quantity"] for item in inventory["items"]}
    assert quantities[batch["id"]] == 8
