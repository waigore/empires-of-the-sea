# AI courts

Rivals act through a deterministic, data-tuned stack (wiki:
[AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).

**Pillars:** P2, P3, P4, P5.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): three profiles, seven archetypes,
  six agendas from `hash(seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers. Declarations need relation ≤ ceiling (50;
  warmonger 70, peacemaker 30), desire ≥ 51, no 4-turn cooldown; goals clamp
  `round(desire / 25)`. At war, desire < 50 offers peace, 3-turn cooldown.
- **Court menu** (`AiDiplomacyOffers`): every panel order is a candidate —
  overtures, alliance/break, trade pact/revoke, boycott/revoke, subsidy/cancel,
  aid. Friendly acts are worth the desire less their spend; retaliation the
  fall in standing (DR-20261110-15).
- **Turn pass** (`AiTurn`): one order per rival through the shared catalogue,
  on the rival's ledger; consent asks queue for the human, one-sided acts land
  at once. Declarations land before combat.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home Army regiment; field armies save, storm or stage.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue onto the weakest
  matchable squadron (120% margin); else blockade or hold via `NavalMovement`.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace, never
  attack; an invader draws a relief column (one regiment keeps the seat) to
  that province, seat first, own land only.
- **Court charts** (`CourtCharts`, `MapPlayCourtFog`): each court holds its own
  fog; voyages, invasions, sorties, blockades and orders read only that chart
  (DR-20261110-21).
- **Colonisation voyages** (`AiColonisationPlanner`, `MapPlayColonisationAi`):
  board an idle Explorer, cross a Passage, land; then prospect or improve.
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore (enemy or Tribe); detach hulls, dock, board, cross;
  storm best coast, else own colony.
- **Economy planner** (`AiEconomyPlanner`): `PlayerEconomy` ledger; recipes by
  stock deficit under labour/inputs; recruit the highest tier it can afford.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots; `research.funding_index` funds.
- **Civilian planner** (`AiCivilianPlanner`): one validated order per idle
  civilian — builders improve shortest commodity or finish a paying town,
  engineers connect towns then road/port/fort, explorers explore and prospect,
  rail builders upgrade roads.
- **Spy planner** (`AiSpyPlanner`): station abroad, screen at war; rivals open
  with one.
- **Market planner** (`AiMarketPlanner`): sell above reserve and this turn's
  inputs; bid short build inputs (3 types; 6 with Trade Fairs).
- **Regiment parity** (`MilitaryParity`): Minor land regiments match the
  strongest Great Power era; Tribes stay at level 1.
- **Rival turn** (`MapPlayEconomyAi`): seed civilians; Extraction → Riches →
  Consumption → Production; trade.
- **Persistence:** agendas, cooldowns, rival ledgers (`AiState.to_dict`).
- **Court dossier** (`IntelDossier`, `CourtDossier`): player's rival reading —
  evidence, suspicion per agenda, best guess, behaviour counts
  ([`intel-dossier.md`](intel-dossier.md)).

## Full-AI observer (debug)

`AI OBSERVER (DEBUG)` / `tools/ai_vs_ai.gd` — see [`ai-observer.md`](ai-observer.md).

## Deferred (REQ-P2-02)

- Intervention and call-to-arms.
- Agenda-sourced dialogue beats.

## Architecture

Planners live in `scripts/ai/` (pure — `REQ-P3-03`);
`scripts/map/map_play_{diplomacy,army_ai,fleet_ai,economy_ai,colonisation_ai,invasion_ai,spies}.gd`
wire them to `PlaySession`.

## Tests

`test_ai_*`, `test_military_parity`, `test_espionage`, `test_visibility`.

```bash
gd-tools test --coverage --min 80
```
