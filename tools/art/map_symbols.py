#!/usr/bin/env python3
"""Prepare the chart's painted map symbols for the project.

Sources are FLUX renders of one object each on a flat magenta backdrop (prompts
in tools/art/map-symbols.md). This script applies the map-symbol recipe so every
stamp shares one origin, one paper grade and one downsampled size:

  1. global chroma key (not a corner flood fill) — `min(r, b) - g` drives alpha,
     so magenta gaps enclosed by foliage go clear too;
  2. despill the surviving edge texels toward green;
  3. trim to the alpha bounds and pad square with a 6 % margin;
  4. grade into the chart: lower the saturation, multiply by warm paper;
  5. resize to 128 px (ship 256) with Lanczos.

Mipmaps come from Godot's importer (`mipmaps/generate=true`), never from here.

Usage:
  python3 tools/art/map_symbols.py <source-dir> <project-root> [--only kind]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 128
SHIP_SIZE = 256
PAD = 0.06
# Multiplied over every stamp so a cut-out sits on the parchment, not on top of
# it. Places take a deeper paper: their pale walls otherwise read as stickers.
PAPER = (0.965, 0.933, 0.871)
PLACE_PAPER = (0.910, 0.871, 0.800)
SATURATION = 0.82
# A map stamp must hold its silhouette against both pale paper and the olive
# land wash, so the grade lifts value contrast after the paper multiply.
CONTRAST = 1.18
# Below this share of `min(r, b) - g` the texel is backdrop, above the ramp top
# it is paint. Trimming a render's soft antialiasing leaves a hard cut edge.
KEY_LOW = 0.03
KEY_HIGH = 0.15

# kind -> (source stem, output size, is a place)
SYMBOLS = {
    "tree": ("tree", SIZE, False),
    "tree_b": ("tree_b", SIZE, False),
    "tree_c": ("tree_c", SIZE, False),
    "conifer": ("conifer", SIZE, False),
    "mountain": ("mountain", SIZE, False),
    "mountain_b": ("mountain_b", SIZE, False),
    "mountain_c": ("mountain_c", SIZE, False),
    "hill": ("hill", SIZE, False),
    "hill_b": ("hill_b", SIZE, False),
    "dune": ("dune", SIZE, False),
    "field": ("field", SIZE, False),
    "reed": ("reed", SIZE, False),
    "grass": ("grass", SIZE, False),
    "town": ("town", SIZE, True),
    "capital": ("capital", SIZE, True),
    "port": ("port", SIZE, True),
    "ship": ("ship", SHIP_SIZE, True),
}
# Estate marks the civil layer leaves on the chart (LandWorksPaint): grain is
# the field stamp, the other three are their own cut-outs.
WORKS = {
    "work_wood": ("work_wood", SIZE, False),
    "work_mine": ("work_mine", SIZE, False),
    "work_riches": ("work_riches", SIZE, False),
    "work_grain": ("work_grain", SIZE, False),
}
CIVILIANS = {
    "explorer": ("civ_explorer", 64, True),
    "engineer": ("civ_engineer", 64, True),
    "builder": ("civ_builder", 64, True),
    "spy": ("civ_spy", 64, True),
    "merchant": ("civ_merchant", 64, True),
    "rail_builder": ("civ_rail_builder", 64, True),
}


def key(rgb: np.ndarray) -> np.ndarray:
    """Alpha from magenta dominance, with a small luminance gate so a deep
    shadow painted on the object never keys as backdrop."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dominance = np.minimum(r, b) - g
    alpha = np.clip(1.0 - (dominance - KEY_LOW) / (KEY_HIGH - KEY_LOW), 0.0, 1.0)
    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    alpha *= np.clip(luma / 0.04, 0.0, 1.0)
    return alpha


def despill(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Pull residual magenta out of the edge texels so a warm silhouette is not
    ringed in pink after the downsample."""
    r, g, b = rgb[..., 0].copy(), rgb[..., 1].copy(), rgb[..., 2].copy()
    edge = alpha < 0.98
    grey = (r + g + b) / 3.0
    r = np.where(edge, np.minimum(r, grey + 0.06), r)
    b = np.where(edge, np.minimum(b, grey + 0.06), b)
    return np.dstack([r, g, b])


def cut(src: Path, paper: tuple[float, float, float]) -> Image.Image:
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    alpha = key(rgb)
    if alpha.max() < 0.5:
        raise SystemExit(f"{src}: nothing survived the magenta key")
    out = np.dstack([despill(rgb, alpha), alpha])
    img = Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")
    box = img.split()[3].point(lambda v: 255 if v > 40 else 0).getbbox()
    if box is None:
        raise SystemExit(f"{src}: nothing survived the magenta key")
    img = img.crop(box)
    # Pad square so every stamp is drawn from the same origin and one scale.
    side = int(round(max(img.width, img.height) * (1.0 + PAD)))
    plate = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    plate.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    return plate


def grade(img: Image.Image, paper: tuple[float, float, float]) -> Image.Image:
    """Lower the palette's saturation, multiply the chart's paper over it, then
    restore the value contrast the multiply flattens."""
    from PIL import ImageEnhance

    rgb = ImageEnhance.Color(img).enhance(SATURATION).convert("RGB")
    attr = np.asarray(rgb).astype(np.float32) / 255.0
    attr *= np.array(paper, dtype=np.float32)
    graded = Image.fromarray((np.clip(attr, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB")
    graded = ImageEnhance.Contrast(graded).enhance(CONTRAST)
    graded.putalpha(img.split()[3])
    return graded


def build(stem: str, size: int, place: bool, sources: Path, dest: Path) -> Path:
    src = sources / f"{stem}.png"
    if not src.is_file():
        raise SystemExit(f"missing source render: {src}")
    img = cut(src, PAPER)
    img = grade(img, PLACE_PAPER if place else PAPER)
    if max(img.size) > size:
        img = img.resize((size, size), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    return dest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path, help="directory of raw magenta renders")
    parser.add_argument("root", type=Path, help="project root")
    parser.add_argument("--only", default="", help="one kind, for a replacement")
    parser.add_argument("--civilians", action="store_true", help="also the crew marks")
    args = parser.parse_args()

    family: dict = dict(SYMBOLS)
    family.update(WORKS)
    if args.civilians:
        family.update(CIVILIANS)
    built = 0
    for kind, (stem, size, place) in family.items():
        if args.only and kind != args.only:
            continue
        if not (args.sources / f"{stem}.png").is_file():
            if args.only:
                raise SystemExit(f"missing source render: {args.sources / (stem + '.png')}")
            continue
        folder = "civilians" if kind in CIVILIANS else "map"
        name = f"{kind}_mark" if kind in CIVILIANS else kind
        dest = build(stem, size, place, args.sources, args.root / "assets" / "art" / folder / f"{name}.png")
        print(dest)
        built += 1
    print(f"built {built} stamp(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
