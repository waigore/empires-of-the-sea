# Naval missions and raiding

Patrol, blockade, defence, interception, retreat and cargo raids; movement,
harbours and the yard live in [fleets.md](fleets.md).

**Pillars:** P2, P3, P4 (turn-end only), P5 (stations and raids on the dossier).
**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Missions and Movement, § Naval Interception Probability, § Naval Retreat Formula,
§ Trade and Transport Interception. Decisions: DR-20261109-16, DR-20261110-13.

## Stations

| Station | Where | Effect |
|---------|-------|--------|
| Patrol | at sea | Intercepts hostiles entering the zone |
| Blockade | at sea beside an enemy coast | Intercepts in zone, higher factor |
| Defend | at sea | Holds; no interception |
| Beachhead | at sea beside a hostile coast | One-turn landing site |

A station spends the turn's move and persists until the squadron sails, docks or
takes another. The home fleet cannot take one. A station whose target is no
longer a hostile shore lapses, and the dossier says so.

## Interception

```text
score = Σ ship.interceptRating
ratio = score / (score + Σ target.fleeRating)
chance = clamp(missionFactor × ratio, 0.05, 0.85)
missionFactor = 0.5 Patrol, 0.9 Blockade
```

Deterministic from seed, turn, zone and owners. Success makes the patroller the
attacker; a miss leaves the mover attacking. No hostility, no interception. Only
Patrol or a standing Blockade rolls, at the end of Movement.

**Privateering Companies** multiplies the interceptor's score by `1.25` before
the clamp (movement and raids); the target's charter never helps.

## Retreat

```text
canRetreat = existsFriendlyOrNeutralAdjacentZone()
chance = 0.6 + (ownAvgMV − enemyAvgMV) × 0.1 − enemyAggression
enemyAggression = 0.1 Patrol, 0.2 Blockade, else 0
```

A friendly or neutral zone holds no fleet hostile to the retreating side. Success
moves every beaten hull to that haven, spends its move and clears its station and
beachhead; failure is a rout. No safe water means no retreat.

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

Hostile Patrol/Blockade squadrons in a sea zone bordering the victim's coast
raid; each rolls in its own zone (the bonus does not cross zones).
Cargo at risk is the **victim's own** purchases, never the pooled book. Escorts
are home-fleet warships; cargo is its merchant hulls.

**A raid sinks a merchant hull** (DR-20261111-17). A second roll sends one
**civilian hull** down (`0.2 × (1 − escortFactor) × 2.0`, clamp 0.05…0.5,
richest hold first). Warships are never prizes; the raider loses no hull.

**Raids cut both ways.** The crown's station off a rival coast raids that rival's
trade by the same formulas against a declared enemy. The tonnage is **prize
cargo**: it leaves the rival's stockpile and lands in the crown's, no free hold
needed and never booked as the crown's own import. Each direction rolls cargo
and hull on separate salts. The dossier prices both; each despatch names the
zone and any hull sent down; the zone rings.

## Deferred (REQ-P2-02)

Rival-on-rival raids + prize cargo (DR-20261111-17). See
[`deferred.md`](deferred.md).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions}.gd` | mission, blockade target, station gates |
| `scripts/rules/{naval_interception,naval_retreat,naval_raid,naval_hull_loss}.gd` | chance, roll, retreat, raids, civilian hulls |
| `scripts/rules/world_market.gd` | per-crown cargo books |
| `scripts/map/{map_play_raids,map_play_fleet_missions}.gd` | ledger, dossier, reports |

Rules are node-free (`REQ-P3-03`). Stations and blockade coasts are dossier
rows; map controls in [fleets.md](fleets.md).

## Tests

`test_fleet_missions`, `test_naval_interception`, `test_naval_retreat`,
`test_naval_raid`, `test_fleet_orders`, `test_battle_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
