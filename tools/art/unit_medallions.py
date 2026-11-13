#!/usr/bin/env python3
"""Prepare the unit medallions (worker tiers, hulls, regiments) for the project.

Sources are FLUX renders of one object each, on a flat magenta backdrop (see
tools/art/unit-medallions.md for the prompts). The frame is never generated: it
is rebuilt from `assets/art/icons/ledger.png` with the open book cleared out of
the field, exactly as tools/art/tech-medallions.md describes, so every medallion
shares the shell's ring, field, vignette and lighting.

This script produces the shipped assets:

  assets/art/workers/<tier>.png      one worker tier
  assets/art/civilians/<type>.png    one worker type
  assets/art/ships/<type>.png        one hull type
  assets/art/regiments/<type>.png    one land regiment type

Worker tiers are the one family that keeps its own colour: each tier's tools are
struck in a different metal, so a rank reads at a glance and not only by
silhouette.

Usage:
  python3 tools/art/unit_medallions.py <source-dir> <project-root> [--only id]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SIZE = 128
FRAME = "assets/art/icons/ledger.png"
# The ring's inner edge, measured off the 128 px source: the field is the disc
# inside it and the ring is kept byte-for-byte.
FIELD_RADIUS = 53.0
# Object width (or height, for tall objects) as a share of the medallion.
FIT = 0.62
FIT_WIDE = 0.70
FIT_TALL = 0.60
# A tier mark sits beside a label in a dense row, so it fills more of the frame
# than a dossier plate does: the field's inner edge is at 53 px (106 across).
TIER_FIT = (0.72, 0.76, 0.66)
# The tiers are the one family struck in dark metals (iron, blued steel), so the
# key's dark gate sits lower or their shaded faces fade into the magenta.
TIER_KEY_FLOOR = 0.015
SHADOW_OFFSET = (2, 3)

CIVILIANS = ["explorer", "engineer", "builder", "spy", "merchant", "rail_builder"]
TIERS = ["peasant", "apprentice", "journeyman", "master"]
# One metal per tier, in rank order: wrought iron, copper, blued steel, gold.
# (hue 0-255, saturation) — the model's own metal is replaced by these, so the
# four ranks stay distinct in colour whatever the render drifts to.
TIER_INK = {
    "peasant": (26.0, 0.10),
    "apprentice": (15.0, 0.70),
    "journeyman": (168.0, 0.55),
    "master": (33.0, 0.62),
}
SHIPS = [
    "carrack", "fluyte", "sloop", "trader", "galleon", "indiaman",
    "frigate", "raider", "ship_of_the_line", "clipper", "merchant_steamship",
    "ironclad",
]
REGIMENTS = [
    "peasant_levies", "pikemen", "arquebusiers", "bowmen", "squires", "knights",
    "culverin", "calivermen", "halberdiers", "musketeers", "cossacks", "lancers",
    "harquebusiers", "horse_artillery", "royal_artillery", "skirmishers",
    "regulars", "grenadiers", "hussars", "cuirassiers", "light_artillery",
    "heavy_artillery", "sharpshooters", "rifle_infantry", "guards", "scouts",
    "carbine_cavalry", "field_artillery", "siege_guns",
]
FAMILIES = {
    "workers": TIERS,
    "civilians": CIVILIANS,
    "ships": SHIPS,
    "regiments": REGIMENTS,
}

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def _luma(rgb: np.ndarray) -> np.ndarray:
    return rgb @ LUMA


def blank_frame(source: Path) -> Image.Image:
    """The shell medallion with its open book replaced by the field it sits on."""
    img = np.asarray(Image.open(source).convert("RGBA")).astype(np.float32) / 255.0
    height, width = img.shape[:2]
    centre = ((width - 1) / 2.0, (height - 1) / 2.0)
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    radius = np.hypot(xx - centre[0], yy - centre[1])
    inside = radius < FIELD_RADIUS
    # The field's own colour at each radius: the median of the texels on that
    # ring, so the vignette and the ring's inner shadow survive. Below the band
    # the open book used to cover, the field is carried inward instead.
    anchor = 44
    profile = np.zeros((int(FIELD_RADIUS) + 2, 3), dtype=np.float32)
    for r in range(anchor, profile.shape[0]):
        band = (radius >= r - 0.5) & (radius < r + 0.5)
        if band.any():
            profile[r] = np.median(img[band][:, :3], axis=0)
    profile[int(FIELD_RADIUS) + 1] = profile[int(FIELD_RADIUS)]
    # Inside deepest measured ring the book used to sit; carry the field in
    # with a gentle lift, which is the gradient the reference has anyway.
    inner = profile[anchor] * 1.55
    t = np.clip(np.arange(profile.shape[0]) / float(anchor), 0.0, 1.0) ** 1.4
    for channel in range(3):
        profile[:anchor, channel] = inner[channel] * (1.0 - t[:anchor]) + (
            profile[anchor, channel] * t[:anchor]
        )
    # One colour per whole pixel of radius, then a light blur so the shelf of
    # 1 px steps does not read as banding at 128 px.
    steps = np.zeros_like(img[:, :, :3])
    for r in range(int(FIELD_RADIUS) + 1):
        band = (radius >= r) & (radius < r + 1)
        steps[band] = profile[min(r, profile.shape[0] - 1)]
    field = Image.fromarray((np.clip(steps, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB")
    field = field.filter(ImageFilter.GaussianBlur(1.2))
    fill = np.asarray(field).astype(np.float32) / 255.0
    out = img.copy()
    out[inside, :3] = fill[inside]
    return Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")


def key(src: Path, floor: float = 0.07) -> Image.Image:
    """Key one painted object off its flat magenta backdrop.

    `floor` is the luminance below which texels fade out, because a model painting
    a dark backdrop must not key as object. The worker tiers are deliberately
    dark metals, so that gate is lowered for them (see `build`).
    """
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magenta = np.minimum(r, b) - g
    alpha = np.clip(1.0 - (magenta - 0.03) / 0.12, 0.0, 1.0)
    alpha *= np.clip((_luma(rgb) - floor) / 0.10, 0.0, 1.0)
    grey = (r + g + b) / 3.0
    edge = alpha < 0.98
    r = np.where(edge, np.minimum(r, grey + 0.05), r)
    b = np.where(edge, np.minimum(b, grey + 0.05), b)
    out = np.dstack([r, g, b, alpha])
    img = Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")
    box = img.split()[3].point(lambda v: 255 if v > 90 else 0).getbbox()
    if box is None:
        raise SystemExit(f"{src}: nothing survived the magenta key")
    return img.crop(box)


def grade(obj: Image.Image, hue: float, sat: float) -> Image.Image:
    """Recast one object's metal: hue and saturation become the tier's, while the
    render's own light and shadow (value) are kept, so form survives the tint. A
    slight lift keeps the darker metals clear of the espresso field."""
    hsv = np.asarray(obj.convert("HSV")).astype(np.float32)
    hsv[..., 0] = hue
    hsv[..., 1] = sat * 255.0
    hsv[..., 2] = np.clip(hsv[..., 2] * 1.12 + 0.04 * 255.0, 0.0, 255.0)
    out = Image.fromarray(np.clip(hsv, 0.0, 255.0).astype(np.uint8), "HSV").convert("RGBA")
    out.putalpha(obj.split()[3])
    return out


def fit(
    obj: Image.Image,
    base: float = FIT,
    wide: float = FIT_WIDE,
    tall: float = FIT_TALL,
) -> Image.Image:
    """Scale the object to the medallion's useful area, keeping its proportions."""
    span = int(round(SIZE * base))
    if obj.width > obj.height * 1.35:
        span = int(round(SIZE * wide))
    elif obj.height > obj.width * 1.35:
        span = int(round(SIZE * tall))
    scale = span / float(max(obj.width, obj.height))
    target = (max(1, round(obj.width * scale)), max(1, round(obj.height * scale)))
    return obj.resize(target, Image.LANCZOS)


