# Civilian units

Land units that explore, improve, colonize and spy; four start, two unlock by
tech.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types; playable: Explorer (explore,
  prospect), Builder (improve, upgrade town), Engineer (road, port), Spy
  (spycraft), Merchant (buy land), Rail Builder (railroad).
- **Empire ledger** (`CivilianRosterPanel`): CREW chip or `C` lists every crew,
  filters, and Visit jumps to it.
- **Movement:** one orthogonal land tile per turn; Builders, Engineers and Rail
  Builders stay on crown land; Explorer, Merchant and Spy cross any border.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted (never
  `unknown`); each shadowed rival Great Power adds +15% RP to a Low+ slot on a
  tech it knows. **Counter-espionage** is ongoing, kills or turns enemy spies,
  and court reports name the deeds ([espionage.md](espionage.md)).
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, prospect 1, improvement 1–4 (lumber + cast
  iron), **upgrade town** (same costs, National Bureaucracy), road, port, rail,
  fort 1–3 ([forts.md](forts.md)).
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops) and lands at the port or a coastal tile
  beside its zone. Explorers/Merchants any coast; others need crown land.
  Landing reveals the tile and neighbours; sunk ships drown passengers.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy, no
  war and prospected mineral; 15× base at assign, debit on complete.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused; `ESTATES` lists orders.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).

## Deferred (REQ-P2-02)

- Rival civilian AI; Minor/Tribe town manufacturing offers.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work, transport, voyage |
| `scripts/rules/spy_networks.gd` | spy hosts and research bonus |
| `scripts/rules/spy_rules.gd` | counter-espionage, dice and court reports |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | deeds |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | works, extraction, ledger |
| `scripts/map/civilian_*.gd`, `map_play_civilian_roster.gd` | markers, passengers, roster jump |
| `scripts/ui/civilian_*.gd`, `improvement_panel.gd` | dossier, roster, estates |

Rules stay node-free (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour tile | tap glowing neighbour tile |
| Work order | dossier button | dossier button |
| Counter-spy | dossier **Counter-espionage** | same |
| Empire roster | CREW chip / `C`; row Visit | same |
| Embark / land | fleet dossier **PASSENGERS** | same |
| Estates ledger | `ESTATES` / province **Build Improvement** | same |
| Cancel / close | dossier / ledger Close | dossier / ledger Close |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_espionage`, `test_visibility`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
