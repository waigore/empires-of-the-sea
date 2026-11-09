# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
Only the observer scripts that slot.

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 unbookkept rivals.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): every knob is a bounded catalog key;
  profiles are `normal`, `aggressive`, `economic`; leaders use the seven wiki
  archetypes and one of six agendas fixed from `hash(seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers; improve-relations is the complement. Declarations
  need relation ≤ ceiling (50; warmonger 70, peacemaker 30), desire ≥ 51 and no
  4-turn cooldown; goals clamp `round(desire / 25)` to target provinces. At
  war, desire below 50 offers peace — immediate to a rival, queued for the
  human, with a 3-turn cooldown.
- **Turn pass** (`AiTurn`): one legal order per rival through `DiplomacyRules`,
  traced; human proposals queue. Declarations land before combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border a rival detaches
  all but one Home Army regiment, then field armies save an occupied province,
  storm an adjacent hostile one (10% margin after wall soak), or stage on the
  nearest frontier via `ArmyMovement`.
- **Naval planner** (`AiNavalPlanner`): at war sortie or pursue one zone onto
  the weakest matchable squadron (120% margin); at peace hold station, via
  `NavalMovement`; a charted zone earns one sighting line, never fog.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace and never
  attack; an invader on home soil draws a relief column from the Home Army
  (one regiment keeps the seat) to that province, the seat first, own land only.
- **Economy planner** (`AiEconomyPlanner`): each rival keeps a `PlayerEconomy`
  ledger. Recipes score by stock deficit (`economy.reserve_target`,
  `economy.recipe_weight`); whole runs are allocated under labour and inputs.
  Recruitment trains the highest affordable tier up to `economy.worker_target`
  and `economy.max_recruits`.
- **Civilian planner** (`AiCivilianPlanner`): one `CivilianWork`-validated order
  per idle rival civilian — builders improve the shortest commodity, engineers
  road/port/fort, explorers prospect and walk to minerals, rail builders
  upgrade roads; training up to `civilian.max_civilians`.
- **Rival turn** (`MapPlayEconomyAi`): seeds opening civilians once per region,
  resolves Extraction → Riches → Consumption → Production on the shared market
  (prices advance once with the player), then sets next assignments. Rival
  stockpiles feed the diplomacy resource-need score.
- **Persistence:** agendas, cooldowns and rival ledgers (`AiState.to_dict`).

## Full-AI observer (debug)

Title screen `AI OBSERVER (DEBUG)` and `tools/ai_vs_ai.gd` pit every Great Power
against the others on the new-game defaults; see [`ai-observer.md`](ai-observer.md)
for the entry points, metrics and trace export.

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
- AI research and world-market trade planners; rival fog exploration.
- Dossier evidence and dialogue.

## Architecture

Planners and catalogs live in `scripts/ai/` (pure rules, no node deps —
`REQ-P3-03`); `scripts/map/map_play_{diplomacy,army_ai,fleet_ai,economy_ai}.gd`
wire them to `PlaySession`.

## Tests

`test_ai_rules` (power, parameters, planners, turn, naval, economy, civilians,
Minor / Tribe relief).

```bash
gd-tools test --coverage --min 80
```
