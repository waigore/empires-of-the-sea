# Map symbols (fal.ai)

The chart's trees, peaks, hills, dunes, fields, reeds, hamlets, citadel, anchor,
hull and estate marks are generated art (`assets/art/map`), drawn by
`MapSymbols` and scaled by `MapCanvasPlan`; `MapGlyphs` keeps the ink fallback
for a build without imported art. Everything used `image_generate` (FLUX) with
the map screen as the style reference. Keep the prompts here so a replacement
stays in the family.

## Base prompt

> One single antique map symbol: **<subject>**. Hand-painted 17th-century atlas
> cartography with poster-like simplification and **STRONG VALUE CONTRAST**:
> flat washes only, the shadowed side nearly as dark as the ink, the whole
> silhouette enclosed in one dark sepia ink line of varying weight, a few short
> hatched strokes for form. No gradient, no airbrush, no soft edge, no
> speckling. The stamp must read as a clear dark shape on pale parchment at
> 20 pixels. Cut-out sprite floating alone in the middle of a perfectly flat
> solid pure magenta #FF00FF background. No ground, no shadow, no halo, no
> plate, no border, no frame, no text, no watermark.

Two lessons from the pass that produced the current set:

- A soft watercolour wash looks right at 128 px and vanishes at 20 px. The
  silhouette has to be inked and the shadow side has to be dark.
- FLUX adds ornaments nobody asked for: a cupola on a hill, a pale headland
  around a field. Name the forbidden object in the prompt ("nothing stands on
  the hill", "no cream edge") and check the render before keying it.

| File | Subject | Variant |
|------|---------|---------|
| `tree.png` | broadleaf oak, lobed crown, two greens | `tree_b` tall narrow crown, `tree_c` wide low crown |
| `conifer.png` | slender pine, three tiers | shared with `scrub` |
| `mountain.png` | twin snow-capped peaks | `mountain_b` single peak, `mountain_c` three-summited massif |
| `hill.png` | three overlapping grassy humps | `hill_b` one wide two-shouldered ridge |
| `dune.png` | crescent dune, two crests | — |
| `field.png` | ploughed wedge, four furrow grooves | — |
| `reed.png` | reed clump, three cattail heads, water lines | — |
| `grass.png` | three meadow tufts | — |
| `town.png` | three cottages, terracotta roofs | — |
| `capital.png` | walled citadel, four towers, keep | — |
| `port.png` | iron anchor with rope | — |
| `ship.png` | three-masted carrack under sail | drawn at 256 px, keel on the waterline |
| `work_wood.png` | stack of felled logs | estate mark |
| `work_mine.png` | pick and mallet over a rock mound | estate mark |
| `work_riches.png` | stack of three gold coins | estate mark |
| `work_grain.png` | tied sheaf of wheat | estate mark |

## Post

`python3 tools/art/map_symbols.py <source-dir> <project-root> [--only kind]`
owns the shipped files:

1. **Global chroma key**, not a corner flood fill: `alpha` ramps to 0 where
   `min(r, b) - g > 48`. Generated foliage encloses magenta gaps that a flood
   fill leaves opaque pink.
2. Despill `b = min(b, g)`, trim to the alpha bounds and pad square with a 6 %
   margin so every stamp shares one origin.
3. **Grade into the chart**: `ImageEnhance.Color(0.82)`, multiply by warm paper
   `#F6EEDE`, then `Contrast(1.18)` — the paper multiply flattens the value
   range the silhouette needs. Settlements and the anchor take a deeper paper
   (`#E8DECC`) because their pale walls otherwise read as white stickers.
4. Resize to 128 px (ship 256), Lanczos, with `mipmaps/generate=true` so the
   draw at 12–22 world px does not alias.

## Placement

`MapCanvasPlan` scatters scenery by terrain. Woods, scrub, hills and mountains
grow in **clusters**: a tile that clears its chance seeds two to four marks
around one centre, and every mark is checked against the terrain under it, so a
grove stops at the coast and a ridge never spills onto plains. `MapSymbols`
reuses `MapCanvasPlan`'s size and flip, adds a position-hashed variant, a small
turn and tone on scenery and a soft ink shadow, so a province never repeats one
stamp. The capital flies its owner's pennant over the painted keep; a fleet
keeps the crown's pennant at the mainmasthead.

Estate marks (`work_*`) are drawn by `LandWorksPaint` on a developed tile, with
the ink glyph as the fallback. Civilian markers are **not** painted: at 27 px a
painted emblem turns to mud, so `CivilianMarker` draws the crew medallion's
trade in ink (spyglass, hammer and saw, arch bridge, hood, scales, rail) inside
a parchment disc with the crown's ring.
