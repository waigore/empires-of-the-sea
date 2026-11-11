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
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew; filter
  and Visit jump to it.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers, Rail
  Builders stay on crown land; Explorer, Merchant, Spy cross any border.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted (never
  `unknown`); each shadowed rival GP adds +15% RP to a Low+ slot it knows.
  **Counter-espionage** kills or turns enemy spies; court reports name deeds
  ([espionage.md](espionage.md)).
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, prospect 1, improve 1–4 (lumber + cast iron),
  **upgrade town** (same costs, National Bureaucracy), road, port, rail, fort
  1–3 ([forts.md](forts.md)).
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops); lands at port or coastal tile beside its
  zone. Explorers/Merchants any coast; others need crown land. Landing reveals
  tile + neighbours; sunk ships drown passengers.
- **Land purchase:** Merchant buys Minor/Tribe resource tile with embassy, no
  war, prospected mineral; 15× base at assign, debit on complete. Rivals run
  the same rule through `AiMerchantWork` and pay from their own ledger.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused; `ESTATES` lists orders.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).
- **Stranding:** crews caught by conquest withdraw to crown land or are lost;
  a fallen crown's crews leave play.
- **Rival civilian AI** (`AiCivilianPlanner`, `MapPlayCivilianAi`): every court
  fields one Explorer, Builder, Engineer and Spy, then trains to
  `civilian.max_civilians`; Builders raise the shortest estate or the town, read
  against the estates ledger's own caps (DR-20261111-10).

## Deferred (REQ-P2-02)

Rival GP–Tribe contact / deeds (DR-20261111-05). See [`deferred.md`](deferred.md).

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
| March | click glowing neighbour | tap glowing neighbour |
| Work order | dossier button | dossier button |
| Counter-spy | dossier **Counter-espionage** | same |
| Empire roster | CREW/`C`; Visit | same |
| Embark / land | fleet **PASSENGERS** | same |
| Estates | `ESTATES` / province Build | same |
| Cancel / close | dossier / ledger Close | same |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_espionage`, `test_visibility`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
