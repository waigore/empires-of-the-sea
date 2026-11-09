# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
The human court is never scripted.

**Pillars:** P2 (rules fidelity), P3 (pure rules, testable), P4 (no per-frame
work), P5 (rivals act without player bookkeeping).

## Implemented

- **Parameter registry** (`AiParameterRegistry`): every weight and threshold is
  a bounded catalog key; planners read through `resolve`.
- **Blessed profiles** (`AiProfile`): `normal`, `aggressive`, `economic`.
- **Personalities** (`AiPersonality`): seven wiki archetypes with leader keys.
- **Hidden agendas** (`AiAgenda`): one of six, hashed once from seed + faction.
- **Power score** (`AiPower`): provinces ×10 + regiments + ships ×5; bands
  +30/+5/−25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50,
  relative power, relations, resource need, rival embassies, invasion capacity
  and multi-war; improve-relations is the complement. Declarations need the
  relation ceiling (50; warmonger 70, peacemaker 30), desire ≥ 51 and no 4-turn
  cooldown; war goals take `round(desire / 25)` provinces. At war, desire below
  50 offers peace to AI courts only.
- **Turn pass** (`AiTurn`): one legal order per rival court per turn through
  `DiplomacyRules`, traced per court. Declarations land before naval combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border a rival detaches
  all but one Home Army regiment into a field army, then each field army saves
  an occupied own province, storms an adjacent hostile one (10% margin after
  wall soak; seats and resources first), or stages on the nearest frontier.
  Orders run through `ArmyMovement` before Combat, so a march this turn fights
  this turn.
- **Naval planner** (`AiNavalPlanner`): a rival squadron engages a fleet it can
  beat (10% margin), threatens the best hostile coast, docks when a stronger
  fleet holds its zone, or cruises home at peace. The home fleet never sails;
  orders run through `NavalMovement` before naval combat.
- **Persistence:** saves keep fixed agendas and pair cooldowns.

Registry defaults pick thresholds; the wiki fixes factors and cooldowns.
AI peace and overtures wait for the human court UI.

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
- AI overtures, alliances and peace offers to the human court.
- AI economy and civilian planners; rival stockpiles.
- Dossier evidence and dialogue.

## Architecture

| File | Role |
|------|------|
| `scripts/ai/ai_parameter_registry.gd` | knob catalog, bounds, defaults |
| `scripts/ai/ai_profile.gd` | blessed profiles |
| `scripts/ai/ai_config.gd` | per-court config |
| `scripts/ai/ai_personality.gd` | leaders, archetypes, weights |
| `scripts/ai/ai_agenda.gd` | agendas, deterministic assignment |
| `scripts/ai/ai_power.gd` | power score and relative bands |
| `scripts/ai/ai_state.gd` | fixed agendas, pair cooldowns |
| `scripts/ai/ai_diplomacy_planner.gd` | war desire, orders, war goals |
| `scripts/ai/ai_military_planner.gd` | split, defend, storm and stage orders |
| `scripts/ai/ai_naval_planner.gd` | engage, threaten, retreat and cruise orders |
| `scripts/ai/ai_turn.gd` | per-turn pass, trace, rule application |
| `scripts/map/map_play_diplomacy.gd` | phase wiring and toasts |
| `scripts/map/map_play_army_ai.gd` | land pass: apply orders, report marches |
| `scripts/map/map_play_fleet_ai.gd` | sea pass: apply orders, report sails |

No node deps in `scripts/ai` (`REQ-P3-03`).

## Tests

`test_ai_rules` (power, parameters, planner, turn, military) and `test_ai_naval`.

```bash
gd-tools test --coverage --min 80
```
