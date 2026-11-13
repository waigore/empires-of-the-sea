#!/usr/bin/env python3
"""Paint the battlefield miniatures: one sprite per land regiment type.

The plate used to stamp every formation with the same musketeer. Each
regiment type in [RegimentCatalog] now gets its own small period figure — a
foot soldier with his own arms and headgear, a rider on his own horse, or a
gun of its own weight — so a line of troops reads as the composition it is
(wiki: quick-battle § The plate).

Everything is painted here rather than rendered: one palette, one key light,
one outline and one brush pass over every sprite, so the 29 miniatures are one
hand by construction (REQ-P1-02, REQ-P1-08).

  assets/art/battle/regiments/<type_id>.png   one miniature, 200 px tall

Usage:
  python3 tools/art/regiment_miniatures.py [project-root] [--sheet PATH]
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Working canvas, in final sprite pixels; the sprites are painted at SS× and
# sampled down, which is what gives the clean painted edge.
BOX_W, BOX_H = 280, 220
SS = 3
HEIGHT = 200
# Height in working units of a standing foot figure (feet at BASE_Y, hat at
# ~86): every sprite is scaled by the same factor, so a gun is drawn shorter
# than a man and a rider taller without any per-type numbers in the view.
REFERENCE_FIGURE = 122.0
BASE_Y = 208.0

# One period palette for the whole set: muted cloth, buff leather, steel,
# brass and wood. Faction colour arrives as a tint in the view, so the art
# itself stays neutral.
PALETTE = {
    "ink": (26, 22, 18),
    "steel": (150, 155, 158),
    "steel_dark": (96, 101, 106),
    "brass": (176, 138, 66),
    "brass_dark": (124, 94, 42),
    "wood": (116, 82, 48),
    "wood_dark": (82, 56, 32),
    "leather": (96, 68, 44),
    "buff": (188, 164, 120),
    "buff_dark": (146, 122, 84),
    "coat_russet": (124, 84, 54),
    "coat_russet_dark": (88, 58, 38),
    "coat_grey": (150, 148, 140),
    "coat_grey_dark": (110, 108, 102),
    "coat_blue": (68, 84, 112),
    "coat_blue_dark": (46, 58, 80),
    "coat_green": (74, 92, 62),
    "coat_green_dark": (52, 66, 44),
    "coat_red": (140, 62, 52),
    "coat_red_dark": (100, 44, 38),
    "flesh": (206, 158, 118),
    "flesh_dark": (168, 120, 88),
    "horse_bay": (128, 86, 52),
    "horse_bay_dark": (94, 62, 38),
    "horse_black": (74, 68, 66),
    "horse_black_dark": (50, 46, 44),
    "horse_grey": (172, 168, 160),
    "horse_grey_dark": (130, 126, 120),
    "hair": (78, 62, 46),
}


def _rgb(name: str) -> tuple[int, int, int]:
    return PALETTE[name]


def _tone(colour, factor: float) -> tuple[int, int, int]:
    r, g, b = colour[:3]
    return (
        max(0, min(255, int(r * factor))),
        max(0, min(255, int(g * factor))),
        max(0, min(255, int(b * factor))),
    )


def _shade(name: str, factor: float) -> tuple[int, int, int]:
    r, g, b = _rgb(name)
    return (
        max(0, min(255, int(r * factor))),
        max(0, min(255, int(g * factor))),
        max(0, min(255, int(b * factor))),
    )


class Painter:
    """Draws in final sprite units on an SS× supersampled canvas."""

    def __init__(self) -> None:
        self.img = Image.new("RGBA", (BOX_W * SS, BOX_H * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    # --- primitives -------------------------------------------------------
    def poly(self, points, colour) -> None:
        self.d.polygon([(x * SS, y * SS) for x, y in points], fill=colour)

    def rect(self, x0, y0, x1, y1, colour) -> None:
        self.d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=colour)

    def ellipse(self, cx, cy, rx, ry, colour) -> None:
        self.d.ellipse(
            [(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS],
            fill=colour,
        )

    def line(self, points, colour, width) -> None:
        self.d.line(
            [(x * SS, y * SS) for x, y in points],
            fill=colour,
            width=max(1, int(round(width * SS))),
            joint="curve",
        )

    def capsule(self, a, b, radius, colour) -> None:
        """A limb: a thick line with round ends."""
        self.line([a, b], colour, radius * 2)
        self.ellipse(a[0], a[1], radius, radius, colour)
        self.ellipse(b[0], b[1], radius, radius, colour)

    def tapered(self, a, b, r0, r1, colour) -> None:
        """A limb that narrows: nested capsules along the span."""
        steps = 6
        for index in range(steps + 1):
            t = float(index) / float(steps)
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            r = r0 + (r1 - r0) * t
            self.ellipse(x, y, r, r, colour)

    # --- figure parts -----------------------------------------------------
    def coat(self, cx, top, bottom, width_top, width_bottom, colour, skirt=True):
        """A coat: shoulders to waist, flaring to a skirt over the thighs."""
        hem = bottom if skirt else top + (bottom - top) * 0.55
        pts = [
            (cx - width_top * 0.5, top),
            (cx + width_top * 0.5, top),
            (cx + width_bottom * 0.5, hem),
            (cx - width_bottom * 0.5, hem),
        ]
        self.poly(pts, colour)
        # The key light falls from the upper left: the away side of the coat
        # goes down a shade and the shoulder catches a lift.
        self.poly([
            (cx + width_top * 0.16, top),
            (cx + width_top * 0.5, top),
            (cx + width_bottom * 0.5, hem),
            (cx + width_bottom * 0.12, hem),
        ], _tone(colour, 0.80))
        self.poly([
            (cx - width_top * 0.5, top),
            (cx - width_top * 0.24, top),
            (cx - width_bottom * 0.26, hem),
            (cx - width_bottom * 0.5, hem),
        ], _tone(colour, 1.13))
        return pts

    def head(self, cx, cy, r, colour, shade=None) -> None:
        self.ellipse(cx, cy, r, r * 1.06, colour)
        if shade:
            self.poly(
                [(cx + r * 0.1, cy - r), (cx + r, cy - r * 0.35),
                 (cx + r * 0.75, cy + r * 0.9), (cx + r * 0.1, cy + r)],
                shade,
            )

    def leg(self, hip, knee, foot, colour, boot) -> None:
        self.tapered(hip, knee, 5.5, 4.2, colour)
        self.tapered(knee, foot, 4.2, 3.6, colour)
        self.capsule(foot, (foot[0] + 7.0, foot[1] + 1.0), 3.6, boot)

    def arm(self, shoulder, elbow, hand, colour, cuff=None) -> None:
        self.tapered(shoulder, elbow, 4.8, 4.0, _tone(colour, 0.86))
        self.tapered(elbow, hand, 4.0, 3.4, _tone(colour, 0.93))
        if cuff is not None:
            self.ellipse(hand[0], hand[1], 3.4, 3.4, cuff)

    # --- headgear ---------------------------------------------------------
    def cap(self, cx, cy, colour) -> None:
        """A soft round cap: the levy's and the cossack's alike."""
        self.ellipse(cx, cy, 9.0, 6.4, colour)
        self.ellipse(cx + 1.0, cy + 3.0, 9.6, 3.0, colour)

    def wide_hat(self, cx, cy, colour, brim=17.0) -> None:
        self.ellipse(cx, cy + 3.0, brim, 4.0, colour)
        self.ellipse(cx, cy - 1.0, 7.0, 6.6, colour)

    def morion(self, cx, cy, colour) -> None:
        """The crested helmet of the sixteenth century."""
        self.ellipse(cx, cy + 1.0, 11.0, 7.0, colour)
        self.poly(
            [(cx - 9.0, cy), (cx - 3.0, cy - 8.0), (cx + 5.0, cy - 9.0),
             (cx + 9.0, cy - 2.0)],
            _shade("steel", 1.12),
        )
        self.poly([(cx - 10.0, cy + 1.0), (cx - 6.0, cy + 4.0), (cx - 12.0, cy + 4.0)],
                  colour)

    def lobster(self, cx, cy, colour) -> None:
        """A lobstered cavalry helmet with its tail."""
        self.ellipse(cx, cy, 9.0, 8.0, colour)
        self.poly(
            [(cx - 8.0, cy + 4.0), (cx + 7.0, cy + 4.0), (cx + 10.0, cy + 11.0),
             (cx - 11.0, cy + 11.0)],
            _shade("steel", 0.92),
        )
        self.line([(cx - 7.0, cy - 1.0), (cx + 6.0, cy - 1.0)], _shade("steel", 1.2), 1.4)

    def shako(self, cx, cy, colour, plume=None) -> None:
        """The tall cylindrical shako of the later eras."""
        self.poly(
            [(cx - 8.0, cy + 3.0), (cx - 7.0, cy - 10.0), (cx + 7.0, cy - 10.0),
             (cx + 8.0, cy + 3.0)],
            colour,
        )
        self.ellipse(cx, cy + 3.0, 9.0, 3.2, colour)
        self.line([(cx - 7.0, cy + 2.0), (cx + 7.0, cy + 2.0)], _shade("steel", 1.3), 1.2)
        if plume:
            self.ellipse(cx + 3.0, cy - 13.0, 3.4, 4.6, plume)

    def mitre(self, cx, cy, colour) -> None:
        """A grenadier's tall mitre cap, gilt at the plate."""
        self.poly(
            [(cx - 8.5, cy + 3.0), (cx - 5.0, cy - 16.0), (cx + 6.0, cy - 16.0),
             (cx + 8.5, cy + 3.0)],
            colour,
        )
        self.poly(
            [(cx - 5.0, cy - 16.0), (cx + 6.0, cy - 16.0), (cx + 5.0, cy - 10.0),
             (cx - 4.0, cy - 10.0)],
            _shade("brass", 1.05),
        )

    def bearskin(self, cx, cy, colour) -> None:
        self.ellipse(cx, cy - 4.0, 10.5, 13.0, colour)
        self.ellipse(cx - 3.0, cy - 8.0, 6.0, 8.0, colour)

    def hood(self, cx, cy, colour) -> None:
        self.ellipse(cx, cy - 2.0, 10.0, 11.0, colour)
        self.poly([(cx - 9.0, cy + 2.0), (cx - 12.0, cy + 12.0), (cx + 2.0, cy + 10.0)],
                  colour)

    # --- weapons ----------------------------------------------------------
    def pike(self, hand, colour="wood") -> None:
        """A pike held at the shoulder: the tallest thing in the line."""
        top = (hand[0] - 3.0, hand[1] - 52.0)
        # One shaft, head to butt: a pike broken into pieces reads as debris.
        self.line([(top[0] + 0.4, top[1] + 12.0), (hand[0] + 2.0, BASE_Y + 1.0)],
                  _rgb(colour), 2.4)
        self.poly([(top[0] - 3.4, top[1] + 14.0), (top[0] + 0.6, top[1] - 6.0),
                   (top[0] + 3.8, top[1] + 14.0)], _rgb("steel"))
        self.rect(hand[0] + 0.0, BASE_Y - 5.0, hand[0] + 4.0, BASE_Y + 1.0,
                  _rgb("wood_dark"))

    def halberd(self, hand) -> None:
        self.line([hand, (hand[0] + 3.0, BASE_Y - 4.0)], _rgb("wood"), 2.4)
        head = (hand[0] - 1.0, hand[1] - 44.0)
        self.line([hand, head], _rgb("wood"), 2.4)
        self.poly([(head[0], head[1] - 4.0), (head[0] + 9.0, head[1] - 1.0),
                   (head[0] + 8.0, head[1] + 7.0), (head[0], head[1] + 4.0)],
                  _rgb("steel"))
        self.poly([(head[0] - 8.0, head[1] + 1.0), (head[0], head[1] - 4.0),
                   (head[0], head[1] + 5.0)], _rgb("steel_dark"))

    def musket(self, a, b, bayonet=False, lock=True) -> None:
        """A longarm from butt (a) to muzzle (b)."""
        self.line([a, b], _rgb("wood_dark"), 4.2)
        shaft = ((a[0] + (b[0] - a[0]) * 0.42), (a[1] + (b[1] - a[1]) * 0.42))
        self.line([shaft, b], _rgb("steel_dark"), 2.6)
        if lock:
            self.ellipse(shaft[0], shaft[1], 2.6, 2.6, _rgb("steel"))
            self.rect(shaft[0] - 1.0, shaft[1] + 2.0, shaft[0] + 5.0, shaft[1] + 6.0,
                     _rgb("steel_dark"))
        # The hand on the small of the stock, so the arm and the gun are one.
        self.ellipse(a[0] + (b[0] - a[0]) * 0.30, a[1] + (b[1] - a[1]) * 0.30,
                     3.0, 3.0, _rgb("flesh_dark"))
        if bayonet:
            tip = (b[0] + (b[0] - a[0]) * 0.16, b[1] + (b[1] - a[1]) * 0.16)
            self.line([b, tip], _rgb("steel"), 1.8)

    def bow(self, hand, colour="wood") -> None:
        """A bow at full draw: an arc, its string pulled back, and the arrow.

        `hand` is the grip. The stave bows away from the archer and the string
        comes back to his cheek, which is what makes the shape read as archery
        rather than a pole (the belly toward the archer reads as a stick).
        """
        cx, cy = hand
        half = 36.0
        stave = []
        for step in range(11):
            t = -1.0 + 2.0 * float(step) / 10.0
            stave.append((cx + 12.0 * (1.0 - t * t), cy + half * t))
        self.line(stave, _rgb(colour), 3.2)
        self.line([stave[0], (cx + 1.0, cy - 1.0), stave[-1]],
                  _shade("buff", 1.08), 1.5)
        # The nocked arrow, its head past the stave's belly.
        self.line([(cx + 1.0, cy), (cx + 34.0, cy)], _rgb("wood_dark"), 1.8)
        self.poly([(cx + 34.0, cy), (cx + 42.0, cy - 2.4), (cx + 42.0, cy + 2.4)],
                  _rgb("steel"))
        self.line([(cx + 1.0, cy), (cx - 6.0, cy - 3.0)], _shade("buff", 0.88), 1.4)
        self.ellipse(cx + 1.0, cy, 2.6, 2.6, _rgb("flesh_dark"))

    def sabre(self, hand, angle=-1.0, length=34.0) -> None:
        tip = (hand[0] + math.cos(angle) * length, hand[1] + math.sin(angle) * length)
        self.line([hand, tip], _rgb("steel"), 2.4)
        self.line([(hand[0] - 3.0, hand[1] + 3.0), (hand[0] + 3.0, hand[1] - 3.0)],
                  _rgb("brass_dark"), 1.6)

    def lance(self, hand, colour="wood", pennon=None) -> None:
        tip = (hand[0] + 46.0, hand[1] - 14.0)
        self.line([(hand[0] - 22.0, hand[1] + 10.0), tip], _rgb(colour), 2.2)
        self.poly([(tip[0] - 1.0, tip[1] - 3.0), (tip[0] + 5.0, tip[1]),
                   (tip[0] - 1.0, tip[1] + 3.0)], _rgb("steel"))
        if pennon:
            self.poly([(tip[0] - 18.0, tip[1] + 2.0), (tip[0] - 4.0, tip[1] + 1.0),
                       (tip[0] - 10.0, tip[1] + 10.0)], pennon)

    def grenade_pouch(self, hip, colour) -> None:
        self.ellipse(hip[0] + 11.0, hip[1] + 2.0, 6.2, 6.8, colour)
        self.ellipse(hip[0] + 11.0, hip[1] + 1.0, 4.4, 4.4, _shade("brass", 1.05))
        self.poly([(hip[0] + 9.0, hip[1] - 4.0), (hip[0] + 13.0, hip[1] - 7.0),
                   (hip[0] + 14.0, hip[1] - 2.0)], _rgb("steel_dark"))

    def quiver(self, back, colour) -> None:
        self.poly(
            [(back[0] - 3.0, back[1] + 14.0), (back[0] + 3.0, back[1] - 12.0),
             (back[0] + 6.0, back[1] - 12.0), (back[0], back[1] + 14.0)],
            colour,
        )
        for index in range(3):
            top = (back[0] + 4.0 + float(index) * 1.2, back[1] - 12.0)
            self.line([top, (top[0] + 3.0, top[1] - 8.0)], _shade("buff", 1.05), 0.9)

    # --- horses -----------------------------------------------------------
    def horse(self, cx, base, colour, dark, caparison=None, barding=False) -> None:
        """A horse standing square, head to the right, its rider's seat marked."""
        body = _rgb(colour)
        shade = _rgb(dark)
        # Barrel, chest, haunch.
        self.ellipse(cx, base - 34.0, 33.0, 17.0, body)
        self.ellipse(cx + 22.0, base - 40.0, 15.0, 15.0, body)
        self.ellipse(cx - 24.0, base - 36.0, 16.0, 16.0, shade)
        # Neck and head, mouth open at the bit, ears pricked.
        self.poly([(cx + 26.0, base - 48.0), (cx + 40.0, base - 74.0),
                   (cx + 50.0, base - 71.0), (cx + 34.0, base - 44.0)], body)
        self.poly([(cx + 40.0, base - 74.0), (cx + 58.0, base - 79.0),
                   (cx + 62.0, base - 72.0), (cx + 46.0, base - 66.0)],
                  _shade(colour, 1.06))
        self.poly([(cx + 55.0, base - 76.0), (cx + 61.0, base - 86.0),
                   (cx + 64.0, base - 84.0), (cx + 60.0, base - 74.0)], body)
        # Mane down the neck.
        self.poly([(cx + 26.0, base - 50.0), (cx + 40.0, base - 76.0),
                   (cx + 44.0, base - 72.0), (cx + 30.0, base - 44.0)], shade)
        # Tail.
        self.poly([(cx - 38.0, base - 44.0), (cx - 46.0, base - 14.0),
                   (cx - 39.0, base - 12.0), (cx - 32.0, base - 44.0)], shade)
        # Four legs, the near pair lighter.
        for index, x in enumerate((-26.0, -18.0, 16.0, 24.0)):
            top = base - 26.0
            knee = base - 14.0
            leg_shade = body if index % 2 == 0 else shade
            self.tapered((cx + x, top), (cx + x + 1.0, knee), 4.6, 3.4, leg_shade)
            self.tapered((cx + x + 1.0, knee), (cx + x + 1.0, base - 2.0),
                         3.4, 2.8, leg_shade)
            self.rect(cx + x - 2.0, base - 4.0, cx + x + 4.0, base, _shade("ink", 1.0))
        if caparison:
            self.poly([(cx - 26.0, base - 50.0), (cx + 24.0, base - 52.0),
                       (cx + 20.0, base - 20.0), (cx - 22.0, base - 20.0)], caparison)
            self.poly([(cx - 26.0, base - 50.0), (cx + 24.0, base - 52.0),
                       (cx + 23.0, base - 44.0), (cx - 25.0, base - 42.0)],
                      caparison)
        if barding:
            self.poly([(cx - 14.0, base - 56.0), (cx + 26.0, base - 58.0),
                       (cx + 22.0, base - 24.0), (cx - 12.0, base - 24.0)],
                      _rgb("steel_dark"))
            self.poly([(cx + 30.0, base - 60.0), (cx + 40.0, base - 52.0),
                       (cx + 34.0, base - 26.0), (cx + 24.0, base - 30.0)],
                      _rgb("steel_dark"))

    def rider_legs(self, hip, colour, boot) -> None:
        """The near leg over the saddle, the far one only hinted."""
        self.tapered(hip, (hip[0] - 6.0, hip[1] + 20.0), 5.4, 4.0, colour)
        self.tapered((hip[0] - 6.0, hip[1] + 20.0), (hip[0] + 2.0, hip[1] + 30.0),
                     4.0, 3.2, boot)

    # --- guns -------------------------------------------------------------
    def wheel(self, cx, cy, radius, spokes=8) -> None:
        self.ellipse(cx, cy, radius, radius, _rgb("wood_dark"))
        self.ellipse(cx, cy, radius * 0.72, radius * 0.72, (0, 0, 0, 0))
        for index in range(spokes):
            angle = math.pi * float(index) / float(spokes)
            dx, dy = math.cos(angle) * radius * 0.8, math.sin(angle) * radius * 0.8
            self.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], _rgb("wood"), 1.8)
        self.ellipse(cx, cy, radius * 0.30, radius * 0.30, _rgb("wood_dark"))

    def barrel(self, breech, muzzle, r_back, r_front, colour="brass") -> None:
        """A taper from breech to muzzle, banded with iron."""
        steps = 10
        for index in range(steps):
            t0 = float(index) / float(steps)
            t1 = float(index + 1) / float(steps)
            p0 = (breech[0] + (muzzle[0] - breech[0]) * t0,
                  breech[1] + (muzzle[1] - breech[1]) * t0)
            p1 = (breech[0] + (muzzle[0] - breech[0]) * t1,
                  breech[1] + (muzzle[1] - breech[1]) * t1)
            r = r_back + (r_front - r_back) * t0
            self.line([p0, p1], _rgb(colour), r * 2.0)
        # Reinforcing bands and the muzzle ring.
        for t in (0.12, 0.34, 0.58, 0.82):
            p = (breech[0] + (muzzle[0] - breech[0]) * t,
                 breech[1] + (muzzle[1] - breech[1]) * t)
            r = r_back + (r_front - r_back) * t + 1.0
            self.ellipse(p[0], p[1], r + 1.2, r + 1.2, _shade(colour, 0.78))
        self.ellipse(muzzle[0], muzzle[1], r_front + 1.4, r_front + 1.4,
                     _shade(colour, 0.7))
        self.ellipse(muzzle[0], muzzle[1], r_front * 0.55, r_front * 0.55, _rgb("ink"))

    def field_carriage(self, cx, base, scale=1.0, tail_right=False) -> None:
        """Two wheels and a trail, the gun's seat on the field."""
        r = 15.0 * scale
        self.wheel(cx - 24.0 * scale, base - r, r)
        self.wheel(cx + 18.0 * scale, base - r * 0.94, r * 0.94)
        # The trail pointing away from the muzzle.
        tail = cx - (54.0 if not tail_right else -44.0) * scale
        self.poly([(cx - 6.0 * scale, base - 26.0 * scale),
                   (tail, base - 2.0), (tail + 8.0 * scale, base - 1.0),
                   (cx + 4.0 * scale, base - 20.0 * scale)], _rgb("wood_dark"))
        # Elevating block under the breech.
        self.poly([(cx - 14.0 * scale, base - 28.0 * scale),
                   (cx + 4.0 * scale, base - 30.0 * scale),
                   (cx + 4.0 * scale, base - 20.0 * scale),
                   (cx - 14.0 * scale, base - 18.0 * scale)], _rgb("wood"))


