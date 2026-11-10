# AI courts

Rival Great Powers act through a deterministic, data-tuned stack (wiki:
[AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 unbookkept rivals.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): every knob is a catalog key;
  profiles `normal` / `aggressive` / `economic`; seven archetypes, six
  agendas from `hash(seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers. Declarations need relation ≤ ceiling (50;
  warmonger 70, peacemaker 30), desire ≥ 51, no 4-turn cooldown; goals clamp
  `round(desire / 25)`. At war, desire < 50 offers peace (rival immediate,
  human queued), 3-turn cooldown.
- **Turn pass** (`AiTurn`): one legal order per rival through `DiplomacyRules`,
  traced; human proposals queue. Declarations land before combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home Army regiment; field armies save, storm (10% margin after walls),
  or stage on the nearest frontier.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue onto the weakest
  matchable squadron (120% margin); else blockade or hold via `NavalMovement`;
  charted zone → one sighting, never fog.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace, never
  attack; an invader draws a relief column (one regiment keeps the seat) to
  that province, seat first, own land only.
- **Colonisation voyages** (`AiColonisationPlanner`, `MapPlayColonisationAi`):
  board an idle Explorer, cross a Passage, land; then prospect or improve.
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore (enemy or Tribe); detach hull capacity, dock, board,
  cross, beachhead; storm best coast, else own colony.
- **Economy planner** (`AiEconomyPlanner`): `PlayerEconomy` ledger; recipes by
  stock deficit; runs under labour/inputs; recruit highest affordable tier to
  caps.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots (weights, shortfalls, war bonus); `research.funding_index` funds; `ResearchTurn` advances.
- **Civilian planner** (`AiCivilianPlanner`): one validated order per idle
  civilian — builders improve shortest commodity or finish a paying town,
  engineers connect towns then road/port/fort, explorers prospect, rail builders
  upgrade roads.
- **Spy planner** (`AiSpyPlanner`): station abroad, screen at war; rivals open
  with one.
- **Market planner** (`AiMarketPlanner`): sell above reserve and this turn's
  inputs; bid short build inputs on free holds (3 types; 6 with Trade Fairs).
- **Regiment parity** (`MilitaryParity`): after movement, Minor land regiments
  match the strongest Great Power era; Tribes stay at level 1.
- **Rival turn** (`MapPlayEconomyAi`): seed civilians; Extraction → Riches →
  Consumption → Production on the shared market; trade; next assignments.
- **Persistence:** agendas, cooldowns, rival ledgers (`AiState.to_dict`).
- **Court dossier** (`IntelDossier`, `CourtDossier`): player's rival reading —
  evidence, banded suspicion per agenda, best guess, behaviour counts
  ([`intel-dossier.md`](intel-dossier.md)).

## Full-AI observer (debug)

`AI OBSERVER (DEBUG)` / `tools/ai_vs_ai.gd` — see [`ai-observer.md`](ai-observer.md).

## Deferred (REQ-P2-02)

- Intervention, call-to-arms and boycotts.
- Rival fog exploration.
- Agenda-sourced dialogue beats.

## Architecture

Planners live in `scripts/ai/` (pure — `REQ-P3-03`);
`scripts/map/map_play_{diplomacy,army_ai,fleet_ai,economy_ai,colonisation_ai,invasion_ai,spies}.gd`
wire them to `PlaySession`.

## Tests

`test_ai_rules`, `test_ai_market`, `test_ai_colonisation`, `test_ai_invasion`,
`test_ai_town_roads`, `test_ai_builder_work`, `test_military_parity`,
`test_ai_observer`, `test_espionage`.

```bash
gd-tools test --coverage --min 80
```
