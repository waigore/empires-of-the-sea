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
| Minor Nation | 3 | Old World only | no | no | no | setup |
| Tribe | 10 | New World only | no | no | no | setup |

Minors track the strongest Great Power's regiment era; Tribes stay at level 1.
Roster, ids, colours and capabilities: `scripts/rules/faction_catalog.gd`.

## Regions

- One deterministic tile map per region (`MapGenerator.generate_region`); a
  seed reproduces both maps and all ownership.
- Old World: temperate terrain, 6 GPs + 3 Minors, ~24–64 provinces, European
  province and sea names (Spanish exonyms).
- New World: wetter and greener terrain, 10 Tribes, Native-flavoured names.
- `WorldMap` holds both grids. Regions never share grid adjacency; **warp
  zones** (one edge sea zone per side) pair 1:1, marked “Passage”.
- The HUD region button (`OLD WORLD ›` / `NEW WORLD ›`) swaps canvas, fog,
  fleets, civilians, works and camera bounds. Squadrons, civilian rosters and
  land works persist per region, and every region advances on end turn —
  including off-screen battles — so leaving a map never pauses it. HUD ship and
  civilian chips are empire totals, and navy food upkeep counts every region.
  The player keeps squadrons only where it owns provinces.

## Setup post-pass

After capitals are fixed, `WorldBootstrap` turns the capital-choice plan into
real works (ports, harbour roads), sets Great Power capital town development to
4, and places four L1 grain farms per Great Power, wired to the seat by road
(wiki: capital-and-connectivity; tile-map-and-generation). Without it the
opening map had no working estates and food demand outran the capital's grain.

## Ownership

`scripts/rules/territory_assignment.gd` grows each faction from a single seed
inside one P–P continent, so holdings are contiguous and no faction spans two
landmasses.

- Seeds are farthest-point sea-bound provinces (GPs and Tribes must own one).
- Balanced budgets: Minors reserve at most 3 provinces each, the rest splits
  evenly across GPs on that continent.
- Multiple factions may share a continent; extra continents stay unclaimed.
- GPs use the capital-choice phase; Minors/Tribes take any owned province.

## Borders on the map

`scripts/map/country_borders.gd` derives internal owner boundaries from the
tile grid. `MapOverlay` draws them **above fog** as an engraved shadow plus the
owner's colour, so nations read at any zoom. Thin province hairlines stay
beneath; terrain and minimap carry a light owner tint. Coastlines keep their ink
treatment, so colour never bleeds into the sea.

## Known limits

Naval transit through warp zones, colonisation, Minor/Tribe AI, town-per-province
roads, regiment parity and market participation are deferred.

## Tests

`test_faction_catalog`, `test_world_setup`, `test_world_bootstrap`,
`test_country_borders`, `test_map_generator`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