# --- the roster ---------------------------------------------------------
# One entry per `RegimentCatalog` type: kind, dress, arms and mount. Two
# entries never share a silhouette, so a plate of them can be read at a glance.
KITS = {
    # Light infantry: the unarmoured men, each with his own tool.
    "peasant_levies": {"kind": "foot", "head": "cap", "coat": "coat_russet",
                       "tool": "pitchfork", "ragged": True},
    "calivermen": {"kind": "foot", "head": "morion", "coat": "coat_grey",
                   "tool": "caliver", "rest": True},
    "skirmishers": {"kind": "foot", "head": "wide_hat", "coat": "coat_green",
                    "tool": "rifle", "crouch": True},
    "sharpshooters": {"kind": "foot", "head": "hood", "coat": "coat_green",
                      "tool": "long_rifle", "crouch": True, "quiver": True},
    # Regular infantry: the drill, carried on a different pole each era.
    "pikemen": {"kind": "foot", "head": "morion", "coat": "coat_blue",
                "tool": "pike"},
    "halberdiers": {"kind": "foot", "head": "morion", "coat": "coat_red",
                    "tool": "halberd"},
    "regulars": {"kind": "foot", "head": "shako", "coat": "coat_blue",
                 "tool": "musket", "belts": True},
    "rifle_infantry": {"kind": "foot", "head": "shako", "coat": "coat_green",
                       "tool": "rifle", "belts": True, "plume": "coat_red"},
    # Heavy infantry: the firearm, and the weight behind it.
    "arquebusiers": {"kind": "foot", "head": "morion", "coat": "coat_russet",
                     "tool": "arquebus", "rest": True},
    "musketeers": {"kind": "foot", "head": "wide_hat", "coat": "coat_red",
                   "tool": "musket", "belts": True},
    "grenadiers": {"kind": "foot", "head": "mitre", "coat": "coat_blue",
                   "tool": "musket", "grenade": True, "belts": True},
    "guards": {"kind": "foot", "head": "bearskin", "coat": "coat_red",
               "tool": "musket", "sash": True, "belts": True},
    # Bowmen: the one bow on the field.
    "bowmen": {"kind": "foot", "head": "hood", "coat": "coat_russet",
               "tool": "bow", "quiver": True},
    # Light cavalry: a horseman without armour.
    "squires": {"kind": "horse", "horse": "horse_bay", "head": "cap",
                "coat": "coat_grey", "tool": "sabre"},
    "cossacks": {"kind": "horse", "horse": "horse_black", "head": "fur",
                 "coat": "coat_green", "tool": "spear"},
    "hussars": {"kind": "horse", "horse": "horse_bay", "head": "shako",
                "coat": "coat_green", "tool": "sabre", "plume": "coat_red",
                "sash": True},
    "scouts": {"kind": "horse", "horse": "horse_bay", "head": "wide_hat",
               "coat": "coat_russet", "tool": "carbine"},
    # Spear cavalry: the shock of the charge.
    "knights": {"kind": "horse", "horse": "horse_black", "head": "great_helm",
                "coat": "steel", "tool": "lance", "barding": True, "pennon": "coat_red"},
    "lancers": {"kind": "horse", "horse": "horse_bay", "head": "morion",
                "coat": "coat_blue", "tool": "lance", "pennon": "buff"},
    # Heavy cavalry: cuirass and carbine.
    "harquebusiers": {"kind": "horse", "horse": "horse_grey", "head": "lobster",
                      "coat": "coat_grey", "tool": "carbine", "cuirass": True},
    "cuirassiers": {"kind": "horse", "horse": "horse_black", "head": "lobster",
                    "coat": "coat_blue", "tool": "sabre", "cuirass": True},
    "carbine_cavalry": {"kind": "horse", "horse": "horse_bay", "head": "shako",
                        "coat": "coat_blue", "tool": "carbine", "belts": True},
    # Light artillery: the gun that travels with the line.
    "horse_artillery": {"kind": "gun", "barrel": "light", "scale": 0.88,
                        "team": True},
    "light_artillery": {"kind": "gun", "barrel": "light", "scale": 0.92},
    "field_artillery": {"kind": "gun", "barrel": "field", "scale": 1.0,
                        "gunner": True},
    # Heavy artillery: the train that opens a siege.
    "culverin": {"kind": "gun", "barrel": "culverin", "scale": 1.02},
    "royal_artillery": {"kind": "gun", "barrel": "royal", "scale": 1.08,
                        "crest": True},
    "heavy_artillery": {"kind": "gun", "barrel": "heavy", "scale": 1.12},
    "siege_guns": {"kind": "gun", "barrel": "mortar", "scale": 1.05,
                   "bed": True},
}


