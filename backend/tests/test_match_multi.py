"""多尺寸混排匹配。"""

from __future__ import annotations

from fastapi.testclient import TestClient

from tests.conftest import add_inventory


def _multi(client: TestClient, project: dict, demands: list[dict]) -> dict:
    response = client.post(
        f"/api/projects/{project['id']}/match-multi",
        json={"demands": demands},
        headers=project["headers"],
    )
    assert response.status_code == 200, response.text
    return response.json()


def _placed(block: dict) -> dict[tuple[int, int], int]:
    return {(p["width_mm"], p["height_mm"]): p["quantity"] for p in block["plan"]["placed"]}


def test_one_block_holds_big_and_small(client: TestClient, project: dict) -> None:
    """80×80 一块砖要同时切 70×70 和 10×10。"""
    add_inventory(client, project, 800, 800, quantity=1)

    body = _multi(
        client,
        project,
        [
            {"length": 700, "width": 700, "quantity": 1},
            {"length": 100, "width": 100, "quantity": 10},
        ],
    )

    assert body["summary"]["blocks_used"] == 1
    assert body["summary"]["missing_pieces"] == 0

    placed = _placed(body["blocks"][0])
    assert placed.get((700, 700)) == 1
    assert placed.get((100, 100), 0) >= 10


def test_big_first_fulfills_everything(client: TestClient, project: dict) -> None:
    """600×1200 两块，300×300 和 100×100 一起排完。"""
    add_inventory(client, project, 600, 1200, quantity=2)

    body = _multi(
        client,
        project,
        [
            {"length": 300, "width": 300, "quantity": 8},
            {"length": 100, "width": 100, "quantity": 20},
        ],
    )

    assert body["summary"]["missing_pieces"] == 0
    assert body["summary"]["blocks_used"] <= 2
    assert body["summary"]["fulfilled_pieces"] == 28


def test_small_pieces_go_into_leftover(client: TestClient, project: dict) -> None:
    """一块 800×800 切 1 片 700×700，剩下的边条能切出 10×10。"""
    add_inventory(client, project, 800, 800, quantity=1)

    body = _multi(
        client,
        project,
        [
            {"length": 700, "width": 700, "quantity": 1},
            {"length": 100, "width": 100, "quantity": 15},
        ],
    )

    assert body["summary"]["missing_pieces"] == 0
    assert body["summary"]["blocks_used"] == 1


def test_missing_pieces_reported(client: TestClient, project: dict) -> None:
    """库存不够时，明确报出缺多少片，而不是假装满足。"""
    add_inventory(client, project, 800, 800, quantity=1)

    body = _multi(
        client,
        project,
        [
            {"length": 700, "width": 700, "quantity": 3},
            {"length": 100, "width": 100, "quantity": 10},
        ],
    )

    assert body["summary"]["missing_pieces"] > 0
    big = next(d for d in body["demands"] if d["short_mm"] == 700)
    assert big["missing"] == 2


def test_skipped_field_is_empty_for_rectangles(client: TestClient, project: dict) -> None:
    """矩形批次正常排，skipped 留空（该字段专门给 L 形用）。"""
    add_inventory(client, project, 800, 800, quantity=1)

    body = _multi(client, project, [{"length": 300, "width": 300, "quantity": 1}])

    assert body["skipped"] == []
    assert len(body["blocks"]) == 1
