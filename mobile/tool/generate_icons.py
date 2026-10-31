"""Generate the Android launcher icons without any third party dependency.

Run from the repository root:
    python mobile/tool/generate_icons.py

The icon is a simple engineering-blue tile with three whole tiles and one
L-shaped remnant (the notch is what the app is about).
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

BG = (21, 101, 192, 255)
WHITE = (255, 255, 255, 255)
PURPLE = (106, 27, 154, 255)
TRANSPARENT = (0, 0, 0, 0)


def rounded_rect(x: int, y: int, w: int, h: int, r: int, size: int) -> bool:
    if x < 0 or y < 0 or x >= size or y >= size:
        return False
    # corner test
    for cx, cy in ((r, r), (w - r - 1, r), (r, h - r - 1), (w - r - 1, h - r - 1)):
        if (x < r and y < r and (x - cx) ** 2 + (y - cy) ** 2 > r * r) or (
            x >= w - r and y < r and (x - cx) ** 2 + (y - cy) ** 2 > r * r
        ) or (x < r and y >= h - r and (x - cx) ** 2 + (y - cy) ** 2 > r * r) or (
            x >= w - r and y >= h - r and (x - cx) ** 2 + (y - cy) ** 2 > r * r
        ):
            return False
    return True


def build(size: int) -> list[list[tuple[int, int, int, int]]]:
    pixels = [[TRANSPARENT for _ in range(size)] for _ in range(size)]
    radius = max(3, int(size * 0.22))
    for y in range(size):
        for x in range(size):
            if rounded_rect(x, y, size, size, radius, size):
                pixels[y][x] = BG

    def fill(x0: float, y0: float, x1: float, y1: float, colour: tuple[int, int, int, int]) -> None:
        for y in range(int(y0 * size), int(y1 * size)):
            for x in range(int(x0 * size), int(x1 * size)):
                if 0 <= x < size and 0 <= y < size and pixels[y][x] != TRANSPARENT:
                    pixels[y][x] = colour

    # three whole tiles (2x2 grid with a visible blue frame)
    fill(0.22, 0.22, 0.46, 0.46, WHITE)
    fill(0.54, 0.22, 0.78, 0.46, WHITE)
    fill(0.22, 0.54, 0.46, 0.78, WHITE)
    # the L-shaped remnant: full square minus a corner
    fill(0.54, 0.54, 0.78, 0.78, PURPLE)
    fill(0.66, 0.54, 0.78, 0.66, BG)
    return pixels


def write_png(path: Path, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    size = len(pixels)
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for pixel in row:
            raw.extend(pixel)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main() -> None:
    for folder, size in SIZES.items():
        pixels = build(size)
        target = ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png"
        write_png(target, pixels)
        print(f"wrote {target.relative_to(ROOT)} ({size}x{size})")


if __name__ == "__main__":
    main()
