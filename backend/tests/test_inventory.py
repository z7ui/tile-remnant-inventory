"""Inventory: rectangle-only manual entry, filters, adjustments."""

from __future__ import annotations

from tests.conftest import add_inventory, auth_headers, device_headers, register_device


def test_create_rectangle_batch_with_units(client, project):
    # cm input, long/short order not required
    batch = add_inventory(client, project, "90cm", "80cm", 3, location="阳台", note="客厅剩料")
    assert (batch["width_mm"], batch["height_mm"]) == (800, 900)
    assert batch["shape_type"] == "rectangle"
    assert batch["quantity"] == 3
    assert batch["initial_quantity"] == 3
    assert batch["area_mm2"] == 800 * 900
    assert batch["source_type"] == "manual"
    assert batch["location"] == "阳台"
    assert batch["root_batch_id"] == batch["id"]
    assert batch["trace_url"].endswith(batch["id"])


def test_create_batch_mm_strings_and_default_unit(client, project):
    batch = add_inventory(client, project, "800mm", "900", 1)
    assert (batch["width_mm"], batch["height_mm"]) == (800, 900)
    # project default unit is mm, so 80 means 80mm
    small = add_inventory(client, project, 80, 120, 1)
    assert (small["width_mm"], small["height_mm"]) == (80, 120)


def test_manual_entry_rejects_l_shape_fields(client, project):
    response = client.post(
        f"/api/projects/{project['id']}/inventory",
        json={"length": 800, "width": 600, "quantity": 1, "shape_type": "l_shape"},
        headers=project["headers"],
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_invalid_dimension_message(client, project):
    response = client.post(
        f"/api/projects/{project['id']}/inventory",
        json={"length": "abc", "width": 600, "quantity": 1},
        headers=project["headers"],
    )
    assert response.status_code == 422
    body = response.json()["error"]
    assert body["code"] == "invalid_dimension"
    assert "长度" in body["message"]


def test_stock_in_movement_written(client, project):
    batch = add_inventory(client, project, 800, 900, 2)
    movements = client.get(f"/api/projects/{project['id']}/movements", headers=project["headers"]).json()
    assert movements["total"] == 1
    item = movements["items"][0]
    assert item["type"] == "stock_in"
    assert item["quantity_before"] == 0 and item["quantity_after"] == 2
    assert item["batch_id"] == batch["id"]
    assert item["width_after_mm"] == 800


def test_inventory_filters(client, project):
    add_inventory(client, project, 900, 800, 2, location="阳台")
    add_inventory(client, project, 600, 600, 5, location="客厅")
    base = f"/api/projects/{project['id']}/inventory"

    by_location = client.get(base, params={"location": "阳台"}, headers=project["headers"]).json()
    assert by_location["total"] == 1
    assert by_location["filters"]["locations"] == ["客厅", "阳台"]

    by_qty = client.get(base, params={"min_quantity": 3}, headers=project["headers"]).json()
    assert by_qty["total"] == 1 and by_qty["items"][0]["quantity"] == 5

    by_size = client.get(base, params={"min_long_mm": 850}, headers=project["headers"]).json()
    assert by_size["total"] == 1
    assert by_size["items"][0]["height_mm"] == 900

    by_keyword = client.get(base, params={"q": "客厅"}, headers=project["headers"]).json()
    assert by_keyword["total"] == 1

    by_shape = client.get(base, params={"shape_type": "l_shape"}, headers=project["headers"]).json()
    assert by_shape["total"] == 0

    paged = client.get(base, params={"page": 1, "page_size": 1}, headers=project["headers"]).json()
    assert paged["total"] == 2 and len(paged["items"]) == 1 and paged["has_more"] is True

    sorted_by_area = client.get(base, params={"sort": "area_desc"}, headers=project["headers"]).json()
    totals = [item["area_mm2"] * item["quantity"] for item in sorted_by_area["items"]]
    assert totals == sorted(totals, reverse=True)


def test_patch_location_and_note(client, project):
    batch = add_inventory(client, project, 800, 600, 1)
    response = client.patch(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        json={"location": "储物间", "note": "靠墙第二排"},
        headers=project["headers"],
    )
    assert response.status_code == 200
    assert response.json()["batch"]["location"] == "储物间"


def test_patch_quantity_writes_adjust_movement(client, project):
    batch = add_inventory(client, project, 800, 600, 4)
    response = client.patch(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        json={"quantity": 2, "adjust_reason": "现场盘点"},
        headers=project["headers"],
    )
    assert response.status_code == 200
    assert response.json()["batch"]["quantity"] == 2
    movements = client.get(
        f"/api/projects/{project['id']}/movements", params={"type": "adjust"}, headers=project["headers"]
    ).json()
    assert movements["total"] == 1
    assert movements["items"][0]["quantity_delta"] == -2
    assert movements["items"][0]["type_label"] == "人工调整"


def test_void_batch_hides_from_available_and_match(client, project):
    batch = add_inventory(client, project, 800, 900, 1)
    voided = client.patch(
        f"/api/projects/{project['id']}/inventory/{batch['id']}",
        json={"status": "void"},
        headers=project["headers"],
    )
    assert voided.status_code == 200
    assert voided.json()["batch"]["is_available"] is False
    match = client.post(
        f"/api/projects/{project['id']}/match",
        json={"length": 800, "width": 900, "quantity": 1},
        headers=project["headers"],
    ).json()
    assert match["candidates"] == []


def test_cannot_read_other_projects_batch(client, device, project):
    batch = add_inventory(client, project, 800, 600, 1)
    other = client.post(
        "/api/projects",
        json={"name": "别人的项目", "default_unit": "mm"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    ).json()
    other_headers = auth_headers(device["device_id"], other["project_token"])
    response = client.get(f"/api/projects/{other['project']['id']}/inventory/{batch['id']}", headers=other_headers)
    assert response.status_code == 404


def test_unknown_batch_404(client, project):
    response = client.get(f"/api/projects/{project['id']}/inventory/nonexistent", headers=project["headers"])
    assert response.status_code == 404
