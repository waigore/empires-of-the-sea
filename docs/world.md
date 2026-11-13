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

Minors track the strongest Great Power's regiment era; Tribes stay level 1
(ids: `faction_catalog`).

## Regions

- One deterministic tile map per region; a seed reproduces both maps and all
  ownership.
- Old World: temperate, 60 provinces for 6 GPs + 6 Minors — each Minor 3, the
  rest split across the GPs.
- New World: wetter, 30 provinces for 10 Tribes; 3 each.
- `WorldMap` holds both grids. Regions share no grid adjacency; **warp zones**
  (one edge sea zone per side) pair 1:1, marked “Passage”; fleets cross to the
  other world.
- A sea zone wears the water it lies on, not pool order (wiki: naming §
  Sea zones, DR-20261113-07).
- The region button swaps canvas, fog, fleets, civilians, works and camera
  bounds. Rosters persist per region; each region advances every turn. Chips are
  empire totals; squadrons stay where provinces are held.

## Setup post-pass

After capitals are fixed, `WorldBootstrap` turns the capital-choice plan into
works (ports, harbour roads), sets capital town development to 4 and
places four L1 grain farms per Great Power on plains (thin sites levelled),
road-wired to the seat (wiki: capital-and-connectivity).

## Ownership

`scripts/rules/territory_assignment.gd` grows each faction from one seed on one
P–P continent, so holdings stay contiguous. A purchased tile is a
**deed**: `TileOwnership` overrides its owner while the province stays with the
seller.

- Seeds are farthest-point sea-bound provinces (GPs and Tribes must own one).
- Minors take 3 each (the wiki floor); the rest splits across the GPs.
- GPs use the capital-choice phase; Minors/Tribes take any owned province.

## Capital loss

`scripts/rules/capital_loss.gd` re-seats a captured crown at its first seaboard
province (else inland); with none left it falls, holdings to the conqueror. Wiki: [DR-20261109-02](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261109-02).

## Borders on the map

`scripts/map/country_borders.gd` derives owner boundaries from the tile grid;
`MapOverlay` draws them **above fog** (`FogLayer` holds fog) as engraved shadow
plus owner colour, hairlines beneath; terrain and minimap carry owner tint.

## Campaign length

Setup offers a **historical** campaign (default: halts after turn 201, i.e. 1800)
or an **endless** one (military victory only). At the cap an undecided age reads
“Campaign complete”, naming the strongest crown by power score — a tie names
no-one (`TurnTime`, `VictoryRules`, `MapPlayCampaign`).

## Known limits

Counter-spy, court reports, rival fog/Passage colonisation and rival first
contact are live (DR-20261111-14). Gaps: [`deferred.md`](deferred.md).

## Tests

`test_faction_catalog`, `test_world_setup`, `test_country_borders`,
`test_map_rules`,
`test_map_screen`, `test_campaign_end`, `test_capital_loss`.

```bash
gd-tools test --coverage --min 80
```
