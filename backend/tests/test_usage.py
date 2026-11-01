"""Confirming usage: deduction, remnant store/discard, idempotency, ledger."""

from __future__ import annotations

import uuid

from tests.conftest import add_inventory, auth_headers, device_headers


def _confirm(client, project, payload):
    body = {"idempotency_key": uuid.uuid4().hex, **payload}
    return client.post(f"/api/projects/{project['id']}/usage/confirm", json=body, headers=project["headers"])


def _alloc(batch, quantity=1, cut="long_side_cut", action="store"):
    return {"batch_id": batch["id"], "quantity": quantity, "cut_option": cut, "remnant_action": action}


def test_full_tile_has_no_remnant(client, project):
    batch = add_inventory(client, project, 800, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 800,
            "width": 800,
            "quantity": 1,
            "allocations": [_alloc(batch, action="store")],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["results"][0]["remnant"] is None
    assert body["results"][0]["remnant_batch"] is None
    assert body["results"][0]["remnant_action"] is None
    assert body["total_waste_mm2"] == 0
    assert [m["type"] for m in body["movements"]] == ["usage"]

    inventory = client.get(
        f"/api/projects/{project['id']}/inventory",
        params={"only_available": "false"},
        headers=project["headers"],
    ).json()
    assert inventory["summary"]["pieces"] == 0
    assert inventory["items"][0]["status"] == "depleted"


def test_long_side_cut_stores_l_shaped_remnant(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 600,
            "quantity": 1,
            "allocations": [_alloc(batch, cut="long_side_cut", action="store")],
        },
    )
    assert response.status_code == 200, response.text
    result = response.json()["results"][0]
    reminder = result["remnant"]
    assert reminder["shape_type"] == "l_shape"
    assert reminder["area_mm2"] == 800 * 900 - 500 * 600
    assert reminder["notch"] is not None

    produced = result["remnant_batch"]
    assert produced["parent_batch_id"] == batch["id"]
    assert produced["root_batch_id"] == batch["id"]
    assert produced["source_type"] == "cut"
    assert produced["shape_type"] == "l_shape"
    assert produced["quantity"] == 1
    assert produced["cut_option"] == "long_side_cut"
    assert produced["used_length_mm"] == 600
    assert produced["used_width_mm"] == 500

    types = [m["type"] for m in response.json()["movements"]]
    assert types.count("usage") == 1
    assert types.count("cut_remnant") == 1

    inventory = client.get(f"/api/projects/{project['id']}/inventory", headers=project["headers"]).json()
    assert inventory["summary"]["pieces"] == 1
    shapes = {item["shape_type"] for item in inventory["items"] if item["quantity"] > 0}
    assert shapes == {"l_shape"}


def test_short_side_cut_produces_different_geometry(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 300,
            "width": 700,
            "quantity": 1,
            "allocations": [_alloc(batch, cut="short_side_cut", action="store")],
        },
    )
    assert response.status_code == 200, response.text
    result = response.json()["results"][0]
    assert result["cut_option"] == "short_side_cut"
    assert result["rotation"] == 90
    assert result["remnant"]["rects"] != []


