# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
The human court is never scripted.

**Pillars:** P2 (rules fidelity), P3 (pure rules, testable), P4 (no per-frame
work), P5 (rivals act without player bookkeeping).

## Implemented

- **Parameter registry** (`AiParameterRegistry`): every weight and threshold is
  a catalog key with bounds; planners read `resolve`.
- **Blessed profiles** (`AiProfile`): `normal`, `aggressive`, `economic`;
  unknown ids fall back, invalid values are rejected.
- **Personalities** (`AiPersonality`): the seven wiki archetypes; leaderKey
  from `LeaderCatalog`.
- **Hidden agendas** (`AiAgenda`): one of six, fixed from
  `hash(game seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments × 1 + ships × 5, with
  relative-power bands +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, relative
  power, relation pressure and modifiers (resource need, rival embassies,
  invasion capacity, multi-war); improve-relations is the complement.
  Declarations need the relation ceiling (50; warmonger 70, peacemaker 30), war
  desire ≥ 51 and no 4-turn cooldown; goals clamp `round(desire / 25)` to the
  target's provinces. At war, desire below 50 offers peace — AI courts only.
- **Turn pass** (`AiTurn`): one legal order per rival court per turn through
  `DiplomacyRules`, traced per court. Declarations land before naval combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border a rival detaches
  all but one Home Army regiment, then each field army saves an occupied own
  province, storms an adjacent hostile one (10% margin after wall soak), or
  stages on the nearest frontier — through `ArmyMovement`, before Combat.
- **Naval planner** (`AiNavalPlanner`): at war a rival sorties or pursues one
  zone onto the weakest hostile squadron it can match (120% caution margin);
  at peace it holds station. Orders run through `NavalMovement`, and entering a
  zone the human already charts earns one sighting line — never fog.
- **Persistence:** saves keep fixed agendas and pair cooldowns
  (`AiState.to_dict`).

Wiki factors and cooldowns fix the numbers, not the pick; AI peace and overture
offers to the human wait for the court UI.

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
- AI overtures, alliances and peace offers to the human court.
- AI economy and civilian planners; rival stockpiles.
- Dossier evidence and dialogue.

## Architecture

| File | Role |
|------|------|
| `scripts/ai/ai_parameter_registry.gd` | knob catalog |
| `scripts/ai/ai_profile.gd` | blessed profiles |
| `scripts/ai/ai_config.gd` | per-court config |
| `scripts/ai/ai_personality.gd` | leaders, archetypes |
| `scripts/ai/ai_agenda.gd` | agendas, assignment |
| `scripts/ai/ai_power.gd` | power score, bands |
| `scripts/ai/ai_state.gd` | agendas, cooldowns |
| `scripts/ai/ai_diplomacy_planner.gd` | war desire, orders, goals |
| `scripts/ai/ai_military_planner.gd` | split, defend, storm, stage |
| `scripts/ai/ai_naval_planner.gd` | sortie, pursue, hold station |
| `scripts/ai/ai_turn.gd` | turn pass, trace |
| `scripts/map/map_play_diplomacy.gd` | phase wiring |
| `scripts/map/map_play_army_ai.gd` | land pass, march toasts |
| `scripts/map/map_play_fleet_ai.gd` | sea pass, sighting toasts |

No node deps in `scripts/ai` (`REQ-P3-03`).

## Tests

`test_ai_rules` (power, parameters, planners, turn, naval).

```bash
gd-tools test --coverage --min 80
```
