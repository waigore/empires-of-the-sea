# Civilian units

Land units: explore, improve, colonize, spy.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six playable types.
- **Hiring:** the rail names each craft's work and study gate
  ([DR-20261118-09](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261118-09));
  a gold line names the court's hire pass, its craft `▸`
  (`MapPlayHirePick`, DR-20261122-12/15).
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew, walks
  the idle ones and names the court's work pick, its crews marked `▸`
  (DR-20261121-12/22-06); a crew aboard reads **Aboard** and answers no order
  chip.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers, Rail
  Builders keep to crown land, Explorer, Merchant, Spy cross borders; one crew
  per tile per crown.
- **Spy** (`SpyNetworks`, `SpyRules`): holds its province charted (never
  `unknown`); each shadowed rival GP adds +15% RP at Low+ funding.
  **Counter-espionage** kills or turns agents; reports name deeds
  ([espionage.md](espionage.md)).
- **Work orders** (Builders: any owned tile); materials are spent at assign,
  never refunded on cancel. **Aboard** a squadron a crew is off the map and
  takes no order, and no ledger hands it one. Explore ≤3, **prospect 1**
  (charted ground), improve 1–4, **upgrade town** (National Bureaucracy), road,
  port (one per seaboard), rail, fort 1–3 ([forts.md](forts.md)), hospital 1–2.
- **Survey** ([DR-20261111-26](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261111-26)):
  a mineral hides until prospected.
- **Court's pick** ([DR-20261117-06](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261117-06),
  [DR-20261117-07](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261117-07)):
  an idle crew's dossier names its pick, priced by its ledger.
- **Towns:** Builders raise them to 4; connected port towns cap extraction;
  levels 2, 4 manufacture ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port (one
  per hull, no troops); lands on a coastal tile beside its zone
  ([DR-20261119-03](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261119-03));
  Explorers/Merchants any coast, others crown land. **A rival reads the
  ground:** its colonist takes the charted coast its workshop can turn
  ([DR-20261119-05](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261119-05)).
  **The crown reads her own step:** the passenger block names the voyage
  (DR-20261121-08).
- **Land purchase:** Merchant buys a Minor/Tribe resource tile (embassy, no war,
  prospected mineral); 15× base, debit on complete; each deed lifts the
  town ([DR-20261118-05](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261118-05)).
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog,
  saves; province stays the seller's.
- **Improvements** yield `min(level, tech, terrain, transport, town)`
  connected; above-cap refused.
- **Stranding:** a crew caught by conquest withdraws or dies.

## Deferred (REQ-P2-02)

Workshop-coast landing live (DR-19-05); see [`deferred.md`](deferred.md).

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

`test_civilian_turn_rules`, `test_diplomacy_rules`, `test_a_map_screen`, `test_ledgers`.

```bash
gd-tools test --coverage --min 80
```