def test_discard_writes_trace_without_new_batch(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 500,
            "width": 600,
            "quantity": 1,
            "allocations": [_alloc(batch, action="discard")],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["results"][0]["remnant_batch"] is None
    assert body["results"][0]["remnant"] is not None  # still shown in the preview
    discard = [m for m in body["movements"] if m["type"] == "remnant_discard"]
    assert len(discard) == 1
    assert discard[0]["remnant_action"] == "discard"
    assert discard[0]["remnant_shape"] == "l_shape"
    assert discard[0]["remnant_area_mm2"] == 800 * 900 - 500 * 600
    assert discard[0]["cut_option"] == "long_side_cut"

    inventory = client.get(f"/api/projects/{project['id']}/inventory", headers=project["headers"]).json()
    assert inventory["summary"]["pieces"] == 0


def test_remnant_action_required_when_remnant_exists(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {"length": 500, "width": 600, "quantity": 1, "allocations": [_alloc(batch, action=None)]},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "remnant_action_required"


def test_infeasible_cut_option_rejected(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 800,
            "width": 900,
            "quantity": 1,
            "allocations": [_alloc(batch, cut="short_side_cut", action=None)],
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "cut_option_infeasible"


def test_insufficient_quantity_in_batch(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {"length": 400, "width": 400, "quantity": 2, "allocations": [_alloc(batch, quantity=2, action="store")]},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "insufficient_quantity"


def test_auto_allocation_without_explicit_batches(client, project):
    add_inventory(client, project, 900, 800, 1)
    response = _confirm(client, project, {"length": 600, "width": 600, "quantity": 1})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["results"][0]["remnant_batch"] is not None
    assert body["results"][0]["remnant_action"] == "store"


def test_auto_allocation_reports_insufficient_inventory(client, project):
    response = _confirm(client, project, {"length": 600, "width": 600, "quantity": 1})
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "insufficient_inventory"


def test_multi_piece_deduction_and_remnant_quantity(client, project):
    batch = add_inventory(client, project, 900, 800, 5)
    response = _confirm(
        client,
        project,
        {
            "length": 400,
            "width": 400,
            "quantity": 3,
            "allocations": [_alloc(batch, quantity=3, action="store")],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    usage_moves = [m for m in body["movements"] if m["type"] == "usage"]
    assert len(usage_moves) == 3
    assert [m["quantity_before"] for m in usage_moves] == [5, 4, 3]
    assert [m["quantity_after"] for m in usage_moves] == [4, 3, 2]
    produced = body["results"][0]["remnant_batch"]
    # 3 片切完只剩 1 条连通的余料，不是 3 条。
    # 旧实现拿「切 1 片的余料」乘片数，形状和数量都是错的。
    assert produced["quantity"] == 1
    assert produced["width_mm"] == 500 and produced["height_mm"] == 800

    inventory = client.get(f"/api/projects/{project['id']}/inventory", headers=project["headers"]).json()
    quantities = {item["id"]: item["quantity"] for item in inventory["items"]}
    assert quantities[batch["id"]] == 2
    assert quantities[produced["id"]] == 1


def test_multi_batch_confirmation(client, project):
    first = add_inventory(client, project, 400, 400, 1)
    second = add_inventory(client, project, 400, 400, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 400,
            "width": 400,
            "quantity": 2,
            "allocations": [
                _alloc(first, quantity=1, action=None),
                _alloc(second, quantity=1, action=None),
            ],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["results"]) == 2
    assert {r["batch_id"] for r in body["results"]} == {first["id"], second["id"]}
    assert len([m for m in body["movements"] if m["type"] == "usage"]) == 2


def test_allocation_quantity_must_match_demand(client, project):
    batch = add_inventory(client, project, 900, 800, 2)
    response = _confirm(
        client,
        project,
        {"length": 400, "width": 400, "quantity": 2, "allocations": [_alloc(batch, quantity=1, action="store")]},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_idempotent_confirmation(client, project):
    batch = add_inventory(client, project, 900, 800, 3)
    key = "repeat-me-please"
    payload = {
        "idempotency_key": key,
        "length": 400,
        "width": 400,
        "quantity": 1,
        "allocations": [_alloc(batch, action="store")],
    }
    first = client.post(f"/api/projects/{project['id']}/usage/confirm", json=payload, headers=project["headers"])
    second = client.post(f"/api/projects/{project['id']}/usage/confirm", json=payload, headers=project["headers"])
    assert first.status_code == 200 and second.status_code == 200
    assert first.json()["usage_id"] == second.json()["usage_id"]
    assert second.json()["replayed"] is True

    inventory = client.get(f"/api/projects/{project['id']}/inventory", headers=project["headers"]).json()
    quantities = {item["id"]: item["quantity"] for item in inventory["items"]}
    assert quantities[batch["id"]] == 2
    movements = client.get(f"/api/projects/{project['id']}/movements", headers=project["headers"]).json()
    assert len([m for m in movements["items"] if m["type"] == "usage"]) == 1


def test_consuming_a_remnant_batch(client, project):
    """Cut an L remnant, then use that L batch for a smaller demand."""
    batch = add_inventory(client, project, 900, 800, 1)
    first = _confirm(
        client,
        project,
        {"length": 500, "width": 600, "quantity": 1, "allocations": [_alloc(batch, action="store")]},
    ).json()
    reminder = first["results"][0]["remnant_batch"]
    before_area = reminder["area_mm2"]

    second = _confirm(
        client,
        project,
        {"length": 500, "width": 200, "quantity": 1, "allocations": [_alloc(reminder, action="store")]},
    )
    assert second.status_code == 200, second.text
    body = second.json()
    assert body["results"][0]["remnant"] is not None
    assert body["results"][0]["remnant"]["area_mm2"] == before_area - 200 * 500

    produced = body["results"][0]["remnant_batch"]
    assert produced["parent_batch_id"] == reminder["id"]
    assert produced["root_batch_id"] == batch["id"]


def test_cannot_use_batch_of_another_project(client, device, project):
    batch = add_inventory(client, project, 900, 800, 1)
    other = client.post(
        "/api/projects",
        json={"name": "另一个工地", "default_unit": "mm"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    ).json()
    headers = auth_headers(device["device_id"], other["project_token"])
    response = client.post(
        f"/api/projects/{other['project']['id']}/usage/confirm",
        json={
            "idempotency_key": uuid.uuid4().hex,
            "length": 400,
            "width": 400,
            "quantity": 1,
            "allocations": [{"batch_id": batch["id"], "quantity": 1, "remnant_action": "store"}],
        },
        headers=headers,
    )
    assert response.status_code == 404


def test_movements_export_csv(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    _confirm(
        client,
        project,
        {"length": 500, "width": 600, "quantity": 1, "allocations": [_alloc(batch, action="store")]},
    )
    response = client.get(f"/api/projects/{project['id']}/movements/export", headers=project["headers"])
    assert response.status_code == 200
    assert "text/csv" in response.headers["content-type"]
    text = response.content.decode("utf-8-sig")
    assert "变动前尺寸" in text
    assert "切割方式" in text
    assert "长边切到底" in text


def test_movement_filters(client, project):
    batch = add_inventory(client, project, 900, 800, 1)
    _confirm(
        client,
        project,
        {"length": 500, "width": 600, "quantity": 1, "allocations": [_alloc(batch, action="discard")]},
    )
    base = f"/api/projects/{project['id']}/movements"
    usage_only = client.get(base, params={"type": "usage"}, headers=project["headers"]).json()
    assert usage_only["total"] == 1
    assert usage_only["items"][0]["type"] == "usage"
    by_batch = client.get(base, params={"batch_id": batch["id"]}, headers=project["headers"]).json()
    assert by_batch["total"] >= 2
    discard = client.get(base, params={"type": "remnant_discard"}, headers=project["headers"]).json()
    assert discard["total"] == 1
    assert discard["items"][0]["remnant_action_label"] == "丢弃"


def test_remnant_below_threshold_is_flagged_but_still_storable(client, project):
    """D4：最窄边小于项目阈值时标 below_threshold，但不拦截入库。

    900×800 切走 880×780，余料是两条 20mm 的窄边，外框仍然是 900×800。
    所以判据必须看最窄段，不能看外框短边——否则提示永远不会出现。
    """
    batch = add_inventory(client, project, 900, 800, 1)
    response = _confirm(
        client,
        project,
        {
            "length": 880,
            "width": 780,
            "quantity": 1,
            "allocations": [_alloc(batch, action="store")],
        },
    )
    assert response.status_code == 200, response.text
    result = response.json()["results"][0]
    remnant = result["remnant"]
    assert remnant is not None
    assert remnant["min_side_mm"] == 20
    assert remnant["below_threshold"] is True
    # 提示归提示，仍然允许强制入库
    assert result["remnant_action"] == "store"
    assert result["remnant_batch"] is not None