def _foot(p: Painter, kit: dict) -> None:
    coat_key = kit["coat"]
    crouch = bool(kit.get("crouch", False))
    hip_y = BASE_Y - (56.0 if crouch else 74.0)
    head_y = hip_y - (30.0 if crouch else 38.0)
    lean = -6.0 if crouch else 0.0
    cx = 142.0

    # Legs first: they sit behind the coat skirt.
    if crouch:
        p.leg((cx - 8.0, hip_y), (cx - 20.0, hip_y + 16.0),
              (cx - 26.0, BASE_Y - 4.0), _shade(coat_key, 0.92), _rgb("leather"))
        p.leg((cx + 4.0, hip_y), (cx + 6.0, hip_y + 26.0),
              (cx + 8.0, BASE_Y - 3.0), _shade(coat_key, 0.92), _rgb("leather"))
    else:
        p.leg((cx - 7.0, hip_y), (cx - 9.0, hip_y + 34.0),
              (cx - 10.0, BASE_Y - 4.0), _shade(coat_key, 0.92), _rgb("leather"))
        p.leg((cx + 6.0, hip_y), (cx + 9.0, hip_y + 34.0),
              (cx + 10.0, BASE_Y - 4.0), _shade(coat_key, 0.90), _rgb("leather"))

    if kit.get("ragged"):
        # A levy's coat is patched and torn at the hem.
        p.coat(cx, hip_y - 22.0, hip_y + 8.0, 26.0, 34.0, _rgb(coat_key))
        for patch in range(3):
            px = cx - 10.0 + float(patch) * 9.0
            p.rect(px, hip_y - 10.0 + float(patch) * 3.0, px + 6.0, hip_y - 3.0,
                   _shade(coat_key, 0.84))
        p.poly([(cx - 17.0, hip_y + 8.0), (cx - 8.0, hip_y + 2.0),
                (cx - 4.0, hip_y + 10.0)], _shade(coat_key, 0.78))
    else:
        p.coat(cx, hip_y - 24.0, hip_y, 28.0, 36.0, _rgb(coat_key))
        p.poly([(cx - 14.0, hip_y - 2.0), (cx + 14.0, hip_y - 2.0),
                (cx + 17.0, hip_y + 2.0), (cx - 17.0, hip_y + 2.0)],
               _shade(coat_key, 0.86))

    # Buff breeches showing under the skirt.
    if not crouch:
        p.rect(cx - 12.0, hip_y, cx + 12.0, hip_y + 8.0, _rgb("buff_dark"))

    shoulder_r = (cx + 12.0, hip_y - 20.0)
    shoulder_l = (cx + 2.0, hip_y - 18.0)

    if kit.get("belts"):
        p.line([(cx - 12.0, hip_y - 18.0), (cx + 13.0, hip_y - 2.0)],
               _shade("buff", 1.05), 2.6)
        p.line([(cx + 12.0, hip_y - 18.0), (cx - 4.0, hip_y - 1.0)],
               _shade("buff", 0.95), 2.6)
        p.ellipse(cx + 1.0, hip_y - 9.0, 2.6, 2.6, _rgb("brass"))

    if kit.get("sash"):
        p.line([(cx - 14.0, hip_y - 12.0), (cx + 10.0, hip_y - 16.0)],
               _rgb("coat_red") if coat_key != "coat_red" else _rgb("brass"), 3.4)
        p.poly([(cx + 10.0, hip_y - 16.0), (cx + 18.0, hip_y - 4.0),
                (cx + 13.0, hip_y + 3.0)], _shade("coat_red", 0.9))

    tool = kit.get("tool", "none")
    if tool in ("pike", "halberd"):
        hand = (cx + 16.0, hip_y - 12.0)
        p.arm(shoulder_r, (cx + 18.0, hip_y - 2.0), hand, _rgb(coat_key),
              cuff=_shade(coat_key, 0.82))
        p.arm(shoulder_l, (cx + 12.0, hip_y - 4.0), (cx + 14.0, hip_y - 14.0),
              _shade(coat_key, 0.94))
        (p.pike if tool == "pike" else p.halberd)(hand)
    elif tool in ("musket", "arquebus", "caliver", "rifle", "long_rifle"):
        if kit.get("rest") and tool == "arquebus":
            # The arquebus on its forked rest: the fork takes the barrel, so
            # the staff reads as one arm with the gun, never a loose stick.
            muzzle = (cx + 42.0, hip_y - 40.0)
            p.musket((cx + 12.0, hip_y - 24.0), muzzle)
            fork = (muzzle[0] - 1.0, muzzle[1] + 2.0)
            p.line([fork, (fork[0] + 2.0, BASE_Y - 6.0)], _rgb("wood"), 2.0)
            p.line([(fork[0] - 3.0, fork[1] - 3.0), fork], _rgb("wood"), 1.8)
            p.line([fork, (fork[0] + 4.0, fork[1] - 3.0)], _rgb("wood"), 1.8)
            p.arm(shoulder_r, (cx + 18.0, hip_y - 12.0), (cx + 24.0, hip_y - 24.0),
                  _rgb(coat_key), cuff=_shade(coat_key, 0.82))
            p.arm(shoulder_l, (cx + 6.0, hip_y - 20.0), (cx + 20.0, hip_y - 30.0),
                  _shade(coat_key, 0.94))
            p.ellipse(cx + 26.0, hip_y - 32.0, 3.2, 4.6, _shade("steel", 0.35))
        elif kit.get("rest") and tool == "caliver":
            muzzle = (cx + 40.0, hip_y - 34.0)
            p.musket((cx + 10.0, hip_y - 22.0), muzzle)
            fork = (muzzle[0] - 1.0, muzzle[1] + 2.0)
            p.line([fork, (fork[0] + 2.0, BASE_Y - 6.0)], _rgb("wood"), 1.8)
            p.line([(fork[0] - 3.0, fork[1] - 3.0), fork], _rgb("wood"), 1.6)
            p.line([fork, (fork[0] + 4.0, fork[1] - 3.0)], _rgb("wood"), 1.6)
            p.arm(shoulder_r, (cx + 20.0, hip_y - 14.0), (cx + 28.0, hip_y - 24.0),
                  _rgb(coat_key), cuff=_shade(coat_key, 0.82))
            p.arm(shoulder_l, (cx + 6.0, hip_y - 20.0), (cx + 22.0, hip_y - 28.0),
                  _shade(coat_key, 0.94))
        elif crouch:
            p.arm(shoulder_r, (cx + 12.0, hip_y - 8.0), (cx + 18.0, hip_y - 16.0),
                  _rgb(coat_key), cuff=_shade(coat_key, 0.82))
            p.arm(shoulder_l, (cx + 4.0, hip_y - 16.0), (cx + 16.0, hip_y - 22.0),
                  _shade(coat_key, 0.94))
            long = 74.0 if tool == "long_rifle" else 62.0
            p.musket((cx + 8.0, hip_y - 12.0), (cx + long, hip_y - 32.0),
                     bayonet=tool == "long_rifle")
        else:
            # Shouldered arms: butt at the hip, muzzle above the shoulder.
            p.arm(shoulder_r, (cx + 16.0, hip_y - 8.0), (cx + 19.0, hip_y - 16.0),
                  _rgb(coat_key), cuff=_shade(coat_key, 0.82))
            p.arm(shoulder_l, (cx + 4.0, hip_y - 16.0), (cx + 14.0, hip_y - 24.0),
                  _shade(coat_key, 0.94))
            p.musket((cx + 13.0, hip_y - 2.0), (cx + 27.0, hip_y - 54.0),
                     bayonet=tool in ("musket", "rifle"))
    elif tool == "bow":
        hand = (cx + 26.0, hip_y - 22.0)
        p.arm(shoulder_r, (cx + 18.0, hip_y - 12.0), hand, _rgb(coat_key),
              cuff=_shade(coat_key, 0.82))
        p.arm(shoulder_l, (cx + 4.0, hip_y - 18.0), (cx + 6.0, hip_y - 26.0),
              _shade(coat_key, 0.94))
        p.bow(hand)
    elif tool == "pitchfork":
        hand = (cx + 14.0, hip_y - 14.0)
        p.arm(shoulder_r, (cx + 16.0, hip_y - 4.0), hand, _rgb(coat_key),
              cuff=_shade(coat_key, 0.82))
        p.arm(shoulder_l, (cx + 4.0, hip_y - 16.0), (cx + 12.0, hip_y - 18.0),
              _shade(coat_key, 0.94))
        p.line([hand, (cx + 20.0, BASE_Y + 1.0)], _rgb("wood"), 2.2)
        p.line([(hand[0], hand[1] + 6.0), (hand[0], hand[1] - 14.0)], _rgb("wood"), 2.0)
        for tine in range(3):
            x = hand[0] - 7.0 + float(tine) * 7.0
            p.line([(x, hand[1] - 2.0), (x, hand[1] - 20.0)], _rgb("steel_dark"), 1.8)
    else:
        p.arm(shoulder_r, (cx + 16.0, hip_y - 8.0), (cx + 18.0, hip_y + 2.0),
              _rgb(coat_key), cuff=_shade(coat_key, 0.82))
        p.arm(shoulder_l, (cx + 4.0, hip_y - 16.0), (cx + 2.0, hip_y - 4.0),
              _shade(coat_key, 0.94))

    # Head and headgear last, so nothing paints over the face.
    p.head(cx + lean, head_y, 8.6, _rgb("flesh"), _rgb("flesh_dark"))
    p.ellipse(cx + lean + 1.0, head_y + 2.0, 3.4, 2.2, _shade("hair", 1.0))
    head = kit.get("head", "cap")
    gear_y = head_y - 4.0
    if head == "cap":
        p.cap(cx + lean, gear_y, _shade(coat_key, 0.9))
    elif head == "wide_hat":
        p.wide_hat(cx + lean, gear_y, _shade("ink", 1.6))
        p.poly([(cx + lean - 12.0, gear_y + 2.0), (cx + lean + 12.0, gear_y + 1.0),
                (cx + lean + 12.0, gear_y + 3.0), (cx + lean - 12.0, gear_y + 4.0)],
               _rgb("brass_dark"))
    elif head == "morion":
        p.morion(cx + lean, gear_y, _rgb("steel"))
    elif head == "shako":
        plume = _rgb(kit["plume"]) if kit.get("plume") else None
        p.shako(cx + lean, gear_y, _shade("ink", 1.5), plume)
    elif head == "mitre":
        p.mitre(cx + lean, gear_y, _shade("ink", 1.5))
    elif head == "bearskin":
        p.bearskin(cx + lean, gear_y, _shade("ink", 1.35))
        p.poly([(cx + lean - 11.0, gear_y - 2.0), (cx + lean + 11.0, gear_y - 2.0),
                (cx + lean + 11.0, gear_y + 2.0), (cx + lean - 11.0, gear_y + 2.0)],
               _rgb("brass"))
    elif head == "hood":
        p.hood(cx + lean, gear_y, _shade(coat_key, 0.86))

    if kit.get("quiver"):
        p.quiver((cx - 14.0, hip_y - 12.0), _rgb("leather"))
    if kit.get("grenade"):
        p.grenade_pouch((cx - 10.0, hip_y + 4.0), _rgb("leather"))


