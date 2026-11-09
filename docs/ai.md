# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
The human court is never scripted.

**Pillars:** P2 (rules fidelity), P3 (pure rules, testable), P4 (no per-frame
work), P5 (rivals act without player bookkeeping).

## Implemented

- **Parameter registry** (`AiParameterRegistry`): every weight and threshold is
  a catalog key with bounds and default; planners read through `resolve`.
- **Blessed profiles** (`AiProfile`): `normal`, `aggressive`, `economic`;
  unknown ids fall back, invalid values are rejected.
- **Personalities** (`AiPersonality`): the seven wiki archetypes; each GP's
  leaderKey comes from `LeaderCatalog`.
- **Hidden agendas** (`AiAgenda`): one of six, assigned once from
  `hash(game seed, faction)` and kept for the run.
- **Power score** (`AiPower`): provinces × 10 + regiments × 1 + ships × 5, with
  relative-power bands +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire per candidate court —
  base 50, relative power, relation pressure (−40/−20/+10); Minor/Tribe targets
  also resource need (+5 each, cap +15), rival embassies (−8 each, cap −24),
  invasion capacity (−20/+10/−25), multi-war (−15).
  Improve-relations desire is the complement. Declarations need the relation
  ceiling (50; warmonger 70, peacemaker 30), war desire ≥ 51 and no 4-turn
  cooldown; war goals clamp `round(desire / 25)` to the target's provinces. At
  war, desire below 50 offers peace — only to AI courts.
- **Turn pass** (`AiTurn`): one legal order per rival court per turn through
  `DiplomacyRules`, traced per court. Declarations land before naval combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border a rival detaches
  all but one Home Army regiment into a field army, then each field army saves
  an occupied own province, storms an adjacent hostile one (a 10% margin after
  wall soak; seats and resources score first), or stages on the nearest
  frontier. Orders run through `ArmyMovement` before Combat, so a march this
  turn fights this turn.
- **Persistence:** saves keep fixed agendas and pair cooldowns
  (`AiState.to_dict`).

Thresholds and biases are registry defaults; the wiki fixes factors and
cooldowns, not the pick. AI peace and overture offers to the human wait for the
court UI.

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
| `scripts/ai/ai_turn.gd` | per-turn pass, trace, rule application |
| `scripts/map/map_play_diplomacy.gd` | phase wiring and toasts |
| `scripts/map/map_play_armies.gd` | land pass: apply orders, report marches |

No node deps in `scripts/ai` (`REQ-P3-03`).

## Tests

`test_ai_rules` (power, parameters, planner, turn, military).

```bash
gd-tools test --coverage --min 80
```
