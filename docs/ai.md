# AI courts

Deterministic ([AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles** (`AiParameterRegistry`, `AiProfile`, `AiConfig`,
  `AiPersonality`, `AiAgenda`): 3 profiles, 7 archetypes, 6 agendas.
- **Money goal** (`AiIncome`): at war the reserve is the muster under
  `army.regiment_target` (+`army.war_extra`), at peace `economy.min_treasury`;
  on `earn` the auction keeps it back and a Passage voyage may open
  (DR-20261113-19/22).
- **Power** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30/+5/−25.
- **War desire** (`AiDiplomacyDesire`): base 50, power, relations, agenda; goals
  `round(desire/25)`. Envy +20; a deed resists; weariness and truces lower it
  (DR-20261113-25, DR-20261114-01).
- **Diplomacy planner** (`AiDiplomacyPlanner`): one order from that tally.
  Declarations need relation ≤ ceiling (50; warmonger 70, peacemaker 30) and
  desire ≥ 51; at war, below `50 + peace_bias` peace is offered. A buyable
  Tribe lifts its envoy chain, not war (DR-20261114-02).
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact,
  boycott, subsidy, aid; friendly acts cost desire and standing
  (DR-20261110-15); isolationist −20, backstabber +25 on a pact
  (DR-20261111-27).
- **Turn pass** (`AiTurn`): one order per rival, wars first.
- **Land planner** (`AiMilitaryPlanner`): at border war, detach all but one
  Home regiment; armies save or storm.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron (DR-20261110-21), else raid a hostile coast (DR-20261111-17,
  DR-20261109-17); at peace, home (DR-20261110-30).
- **Minor/Tribe defence** (`AiDefensePlanner`): hold; invaders draw relief.
- **Court charts** (`CourtCharts`/`MapPlayCourtFog`): each court's own fog, read
  by voyages, invasions, work, diplomacy (DR-20261113-03).
- **Colonisation** (`AiColonisationPlanner`): the squadron docks at the crown's
  harbour to board, cross and land, then crosses home empty (DR-20261111-05,
  DR-20261114-03).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): detach
  hulls, dock, board, cross; storm the coast (DR-20261114-03).
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest affordable
  tier keeping a peasant and the cash floor.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots;
  funding shifts with leader weight and a tech thief's +1 step
  (DR-20261111-27), above the money-goal reserve; when `none`, one Low study
  pays the cash floor (DR-20261113-24).
- **Tribal courts** (`TribeContact`): rivals open first contact with every
  charted Tribe, then overtures and deeds (DR-20261111-14).
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  builders finish towns, engineers raise roads/ports/forts/hospitals
  (DR-20261111-16), explorers prospect, merchants buy deeds (DR-20261111-10).
- **Spy** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above reserve,
  bid short inputs above it; merchants sail home, one hull more when tonnage
  outruns (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading era; Tribes
  stay 1; rivals re-equip and pay to attack.
- **Rival muster** (`AiArmyReinforce`): a line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04) and its pattern's inputs (DR-20261113-08); at war the wornest
  army takes a train (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): civilians; Extraction → Riches →
  Consumption → Production; trade.
- **War footing** (`AiPhasePlanner`): `war`/`fronts`/`peace`; overstretch takes
  peace (DR-20261113-15).
- **Objective ledger** (`AiObjective*`, `MapPlayObjectivesAi`): rank then
  allocate a 0–100 utility ([`ai-objectives.md`](ai-objectives.md)).
- **Persistence:** agendas, cooldowns, ledgers, claims
  (`AiState.to_dict`), dossier.

## Deferred (REQ-P2-02)

New World colony; soft priority — [`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`;
suites `test_ai_*`, `test_military_parity`, `test_espionage`, `test_visibility`.

```bash
gd-tools test --coverage --min 80
```