def _horse(p: Painter, kit: dict) -> None:
    horse_key = kit["horse"]
    p.horse(112.0, BASE_Y, horse_key, kit["horse"] + "_dark",
            barding=bool(kit.get("barding")))
    seat = (108.0, BASE_Y - 62.0)
    # Saddle cloth in the rider's coat colour.
    coat = kit["coat"]
    p.poly([(seat[0] - 22.0, seat[1] + 14.0), (seat[0] + 18.0, seat[1] + 12.0),
            (seat[0] + 14.0, seat[1] + 24.0), (seat[0] - 20.0, seat[1] + 26.0)],
           _shade(coat, 0.9))
    # Rider: hips, torso leaning into the charge, near leg over the saddle.
    p.rider_legs(seat, _shade(coat, 0.96), _rgb("leather"))
    torso_top = seat[1] - 26.0
    p.coat(seat[0] + 2.0, torso_top, seat[1] + 4.0, 24.0, 26.0, _rgb(coat),
           skirt=False)
    if kit.get("cuirass"):
        p.poly([(seat[0] - 9.0, torso_top + 2.0), (seat[0] + 12.0, torso_top),
                (seat[0] + 12.0, torso_top + 20.0), (seat[0] - 10.0, torso_top + 22.0)],
               _rgb("steel"))
        p.line([(seat[0] - 8.0, torso_top + 5.0), (seat[0] + 11.0, torso_top + 4.0)],
               _shade("steel", 1.2), 1.4)
    if kit.get("belts"):
        p.line([(seat[0] - 10.0, torso_top + 4.0), (seat[0] + 12.0, torso_top + 16.0)],
               _shade("buff", 1.05), 2.4)
    if kit.get("sash"):
        p.line([(seat[0] - 11.0, torso_top + 14.0), (seat[0] + 11.0, torso_top + 10.0)],
               _rgb("brass"), 3.0)
    # The far arm holds the reins low; the near one carries the weapon.
    p.arm((seat[0] + 10.0, torso_top + 6.0), (seat[0] + 18.0, torso_top + 16.0),
          (seat[0] + 26.0, torso_top + 14.0), _shade(coat, 0.92))
    tool = kit.get("tool", "sabre")
    if tool == "lance":
        hand = (seat[0] + 18.0, torso_top + 10.0)
        p.arm((seat[0] + 4.0, torso_top + 6.0), (seat[0] + 12.0, torso_top + 18.0),
              hand, _rgb(coat))
        pennon = _rgb(kit["pennon"]) if kit.get("pennon") else None
        p.lance(hand, pennon=pennon)
    elif tool == "sabre":
        hand = (seat[0] + 14.0, torso_top - 8.0)
        p.arm((seat[0] + 4.0, torso_top + 6.0), (seat[0] + 10.0, torso_top - 2.0),
              hand, _rgb(coat))
        p.sabre(hand, angle=-0.95, length=40.0)
    elif tool == "carbine":
        p.arm((seat[0] + 4.0, torso_top + 6.0), (seat[0] + 12.0, torso_top - 4.0),
              (seat[0] + 18.0, torso_top - 10.0), _rgb(coat))
        p.musket((seat[0] - 4.0, torso_top + 10.0), (seat[0] + 34.0, torso_top - 16.0))
    else:  # spear
        hand = (seat[0] + 12.0, torso_top - 6.0)
        p.arm((seat[0] + 4.0, torso_top + 6.0), (seat[0] + 8.0, torso_top - 2.0),
              hand, _rgb(coat))
        p.line([(hand[0] - 30.0, hand[1] + 26.0), (hand[0] + 44.0, hand[1] - 34.0)],
               _rgb("wood"), 1.8)
        p.poly([(hand[0] + 40.0, hand[1] - 34.0), (hand[0] + 48.0, hand[1] - 40.0),
                (hand[0] + 46.0, hand[1] - 30.0)], _rgb("steel"))
    # Head and helmet, tilted forward over the horse's neck.
    head_centre = (seat[0] + 8.0, torso_top - 12.0)
    p.head(head_centre[0], head_centre[1], 8.2, _rgb("flesh"), _rgb("flesh_dark"))
    head = kit.get("head", "cap")
    if head == "cap":
        p.cap(head_centre[0], head_centre[1] - 4.0, _shade(coat, 0.86))
    elif head == "fur":
        p.ellipse(head_centre[0], head_centre[1] - 5.0, 10.5, 9.0, _shade("hair", 1.0))
        p.ellipse(head_centre[0], head_centre[1] - 1.0, 11.5, 3.4, _shade("coat_red", 0.8))
    elif head == "wide_hat":
        p.wide_hat(head_centre[0], head_centre[1] - 4.0, _shade("ink", 1.6), brim=15.0)
    elif head == "morion":
        p.morion(head_centre[0], head_centre[1] - 4.0, _rgb("steel"))
    elif head == "lobster":
        p.lobster(head_centre[0], head_centre[1] - 3.0, _rgb("steel"))
    elif head == "shako":
        plume = _rgb(kit["plume"]) if kit.get("plume") else None
        p.shako(head_centre[0], head_centre[1] - 4.0, _shade("ink", 1.5), plume)
    elif head == "great_helm":
        p.ellipse(head_centre[0], head_centre[1] - 3.0, 9.4, 9.0, _rgb("steel"))
        p.line([(head_centre[0] - 7.0, head_centre[1] - 2.0),
                (head_centre[0] + 7.0, head_centre[1] - 3.0)],
               _shade("steel", 0.55), 2.2)
        p.ellipse(head_centre[0] - 2.0, head_centre[1] - 10.0, 9.0, 3.4,
                  _shade("coat_red", 0.9))


