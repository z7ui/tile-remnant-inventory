"""Unit tests: cm/mm parsing, normalisation and validation."""

from __future__ import annotations

import pytest

from app.units import DimensionError, mm_to_display, parse_length_mm, parse_quantity


@pytest.mark.parametrize(
    ("raw", "unit", "expected"),
    [
        (800, "mm", 800),
        ("800", "mm", 800),
        ("800mm", "cm", 800),
        ("80cm", "mm", 800),
        ("80cm", "cm", 800),
        (" 90 cm ", "mm", 900),
        ("80.5cm", "mm", 805),
        ("1.2m", "mm", 1200),
        (80, "cm", 800),
        ("1200", "cm", 12000),
        ("0.1cm", "mm", 1),
    ],
)
def test_parse_length(raw, unit, expected):
    assert parse_length_mm(raw, unit) == expected


@pytest.mark.parametrize("raw", ["", "abc", "80cmx", "-5", "0", "0cm", None, True, "8 0"])
def test_parse_length_rejects_garbage(raw):
    with pytest.raises(DimensionError):
        parse_length_mm(raw, "mm")


def test_parse_length_rejects_above_max():
    with pytest.raises(DimensionError):
        parse_length_mm("999999mm", "mm")


def test_parse_quantity():
    assert parse_quantity("3") == 3
    assert parse_quantity(1) == 1
    for bad in ["0", "-1", "abc", None, 1.5]:
        with pytest.raises(DimensionError):
            parse_quantity(bad)


def test_mm_to_display():
    assert mm_to_display(800, "cm") == "80cm"
    assert mm_to_display(805, "cm") == "80.5cm"
    assert mm_to_display(800, "mm") == "800mm"
