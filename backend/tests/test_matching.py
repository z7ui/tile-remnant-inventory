"""Matching: units, rotation, coverage, sorting and multi-batch allocation."""

from __future__ import annotations

import pytest

from tests.conftest import add_inventory


def _match(client, project, length, width, quantity=1, **extra):
    response = client.post(
        f"/api/projects/{project['id']}/match",
        json={"length": length, "width": width, "quantity": quantity, **extra},
        headers=project["headers"],
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize(
    ("length", "width"),
    [(800, 900), ("90cm", "80cm"), ("800mm", "900mm")],
)
def test_900x800_matches_all_input_forms(client, project, length, width):
    add_inventory(client, project, 900, 800, 1)
    result = _match(client, project, length, width)
    assert result["total_candidates"] == 1
    candidate = result["candidates"][0]
    assert candidate["batch"]["width_mm"] == 800
    assert candidate["batch"]["height_mm"] == 900
    assert candidate["match"]["waste_mm2"] == 0
    assert candidate["match"]["remnant"] is None
    assert result["unfulfilled_quantity"] == 0


def test_unit_param_is_used_when_no_suffix(client, project):
    add_inventory(client, project, 900, 800, 1)
    result = _match(client, project, 80, 90, unit="cm")
    candidate = result["candidates"][0]
    assert candidate["match"]["waste_mm2"] == 0
    assert result["demand"]["short_mm"] == 800
    assert result["demand"]["long_mm"] == 900


def test_demand_larger_than_stock_is_rejected(client, project):
    add_inventory(client, project, 900, 800, 1)
    result = _match(client, project, 901, 801)
    assert result["candidates"] == []
    assert result["total_candidates"] == 0
    assert result["unfulfilled_quantity"] == 1
    assert result["allocation"] == []


def test_rotation_is_allowed_and_reported(client, project):
    add_inventory(client, project, 600, 900, 1)
    result = _match(client, project, "50cm", 580)
    candidate = result["candidates"][0]
    options = {opt["cut_option"]: opt for opt in candidate["cut_options"]}
    assert options["long_side_cut"]["placement"]["w"] == 500
    assert options["long_side_cut"]["placement"]["h"] == 580
    assert options["long_side_cut"]["rotation"] == 0
    assert options["short_side_cut"]["placement"]["w"] == 580
    assert options["short_side_cut"]["rotation"] == 90
    assert candidate["match"]["cut_option"] in ("long_side_cut", "short_side_cut")


def test_sorted_by_waste_then_remnant_value(client, project):
    add_inventory(client, project, 900, 800, 1)  # 720000 - 360000 = 360000 waste
    add_inventory(client, project, 900, 900, 1)  # 810000 - 360000 = 450000 waste
    result = _match(client, project, 600, 600)
    wastes = [c["match"]["waste_mm2"] for c in result["candidates"]]
    assert wastes == sorted(wastes)
    assert result["candidates"][0]["match"]["waste_mm2"] == 360000


def test_l_shape_preferred_when_it_saves_waste(client, project):
    add_inventory(client, project, 900, 800, 1)
    # full-tile use of the small batch would waste more than the L cut of the big one
    add_inventory(client, project, 600, 600, 1)
    result = _match(client, project, 600, 600)
    assert result["candidates"][0]["batch"]["area_mm2"] == 360000
    assert result["candidates"][0]["match"]["waste_mm2"] == 0


def test_multi_batch_allocation(client, project):
    add_inventory(client, project, 400, 400, 1)
    add_inventory(client, project, 400, 400, 1)
    result = _match(client, project, 400, 400, quantity=2)
    assert result["total_candidates"] == 2
    assert result["unfulfilled_quantity"] == 0
    assert len(result["allocation"]) == 2
    assert sum(a["quantity"] for a in result["allocation"]) == 2


def test_unfulfilled_quantity_reported(client, project):
    add_inventory(client, project, 400, 400, 1)
    result = _match(client, project, 400, 400, quantity=3)
    assert result["unfulfilled_quantity"] == 2


def test_max_pieces_per_batch(client, project):
    add_inventory(client, project, 900, 800, 5)
    result = _match(client, project, 400, 400, quantity=5)
    candidate = result["candidates"][0]
    assert candidate["match"]["max_pieces"] == 4
    assert candidate["batch"]["quantity"] == 5
    # 一块 900×800 能切 4 片，5 块共 20 片，5 片需求完全满足
    assert result["unfulfilled_quantity"] == 0


def test_match_invalid_dimension(client, project):
    response = client.post(
        f"/api/projects/{project['id']}/match",
        json={"length": "0", "width": 600, "quantity": 1},
        headers=project["headers"],
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_dimension"


def test_match_returns_remnant_preview_and_trace_link(client, project):
    add_inventory(client, project, 900, 800, 1)
    result = _match(client, project, 500, 600)
    candidate = result["candidates"][0]
    for option in candidate["cut_options"]:
        assert option["feasible"] is True
        assert option["remnant"]["area_mm2"] == 800 * 900 - 500 * 600
        assert option["remnant"]["rects"]
        assert option["utilization"] > 0
    assert candidate["batch"]["trace_url"].endswith(candidate["batch"]["id"])
    assert result["demand"]["short_mm"] == 500
    assert result["demand"]["long_mm"] == 600
