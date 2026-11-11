#!/usr/bin/env python3
"""Prepare the commodity medallions (assets/art/goods) for the project.

Every good in CommodityCatalog gets one plate cut in the shell/tech medallion
family: thick beveled brass ring, dark espresso field, top-left light, one
subject sculpted in polished brass. The ring is never generated — it is the
shipped `assets/art/icons/ledger.png` with its centre cleared, and only the
subject is rendered onto a magenta sheet by FLUX Kontext.

Sources are magenta sheets, one per commodity id, named `<id>.png`. The object
prompts live in tools/art/goods-medallions.md and are read from that table, so
the doc stays the single record of what each plate depicts.

Usage:
  python3 tools/art/goods_icons.py --generate <sheet-dir>   # render missing sheets
  python3 tools/art/goods_icons.py <sheet-dir> [project-root]

`--generate` needs FAL_KEY in the environment (https://fal.ai).
"""
from __future__ import annotations

import base64
import io
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageFilter

SIZE = 128
FIELD_R = 51.0  # fill radius: the ring's inner edge sits at ~53.5 px
FEATHER = 2.6
DEFAULT_FIT = 0.64
# Wide or tall subjects get a smaller plate so they never kiss the ring.
FIT = {
    "bronze": 0.66, "castIron": 0.60, "cigars": 0.60, "coal": 0.64, "fabric": 0.60,
    "furHats": 0.60, "furs": 0.58, "gems": 0.62, "horses": 0.58, "lumber": 0.60,
    "meat": 0.60, "paper": 0.60, "silver": 0.60, "spices": 0.62, "steel": 0.58,
    "sugarCane": 0.58, "timber": 0.58, "tobacco": 0.58, "diamonds": 0.58,
    "wool": 0.56, "gold": 0.58, "furHats": 0.62,
}
TAIL = (
    " sculpted in polished brass with warm gold highlights and deep bronze shadows, "
    "lit from the upper left, rendered in exactly the same glossy metallic style as the "
    "gold ring of the reference medallion. Centred, one object only, a bold simple "
    "silhouette that stays legible when small, no open book, no pages, no ring, no frame, "
    "no text, no lettering. Isolated on a solid pure magenta #FF00FF background."
)


# --- prompts ------------------------------------------------------------------


def prompts(project: Path) -> dict[str, str]:
    """`id -> subject` from the doc's table; the doc is the single record."""
    text = (project / "tools/art/goods-medallions.md").read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"\|\s*`([A-Za-z]+)`\s*\|\s*(.+?)\s*\|\s*$", line)
        if match:
            out[match.group(1)] = match.group(2)
    if not out:
        raise SystemExit("no prompt rows found in tools/art/goods-medallions.md")
    return out


# --- blank medallion ----------------------------------------------------------


