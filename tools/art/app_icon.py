#!/usr/bin/env python3
"""Derive the app icon and Android launcher layers from the master art.

The master is `assets/art/branding/app_icon.png`: a 1024 square of a carrack
under sail inside a gold medallion (see tools/art/app-icon.md for the art
brief). Everything else is cut from it so the face of the game never drifts:

  icon.png                                1024 project icon (config/icon)
  assets/art/branding/launcher_main_192.png      legacy launcher icon
  assets/art/branding/launcher_foreground_432.png adaptive foreground (66%)
  assets/art/branding/launcher_background_432.png adaptive background
  assets/art/branding/launcher_monochrome_432.png themed (monochrome) layer

The medallion is cropped a few pixels inside its outer rim before every export,
which drops the pale anti-aliased fringe the generator leaves against the
sheet and keeps the dark plate colour behind it.

Usage:
  python3 tools/art/app_icon.py [project-root]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

MASTER = Path("assets/art/branding/app_icon.png")
ICON_SIZE = 1024
LAUNCHER_MAIN = 192
LAUNCHER_LAYER = 432
## Adaptive icons guarantee only the central 66% of each layer is visible.
SAFE_FRACTION = 0.66
## Crop inside the master's outer rim (rim radius is ~511 of 1024).
CROP_RADIUS = 500.0
## Plate colour behind the medallion; matches the ring's outer shadow.
PLATE = (26, 16, 9, 255)

SUPERSAMPLE = 4


def _disc_mask(size: int, radius: float, centre: tuple[float, float]) -> Image.Image:
    """Anti-aliased circular alpha mask."""
    big = Image.new("L", (size * SUPERSAMPLE, size * SUPERSAMPLE), 0)
    draw = ImageDraw.Draw(big)
    cx, cy, r = (
        centre[0] * SUPERSAMPLE,
        centre[1] * SUPERSAMPLE,
        radius * SUPERSAMPLE,
    )
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def _medallion(master: Image.Image, diameter: int) -> Image.Image:
    """The master's medallion, cropped at CROP_RADIUS, as a transparent square."""
    centre = (master.width / 2.0, master.height / 2.0)
    box = (
        int(centre[0] - CROP_RADIUS),
        int(centre[1] - CROP_RADIUS),
        int(centre[0] + CROP_RADIUS),
        int(centre[1] + CROP_RADIUS),
    )
    disc = master.crop(box).convert("RGBA").resize((diameter, diameter), Image.LANCZOS)
    disc.putalpha(_disc_mask(diameter, diameter / 2.0 - 0.5, (diameter / 2.0, diameter / 2.0)))
    return disc


def _plate(size: int) -> Image.Image:
    """Opaque dark plate with a soft radial lift behind the medallion."""
    img = Image.new("RGBA", (size, size), PLATE)
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx = cy = size / 2.0
    for step in range(24, 0, -1):
        t = step / 24.0
        r = size * 0.52 * t
        alpha = int(38 * (1.0 - t) ** 1.6)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(96, 60, 28, alpha))
    return Image.alpha_composite(img, glow)


def _write_icon(master: Image.Image, root: Path) -> None:
    plate = _plate(ICON_SIZE)
    diameter = ICON_SIZE - 2 * 12
    plate.alpha_composite(_shadow(diameter), (12, 18))
    plate.alpha_composite(_medallion(master, diameter), (12, 12))
    plate.convert("RGB").save(root / "icon.png", optimize=True)


def _shadow(diameter: int) -> Image.Image:
    """Soft drop shadow so the medallion sits on the plate instead of floating."""
    layer = Image.new("L", (diameter, diameter), 0)
    draw = ImageDraw.Draw(layer)
    inset = int(diameter * 0.03)
    draw.ellipse((inset, inset, diameter - inset, diameter - inset), fill=150)
    layer = layer.filter(ImageFilter.GaussianBlur(diameter * 0.018))
    shadow = Image.new("RGBA", (diameter, diameter), (0, 0, 0, 0))
    shadow.putalpha(layer)
    return shadow


def _write_launcher(master: Image.Image, root: Path) -> None:
    out = root / "assets/art/branding"

    main = _medallion(master, LAUNCHER_MAIN)
    plate = _plate(LAUNCHER_MAIN)
    plate.alpha_composite(_shadow(LAUNCHER_MAIN), (0, 2))
    plate.alpha_composite(main, (0, 0))
    plate.convert("RGB").save(out / "launcher_main_192.png", optimize=True)

    _plate(LAUNCHER_LAYER).convert("RGB").save(out / "launcher_background_432.png", optimize=True)

    safe = int(LAUNCHER_LAYER * SAFE_FRACTION)
    foreground = Image.new("RGBA", (LAUNCHER_LAYER, LAUNCHER_LAYER), (0, 0, 0, 0))
    offset = (LAUNCHER_LAYER - safe) // 2
    foreground.alpha_composite(_medallion(master, safe), (offset, offset))
    foreground.save(out / "launcher_foreground_432.png", optimize=True)

    _monochrome(LAUNCHER_LAYER).save(out / "launcher_monochrome_432.png", optimize=True)


def _monochrome(size: int) -> Image.Image:
    """One-colour glyph: a ring with the carrack inside, drawn from polygons."""
    scale = SUPERSAMPLE
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    cx = cy = big / 2.0
    outer = big * 0.275
    inner = big * 0.243
    draw.ellipse((cx - outer, cy - outer, cx + outer, cy + outer), fill=white)
    draw.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=(0, 0, 0, 0))

    # Ship in a 100-unit box, bow to the right, mapped into the ring.
    unit = big * 0.00235
    ox, oy = cx - 50.0 * unit, cy - 50.0 * unit

    def poly(points: list[tuple[float, float]]) -> None:
        draw.polygon([(ox + x * unit, oy + y * unit) for x, y in points], fill=white)

    def bar(x: float, y0: float, y1: float, width: float) -> None:
        poly([(x - width / 2, y0), (x + width / 2, y0), (x + width / 2, y1), (x - width / 2, y1)])

    # hull with stern castle and forecastle
    poly([
        (8, 62), (26, 62), (26, 54), (36, 54), (36, 66), (86, 66), (94, 72),
        (86, 84), (70, 90), (26, 90), (12, 84), (6, 74),
    ])
    # masts and bowsprit
    bar(28, 22, 74, 2.6)
    bar(50, 14, 76, 3.0)
    bar(72, 24, 74, 2.6)
    poly([(90, 70), (100, 60), (100, 64), (92, 74)])
    # sails, kept apart by clear gaps
    poly([(22, 26), (40, 26), (41, 44), (25, 48)])
    poly([(20, 50), (42, 50), (43, 64), (22, 68)])
    poly([(44, 18), (62, 18), (63, 36), (46, 40)])
    poly([(43, 42), (64, 42), (65, 58), (45, 62)])
    poly([(42, 64), (66, 64), (67, 76), (43, 78)])
    poly([(74, 34), (86, 64), (74, 60)])
    poly([(91, 66), (100, 57), (97, 70)])
    # pennants
    poly([(28, 22), (35, 24), (28, 26)])
    poly([(50, 14), (58, 16), (50, 18)])
    poly([(72, 24), (79, 26), (72, 28)])

    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    master_path = root / MASTER
    if not master_path.is_file():
        print(f"error: master art missing: {master_path}", file=sys.stderr)
        return 1
    master = Image.open(master_path).convert("RGBA")
    if master.width != master.height:
        print("error: master art must be square", file=sys.stderr)
        return 1
    _write_icon(master, root)
    _write_launcher(master, root)
    print("wrote icon.png and the launcher layers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())