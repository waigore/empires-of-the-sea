# AI courts

Rivals act through a deterministic, data-tuned stack (wiki:
[AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 unbookkept rivals.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): every knob is a catalog key; three
  profiles, seven archetypes, six agendas (`hash(seed, faction)`).
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers. Declarations need relation ≤ ceiling (50;
  warmonger 70, peacemaker 30), desire ≥ 51, no 4-turn cooldown; goals
  `round(desire / 25)`. At war, desire < 50 offers peace. A deed in a
  Minor/Tribe's land is a stake (`DeedProtection`): its holder never stands
  aside (25%; 50% with two) and a declaration costs −8 per warden (cap −24).
- **Court menu** (`AiDiplomacyOffers`): every panel order is a candidate —
  overtures, alliance/break, trade pact/revoke, boycott/revoke, subsidy/cancel,
  aid. Friendly acts worth desire less spend; retaliation the fall in standing
  (DR-20261110-15).
- **Turn pass** (`AiTurn`): one order per rival through the shared catalogue;
  consent asks queue for the human, one-sided acts land; declarations before
  combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home Army regiment; field armies save, storm or stage.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue onto the weakest
  matchable squadron (120% margin); else blockade or hold via `NavalMovement`.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace; an invader
  draws a relief column (one regiment keeps the seat), seat first, own land
  only.
- **Colonisation** (`AiColonisationPlanner`, `MapPlayColonisationAi`): idle
  Explorer boards, crosses, lands; then prospect or improve.
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore; detach hulls, dock, board, cross; storm best coast,
  else own colony.
- **Economy** (`AiEconomyPlanner`): ledger recipes by stock deficit; recruit
  the highest tier it can afford.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots; `research.funding_index` funds.
- **Civilian planner** (`AiCivilianPlanner`): one validated order per idle
  civilian — builders improve shortest commodity or finish a paying town,
  engineers connect towns then road/port/fort, explorers prospect, rail builders
  upgrade roads.
- **Spy planner** (`AiSpyPlanner`): station abroad, screen at war; rivals open
  with one.
- **Market planner** (`AiMarketPlanner`): sell above reserve and this turn's
  inputs; bid short build inputs (3 types; 6 with Trade Fairs).
- **Regiment parity** (`MilitaryParity`): Minor land regiments match the
  strongest Great Power era; Tribes stay at level 1.
- **Rival turn** (`MapPlayEconomyAi`): seed civilians; Extraction → Riches →
  Consumption → Production; trade.
- **Persistence:** agendas, cooldowns, rival ledgers (`AiState.to_dict`).
- **Court dossier** (`IntelDossier`): rival reading — evidence, suspicion per
  agenda, best guess ([`intel-dossier.md`](intel-dossier.md)).

## Deferred (REQ-P2-02)

- **Rival boycotts and rival land purchase** (a rival needs trade envoys
  with a Minor/Tribe before a deed is legal).
- Rival fog exploration.
- Agenda-sourced dialogue beats.

## Architecture

Planners live in `scripts/ai/` (pure — `REQ-P3-03`);
`scripts/map/map_play_{diplomacy,army_ai,fleet_ai,economy_ai,colonisation_ai,invasion_ai,spies}.gd`
wire them to `PlaySession`.

## Tests

`test_ai_rules`, `test_ai_market`, `test_ai_colonisation`, `test_ai_invasion`,
`test_ai_town_roads`, `test_ai_builder_work`, `test_military_parity`,
`test_ai_observer`, `test_ai_diplomacy_offers`, `test_espionage`.

```bash
gd-tools test --coverage --min 80
```
