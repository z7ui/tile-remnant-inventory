"""Projects, invites, membership and access control."""

from __future__ import annotations

from tests.conftest import add_inventory, auth_headers, device_headers, register_device


def _create(client, device, name="金域蓝湾 3 栋 1802", unit="mm"):
    return client.post(
        "/api/projects",
        json={"name": name, "default_unit": unit},
        headers=device_headers(device["device_id"], device["device_secret"]),
    )


def test_create_project_returns_token_and_invite(client, device):
    response = _create(client, device)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["project"]["name"] == "金域蓝湾 3 栋 1802"
    assert body["project"]["role"] == "owner"
    assert len(body["project_token"]) > 20
    invite = body["invite"]
    assert len(invite["code"]) == 10
    assert invite["never_expires"] is True
    assert invite["qr_payload"].startswith("tileremnant://join")
    assert invite["code"] in invite["qr_payload"]
    assert invite["status"] == "active"


def test_duplicate_project_name_is_allowed_and_code_differs(client, device):
    """项目名允许重复，靠特征码区分（大小写、空格归一后同名也算重复）。"""
    first = _create(client, device, "Demo Project")
    assert first.status_code == 201
    first_code = first.json()["project"]["code"]
    assert first_code and len(first_code) == 4

    codes = {first_code}
    for duplicate in ["demo project", "  Demo Project  ", "DEMO   PROJECT"]:
        response = _create(client, device, duplicate)
        assert response.status_code == 201, duplicate
        code = response.json()["project"]["code"]
        assert len(code) == 4
        assert code not in codes, "特征码必须唯一"
        codes.add(code)


def test_duplicate_name_across_devices_is_allowed(client, device):
    assert _create(client, device, "滨江一号").status_code == 201
    other = register_device(client, "另一台手机")
    response = _create(client, other, "滨江一号")
    # 别人也能用同一个名字，但拿到的是不同项目、不同特征码
    assert response.status_code == 201
    assert response.json()["project"]["code"] != ""


def test_name_available_always_true(client, device):
    """名字预检永远返回可创建——枚举项目名因此失去意义。"""
    assert _create(client, device, "保利天悦").status_code == 201
    headers = device_headers(device["device_id"], device["device_secret"])

    taken = client.get("/api/projects/name-available", params={"name": " 保利天悦 "}, headers=headers)
    assert taken.status_code == 200
    assert taken.json()["available"] is True
    assert taken.json()["same_name_count"] == 1

    free = client.get("/api/projects/name-available", params={"name": "全新项目"}, headers=headers)
    assert free.json()["available"] is True
    assert free.json()["same_name_count"] == 0