def _smoothstep(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def blank_medallion(source: Path) -> Image.Image:
    """Clear the centre of a shipped plate, keeping ring, bevel and vignette."""
    im = Image.open(source).convert("RGBA")
    a = np.asarray(im, dtype=np.float32) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    h, w = rgb.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.hypot(xx - (w / 2 - 0.5), yy - (h / 2 - 0.5))
    band = np.round(r).astype(int)
    prof = {}
    for rad in range(0, 61):
        m = band == rad
        if m.sum() > 8:
            prof[rad] = np.array([np.median(rgb[..., c][m]) for c in range(3)])
    edge = np.mean([prof[k] for k in range(46, 53) if k in prof], axis=0)
    mid = np.mean([prof[k] for k in range(38, 45) if k in prof], axis=0)
    centre = np.clip(mid * 1.28, 0.0, 1.0)
    t = _smoothstep(r / FIELD_R)[..., None]
    fill = centre * (1.0 - t) + edge * t
    w_edge = _smoothstep((r - (FIELD_R - FEATHER)) / FEATHER)[..., None]
    merged = fill * (1.0 - w_edge) + rgb * w_edge
    out = np.where((r <= FIELD_R)[..., None], merged, rgb)
    return Image.fromarray(
        (np.dstack([np.clip(out, 0.0, 1.0), alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA"
    )


# --- key and composite --------------------------------------------------------


def _hsv_to_rgb(h: np.ndarray, s: np.ndarray, v: np.ndarray) -> np.ndarray:
    i = np.floor(h * 6.0).astype(int) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p, q, t = v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s)
    picks = [
        (v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q),
    ]
    out = np.zeros(h.shape + (3,))
    for k, chan in enumerate(picks):
        m = i == k
        if m.any():
            out[m] = np.stack([c[m] for c in chan], axis=-1)
    return out


def family_tone(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Pull every subject hue into the family's warm brass band.

    The generator sometimes renders a gem or a billet with a red or clay cast;
    the ring is brass, so an off-hue plate reads as a different set. Luminance
    is untouched, so highlights and bronze shadows survive.
    """
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    d = mx - mn
    safe = np.where(d > 1e-6, d, 1.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lit = d > 1e-6
    is_r, is_g = lit & (mx == r), lit & (mx == g) & ~(mx == r)
    is_b = lit & (mx == b) & ~(mx == r) & ~(mx == g)
    hue = np.zeros_like(mx)
    hue[is_r] = (((g - b) / safe) % 6.0)[is_r]
    hue[is_g] = (((b - r) / safe) + 2.0)[is_g]
    hue[is_b] = (((r - g) / safe) + 4.0)[is_b]
    hue = hue / 6.0
    sat = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    pulled = np.clip(0.095 + (hue - 0.095) * 0.35, 0.055, 0.125)
    out = _hsv_to_rgb(pulled, np.minimum(sat, 0.88), mx)
    weight = np.clip(alpha, 0.0, 1.0)[..., None]
    return rgb * (1.0 - weight) + out * weight


def key(path: Path) -> Image.Image:
    """Magenta sheet -> subject alpha, despilled at the edges."""
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    magenta = np.clip(1.0 - (np.minimum(r, b) - g) / 0.10, 0.0, 1.0)
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    alpha = np.minimum(magenta, np.clip((luma - 0.150) / 0.150, 0.0, 1.0))
    spill = np.clip(np.minimum(r, b) - g, 0.0, 1.0)
    edge = (alpha > 0.0) & (alpha < 1.0)
    k = spill * 0.5 * (1.0 - alpha)
    r = np.where(edge, r - k, r)
    g = np.where(edge, g + k, g)
    b = np.where(edge, b - k, b)
    rgb = family_tone(np.clip(np.dstack([r, g, b]), 0.0, 1.0), alpha)
    return Image.fromarray(
        (np.dstack([np.clip(rgb, 0.0, 1.0), alpha]) * 255.0 + 0.5).astype(np.uint8), "RGBA"
    )


def fit(sprite: Image.Image, ratio: float) -> Image.Image:
    box = sprite.split()[3].getbbox()
    if box is None:
        raise SystemExit("empty alpha after keying")
    cut = sprite.crop(box)
    scale = min(round(SIZE * ratio) / cut.width, round(SIZE * ratio) / cut.height)
    size = (max(1, round(cut.width * scale)), max(1, round(cut.height * scale)))
    return cut.resize(size, Image.LANCZOS)


def with_shadow(sprite: Image.Image) -> Image.Image:
    pad = 4
    layer = Image.new("RGBA", (sprite.width + pad * 2, sprite.height + pad * 2), (0, 0, 0, 0))
    blob = Image.new("RGBA", sprite.size, (18, 10, 4, 255))
    blob.putalpha(sprite.split()[3].point(lambda v: int(v * 0.55)))
    layer.paste(blob, (pad + 2, pad + 2), blob)
    layer = layer.filter(ImageFilter.GaussianBlur(1.6))
    layer.paste(sprite, (pad, pad), sprite)
    return layer


def compose(sheet: Path, base: Image.Image, name: str) -> Image.Image:
    plate = with_shadow(fit(key(sheet), FIT.get(name, DEFAULT_FIT)))
    canvas = base.copy()
    canvas.alpha_composite(
        plate, ((SIZE - plate.width) // 2, (SIZE - plate.height) // 2)
    )
    return canvas


# --- generation ---------------------------------------------------------------


def generate(project: Path, sheets: Path, names: list[str]) -> None:
    base = blank_medallion(project / "assets/art/icons/ledger.png")
    sheets.mkdir(parents=True, exist_ok=True)
    table = prompts(project)
    encoded = base64.b64encode(
        _png_bytes(base)
    ).decode()
    key = os.environ.get("FAL_KEY", "")
    if not key:
        raise SystemExit("FAL_KEY is not set")

    def one(name: str) -> None:
        dest = sheets / f"{name}.png"
        if dest.exists():
            return
        payload = {
            "prompt": table[name] + TAIL,
            "image_url": "data:image/png;base64," + encoded,
            "num_images": 1,
            "output_format": "png",
            "guidance_scale": 3.5,
        }
        for _ in range(3):
            res = requests.post(
                "https://fal.run/fal-ai/flux-pro/kontext",
                headers={"Authorization": "Key " + key, "Content-Type": "application/json"},
                json=payload,
                timeout=300,
            )
            if res.status_code != 200:
                print("retry", name, res.status_code, res.text[:160])
                continue
            img = requests.get(res.json()["images"][0]["url"], timeout=120)
            img.raise_for_status()
            dest.write_bytes(img.content)
            print("generated", name)
            return
        raise SystemExit(f"could not generate {name}")

    with ThreadPoolExecutor(max_workers=5) as pool:
        list(pool.map(one, names))


def _png_bytes(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def main(argv: list[str]) -> None:
    generate_only = "--generate" in argv
    args = [a for a in argv if a != "--generate"]
    if not args:
        raise SystemExit(__doc__)
    sheets = Path(args[0]).expanduser()
    root = Path(args[1]) if len(args) > 1 else Path(__file__).resolve().parents[2]
    table = prompts(root)
    names = sorted(p.stem for p in sheets.glob("*.png")) if sheets.exists() else []
    if generate_only:
        generate(root, sheets, sorted(table))
        return
    unknown = [n for n in names if n not in table]
    if unknown:
        raise SystemExit(f"sheets with no prompt row: {', '.join(unknown)}")
    if not names:
        raise SystemExit(f"no sheets in {sheets}")
    base = blank_medallion(root / "assets/art/icons/ledger.png")
    out = root / "assets/art/goods"
    out.mkdir(parents=True, exist_ok=True)
    for name in names:
        compose(sheets / f"{name}.png", base, name).save(out / f"{name}.png", optimize=True)
        print(f"{name}.png {SIZE}x{SIZE}")


if __name__ == "__main__":
    main(sys.argv[1:])
