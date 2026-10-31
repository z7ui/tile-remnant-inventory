"""Pytest fixtures: isolated SQLite database + authenticated devices/projects."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

_TEST_DIR = Path(tempfile.mkdtemp(prefix="tile-remnant-tests-"))
os.environ["DATABASE_URL"] = f"sqlite:///{(_TEST_DIR / 'test.db').as_posix()}"
os.environ["DATA_DIR"] = str(_TEST_DIR)
os.environ["BCRYPT_ROUNDS"] = "4"
os.environ["RATE_LIMIT_ENABLED"] = "false"
os.environ["ENVIRONMENT"] = "test"
os.environ["PUBLIC_BASE_URL"] = "https://tiles.test"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["LOG_LEVEL"] = "WARNING"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def _fresh_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture()
def client() -> TestClient:
    return TestClient(app)


def auth_headers(device_id: str, token: str) -> dict[str, str]:
    return {"X-Device-Id": device_id, "X-Project-Token": token}


def device_headers(device_id: str, secret: str) -> dict[str, str]:
    return {"X-Device-Id": device_id, "X-Device-Secret": secret}


def register_device(client: TestClient, name: str = "工头手机") -> dict:
    response = client.post("/api/devices/register", json={"name": name, "platform": "android"})
    assert response.status_code == 200, response.text
    return response.json()


@pytest.fixture()
def device(client: TestClient) -> dict:
    return register_device(client)


@pytest.fixture()
def project(client: TestClient, device: dict) -> dict:
    response = client.post(
        "/api/projects",
        json={"name": "金域蓝湾 3 栋 1802", "default_unit": "mm"},
        headers=device_headers(device["device_id"], device["device_secret"]),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return {
        "id": body["project"]["id"],
        "token": body["project_token"],
        "invite_code": body["invite"]["code"],
        "device": device,
        "headers": auth_headers(device["device_id"], body["project_token"]),
    }


def add_inventory(client: TestClient, project: dict, length, width, quantity=1, **extra) -> dict:
    payload = {"length": length, "width": width, "quantity": quantity, **extra}
    response = client.post(f"/api/projects/{project['id']}/inventory", json=payload, headers=project["headers"])
    assert response.status_code == 201, response.text
    return response.json()["batch"]
