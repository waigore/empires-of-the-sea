# Civilian units

Land units that explore, improve, buy land, colonize and spy. Three start;
Merchant and Rail Builder unlock by tech; Spy trains at the capital.

**Pillars:** P2, P3, P1 (map feedback), P4, P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types.
- **Playable:** Explorer (explore, prospect), Builder (improve, upgrade town),
  Engineer (road, port), Merchant (buy land), Rail Builder (railroad), Spy
  (counter-espionage; presence and RP boost in
  [espionage.md](espionage.md)).
- **Empire ledger** (`CivilianRosterPanel`): the CREW chip or `C` lists every
  crew, filters by region/craft; Visit jumps to its dossier.
- **Movement:** one orthogonal land tile per turn; Builders, Engineers and Rail
  Builders stay on crown land; Merchants and Spies may cross foreign provinces.
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Costs at assign, not refunded. Explore ≤3, prospect 1,
  improvement 1–4 (lumber + cast iron), **upgrade town** (same costs, National
  Bureaucracy), road 1+1 (level 2 tech), port 5+5 (2 turns), rail 2 lumber +
  2 steel (2 turns), fort 1–3 ([forts.md](forts.md)).
- **Town development:** Builder raises towns to level 4; capital/connected port
  towns cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops), lands at the port province or a coastal
  tile beside its zone. Explorers/Merchants any coast; others need crown land.
  Landing reveals the tile and neighbours; sunk ships drown passengers.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy, no
  war and prospected mineral; 15× base at assign, debit on complete.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused. `ESTATES` lists yield and orders.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders and Spies exempt).

## Deferred (REQ-P2-02)

- Rival civilian AI; Minor/Tribe town manufacturing offers.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work, transport, voyage |
| `scripts/rules/spy_rules.gd` | spy presence, screen, dice and RP bonus |
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

`test_civilian_field_rules`, `test_civilian_voyage`, `test_espionage`,
`test_map_screen_crown_orders`, `test_map_model`.

```bash
gd-tools test --coverage --min 80
```
