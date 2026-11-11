# Civilian units

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types; playable: Explorer (explore,
  prospect — DR-20261111-26), Builder (improve, upgrade town), Engineer
  (road, port), Spy, Merchant (buy land), Rail Builder (railroad).
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew; Visit
  jumps to it.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers, Rail
  Builders stay on crown land; Explorer, Merchant, Spy cross any border. One
  crew per tile per crown (Rail Builders exempt); presence keeps it visible.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted; each
  shadowed rival GP adds +15% RP to a Low+ slot. **Counter-espionage** kills or
  turns agents; court reports name deeds ([espionage.md](espionage.md)).
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, **prospect 1** (any charted swamp/hills/
  mountain/desert tile of its own province), improve 1–4, **upgrade town**
  (National Bureaucracy), road, port, rail, fort 1–3 ([forts.md](forts.md)),
  hospital 1–2.
- **Survey** ([DR-20261111-26](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-26)):
  a mineral is hidden until that crown's Explorer prospects its tile; selecting
  one marks the ground and a tap surveys it.
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
  A Minor or Tribe town has no Builder: a purchased deed raises it to
  `min(4, 1 + deeds)` and a lost deed never lowers it (`MinorTownGrowth`,
  DR-20261112-01).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops); lands at a port or coastal tile beside it.
  Explorers/Merchants any coast; others need crown land. Sunk ships drown
  passengers.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy, no
  war and a prospected mineral; 15× base at assign, debit on complete. The deed
  develops the seller's town (DR-20261112-01). Rivals use `AiMerchantWork` and
  their own ledger.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; the province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused; `ESTATES` lists orders.
- **Stranding:** crews caught by conquest withdraw to crown land or die with
  the province.

## Deferred (REQ-P2-02)

None. Rival hospitals are live (`AiHospitalWork`); ranked gaps in
[`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work |
| `scripts/rules/mineral_survey.gd` | survey |
| `scripts/rules/spy_*.gd` | spycraft, court reports |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | deeds |
| `scripts/rules/minor_town_growth.gd` | a deed raises a Minor/Tribe town |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | works, ledger |
| `scripts/map/civilian_*.gd`, `scripts/ui/civilian_*.gd` | markers, dossier |

Rules stay node-free (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour | tap glowing neighbour |
| Survey | tap a survey mark | same |
| Work order | dossier button | dossier button |
| Counter-spy | dossier **Counter-espionage** | same |
| Empire roster | CREW/`C`; Visit | same |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_espionage`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
