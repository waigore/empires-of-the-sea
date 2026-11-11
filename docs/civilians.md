# Civilian units

Land units: explore, improve, colonize, spy.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types; playable: Explorer (explore,
  prospect — DR-20261111-26 uncover), Builder (improve, upgrade town), Engineer
  (road, port), Spy (spycraft), Merchant (buy land), Rail Builder (railroad).
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew; filter
  and Visit jump to it.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers, Rail
  Builders stay on crown land; Explorer, Merchant, Spy cross any border. One
  crew per tile per crown (Rail Builders exempt); presence keeps a province
  visible.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted (never
  `unknown`); each shadowed rival GP adds +15% RP to a Low+ slot.
  **Counter-espionage** kills or turns agents; court reports name deeds
  ([espionage.md](espionage.md)).
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, **prospect 1** (any charted swamp/hills/
  mountain/desert tile of its own province, announcing the find or none),
  improve 1–4, **upgrade town** (National Bureaucracy),
  road, port, rail, fort 1–3 ([forts.md](forts.md)), hospital 1–2.
- **Survey** ([DR-20261111-26](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-26)):
  a mineral is hidden until that crown's Explorer prospects its tile; selecting
  one marks the unsurveyed ground and a tap surveys it.
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops); lands at a port or coastal tile beside its
  zone. Explorers/Merchants any coast; others need crown land. Sunk ships drown
  passengers.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy, no
  war and a prospected mineral; 15× base at assign, debit on complete. Each
  deed lifts the province town. Rivals run it through `AiMerchantWork`, from
  their own ledger.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; the province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused; `ESTATES` lists the orders.
- **Stranding:** crews caught by conquest withdraw to crown land or are lost
  with the province.

## Deferred (REQ-P2-02)

None. Rival hospitals are live (`AiHospitalWork`); ranked gaps in
[`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work |
| `scripts/rules/mineral_survey.gd` | known resource, survey |
| `scripts/rules/spy_*.gd` | spycraft, court reports |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | deeds |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | works, ledger |
| `scripts/map/civilian_*.gd`, `scripts/ui/civilian_*.gd` | markers, dossier |

Rules stay node-free (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour | tap glowing neighbour |
| Survey | tap a survey mark (Explorer selected) | same |
| Work order | dossier button | dossier button |
| Counter-spy | dossier **Counter-espionage** | same |
| Empire roster | CREW/`C`; Visit | same |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_espionage`, `test_visibility`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
