#!/usr/bin/env python3
"""Prepare the Battle Simulator's generated art for the project.

Sources are FLUX renders (see tools/art/battle-plate.md for the prompts). This
script produces the shipped assets:

  assets/art/battle/ground_<terrain>.png   painted panorama, 2048x1152
  assets/art/battle/soldier.png            cut-out musketeer
  assets/art/battle/cannon.png             cut-out field gun
  assets/art/battle/horse.png              cut-out cavalryman
  assets/art/battle/wall_<kind>.png        cut-out wall segment, gate centred
  assets/art/battle/rubble.png             cut-out breach heap

Usage:
  python3 tools/art/battle_plate.py <source-dir> <project-root>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

PLATE_W, PLATE_H = 1600, 900
# Source crop from the top, as a fraction: the renders carry faint straight
# streaks in an otherwise empty sky.
PLATES = {
    "open": ("open.png", 0.08),
    "hill": ("hill.png", 0.0),
    "woods": ("woods.png", 0.0),
    "town": ("town.png", 0.08),
    "marsh": ("swamp.png", 0.0),
}
CUTOUTS = {
    "soldier": ("soldier.png", 320),
    "cannon": ("cannon.png", 320),
    "horse": ("horse.png", 320),
    "rubble": ("rubble.png", 256),
    "wall_wood": ("seg_wood.png", 320),
    "wall_stone": ("seg_stone.png", 320),
    "wall_modern": ("seg_modern.png", 320),
}
# Wall art is drawn one segment per gate, so a render that came back much wider
# than a segment is cropped to the gatehouse it centres on.
CUTOUT_CROPS = {
    "wall_modern": 0.40,
}
# Faint straight streaks the renderer left in an otherwise empty sky; soft them
# out along the streak so the sky keeps its brushwork. Segments are (x0, y0,
# x1, y1, half-width) in source pixels.
SKY_PATCHES = {
    "open": [(104.0, 55.0, 580.0, 140.0, 10.0), (260.0, 90.0, 520.0, 130.0, 7.0)],
}


def key(src: Path, height: int, keep_width: float = 1.0) -> Image.Image:
    """Key a painted object off its flat chroma backdrop into an RGBA cut-out."""
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    if keep_width < 1.0:
        width = a.shape[1]
        left = int(round(width * (1.0 - keep_width) * 0.5))
        a = a[:, left:left + int(round(width * keep_width)), :]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # The backdrop is magenta: red and blue high, green low. Real paint is not.
    magenta = np.minimum(r, b) - g
    alpha = np.clip(1.0 - (magenta - 0.04) / 0.16, 0.0, 1.0)
    grey = (r + g + b) / 3.0
    edge = alpha < 0.98
    r = np.where(edge, np.minimum(r, grey + 0.06), r)
    b = np.where(edge, np.minimum(b, grey + 0.06), b)
    out = np.dstack([r, g, b, alpha])
    img = Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")
    img = img.crop(img.split()[3].point(lambda v: 255 if v > 60 else 0).getbbox())
    scale = float(height) / float(img.height)
    return img.resize((max(1, round(img.width * scale)), height), Image.LANCZOS)


def soften(im: Image.Image, segments: list) -> Image.Image:
    """Cover each streak with sky sampled a little to the side, feathered in.

    Blurring the band instead would leave a smoother-than-paint stripe, which
    reads as a new artefact; lifting neighbouring sky keeps the brushwork.
    """
    base = np.asarray(im.convert("RGB")).astype(np.float32)
    height, width = base.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    out = base.copy()
    for x0, y0, x1, y1, half in segments:
        vx, vy = x1 - x0, y1 - y0
        length = max(float(np.hypot(vx, vy)), 1.0)
        nx, ny = -vy / length, vx / length
        weight = np.zeros((height, width), dtype=np.float32)
        length2 = max(vx * vx + vy * vy, 1.0)
        t = np.clip(((xx - x0) * vx + (yy - y0) * vy) / length2, 0.0, 1.0)
        dist = np.hypot(xx - (x0 + t * vx), yy - (y0 + t * vy))
        weight = np.clip(1.0 - dist / (half * 2.8), 0.0, 1.0) ** 2
        # Sample 3x the band width to the side: same gradient, clean paint.
        shift_x = int(round(nx * half * 3.0))
        shift_y = int(round(ny * half * 3.0))
        donor = np.roll(np.roll(base, shift_y, axis=0), shift_x, axis=1)
        # np.roll wraps; keep the wrapped strip out of the blend.
        if shift_x > 0:
            donor[:, :shift_x] = base[:, :shift_x]
        elif shift_x < 0:
            donor[:, shift_x:] = base[:, shift_x:]
        if shift_y > 0:
            donor[:shift_y, :] = base[:shift_y, :]
        elif shift_y < 0:
            donor[shift_y:, :] = base[shift_y:, :]
        weight = weight[..., None]
        out = out * (1.0 - weight) + donor * weight
    return Image.fromarray(np.clip(out, 0.0, 255.0).astype(np.uint8), "RGB")


def main(source: Path, root: Path) -> None:
    out = root / "assets" / "art" / "battle"
    out.mkdir(parents=True, exist_ok=True)
    for terrain, (name, crop) in PLATES.items():
        im = Image.open(source / name).convert("RGB")
        if terrain in SKY_PATCHES:
            im = soften(im, SKY_PATCHES[terrain])
        if crop > 0.0:
            im = im.crop((0, round(im.height * crop), im.width, im.height))
        # Painted gradation compresses cleanly; a PNG plate costs 2 MB each.
        im.resize((PLATE_W, PLATE_H), Image.LANCZOS).save(
            out / f"ground_{terrain}.jpg", quality=90, subsampling=0, optimize=True
        )
        print(f"ground_{terrain}.jpg {im.size} -> {PLATE_W}x{PLATE_H}")
    for name, (file, height) in CUTOUTS.items():
        img = key(source / file, height, CUTOUT_CROPS.get(name, 1.0))
        img.save(out / f"{name}.png", optimize=True)
        print(f"{name}.png {img.size}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
