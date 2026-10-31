"""Traceability endpoint."""

from __future__ import annotations

import uuid

from tests.conftest import add_inventory, device_headers


def _confirm(client, project, payload):
    body = {"idempotency_key": uuid.uuid4().hex, **payload}
    return client.post(f"/api/projects/{project['id']}/usage/confirm", json=body, headers=project["headers"])


def _cut_and_store(client, project):
    batch = add_inventory(client, project, 900, 800, 1, location="阳台")
    body = _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 600,
            "quantity": 1,
            "allocations": [
                {"batch_id": batch["id"], "quantity": 1, "cut_option": "long_side_cut", "remnant_action": "store"}
            ],
        },
    ).json()
    return batch, body["results"][0]["remnant_batch"], body


def test_trace_compares_original_demand_and_remnant(client, project):
    batch, remnant, usage = _cut_and_store(client, project)
    response = client.get(f"/api/projects/{project['id']}/trace/{remnant['id']}", headers=project["headers"])
    assert response.status_code == 200, response.text
    body = response.json()

    comparison = body["comparison"]
    assert comparison["original"]["area_mm2"] == 800 * 900
    assert comparison["original"]["label"] == "原砖"
    assert comparison["demand"]["length_mm"] == 600
    assert comparison["demand"]["width_mm"] == 500
    assert comparison["demand"]["area_mm2"] == 300000
    assert comparison["remnant"]["area_mm2"] == 420000
    assert comparison["remnant"]["shape_type"] == "l_shape"
    assert comparison["remnant"]["rects"]
    assert comparison["demand"]["cut_option_label"] == "长边切到底"

    assert [a["id"] for a in body["ancestors"]] == [batch["id"]]
    assert body["chain"]["current_index"] == 1
    assert body["batch"]["id"] == remnant["id"]
    assert body["root"]["id"] == batch["id"]
    assert body["usage"]["quantity"] == 1

    types = [m["type"] for m in body["movements"]]
    assert "usage" in types and "cut_remnant" in types
    assert body["links"]["self"].endswith(remnant["id"])


def test_trace_of_parent_lists_children(client, project):
    batch, remnant, _ = _cut_and_store(client, project)
    body = client.get(f"/api/projects/{project['id']}/trace/{batch['id']}", headers=project["headers"]).json()
    assert [c["id"] for c in body["children"]] == [remnant["id"]]
    assert body["comparison"]["remnant"] is None  # the parent itself is not a remnant
    assert body["comparison"]["demand"] is None


def test_trace_discard_is_visible_in_ledger(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 600,
            "quantity": 1,
            "allocations": [
                {"batch_id": batch["id"], "quantity": 1, "cut_option": "long_side_cut", "remnant_action": "discard"}
            ],
        },
    )
    body = client.get(f"/api/projects/{project['id']}/trace/{batch['id']}", headers=project["headers"]).json()
    discard = [m for m in body["movements"] if m["type"] == "remnant_discard"]
    assert len(discard) == 1
    assert discard[0]["remnant_shape"] == "l_shape"
    assert body["children"] == []


def test_trace_deep_chain(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    first = _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 600,
            "quantity": 1,
            "allocations": [
                {"batch_id": batch["id"], "quantity": 1, "cut_option": "long_side_cut", "remnant_action": "store"}
            ],
        },
    ).json()["results"][0]["remnant_batch"]
    second = _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 200,
            "quantity": 1,
            "allocations": [
                {"batch_id": first["id"], "quantity": 1, "cut_option": "long_side_cut", "remnant_action": "store"}
            ],
        },
    ).json()["results"][0]["remnant_batch"]

    body = client.get(f"/api/projects/{project['id']}/trace/{second['id']}", headers=project["headers"]).json()
    assert [a["id"] for a in body["ancestors"]] == [batch["id"], first["id"]]
    assert body["chain"]["current_index"] == 2
    assert len(body["chain"]["nodes"]) >= 3
    assert body["root"]["id"] == batch["id"]
    assert body["comparison"]["original"]["area_mm2"] == 720000


def test_trace_unknown_batch(client, project):
    assert client.get(f"/api/projects/{project['id']}/trace/deadbeefdeadbeef", headers=project["headers"]).status_code == 404
