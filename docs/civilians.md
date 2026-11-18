# Civilian units

Land units: explore, improve, colonize, spy.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types, all playable.
- **Hiring:** the capital's muster rail names each craft's work and the study its
  hire waits on, greying a gated row
  ([DR-20261118-09](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261118-09)).
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew (world,
  craft, orders); Visit jumps to it; **Find the next crew that waits** walks the
  idle crews.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers and Rail
  Builders stay on crown land, Explorer, Merchant and Spy cross any border; one
  crew per tile per crown (those three exempt); presence keeps a province
  visible.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted (never
  `unknown`); each shadowed rival GP adds +15% RP at Low+ funding.
  **Counter-espionage** kills or turns agents; court reports name deeds
  ([espionage.md](espionage.md)).
- **Work orders** on the unit tile (Builders: any owned tile); cancel
  returns it. Explore ≤3, **prospect 1** (charted surveyable
  ground), improve 1–4, **upgrade town** (National
  Bureaucracy), road, port (one per seaboard), rail, fort 1–3
  ([forts.md](forts.md)), hospital 1–2.
- **Survey** ([DR-20261111-26](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-26)):
  a mineral stays hidden until the crown's Explorer prospects it.
- **Court's pick** ([DR-20261117-06](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261117-06),
  [DR-20261117-07](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261117-07)):
  an idle crew's dossier names the planner's next work, priced by its ledger, and
  the ground when it is not underfoot; or the march. A crew with no order says
  so.
- **Town development:** Builders raise towns to 4; connected port towns cap
  extraction; levels 2 and 4 manufacture ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port (one
  per hull, never with troops); lands on a coastal tile beside its zone, the
  grounds offered per coast; Explorers/Merchants any coast, others need crown
  land.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile (embassy, no war,
  prospected mineral); 15× base at assign, debit on complete; each deed lifts the
  province town. Both surfaces name the deed's return
  ([DR-20261118-05](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261118-05)).
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog
  and saves; the province stays the seller's.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused.
- **Stranding:** crews caught by conquest withdraw or die.

## Deferred (REQ-P2-02)

None open — see [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work |
| `scripts/rules/mineral_survey.gd` | known resource, survey |
| `scripts/rules/spy_*.gd` | spycraft, court reports |
| `scripts/rules/land_purchase.gd`, `scripts/rules/deed_terms.gd`, `scripts/world/tile_ownership.gd` | deeds |
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
| Empire roster | CREW/`C`; Visit, **Find the next crew that waits** | same |

## Tests

`test_civilian_turn_rules`, `test_diplomacy_rules`,
`test_map_screen` (the crown orders).

```bash
gd-tools test --coverage --min 80
```
