# World: Great Powers, Minors and Tribes

Two-region world setup, faction types and the political map (wiki:
[factions](https://github.com/waigore/empires-of-the-sea/wiki/factions),
[game-setup](https://github.com/waigore/empires-of-the-sea/wiki/game-setup),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology)).

**Pillars:** P2 (setup fidelity), P1 (legible political map), P3 (pure rules).

## Factions

| Type | Count | Region | Orders | Navy | Can win | Capital |
|------|------:|--------|:------:|:----:|:-------:|---------|
| Great Power | 6 | Old World (+ New later) | yes | yes | yes | sea-bound choice |
| Minor Nation | 6 | Old World only | no | no | no | setup |
| Tribe | 10 | New World only | no | no | no | setup |

Minors track the strongest Great Power's regiment era; Tribes stay at level 1.
Ids: `scripts/rules/faction_catalog.gd`.

## Regions

- One deterministic tile map per region; a seed reproduces both maps and all
  ownership.
- Old World: temperate, 60 provinces for 6 GPs + 6 Minors; each Minor takes
  3, the rest splits across the GPs.
- New World: wetter, 30 provinces for 10 Tribes, 3 each.
- `WorldMap` holds both grids. Regions share no grid adjacency; **warp zones**
  (one edge sea zone per side) pair 1:1, marked “Passage”; fleets cross to the
  other world.
- The region button swaps canvas, fog, fleets, civilians, works and camera
  bounds. Rosters persist per region; every region advances each turn. Chips are
  empire totals; squadrons stay where provinces are held.

## Setup post-pass

After capitals are fixed, `WorldBootstrap` turns the capital-choice plan into
real works (ports, harbour roads), sets capital town development to 4 and
places four L1 grain farms per Great Power on plains (thin sites levelled),
wired to the seat by road (wiki: capital-and-connectivity).

## Ownership

`scripts/rules/territory_assignment.gd` grows each faction from one seed inside
a single P–P continent so holdings stay contiguous. A purchased tile is a
**deed**: `TileOwnership` overrides its owner while the province stays with the
seller.

- Seeds are farthest-point sea-bound provinces (GPs and Tribes must own one).
- Minors take 3 each (the wiki floor); the rest splits across the GPs.
- GPs use the capital-choice phase; Minors/Tribes take any owned province.

## Capital loss

`scripts/rules/capital_loss.gd` re-seats a captured crown at its first seaboard
province (else inland); a crown with none left falls and its holdings pass to
the conqueror. Wiki: [DR-20261109-02](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261109-02).

## Borders on the map

`scripts/map/country_borders.gd` derives owner boundaries from the tile grid.
`MapOverlay` draws them **above fog** (`FogLayer` holds fog) as engraved
shadow plus owner colour. Province hairlines stay beneath; terrain and minimap
carry owner tint.

## Campaign length

Setup offers a **historical** campaign (default: stops after turn 201, year 1800)
or an **endless** one (military victory only). At the cap an undecided age
halts; the plate reads “Campaign complete” with the strongest crown by power
score — a tie names no-one. `TurnTime`, `VictoryRules`, `MapPlayCampaign`.

## Known limits

Counter-spy, court reports, rival fog/Passage colonisation and rival GP–Tribe
first contact (DR-20261111-14) are live. Remaining gaps:
[`deferred.md`](deferred.md).

## Tests

`test_faction_catalog`, `test_world_setup`, `test_world_bootstrap`,
`test_country_borders`, `test_map_generator`, `test_map_rules`,
`test_map_screen`, `test_campaign_end`, `test_capital_loss`.

```bash
gd-tools test --coverage --min 80
```
