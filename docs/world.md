# World: Great Powers, Minors and Tribes

Two-region world, faction types, political map (wiki:
[factions](https://github.com/waigore/empires-of-the-sea/wiki/factions),
[game-setup](https://github.com/waigore/empires-of-the-sea/wiki/game-setup),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology)).
**Pillars:** P2, P1, P3.

## Factions

Minors track the strongest Great Power's regiment era; Tribes stay level 1.

| Type | Count | Region | Orders | Navy | Can win | Capital |
|------|------:|--------|:------:|:----:|:-------:|---------|
| Great Power | 6 | Old World (+ New later) | yes | yes | yes | sea-bound choice |
| Minor Nation | 6 | Old World only | no | no | no | setup |
| Tribe | 10 | New World only | no | no | no | setup |

## Regions

- One deterministic tile map per region; a seed reproduces both. Presets cascade
  in area (Small `84×56` / Standard `96×64` / Large `128×84`), province counts
  fixed; Standard sits in the wiki's 30–40 tiles/province band (#700).
- Old World: temperate, 60 provinces for 6 GPs + 6 Minors — Minor 3 each.
  New World: wetter, 30 provinces for 10 Tribes; 3 each.
- `WorldMap` holds both grids. No adjacency across regions; **warp zones**
  (one edge sea zone per side) pair 1:1, marked “Passage”; fleets cross.
- A sea zone wears its water, not pool order (naming § Sea zones,
  DR-20261113-07).
- **Resources:** `ResourceSeeder` fills **30% of region land** — every forest
  cell always, the rest by `1/price` weight, a slice per province
  (DR-20261115-16).
- Region button swaps canvas, fog, fleets, civilians, works and camera.

## Setup post-pass

`WorldBootstrap` builds the capital-choice works (ports, harbour roads), levels
capital towns to 4 and seats four road-wired L1 grain farms per Great Power
(wiki: capital-and-connectivity).

## Ownership

`territory_assignment` grows each faction from one seed on one P–P continent,
so holdings stay contiguous. A bought tile is a **deed**: `TileOwnership`
overrides its owner while the province stays with the seller.

- Seeds are farthest-point sea-bound provinces (GPs and Tribes must own one).
- Minors take 3 each (the wiki floor); the rest splits across the GPs.
- GPs use the capital-choice phase; Minors/Tribes take any owned province.
- `capital_loss` re-seats a captured crown at its first seaboard province (else
  inland); with none left it falls, holdings to the conqueror
  ([DR-20261109-02](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261109-02)).

## Borders on the map

`country_borders` derives owner boundaries from the grid; `MapOverlay` draws
them **above fog** as engraved shadow plus owner colour; terrain and minimap
carry tint.

The ground keeps its terrain under the crown's wash (`REQ-P1-03`): an owned tile
is half-washed toward its crown, so `Palette.TERRAIN_COLORS` is set deep enough
that every pair stays `TERRAIN_GAP` apart once tinted. Woods lay a **grove** per
tile — `MapGrove` rings companions around a crown tree, one more when the tile
is walled by the same wood — so a wood thickens inland, not as loose specks.

## Campaign length

**Historical** halts after turn 201 (1800); **endless** runs to a military win.
An undecided cap reads “Campaign complete”, naming the strongest crown, a tie
naming no-one (`TurnTime`, `VictoryRules`, `MapPlayCampaign`).

## Tests

`test_generated_world_rules`, `test_country_borders`, `test_map_view_rules`,
`test_map_screen`, `test_campaign_end`, `test_campaign_rules`.

```bash
gd-tools test --coverage --min 80
```
