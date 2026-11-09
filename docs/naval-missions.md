# Naval missions and raiding

Patrol, blockade, defence, interception, retreat and cargo raids. Movement,
harbours and the yard stay in [fleets.md](fleets.md).

**Pillars:** P2, P3, P4 (turn-end only), P5 (stations and raids are discoverable
on the dossier).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Missions and Movement, § Naval Interception Probability, § Naval Retreat
Formula, § Trade and Transport Interception. Decisions:
[DR-20261109-16](https://github.com/waigore/empires-of-the-sea/wiki/dr-20261109-16).

## Stations

| Station | Where | Effect |
|---------|-------|--------|
| Patrol | at sea | Intercepts hostile fleets entering the zone |
| Blockade | at sea beside an enemy coast | Intercepts in the zone at the higher factor |
| Defend | at sea | Holds; no interception |
| Beachhead | at sea beside a hostile coast | One-turn landing site (DR-20261109-13) |

A station spends the turn's move and persists until the squadron sails, docks
or takes another station. The home fleet cannot take one. A station whose
target is no longer a hostile shore lapses, and the dossier says so.

## Interception

```text
score = Σ ship.interceptRating
ratio = score / (score + Σ target.fleeRating)
chance = clamp(missionFactor × ratio, 0.05, 0.85)
missionFactor = 0.5 Patrol, 0.9 Blockade
```

The roll is deterministic from campaign seed, turn, zone and owners. Success
makes the patroller the attacker; a miss leaves the mover attacking. No
hostility, no interception. Only Patrol or a standing Blockade rolls; other
squadrons in the zone add nothing. Resolves at end of Movement, before battle.

**Privateering Companies** multiplies the interceptor's score by `1.25` before
the clamp (movement and trade raids); the target's charter never helps. The
dossier names the bonus for a squadron at sea.

## Retreat

```text
canRetreat = existsFriendlyOrNeutralAdjacentZone()
chance = 0.6 + (ownAvgMV − enemyAvgMV) × 0.1 − enemyAggression
enemyAggression = 0.1 Patrol, 0.2 Blockade, else 0
```

A friendly or neutral zone has no fleet hostile to the retreating side. Success
moves every beaten hull to that haven, spends its move and clears its station
and beachhead; failure is a normal rout. No model or no safe water means no
retreat.

## Raids

```text
base = patrol interception chance of the raider group
chance = clamp(base × blockadeBonus × (1 − escortFactor), 0.05, 0.85)
blockadeBonus = 1.25 for a blockade raider
escortFactor = min(0.5, escortHull / cargoHull × 0.3)
cargoLost = imports × raidEfficiency
raidEfficiency = 0.3…0.7 by relative strength
```

Only hostile Patrol/Blockade squadrons in a sea zone bordering the victim's
coast raid; each rolls in its own zone (blockade bonus does not cross zones).
Cargo at risk is this turn's world-market imports; losses leave the stockpile
before the ledger closes. Escorts are home-fleet warship HULL; cargo is its
merchant HULL. Deferred: civilian/home-fleet hull losses and AI victim economies.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | mission and blockade target on the fleet |
| `scripts/rules/fleet_missions.gd` | station gates, notes, scores |
| `scripts/rules/naval_interception.gd` | chance, deterministic roll, attacker |
| `scripts/rules/naval_retreat.gd` | chance, safe water, haven move |
| `scripts/rules/naval_raid.gd` | cargo at risk, escort, losses |
| `scripts/map/map_play_fleet_missions.gd` | dossier rows and intents |
| `scripts/map/map_play_raids.gd` | applies the raid to the ledger |
| `scripts/ui/fleet_mission_section.gd` | station buttons |

Rules are node-free (`REQ-P3-03`); the map emits intents and reports results.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Take a station | dossier button | same |
| Blockade a coast | dossier row per enemy coast | same |
| End the turn | End turn | same |

## Tests

`test_fleet_missions`, `test_naval_interception`, `test_naval_retreat`,
`test_naval_raid`, `test_fleet_orders`, `test_battle_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
