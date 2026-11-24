# Naval missions and raiding

Stations, interception, retreat, raids; movement and the yard:
[fleets.md](fleets.md).

**Pillars:** P2–P5. **Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Missions and Movement, § Naval Interception Probability, § Trade and Transport
Interception. Decisions: DR-20261109-16, DR-20261110-13, DR-20261120-02,
DR-20261124-04, DR-20261124-06.

## Stations

| Station | Where | Effect |
|---------|-------|--------|
| Patrol | at sea | Intercepts hostiles entering |
| Blockade | at sea beside an enemy coast's port | Intercepts; severs that harvest |
| Defend | at sea | Holds; no interception |
| Beachhead | at sea beside a hostile coast | One-turn landing site |

A station spends the move and persists until the squadron sails, docks or
retakes one; the home fleet holds none; a target no longer hostile lapses it.
A blockade stands only in the water its port faces (`port_sea_zones`).

A sealed harbour severs the coast; the capital's cuts every sea path
(`REQ-P5-05`).

## Interception

```text
score = Σ ship.interceptRating
ratio = score / (score + Σ target.fleeRating)
chance = clamp(missionFactor × ratio, 0.05, 0.85)
missionFactor = 0.5 Patrol, 0.9 Blockade
```

Deterministic from seed, turn, zone and owners. Success makes the patroller the
attacker; a miss leaves the mover. Only Patrol or a standing Blockade rolls, and
only at war.

**The dossier prices the catch (DR-20261120-02):** a station at sea prints
`Interception: 62% to catch 4 hulls if they stay.` over its holders and every
hostile the crown has **read**; an unread rival and empty water print none.

**Privateering Companies** multiplies the interceptor's score by `1.25` before
the clamp; a target's charter never helps.

## Retreat

```text
canRetreat = existsFriendlyOrNeutralAdjacentZone()
chance = 0.6 + (ownAvgMV − enemyAvgMV) × 0.1 − enemyAggression
enemyAggression = 0.1 Patrol, 0.2 Blockade, else 0
```

A haven is a zone no hostile fleet holds. Success moves every beaten hull there
and clears its station; failure is a rout, and no safe water means no retreat.

**The dossier prices the way out (DR-20261124-06):** a water the crown would lose
reads `Beaten here by England: 40% to slip into the Golfo de México.` beside its
share, over the strongest court there — or `no adjacent water is safe` when the
rout is certain. A water the crown holds prints none.

## Raids

```text
base = patrol interception chance of the raider group
chance = clamp(base × blockadeBonus × (1 − escortFactor), 0.05, 0.85)
blockadeBonus = 1.25 for a blockade raider
escortFactor = min(0.5, escortHull / cargoHull × 0.3)
cargoLost = imports × raidEfficiency
raidEfficiency = 0.3…0.7 by relative strength
shipLossChance = 0.2 × (1 − escortFactor) × 2.0, clamp 0.05…0.5
```

Hostile Patrol/Blockade squadrons raid a zone bordering the victim's coast.
Cargo at risk is the **victim's own**: escorts are home-fleet warships, cargo its
merchant hulls.

**A raid sinks a merchant hull** (DR-20261111-17): a second roll sends one
**civilian hull** down (richest hold first). Warships are never prizes.

**The market sheet names the cover (DR-20261124-04):** `CONVOY  1 warship cuts a
raid by 20%.`

**Raids cut both ways.** Any crown's station off a hostile coast raids a
declared enemy: **prize cargo** leaves the victim's stockpile for the raider's,
never an import, priced on the dossier (DR-20261111-20, DR-20261120-01).

## Deferred (REQ-P2-02)

Gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions}.gd` | mission, blockade target, station gates |
| `scripts/rules/blockades.gd` | sealed coasts, paths cut |
| `scripts/rules/{naval_station,naval_interception,naval_retreat,naval_raid,naval_hull_loss,convoy_read}.gd` | station, chance, retreat, raids, hulls, convoy |
| `scripts/rules/world_market.gd` | crown cargo books |
| `scripts/map/{map_play_raids,map_play_fleet_missions,map_play_station_notes}.gd` | ledger, dossier, prices, reports |

Rules are node-free (`REQ-P3-03`); stations are dossier rows
([fleets.md](fleets.md)).

## Tests

`test_naval_rules`, `test_fleet_orders`,
`test_a_battle_rules`, `test_a_map_screen`, `test_economy_screen`.

```bash
gd-tools test --coverage --min 80
```
