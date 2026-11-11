# Commodity medallions (fal.ai)

Every good in `CommodityCatalog` shows its own medallion wherever the ledger,
the market tab or the province dossier names it. The plates live in
`assets/art/goods/` and belong to the same family as the shell icons
(`tools/art/shell-icons.md`) and the tech plates (`tools/art/tech-medallions.md`):
thick beveled brass ring, dark espresso field, top-left light, one subject
sculpted in polished brass.

## One frame, many subjects

The frame is never generated. `assets/art/icons/ledger.png` is cleared to an
empty field (the inner disc filled with the sampled field colour and a slight
radial vignette, feathered into the ring shadow) and kept as the base. Only the
central subject is generated, then keyed and pasted onto that base, so all 27
plates share the exact ring, field, vignette and lighting.

## Prompt

Reference: the blank medallion. FLUX Kontext (`fal-ai/flux-pro/kontext`) at
1024², then keyed down to 128².

> A single **[object]**, sculpted in polished brass with warm gold highlights
> and deep bronze shadows, lit from the upper left, rendered in exactly the same
> glossy metallic style as the gold ring of the reference medallion. Centred,
> one object only, a bold simple silhouette that stays legible when small, no
> open book, no pages, no ring, no frame, no text, no lettering. Isolated on a
> solid pure magenta #FF00FF background.

Keep "no open book": the base is edited from `ledger.png`, so without that ban
the model keeps painting the open book behind the new subject.

## Post

1. Key magenta dominance, not one hex: `alpha = 1 - (min(r,b) - g) / 0.10`,
   clamped — the sheet's magenta varies with lighting.
2. Key the dark field out by luminance too:
   `alpha *= clamp((luma - 0.150) / 0.15, 0, 1)`.
3. Pull every subject hue into the family's brass band (hue → 0.095 ± 0.035,
   saturation ≤ 0.88) with luminance untouched: the model renders a gem, a
   silver goblet or a steel billet with a red or clay cast, and an off-hue plate
   reads as a different set. No plate is recoloured by hand.
4. Despill translucent texels toward green, crop to the alpha bounds, fit inside
   0.56–0.64 × 128 px (wide or tall subjects take the smaller figure), add a
   soft dark shadow, composite onto the blank medallion, save 128×128 RGBA.
5. Import with `mipmaps/generate=true`, lossless, matching the shell icons.

## Wiring

`scripts/ui/commodity_icons.gd` loads a plate per catalog id (`badge()` for a
row, `cell()` for a fixed-width name column). It returns `null` for an unknown
good and a same-size gap for a missing file, so one absent plate leaves a hole
instead of collapsing a row. `test_commodity_icons.gd` fails when a catalog id
has no plate or a plate file is missing.

## Object prompts

One line per plate; the tail above follows `[object]`.
`tools/art/goods_icons.py` reads this table (it is the only record of what each
plate depicts), so keep the id and the row shape intact.

| Plate | `[object]` |
|-------|------------|
| `grain` | A single sheaf of ripe wheat stalks bound with a twisted cord, the ears fanned at the top, three stalks only, |
| `meat` | A plump cured ham joint lying on its side with the pale bone end sticking out at the left and a net of crossed string over its rind, no hanging loop, no hook, no cord, |
| `wool` | A soft rounded bale of raw wool fleece with a cord tied around it, tufted fleece texture, no coil, no spool, no pipe, no metal tube, |
| `horses` | A horse's head in profile facing left with a short cropped mane and a plain bridle with a ring, |
| `timber` | Two rough sawn logs stacked, the near end of the top log showing growth rings and a bark edge, |
| `iron` | A single rough chunk of iron ore with jagged facets and one broken bright metallic face, |
| `copper` | A coil of thick copper wire seen from the side, one end unspooling outward, |
| `tin` | Two chunky wedge-shaped tin ingots, one stacked across the other, flat hammered tops, |
| `coal` | A heap of rough coal lumps filling a small wooden scuttle bucket with an arched handle, |
| `sugarCane` | Three thick sugar cane stalks bound together with a cord, the cut ends showing fibrous rings, |
| `tobacco` | Three broad cured tobacco leaves hung from a cord by their stems, ragged dry edges, |
| `cotton` | An open cotton boll on a short stem with two leaves, its white fluff sculpted as soft brass wool, |
| `furs` | A rolled fur pelt tied with a leather thong, the bushy tail hanging at one side, |
| `lumber` | A bundle of three sawn planks stacked flat and bound with a cord, the plank ends facing the viewer, |
| `castIron` | A squat three-legged cast-iron cooking pot with a swing handle over its rim, |
| `fabric` | A rolled bolt of plain cloth with two folds spilling out at the side, no pattern or print, |
| `refinedSugar` | A tall sugar loaf cone wrapped in paper at its base, the paper torn open at one corner, |
| `cigars` | Three rolled cigars bundled with a paper band, one drawn forward, their cut ends visible, |
| `furHats` | A tall beaver top hat with a wide curled brim and a rounded crown, side view, crown and brim brightly lit with polished highlights, no band, no feather, no sewing spool, no needle, no thread, |
| `steel` | Three long square steel bars standing upright in a tight bundle bound with a thin iron strap, bright polished faces with chamfered edges, no brick, no clay, |
| `paper` | A stack of four loose foolscap sheets with one corner curled up and a small folded leaf on top, |
| `bronze` | A bronze hand bell standing upright, moulded handle on top, flared mouth downward with a small clapper visible at the rim, a raised band around its waist, |
| `gold` | A small heap of thick gold coins with one coin standing upright on its edge, |
| `silver` | A single silver goblet with a rounded bowl, a slim stem and a broad foot, a moulded rim, no coins, |
| `gems` | A heap of five cut gemstones, one large oval faceted stone in front, |
| `diamonds` | A single large brilliant-cut diamond standing on its point, every facet polished brass with no colour, no ring, no band, no jewellery setting, |
| `spices` | An open wooden spice box with three neat mounds of ground spice inside, one cinnamon quill and a star anise lying beside it, no lid, |

## Regenerating

```sh
python3 tools/art/goods_icons.py --generate <sheet-dir>   # needs FAL_KEY
python3 tools/art/goods_icons.py <sheet-dir> .
```

The first pass writes one magenta sheet per id; the second keys, tones, fits and
composites them onto the blank medallion. Review the 27 plates as contact sheets
at 128 px and at 22–24 px on the panel colour before committing: a subject that
turns into a blob or an off-hue object is fixed by rewriting its row here and
re-running both passes, never by hand-painting the PNG.