def test_join_with_invite_and_persist_across_restarts(client, device, project):
    worker = register_device(client, "师傅手机")
    response = client.post(
        "/api/projects/join",
        json={"invite_code": project["invite_code"].lower()},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["project"]["role"] == "member"
    token = body["project_token"]

    # "restart": a brand new client, only the stored device id + project token
    from fastapi.testclient import TestClient

    from app.main import app

    fresh = TestClient(app)
    headers = auth_headers(worker["device_id"], token)
    detail = fresh.get(f"/api/projects/{project['id']}", headers=headers)
    assert detail.status_code == 200
    listed = fresh.get("/api/projects", headers=device_headers(worker["device_id"], worker["device_secret"]))
    assert [p["id"] for p in listed.json()["items"]] == [project["id"]]
    # no second scan needed: the token keeps working
    inventory = fresh.get(f"/api/projects/{project['id']}/inventory", headers=headers)
    assert inventory.status_code == 200


def test_one_device_can_join_multiple_projects(client, device, project):
    second = _create(client, device, "第二个工地")
    assert second.status_code == 201
    headers = device_headers(device["device_id"], device["device_secret"])
    listed = client.get("/api/projects", headers=headers)
    assert listed.status_code == 200
    assert len(listed.json()["items"]) == 2


def test_invalid_invite_code(client, device):
    response = client.post(
        "/api/projects/join",
        json={"invite_code": "ZZZZZZZZZZ"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "invite_invalid"


def test_invite_is_long_lived_but_revocable(client, device, project):
    headers = project["headers"]
    # long lived: no expiry field, still valid after many joins
    current = client.get(f"/api/projects/{project['id']}/invite", headers=headers).json()["invite"]
    assert current["never_expires"] is True and current["code"] == project["invite_code"]

    revoked = client.post(f"/api/projects/{project['id']}/invite/revoke", headers=headers)
    assert revoked.status_code == 200
    assert revoked.json()["invite"]["status"] == "revoked"
    assert revoked.json()["invite"]["code"] is None

    worker = register_device(client, "工人甲")
    join = client.post(
        "/api/projects/join",
        json={"invite_code": project["invite_code"]},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    )
    assert join.status_code == 404

    reset = client.post(f"/api/projects/{project['id']}/invite/reset", headers=headers)
    assert reset.status_code == 200
    new_code = reset.json()["invite"]["code"]
    assert new_code != project["invite_code"]
    join_again = client.post(
        "/api/projects/join",
        json={"invite_code": new_code},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    )
    assert join_again.status_code == 200


def test_only_owner_can_see_invite_and_members(client, device, project):
    worker = register_device(client, "工人乙")
    joined = client.post(
        "/api/projects/join",
        json={"invite_code": project["invite_code"]},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    ).json()
    member_headers = auth_headers(worker["device_id"], joined["project_token"])

    assert client.get(f"/api/projects/{project['id']}/invite", headers=member_headers).status_code == 403
    assert client.get(f"/api/projects/{project['id']}/members", headers=member_headers).status_code == 403
    members = client.get(f"/api/projects/{project['id']}/members", headers=project["headers"])
    assert members.status_code == 200
    assert members.json()["total"] == 2


def test_non_member_gets_403(client, device, project):
    stranger = register_device(client, "陌生人")
    # fabricated token
    fake = auth_headers(stranger["device_id"], "not-a-real-token-value")
    assert client.get(f"/api/projects/{project['id']}/inventory", headers=fake).status_code == 403
    # valid token of another device must not work either
    forged = auth_headers(stranger["device_id"], project["token"])
    assert client.get(f"/api/projects/{project['id']}/inventory", headers=forged).status_code == 403
    # project id alone is never enough
    assert client.get(f"/api/projects/{project['id']}/inventory").status_code == 401


def test_remove_membership_keeps_inventory_and_allows_rejoin(client, device, project):
    add_inventory(client, project, 900, 800, 2)
    worker = register_device(client, "工人丙")
    joined = client.post(
        "/api/projects/join",
        json={"invite_code": project["invite_code"]},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    ).json()
    headers = auth_headers(worker["device_id"], joined["project_token"])

    removed = client.delete(f"/api/projects/{project['id']}/membership", headers=headers)
    assert removed.status_code == 200
    assert client.get(f"/api/projects/{project['id']}/inventory", headers=headers).status_code == 403

    # owner still sees the stock
    inventory = client.get(f"/api/projects/{project['id']}/inventory", headers=project["headers"])
    assert inventory.status_code == 200
    assert inventory.json()["summary"]["pieces"] == 2

    # re-join with the still valid invite
    again = client.post(
        "/api/projects/join",
        json={"invite_code": project["invite_code"]},
        headers=device_headers(worker["device_id"], worker["device_secret"]),
    )
    assert again.status_code == 200
    new_headers = auth_headers(worker["device_id"], again.json()["project_token"])
    assert client.get(f"/api/projects/{project['id']}/inventory", headers=new_headers).status_code == 200


def test_owner_cannot_leave(client, device, project):
    response = client.delete(f"/api/projects/{project['id']}/membership", headers=project["headers"])
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "owner_cannot_leave"


def test_soft_delete_project(client, device, project):
    response = client.delete(f"/api/projects/{project['id']}", headers=project["headers"])
    assert response.status_code == 200
    assert client.get(f"/api/projects/{project['id']}", headers=project["headers"]).status_code == 403
    listed = client.get("/api/projects", headers=device_headers(device["device_id"], device["device_secret"]))
    assert listed.json()["items"] == []


def test_device_registration_requires_secret(client):
    assert client.get("/api/projects").status_code == 401
    assert client.get("/api/projects", headers={"X-Device-Id": "deadbeef", "X-Device-Secret": "nope"}).status_code == 401


def test_heartbeat(client, device):
    response = client.post(
        "/api/devices/heartbeat",
        json={"app_version": "0.1.0"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True