def _gun(p: Painter, kit: dict) -> None:
    scale = float(kit.get("scale", 1.0))
    kind = kit["barrel"]
    # A team needs the right of the frame; the gun sits further left for it.
    cx = 96.0 if kit.get("team") else 150.0
    base = BASE_Y
    if kind == "mortar":
        # A mortar squats on its bed and throws high: short, fat, angled up.
        p.poly([(cx - 34.0, base), (cx + 26.0, base), (cx + 22.0, base - 14.0),
                (cx - 30.0, base - 14.0)], _rgb("wood_dark"))
        p.poly([(cx - 24.0, base - 14.0), (cx + 20.0, base - 14.0),
                (cx + 18.0, base - 21.0), (cx - 22.0, base - 21.0)], _rgb("wood"))
        p.barrel((cx, base - 30.0), (cx + 22.0, base - 70.0), 14.0, 10.0)
        p.poly([(cx - 18.0, base - 23.0), (cx + 6.0, base - 23.0),
                (cx, base - 44.0), (cx - 14.0, base - 38.0)], _rgb("steel_dark"))
        return
    p.field_carriage(cx, base, scale)
    if kind == "culverin":
        p.barrel((cx - 26.0 * scale, base - 38.0 * scale),
                 (cx + 54.0 * scale, base - 48.0 * scale), 8.0, 5.5)
    elif kind == "royal":
        p.barrel((cx - 26.0 * scale, base - 42.0 * scale),
                 (cx + 50.0 * scale, base - 48.0 * scale), 12.0, 8.0)
        # The crown's gun: gilt rays cast on the breech.
        p.ellipse(cx - 14.0 * scale, base - 44.0 * scale, 8.0 * scale, 8.0 * scale,
                  _rgb("brass_dark"))
        for ray in range(6):
            angle = math.pi * float(ray) / 5.0
            p.line([(cx - 14.0 * scale, base - 44.0 * scale),
                    (cx - 14.0 * scale + math.cos(angle) * 11.0 * scale,
                     base - 44.0 * scale - math.sin(angle) * 11.0 * scale)],
                   _shade("brass", 1.25), 1.4)
    elif kind == "heavy":
        p.barrel((cx - 28.0 * scale, base - 40.0 * scale),
                 (cx + 46.0 * scale, base - 46.0 * scale), 15.0, 11.0)
    elif kind == "field":
        p.barrel((cx - 24.0 * scale, base - 38.0 * scale),
                 (cx + 46.0 * scale, base - 44.0 * scale), 10.0, 7.0)
    else:  # light
        p.barrel((cx - 22.0 * scale, base - 36.0 * scale),
                 (cx + 40.0 * scale, base - 41.0 * scale), 7.6, 5.2)
    if kit.get("team"):
        # A trace horse at the limber: the flying battery.
        hx = cx + 66.0 * scale
        p.horse(hx, base, "horse_bay", "horse_bay_dark")
        p.line([(cx + 26.0 * scale, base - 20.0 * scale),
                (hx - 34.0, base - 40.0)], _rgb("leather"), 1.6)
    if kit.get("gunner"):
        # A gunner at the trail handspike, sponge over his shoulder.
        gx = cx - 66.0 * scale
        p.leg((gx - 4.0, base - 52.0), (gx - 6.0, base - 24.0), (gx - 8.0, base - 4.0),
              _rgb("coat_blue"), _rgb("leather"))
        p.leg((gx + 5.0, base - 52.0), (gx + 7.0, base - 24.0), (gx + 8.0, base - 4.0),
              _shade("coat_blue", 0.9), _rgb("leather"))
        p.coat(gx, base - 76.0, base - 50.0, 20.0, 22.0, _rgb("coat_blue"))
        p.head(gx, base - 84.0, 7.4, _rgb("flesh"), _rgb("flesh_dark"))
        p.shako(gx, base - 88.0, _shade("ink", 1.5))
        p.arm((gx + 8.0, base - 72.0), (gx + 16.0, base - 60.0),
              (gx + 12.0, base - 46.0), _rgb("coat_blue"))
        p.line([(gx + 12.0, base - 46.0), (gx + 2.0, base - 96.0)],
               _rgb("wood"), 1.6)
        p.ellipse(gx + 1.0, base - 98.0, 3.6, 4.2, _rgb("buff_dark"))


