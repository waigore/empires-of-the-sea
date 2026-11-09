# AI courts

Rival Great Powers act through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).

**Pillars:** P2 rules fidelity, P3 pure testable rules, P4 no per-frame work,
P5 rivals act unmanaged.

## Implemented

- **Parameter registry** (`AiParameterRegistry`): every weight and threshold is
  a bounded catalog key read via `resolve`.
- **Blessed profiles** (`AiProfile`): `normal`, `aggressive`, `economic`;
  unknown ids fall back, invalid values are rejected.
- **Personalities** (`AiPersonality`): the seven wiki archetypes; leaderKey
  from `LeaderCatalog`.
- **Hidden agendas** (`AiAgenda`): one of six, fixed from
  `hash(game seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments × 1 + ships × 5, with
  relative-power bands +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, relative
  power, relations and modifiers (resource need, rival embassies, invasion
  capacity, multi-war); improve-relations is the complement. Rivals offer the
  next overture (NAP) or an Allied alliance. Declarations need the relation
  ceiling (50; warmonger 70, peacemaker 30), desire ≥ 51 and no 4-turn cooldown;
  goals clamp `round(desire / 25)` to the target's provinces. Below 50 a war
  offers peace — immediate to rivals, queued for the human court, then a
  3-turn cooldown.
- **Turn pass** (`AiTurn`): one legal order per rival per turn through
  `DiplomacyRules`, traced; human proposals queue. Declarations land before
  naval combat.
- **Land planner** (`AiMilitaryPlanner`): a rival at war on its border keeps one
  Home Army regiment; each field army saves an occupied own province, storms an
  adjacent hostile one (10% margin after wall soak), or stages on the nearest
  frontier — via `ArmyMovement`, before Combat.
- **Naval planner** (`AiNavalPlanner`): at war a rival sorties or pursues onto
  the weakest reachable hostile squadron (120% caution margin); at peace it
  holds station. Orders run through `NavalMovement`; entering a charted zone
  earns one sighting line — never fog.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace and never
  attack; an invader on home soil draws a relief column from the Home Army
  (one regiment keeps the seat) to that province, the seat first, own land only.
- **Persistence:** saves keep agendas and pair cooldowns
  (`AiState.to_dict`).

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
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
| `scripts/ai/ai_naval_planner.gd` | sortie, pursue, hold |
| `scripts/ai/ai_defense_planner.gd` | Minor / Tribe relief |
| `scripts/ai/ai_turn.gd` | turn pass, trace |
| `scripts/map/map_play_diplomacy.gd` | phase wiring |
| `scripts/map/map_play_army_ai.gd` | land pass, march toasts |
| `scripts/map/map_play_fleet_ai.gd` | sea pass, sighting toasts |

No node deps in `scripts/ai` (`REQ-P3-03`).

## Tests

`test_ai_rules` (power, parameters, planners, turn, naval) and `test_ai_defense`
(Minor / Tribe relief).

```bash
gd-tools test --coverage --min 80
```
