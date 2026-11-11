# AI courts

Rivals act through a deterministic, data-tuned stack (wiki:
[AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

**Pillars:** P2–P5.

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): three profiles, seven archetypes,
  six hashed agendas.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30 / +5 / −25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations and modifiers. Declarations need relation ≤ ceiling (50;
  warmonger 70, peacemaker 30), desire ≥ 51, no 4-turn cooldown; goals
  `round(desire / 25)`. At war, desire < 50 offers peace. A deed in a
  Minor/Tribe's land is a stake (`DeedProtection`) that resists a declaration.
- **Court menu** (`AiDiplomacyOffers`): every panel order is a candidate —
  overtures, alliance, trade pact, boycott, subsidy, aid. Friendly acts cost
  desire; retaliation standing (DR-20261110-15).
- **Turn pass** (`AiTurn`): one order per rival through the shared catalogue;
  consent asks queue for the human; declarations first.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home Army regiment; field armies save, storm or stage.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  matchable squadron (120% margin) else hold, charted water only
  (DR-20261110-21); at peace it comes home (DR-20261110-30).
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace, never
  attack; an invader draws a relief column (one regiment keeps the seat).
- **Court charts** (`CourtCharts`, `MapPlayCourtFog`): each court holds its own
  fog; voyages, invasions and work read only that chart (DR-20261110-21).
- **Colonisation** (`AiColonisationPlanner`, `MapPlayColonisationAi`): the
  squadron docks at the crown's own harbour (seat first) and the Explorer
  musters there; board, cross, land (DR-20261111-05).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore; detach hulls, dock, board, cross; storm best coast.
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest
  affordable tier, keeping a peasant and `economy.min_treasury`
  (DR-20261111-06).
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots; `research.funding_index` funds.
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  per idle civilian — builders improve or finish a town, engineers
  connect then road/port/fort, explorers prospect, rail builders upgrade roads;
  merchants buy a Minor/Tribe deed when embassy, peace, mineral and price allow
  (`civilian.merchant_weight`).
- **Spy planner** (`AiSpyPlanner`): station abroad, screen at war; rivals open
  with one.
- **Market planner** (`AiMarketPlanner`): sell above reserve and the turn's
  inputs; bid short build inputs (3 types; 6 with Trade Fairs).
- **Cargo planner** (`AiCargoPlanner`): merchants sail home for their holds;
  one hull more when tonnage outruns them (`cargo.*`, DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading power's
  era; Tribes stay at level 1. Rivals re-equip and pay attack prices
  (`RegimentUpgrades`, `ArmyAttackCost`).
- **Rival muster** (`AiArmyReinforce`): one line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04).
- **Rival turn** (`MapPlayEconomyAi`): civilians, Extraction → Riches →
  Consumption → Production, trade.
- **Persistence:** agendas, cooldowns, ledgers (`AiState.to_dict`).
- **Court dossier** (`IntelDossier`,
  [`intel-dossier.md`](intel-dossier.md)).

## Deferred (REQ-P2-02)

- Rival boycotts.
- Agenda-sourced dialogue beats.

## Architecture

Planners live in `scripts/ai/` (`REQ-P3-03`);
`scripts/map/map_play_*` wire them to `PlaySession`.

## Tests

`test_ai_*`, `test_military_parity`, `test_espionage`, `test_visibility`.

```bash
gd-tools test --coverage --min 80
```