def paint(type_id: str) -> Image.Image:
    kit = KITS[type_id]
    p = Painter()
    kind = kit["kind"]
    if kind == "foot":
        _foot(p, kit)
    elif kind == "horse":
        _horse(p, kit)
    else:
        _gun(p, kit)
    return _finish(p.img)


def _finish(canvas: Image.Image) -> Image.Image:
    """One key light, one brush pass and one ink edge over every sprite."""
    small = canvas.resize((BOX_W, BOX_H), Image.LANCZOS)
    rgb = np.asarray(small).astype(np.float32) / 255.0
    alpha = rgb[..., 3]
    height, width = alpha.shape
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float32)
    # Key light from the upper left, as the plate's own paintings are lit.
    light = 1.14 - 0.26 * (xx / float(width)) - 0.20 * (yy / float(height))
    # A little canvas tooth, so a flat fill reads as paint not vector.
    tooth = _tooth(height, width)
    painted = (alpha > 0.004)[..., None]
    lit = np.clip(rgb[..., :3] * light[..., None] * tooth[..., None], 0.0, 1.0)
    rgb[..., :3] = np.where(painted, lit, 0.0)
    out = (rgb * 255.0).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    # Ink edge: the silhouette grown by a pixel and dropped underneath. It is
    # what keeps a 20 px miniature legible on a painted field.
    mask = img.split()[3].point(lambda v: 255 if v > 40 else 0)
    grow = mask.filter(ImageFilter.MaxFilter(3))
    edge = Image.new("RGBA", img.size, (18, 14, 11, 0))
    edge.putalpha(grow.point(lambda v: int(v * 0.62)))
    plate = Image.new("RGBA", img.size, (0, 0, 0, 0))
    plate.alpha_composite(edge)
    plate.alpha_composite(img)
    box = plate.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        raise RuntimeError("nothing painted")
    cropped = plate.crop(box)
    # One scale for the whole set, measured off a standing foot figure: a gun
    # stays lower than a man and a horseman taller, as real miniatures do.
    scale = float(HEIGHT) / REFERENCE_FIGURE
    return cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.LANCZOS,
    )


