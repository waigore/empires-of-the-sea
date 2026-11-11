# Map symbols (fal.ai)

The chart's trees, peaks, hills, dunes, fields, reeds, hamlets, citadel, anchor
and hull are generated art (`assets/art/map`), drawn by `MapSymbols` and scaled
by `MapCanvasPlan`; `MapGlyphs` keeps the ink fallback for a build without
imported art. Everything used `image_generate` (FLUX) with the map screen as the
style reference. Keep the prompts here so a replacement stays in the family.

## Base prompt

> One single antique map symbol: **<subject>**. Hand-painted 17th-century atlas
> cartography style: watercolour wash over fine sepia ink linework, muted
> <palette>, crisp dark sepia ink outline, soft light from the upper left, bold
> simple silhouette that still reads when shrunk to 20 pixels. Cut-out sprite
> floating alone in the middle of a perfectly flat solid pure magenta #FF00FF
> background. No ground, no shadow, no halo, no plate, no border, no frame, no
> text, no watermark.

Small stamps carry **POSTER-LIKE SIMPLIFICATION**: two or three flat colours,
one thick outline, no hatching, no dithering, no gradient. Fine engraving is
what turns to mud at 12–22 px.

| File | Subject | Variant |
|------|---------|---------|
| `tree.png` | broadleaf oak, round crown, two greens | `tree_b` tall narrow crown, `tree_c` wide low crown |
| `conifer.png` | slender pine, three tiers | shared with `scrub` |
| `mountain.png` | twin snow-capped peaks | `mountain_b` single peak, `mountain_c` three-summited massif |
| `hill.png` | low rounded grassy hill | `hill_b` two-shouldered ochre hill |
| `dune.png` | crescent dune, two crests | — |
| `field.png` | ploughed patch, furrow bands | — |
| `reed.png` | three marsh reeds, brown heads | — |
| `grass.png` | three meadow tufts | — |
| `town.png` | three cottages, terracotta roofs | — |
| `capital.png` | walled citadel, four towers, keep | — |
| `port.png` | iron anchor with rope | — |
| `ship.png` | three-masted carrack under sail | drawn at 256 px, keel on the waterline |

## Post

1. **Global chroma key**, not a corner flood fill: `alpha` ramps to 0 where
   `min(r, b) - g > 48`. Generated foliage encloses magenta gaps that a flood
   fill leaves opaque pink.
2. Despill `b = min(b, g)`, trim to the alpha bounds and pad square with a 6 %
   margin so every stamp shares one origin.
3. **Grade into the chart**: `ImageEnhance.Color(0.82)` then multiply by warm
   paper `#F6EEDE`; settlements and the anchor take a deeper paper
   (`#E8DECC`) because their pale walls otherwise read as white stickers.
4. Resize to 128 px (ship 256), Lanczos, with `mipmaps/generate=true` so the
   draw at 12–22 world px does not alias.

`MapSymbols` reuses `MapCanvasPlan`'s size and flip, adds a position-hashed
variant, a small turn and tone on scenery and a soft ink shadow, so a province
never repeats one stamp. The capital flies its owner's pennant over the painted
keep; a fleet keeps the crown's pennant at the mainmasthead.
