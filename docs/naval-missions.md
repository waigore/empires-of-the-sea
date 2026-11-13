# Naval missions and raiding

Patrol, blockade, defence, interception, retreat and raids; movement,
harbours and the yard live in [fleets.md](fleets.md).

**Pillars:** P2, P3, P4 (turn-end only), P5 (stations and raids on the dossier).
**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Missions and Movement, § Naval Interception Probability, § Naval Retreat Formula,
§ Trade and Transport Interception. Decisions: DR-20261109-16, DR-20261110-13.

## Stations

| Station | Where | Effect |
|---------|-------|--------|
| Patrol | at sea | Intercepts hostiles entering the zone |
| Blockade | at sea beside an enemy coast | Intercepts; severs that coast's harvest |
| Defend | at sea | Holds; no interception |
| Beachhead | at sea beside a hostile coast | One-turn landing site |

A station spends the move and persists until the squadron sails, docks or
retakes one; the home fleet holds none, and a station whose target is no
longer hostile lapses.

A sealed harbour is no landfall: a blockade severs the coast, so its province
yields nothing by sea, and holding the crown's capital harbour cuts every sea
path (wiki: capital-and-connectivity § Blockade). Despatch and dossier name it
(`REQ-P5-05`).

## Interception

```text
score = Σ ship.interceptRating
ratio = score / (score + Σ target.fleeRating)
chance = clamp(missionFactor × ratio, 0.05, 0.85)
missionFactor = 0.5 Patrol, 0.9 Blockade
```

Deterministic from seed, turn, zone and owners. Success makes the patroller the
attacker; a miss leaves the mover attacking. Only Patrol or a standing Blockade
rolls, and only against a hostile.

**Privateering Companies** multiplies the interceptor's score by `1.25` before
the clamp (movement and raids); the target's charter never helps.

## Retreat

```text
canRetreat = existsFriendlyOrNeutralAdjacentZone()
chance = 0.6 + (ownAvgMV − enemyAvgMV) × 0.1 − enemyAggression
enemyAggression = 0.1 Patrol, 0.2 Blockade, else 0
```

A haven is a zone with no fleet hostile to the retreating side. Success moves every
beaten hull there, spends its move and clears its station and beachhead; failure
is a rout, and no safe water means no retreat.

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

Hostile Patrol/Blockade squadrons in a zone bordering the victim's coast raid;
the bonus does not cross zones. Cargo at risk is the **victim's own** purchases,
never the pooled book: escorts are home-fleet warships, cargo its merchant hulls.

**A raid sinks a merchant hull** (DR-20261111-17): a second roll sends one
**civilian hull** down (richest hold first). Warships are never prizes; the
raider loses no hull.

**Raids cut both ways.** Any crown's station off a hostile coast raids a
declared enemy's trade by the same formulas: **prize cargo** leaves the victim's
stockpile for the raider's, no free hold needed and never booked as an import
(DR-20261111-20). Each raider rolls cargo and hull on separate salts. The
crown's raids reach its despatch; rivals' are their own affair. The dossier
prices both and names the zone, any hull and the ring.

## Deferred (REQ-P2-02)

Rival raids shipped (DR-20261111-20); gaps: [`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions}.gd` | mission, blockade target, station gates |
| `scripts/rules/blockades.gd` | sealed coasts, the sea paths they cut |
| `scripts/rules/{naval_interception,naval_retreat,naval_raid,naval_hull_loss}.gd` | chance, roll, retreat, raids, civilian hulls |
| `scripts/rules/world_market.gd` | per-crown cargo books |
| `scripts/map/{map_play_raids,map_play_fleet_missions}.gd` | ledger, dossier, reports |

Rules are node-free (`REQ-P3-03`); stations and blockade coasts are dossier
rows ([fleets.md](fleets.md) for map controls).

## Tests

`test_naval_rules`, `test_fleet_orders`,
`test_battle_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