def _tooth(height: int, width: int) -> np.ndarray:
    """Smoothed value noise around 1.0: the weave of the canvas."""
    rng = np.random.default_rng(7)
    coarse = rng.normal(0.0, 1.0, (max(2, height // 5), max(2, width // 5)))
    noise = np.asarray(
        Image.fromarray(((coarse * 32.0) + 128.0).clip(0, 255).astype(np.uint8), "L")
        .resize((width, height), Image.BICUBIC)
    ).astype(np.float32)
    noise = (noise - 128.0) / 128.0
    return 1.0 + noise * 0.045


def sheet(images: dict, dest: Path) -> None:
    """A contact sheet, five across, so the whole set can be reviewed at once."""
    cols = 5
    cell_w, cell_h = 200, 230
    zoom = 0.9
    rows = (len(images) + cols - 1) // cols
    out = Image.new("RGB", (cols * cell_w, rows * cell_h), (58, 52, 44))
    draw = ImageDraw.Draw(out)
    for index, (type_id, img) in enumerate(images.items()):
        col, row = index % cols, index // cols
        shown = img.resize(
            (max(1, round(img.width * zoom)), max(1, round(img.height * zoom))),
            Image.LANCZOS,
        )
        x = col * cell_w + (cell_w - shown.width) // 2
        y = row * cell_h + (cell_h - shown.height) - 10
        out.paste(shown, (x, y), shown)
        draw.text((col * cell_w + 8, row * cell_h + 4), type_id, fill=(232, 220, 190))
    out.save(dest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", type=Path)
    parser.add_argument("--sheet", default="", help="also write a contact sheet here")
    parser.add_argument("--only", default="", help="one type id, for a replacement")
    args = parser.parse_args()
    dest = args.root / "assets" / "art" / "battle" / "regiments"
    dest.mkdir(parents=True, exist_ok=True)
    painted: dict[str, Image.Image] = {}
    for type_id in KITS:
        if args.only and type_id != args.only:
            continue
        img = paint(type_id)
        img.save(dest / f"{type_id}.png", optimize=True)
        painted[type_id] = img
        print(f"{type_id}.png {img.size}")
    if args.sheet and painted:
        sheet(painted, Path(args.sheet))
        print(f"sheet {args.sheet}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())