# Naval missions and raiding

Stations, interception, retreat and raids; movement and the yard live in
[fleets.md](fleets.md).

**Pillars:** P2, P3, P4 (turn-end only), P5 (stations and raids on the dossier).
**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Missions and Movement, § Naval Interception Probability, § Trade and Transport
Interception. Decisions: DR-20261109-16, DR-20261110-13, DR-20261120-02.

## Stations

| Station | Where | Effect |
|---------|-------|--------|
| Patrol | at sea | Intercepts hostiles entering the zone |
| Blockade | at sea beside an enemy coast's port | Intercepts; severs that coast's harvest |
| Defend | at sea | Holds; no interception |
| Beachhead | at sea beside a hostile coast | One-turn landing site |

A station spends the move and persists until the squadron sails, docks or
retakes one; the home fleet holds none; a target no longer hostile lapses it.
A blockade stands only in the water its port faces (`port_sea_zones`), so the
dossier's rows and the rival pass name that water alone.

A sealed harbour severs the coast; the capital's cuts every sea path (wiki:
capital-and-connectivity § Blockade; `REQ-P5-05`).

## Interception

```text
score = Σ ship.interceptRating
ratio = score / (score + Σ target.fleeRating)
chance = clamp(missionFactor × ratio, 0.05, 0.85)
missionFactor = 0.5 Patrol, 0.9 Blockade
```

Deterministic from seed, turn, zone and owners. Success makes the patroller the
attacker; a miss leaves the mover. Only Patrol or a standing Blockade
rolls, and only against a hostile.

**The dossier prices the catch (DR-20261120-02):** a station at sea prints its
chance — `Interception: 62% to catch 4 hulls if they stay.` — over its holders
and every hostile the crown has **read**; an unread rival and empty water get no
line.

**Privateering Companies** multiplies the interceptor's score by `1.25` before
the clamp (movement and raids); the target's charter never helps.

## Retreat

```text
canRetreat = existsFriendlyOrNeutralAdjacentZone()
chance = 0.6 + (ownAvgMV − enemyAvgMV) × 0.1 − enemyAggression
enemyAggression = 0.1 Patrol, 0.2 Blockade, else 0
```

A haven is a zone no hostile fleet holds. Success moves every beaten hull there
and clears its station; failure is a rout, and no safe water means no retreat.

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

Hostile Patrol/Blockade squadrons raid a zone bordering the victim's coast; the
bonus never crosses zones. Cargo at risk is the **victim's own**: escorts are
home-fleet warships, cargo its merchant hulls.

**A raid sinks a merchant hull** (DR-20261111-17): a second roll sends one
**civilian hull** down (richest hold first). Warships are never prizes; the
raider loses none.

**Raids cut both ways.** Any crown's station off a hostile coast raids a
declared enemy by the same formulas: **prize cargo** leaves the victim's
stockpile for the raider's, never booked as an import, and the dossier prices
that group over its at-war coasts, naming the coast a patrol works and the hull a
hit sinks (DR-20261111-20, DR-20261120-01).

## Deferred (REQ-P2-02)

Gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions}.gd` | mission, blockade target, station gates |
| `scripts/rules/blockades.gd` | sealed coasts, the paths they cut |
| `scripts/rules/{naval_station,naval_interception,naval_retreat,naval_raid,naval_hull_loss}.gd` | station read, chance, roll, retreat, raids, hulls |
| `scripts/rules/world_market.gd` | crown cargo books |
| `scripts/map/{map_play_raids,map_play_fleet_missions,map_play_station_notes}.gd` | ledger, dossier, prices, reports |

Rules are node-free (`REQ-P3-03`); stations and blockade coasts are dossier
rows ([fleets.md](fleets.md) for map controls).

## Tests

`test_naval_rules`, `test_fleet_orders`,
`test_battle_rules`, `test_a_map_screen`.

```bash
gd-tools test --coverage --min 80
```