def compose(frame: Image.Image, obj: Image.Image, shadow: float = 0.55) -> Image.Image:
    """Drop the object onto the frame with a soft shadow to the lower right."""
    plate = frame.copy()
    left = (SIZE - obj.width) // 2
    top = (SIZE - obj.height) // 2
    alpha = obj.split()[3].filter(ImageFilter.GaussianBlur(3.0))
    drop = Image.new("RGBA", obj.size, (0, 0, 0, 0))
    drop.putalpha(alpha.point(lambda v: int(v * shadow)))
    plate.alpha_composite(drop, (left + SHADOW_OFFSET[0], top + SHADOW_OFFSET[1]))
    plate.alpha_composite(obj, (left, top))
    return plate


def build(family: str, unit_id: str, sources: Path, root: Path, frame: Image.Image) -> Path:
    src = sources / f"{unit_id}.png"
    if not src.is_file():
        raise SystemExit(f"missing source render: {src}")
    dest = root / "assets" / "art" / family / f"{unit_id}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    obj = key(src, TIER_KEY_FLOOR if family == "workers" else 0.07)
    if family == "workers":
        obj = grade(obj, *TIER_INK[unit_id])
        compose(frame, fit(obj, *TIER_FIT)).save(dest)
    else:
        compose(frame, fit(obj)).save(dest)
    return dest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path, help="directory of raw magenta renders")
    parser.add_argument("root", type=Path, help="project root")
    parser.add_argument("--only", default="", help="one unit id, for a replacement")
    parser.add_argument("--blank", default="", help="also write the bare frame here")
    args = parser.parse_args()

    frame = blank_frame(args.root / FRAME)
    if args.blank:
        frame.save(args.blank)
    built = 0
    for family, ids in FAMILIES.items():
        for unit_id in ids:
            if args.only and unit_id != args.only:
                continue
            if not (args.sources / f"{unit_id}.png").is_file() and args.only:
                raise SystemExit(f"missing source render: {args.sources / (unit_id + '.png')}")
            build(family, unit_id, args.sources, args.root, frame)
            built += 1
    print(f"built {built} medallion(s) into {args.root / 'assets' / 'art'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
