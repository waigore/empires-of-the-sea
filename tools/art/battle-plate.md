# Battlefield plate assets (fal.ai)

The Quick Battle plate used to be painted entirely in code — flat colour bands
for ground, rectangles for men. It is now generated art: one painted panorama
per terrain, plus cut-out wall segments, miniatures and breach rubble that the
view composites and animates (`scripts/ui/battle_plate.gd`).

Everything is made with `image_generate` (FLUX). Keep the prompts here so a
replacement plate stays in the same period, light and composition.

## Panoramas — `ground_<terrain>.jpg` (1600×900)

Prompt skeleton (fill the place clause per terrain):

> Wide cinematic oil painting on aged canvas of <place>, circa 1650.
> Composition: the horizon line sits exactly 60 percent down from the top edge;
> the sky occupies the upper 60 percent, the empty ground the lower 40 percent.
> <ground: what the field looks like>. <distance: treeline / hills / town>.
> <sky and light>. Painted in the manner of 17th-century Dutch landscape
> masters: visible brushwork, glazed shadows, muted <palette>. No people, no
> soldiers, no horses, no cannons, no buildings, no tents, no text, no
> signature, no watermark, no frame, no contrails, no straight scratches in the
> sky. Keep the centre calm and uncluttered.

| Terrain | Place clause |
|---------|--------------|
| open | an open European battlefield at late golden hour: tussocky meadow grass, a trodden dirt track, low hazy treeline, low sun on the right |
| hill | a hillside battlefield on the outskirts of a town: a grassy slope, hawthorn scrub, whitewashed houses with red roofs and a church spire in the middle distance |
| woods | a wooded battlefield edge in northern Europe: a clearing of trampled grass and leaf litter between ancient oaks, shafts of sun through the canopy |
| town | the open ground before a walled town: a cobbled approach, hay bundles, and a run of 17th-century town houses with a tall spire above them |
| marsh | marshland in the Low Countries: reed beds, standing water, drowned willows, a decayed causeway, silver light and low mist |

Post: crop the top 8 % where a sky is otherwise empty, resize to 1600×900,
JPEG q90 (a PNG plate costs 2 MB each). Each panorama records the horizon
fraction of *its own* painting in `BattlePlate.PLATES`; the view cover-fits the
image and pins that line to the plate's horizon, so a wide 5:1 overlay and a
tall simulator both stand the armies on the painted field.

## Cut-outs — `soldier.png`, `cannon.png`, `horse.png`, `rubble.png`

> One single <subject>, painted miniature style like a 17th-century oil
> painting: <materials>. Isolated single object, complete and centred, on a
> solid uniform pure magenta background (#FF00FF), no shadows on the
> background, crisp clean silhouette edges, no ground, no text, no frame.

Subjects: a musketeer standing side profile facing right (full body, hat to
boots, musket at his side); a field gun on its carriage, barrel right; a
cavalryman on a galloping horse, sword raised; a heap of fallen grey masonry
with splintered planks at a gate.

Key with `tools/art/battle_plate.py`: the backdrop is sampled from the border
and the cut-out alpha comes from "magenta-ness" (`min(r, b) - g`), with a
despill pass on the edge. Crop to the alpha bounds, then scale by height —
320 px for figures, 256 px for rubble.

## Wall segments — `wall_wood.png`, `wall_stone.png`, `wall_modern.png`

> One section of a <wooden palisade / stone curtain wall / bastioned brick
> rampart> seen dead-on, roughly four units wide by three units tall, filling
> the frame edge to edge: <detail>, one central gatehouse with a closed arched
> timber gate. Painted in the style of a 17th-century oil painting, muted
> period palette. Isolated object on a solid uniform pure magenta background
> (#FF00FF): no ground, no grass, no sky, no figures, no cannon, no shadow on
> the background, crisp clean edges, no text, no frame.

The gate sits at the segment's centre, which is where `BattlePlate.draw_wall`
puts each of the three gates — the same three the rules breach. Segments are
drawn once, the garrison is drawn over them, then the top 15 % of the segment
is painted again over the men so the defenders stand behind their merlons.

## Regiment miniatures — `regiments/<type_id>.png` (200 px tall)

One painted sprite per land regiment type in `RegimentCatalog` (29 of them), so
a formation shows its composition: a file of musketeers, a block of pikes, a
rider, a gun. Painted, not rendered — `tools/art/regiment_miniatures.py` draws
them all with one palette, one key light (upper left), one canvas tooth and one
ink edge, so the set is one hand by construction.

```bash
python3 tools/art/regiment_miniatures.py . --sheet /tmp/mini.png
```

Each kit in `KITS` picks the body (foot, horse, gun), the headgear, the coat
colour and the arm: `pike`, `halberd`, `musket`, `rifle`, `bow`, `sabre`,
`lance`, `carbine`, plus the gun's barrel (`culverin`, `royal`, `heavy`,
`field`, `light`, `mortar`). Two entries never share a silhouette.

The sprites are painted on **one scale**, measured off a standing foot figure
(`RegimentMiniatures.FIGURE_HEIGHT = 200`): a gun is drawn lower than a man and
a rider taller, and the view scales every type by the foot soldier's height, so
relative sizes survive onto the plate. Faction colour is a tint in the view, so
the art itself stays neutral.

The plate groups the line by type, stands each regiment as its own miniature
and prints the composition under the line (`RegimentMiniatures.caption`), in
the blocks' own order. A type with no art falls back to `soldier.png`.

## Import

Mipmaps on for all of them (`mipmaps/generate=true`): the plate is drawn far
smaller than the source in the simulator and larger in the map overlay.


## Verify

```bash
tools/run.sh scenes/battle_sim.tscn        # the plate in the dev screen
godot --path . -s tests/battle_field_shot.gd -- terrain=town fort=2 gates=1
godot --path . -s tests/quick_battle_shot.gd -- terrain=open fort=1
```
