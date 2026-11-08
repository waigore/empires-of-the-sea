# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
The human court is never scripted.

**Pillars:** P2 (rules fidelity), P3 (pure rules, testable), P4 (no per-frame
work), P5 (rivals act without player bookkeeping).

## Implemented

- **Parameter registry** (`AiParameterRegistry`): every weight and threshold is
  a catalog key with category, bounds and default. Planners read only through
  `resolve`, so profiles tune behaviour without code edits.
- **Blessed profiles** (`AiProfile`): `normal`, `aggressive`, `economic`.
  Unknown ids fall back to normal; invalid values are rejected at load.
- **Personalities** (`AiPersonality`): the seven wiki archetypes with domain
  weights, a war-gate shift and a war-desire bias. Each GP's leaderKey comes
  from `LeaderCatalog`, the roster setup and combat share (Spain Isabella,
  England Victoria, France Napoleon, Portugal Henry, United Provinces
  De Ruyter, Sweden Gustavus).
- **Hidden agendas** (`AiAgenda`): one of six, assigned once from
  `hash(game seed, faction)` and kept for the run.
- **Power score** (`AiPower`): provinces × 10 + regiments × 1 + ships × 5, with
  relative-power bands +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire per candidate court —
  base 50, relative power, relation pressure (−40 / −20 / +10); for Minor/Tribe
  targets also resource need (+5 each, cap +15), rival embassies (−8 each, cap
  −24), invasion capacity (−20 / +10 / −25) and multi-war (−15).
  Improve-relations desire is the complement. Declarations need the relation
  ceiling (50; warmonger 70, peacemaker 30), war desire ≥ 51 and no 4-turn
  cooldown; war goals clamp `round(desire / 25)` to the target's provinces. At
  war, desire below 50 offers peace — only to AI courts.
- **Turn pass** (`AiTurn`): at most one legal order per rival court per turn,
  applied through `DiplomacyRules`, with a per-court trace of candidates and
  factors. War declarations land before naval combat in the same turn.
- **Persistence:** local saves keep each court's fixed agenda and pair cooldowns
  (`AiState.to_dict`), so a load cannot re-roll an agenda or restart a war
  cooldown.

Selection thresholds and biases are implementation defaults in the registry;
the wiki fixes the factors and cooldown lengths, not the pick. AI peace and
overture offers to the human wait for the court UI.

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
- AI overtures, alliances and peace offers to the human court.
- AI economy, military and civilian planners; rival stockpiles.
- Dossier evidence and dialogue.

## Architecture

| File | Role |
|------|------|
| `scripts/ai/ai_parameter_registry.gd` | knob catalog, bounds, defaults |
| `scripts/ai/ai_profile.gd` | blessed profiles |
| `scripts/ai/ai_personality.gd` | leaders, archetypes, weights |
| `scripts/ai/ai_agenda.gd` | agendas, deterministic assignment |
| `scripts/ai/ai_power.gd` | power score and relative bands |
| `scripts/ai/ai_config.gd` | per-court config for the run |
| `scripts/ai/ai_state.gd` | fixed agendas, pair cooldowns |
| `scripts/ai/ai_diplomacy_planner.gd` | war desire, orders, war goals |
| `scripts/ai/ai_turn.gd` | per-turn pass, trace, rule application |
| `scripts/map/map_play_diplomacy.gd` | phase wiring and toasts |

No node deps in `scripts/ai` (`REQ-P3-03`).

## Tests

`test_ai_parameters`, `test_ai_personality`, `test_ai_power`,
`test_ai_planner`, `test_ai_turn`.

```bash
gd-tools test --coverage --min 80
```
