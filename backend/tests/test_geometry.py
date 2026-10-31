"""Geometry engine tests: rotation, coverage, L shapes, remnant preservation."""

from __future__ import annotations

import pytest

from app import geometry


def test_rectangle_region_normalises_short_long():
    w, h, region = geometry.build_rectangle_region(900, 800)
    assert (w, h) == (800, 900)
    assert region == [(0, 0, 800, 900)]


def test_rotation_matching():
    """900x800 stock must accept an 800x900 demand (rotated)."""
    w, h, region = geometry.build_rectangle_region(900, 800)
    assert geometry.fits(region, 800, 900)
    assert geometry.fits(region, 900, 800)
    # 801 x 901 does not fit
    assert not geometry.fits(region, 801, 901)


def test_demand_must_be_fully_covered():
    w, h, region = geometry.build_rectangle_region(600, 600)
    assert geometry.fits(region, 600, 300)
    assert not geometry.fits(region, 601, 300)
    assert not geometry.fits(region, 300, 601)


def test_full_tile_demand_has_no_remnant():
    w, h, region = geometry.build_rectangle_region(800, 900)
    preview = geometry.usage_preview(region, w, h, 800, 900, "long_side_cut")
    assert preview["feasible"] is True
    assert preview["remnant"] is None
    assert preview["waste_mm2"] == 0
    assert preview["utilization"] == 1.0


def test_corner_cut_produces_l_shape_and_preserves_area():
    w, h, region = geometry.build_rectangle_region(900, 800)
    preview = geometry.usage_preview(region, w, h, 500, 600, "long_side_cut")
    assert preview["feasible"] is True
    remnant = preview["remnant"]
    assert remnant["shape_type"] == "l_shape"
    assert remnant["area_mm2"] == 800 * 900 - 500 * 600
    assert remnant["notch"] is not None
    # geometry rects must add up to the reported area
    assert sum(r["w"] * r["h"] for r in remnant["rects"]) == remnant["area_mm2"]


def test_cut_through_full_width_leaves_rectangle_remnant():
    w, h, region = geometry.build_rectangle_region(900, 800)
    preview = geometry.usage_preview(region, w, h, 800, 600, "long_side_cut")
    remnant = preview["remnant"]
    assert remnant["shape_type"] == "rectangle"
    assert (remnant["width_mm"], remnant["height_mm"]) == (300, 800)
    assert remnant["area_mm2"] == 800 * 300


def test_short_side_cut_rotates_the_demand():
    w, h, region = geometry.build_rectangle_region(900, 800)
    long_side = geometry.usage_preview(region, w, h, 300, 700, "long_side_cut")
    short_side = geometry.usage_preview(region, w, h, 300, 700, "short_side_cut")
    assert long_side["feasible"] and short_side["feasible"]
    assert long_side["placement"]["w"] == 300 and long_side["placement"]["h"] == 700
    assert short_side["placement"]["w"] == 700 and short_side["placement"]["h"] == 300
    # different cut orientation -> different remnant geometry
    assert long_side["remnant"]["notch_corner"] == "bottom_left"
    assert short_side["remnant"]["notch_corner"] == "bottom_left"
    # 300x700 notch vs 700x300 notch -> visually different L
    assert long_side["remnant"]["notch"] != short_side["remnant"]["notch"]
    assert long_side["remnant"]["rects"] != short_side["remnant"]["rects"]


def test_l_shape_region_matching_and_cut():
    w, h, region = geometry.build_l_region(900, 800, 200, 300, "top_right")
    assert (w, h) == (800, 900)
    assert geometry.region_area(region) == 800 * 900 - 200 * 300
    # the L can host 550x600 inside its big sub-rectangle
    assert geometry.fits(region, 550, 600)
    assert not geometry.fits(region, 700, 700)
    preview = geometry.usage_preview(region, w, h, 550, 600, "long_side_cut")
    assert preview["feasible"] is True
    assert preview["remnant"]["area_mm2"] == geometry.region_area(region) - 550 * 600


def test_l_shape_area_never_grows_after_cut():
    w, h, region = geometry.build_l_region(900, 800, 200, 300, "bottom_left")
    before = geometry.region_area(region)
    for option in ("long_side_cut", "short_side_cut"):
        preview = geometry.usage_preview(region, w, h, 200, 300, option)
        if not preview["feasible"]:
            continue
        remnant_area = preview["remnant"]["area_mm2"] if preview["remnant"] else 0
        assert remnant_area + 200 * 300 == before


def test_subtract_rect_keeps_region_disjoint():
    region = [(0, 0, 100, 100)]
    left = geometry.subtract_rect(region, (20, 20, 30, 30))
    assert geometry.region_area(left) == 10000 - 900
    assert all(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1] for a in left for b in left if a is not b)


def test_describe_l_shape_reports_notch_corner():
    w, h, region = geometry.build_l_region(900, 800, 200, 300, "top_right")
    desc = geometry.describe(region, w, h)
    assert desc["type"] == "l_shape"
    assert desc["composite"] is False
    assert desc["notch"] == {"x": 600, "y": 600, "w": 200, "h": 300}
    assert desc["notch_corner"] == "top_right"


def test_pieces_available_simulation():
    region = geometry.build_rectangle_region(900, 800)[2]
    assert geometry.pieces_available(region, 800, 900, 400, 400, 10) == 4
    assert geometry.pieces_available(region, 800, 900, 800, 900, 10) == 1


@pytest.mark.parametrize("corner", ["bottom_left", "bottom_right", "top_left", "top_right"])
def test_all_l_corners_build_correct_area(corner):
    w, h, region = geometry.build_l_region(1000, 900, 150, 400, corner)
    assert geometry.region_area(region) == 1000 * 900 - 150 * 400
    assert w <= h


def test_invalid_l_shape_rejected():
    with pytest.raises(ValueError):
        geometry.build_l_region(800, 800, 800, 300, "top_right")
