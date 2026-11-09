# AI courts

Rival Great Powers act on their own through a deterministic, data-tuned stack
(wiki: [AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture),
[diplomacy planner](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy-planner)).
The human court is never scripted.

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 rivals act unbookkept.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): every knob is a catalog key;
  profiles are `normal`, `aggressive`, `economic`; leaders use the seven wiki
  archetypes and one of six agendas from `hash(seed, faction)`.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers; improve-relations is the complement. Declarations
  need relation ≤ ceiling (50; warmonger 70), desire ≥ 51 and no 4-turn
  cooldown; goals clamp `round(desire / 25)`. At war, desire below 50 offers
  peace — immediate to a rival, queued for the human, 3-turn cooldown.
- **Turn pass** (`AiTurn`): one legal order per rival through `DiplomacyRules`,
  traced; human proposals queue.
- **Land planner** (`AiMilitaryPlanner`): at war a rival detaches all but one
  Home Army regiment, then field armies relieve an occupied province, storm an
  adjacent hostile one (10% margin after wall soak), or stage via `ArmyMovement`.
- **Naval planner** (`AiNavalPlanner`): at war sortie or pursue onto the weakest
  matchable squadron (120% margin); at peace hold station; a charted zone earns
  one sighting line, never fog.
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace and never
  attack; an invader on home soil draws a relief column (one regiment keeps the
  seat) to that province, the seat first, own land only.
- **Colonisation voyages** (`AiColonisationPlanner`, `MapPlayColonisationAi`):
  a rival takes an idle Explorer (or Builder for overseas land) aboard, crosses
  a Passage and lands; the civilian planner then prospects or improves there.
- **Economy planner** (`AiEconomyPlanner`): each rival keeps a `PlayerEconomy`
  ledger. Recipes score by stock deficit; whole runs allocate under labour and
  inputs. Recruitment trains the highest affordable tier up to the worker and
  recruit caps.
- **Civilian planner** (`AiCivilianPlanner`): one validated order per idle
  civilian — builders improve the shortest commodity, engineers connect every
  town to the capital then road/port/fort, explorers prospect, rail builders
  upgrade roads.
- **Market planner** (`AiMarketPlanner`): sells above the reserve and this
  turn's production inputs, then bids short build inputs on free holds — three
  bid types, six with Trade Fairs.
- **Regiment parity** (`MilitaryParity`): after movement each Minor Nation's
  land regiments upgrade in place to the strongest Great Power's buildable era;
  Tribes stay at level 1.
- **Rival turn** (`MapPlayEconomyAi`): seeds opening civilians, resolves
  Extraction → Riches → Consumption → Production on the shared market, trades,
  then sets next assignments.
- **Persistence:** agendas, cooldowns and rival ledgers (`AiState.to_dict`).

## Deferred (REQ-P2-02)

- Intervention, call-to-arms, boycotts and spy actions.
- AI research; rival fog exploration.
- Dossier evidence and dialogue.

## Architecture

Planners and catalogs live in `scripts/ai/` (pure, no node deps — `REQ-P3-03`);
`scripts/map/map_play_{diplomacy,army_ai,fleet_ai,economy_ai,colonisation_ai}.gd`
wire them to `PlaySession`.

## Tests

`test_ai_rules`, `test_ai_market`, `test_ai_colonisation`, `test_ai_town_roads`,
`test_military_parity`.

```bash
gd-tools test --coverage --min 80
```
