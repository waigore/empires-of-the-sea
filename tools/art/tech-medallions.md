# Tech medallion plates (fal.ai)

Every researched advance shows a medallion in the college ledger. The plates
live in `assets/art/tech/` and belong to the same family as the shell icons
(`tools/art/shell-icons.md`): thick beveled brass ring, dark espresso field,
top-left light, one object sculpted in polished brass.

## One frame, many objects

The frame is never generated. `assets/art/icons/ledger.png` is cleared to an
empty field (the inner disc filled with the sampled field colour and a slight
radial gradient, feathered into the ring shadow) and kept as the base. Only the
central object is generated, then keyed and pasted onto that base, so all 48
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
the model keeps painting the open book behind the new object.

## Post

1. Key magenta dominance, not one hex: `alpha = 1 - (min(r,b) - g) / 0.10`,
   clamped — the sheet's magenta varies with lighting.
2. Inside the ring, key the dark field out by luminance:
   `alpha *= clamp((luma - 0.150) / 0.15, 0, 1)`, which leaves the brass object
   and its bronze shadows and drops the field.
3. Despill translucent texels toward green, crop to the alpha bounds, fit inside
   **0.70 × 128 px** (0.58–0.66 for wide or tall objects), add a soft dark
   shadow, composite onto the blank medallion, save 128×128 RGBA.
4. Import with `mipmaps/generate=true`, lossless, matching the shell icons.

## Plates

`scripts/ui/tech_icons.gd` maps each tech id to a plate; a chain shares one
plate, and a long chain may grow a grander later plate (`seed_drill`,
`circular_saw`, `safety_lamp`, `amalgamation`, `scouting`, `riverboats`).
`test_research_rules.gd` fails when a catalog tech has no plate or a plate file is
missing.

Six plates reuse an existing shell medallion object unchanged — `empire`
(crown), `money` (coin), `ship_of_line` (ship), `iron_weapons` (swords),
`navigation` (globe), `press` (gazette) — because the icon already draws exactly
that object on the same frame.

## Object prompts

One line per generated plate; the tail above follows `[object]`.

| Plate | `[object]` |
|-------|------------|
| `amalgamation` | a glass retort flask with a long condensing pipe and droplets |
| `cattle` | a bull's head facing forward with broad curved horns |
| `cavalry` | a curved cavalry sabre crossed with a plumed dragoon helmet, both clearly separated |
| `circular_saw` | a large circular saw blade with sharp teeth mounted on an arbour |
| `clipper` | a clipper ship with tall raked masts under full sail, side view |
| `coal` | a heap of rough coal lumps with a pickaxe standing in them |
| `copper_tin` | a stack of three plain chunky trapezoid metal ingots, one on top of another, with a pickaxe head resting across the top ingot |
| `cotton` | an open cotton boll with a spool of thread |
| `crucible` | a crucible pouring molten metal into an ingot mould beside a cogwheel |
| `diplomacy` | a rolled scroll with a wax seal and a quill laid across it |
| `dynamite` | three sticks of dynamite bound together with a fuse and a spark |
| `field_gun` | a field cannon on a wheeled carriage with a rammer |
| `fields` | a sheaf of ripe wheat standing in a freshly ploughed furrow |
| `fort` | a star-fort bastion with embrasures, seen from above at an angle |
| `furs` | a rolled bundle of two fur pelts tied with a leather thong, the fur sculpted as tufted brass strands, one pelt unrolling at the side |
| `gems` | a cluster of cut gemstones: one large brilliant-cut stone with two smaller ones |
| `gold` | a cluster of raw gold nuggets with two coins beside them |
| `horse` | a horse's head in profile with a flowing mane |
| `hull` | a wooden ship's ribbed hull frame under construction, the full hull visible from keel to gunwale with a mast step in its centre |
| `iron_mining` | a miner's pickaxe crossed with a lump of iron ore |
| `iron_ship` | the riveted iron bow of a steamship with an anchor on its plate |
| `mine_timbering` | a mine shaft headframe built from squared timber beams over a dark shaft |
| `military_funding` | a strongbox of coins with a cannon barrel laid across its lid |
| `paddlewheel` | a paddle steamer with a big side paddle wheel and a smokestack |
| `propaganda` | a herald's trumpet with a hanging banner and a laurel wreath |
| `regiments` | three muskets with bayonets stacked upright in a tripod |
| `rifles` | an eighteenth-century flintlock musket with a long barrel, wooden stock and a fixed bayonet, side view, historical firearm only |
| `riverboats` | a stern-wheel riverboat with a tall smokestack |
| `road` | a stretch of rough cobbled causeway with a stone milestone standing at its edge, hand-laid stones, no painted lines, no asphalt |
| `safety_lamp` | a miner's safety lamp with a wire gauze cylinder around a small flame |
| `sawmill` | a long saw blade cutting down through a squared timber log |
| `scouting` | a single brass spyglass with three sliding tubes, extended diagonally, no stand and nothing else |
| `seed_drill` | a simple horse-drawn seed drill: a wooden hopper box on two large spoked wheels with three iron coulters beneath, side view, every part clearly separated |
| `sheep` | a ram's head in profile with a heavy curled horn |
| `spices` | a cluster of spice pods, a star anise and a cinnamon quill |
| `steam_engine` | a stationary beam steam engine: a riveted vertical boiler beside one large spoked flywheel with a connecting rod, every part clearly separated |
| `steam_mining` | a vertical steam pump engine with a boiler, beam and flywheel |
| `sugar` | three stalks of sugar cane bound together with a cord |
| `tobacco` | two cured tobacco leaves laid across each other with a small neat stack of three rolled cigars beside them |
| `trade_fairs` | a merchant's balance scales above a stack of bound trade bales |
| `university` | a domed scholars' tower with a laurel wreath hung across it |
| `workshop` | a smith's hammer crossed with a pair of pincers above an anvil |

## Regenerating

No build script owns these files: a replacement plate goes into
`assets/art/tech/` by hand with the recipe above, and its object prompt belongs
in the table above so the next replacement stays in the same family.

