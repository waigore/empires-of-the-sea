# AI courts

Deterministic ([AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles** (`AiParameterRegistry`, `AiProfile`, `AiConfig`,
  `AiPersonality`, `AiAgenda`): 3 profiles, 7 archetypes, 6 agendas.
- **Money goal** (`AiIncome`): at war the reserve is the next muster, or the
  hull (`AiNavy`) once its chest is in reach; at peace the cash floor, plus the
  muster chest once the purse holds the cheapest line's own price. A stalled
  chest re-routes (`AiDeferral`, #603); on `earn` the auction holds it back
  (DR-20261113-19/22, DR-20261114-06/11).
- **Power** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30/+5/−25.
- **War desire** (`AiDiplomacyDesire`): base 50, power, relations, agenda;
  goals `round(desire/25)`; weariness and truces lower it
  (DR-20261113-25, DR-20261114-01).
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact,
  boycott, subsidy, aid (DR-20261110-15, DR-20261111-27).
- **Turn pass** (`AiTurn`): one order per rival, wars first.
- **Land planner** (`AiMilitaryPlanner`): at border war, detach all but one
  Home regiment; armies save or storm.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron, else raid a hostile coast; at peace, home (DR-20261110-21/30).
- **Minor/Tribe defence** (`AiDefensePlanner`): hold; invaders draw relief.
- **Court charts** (`CourtCharts`/`MapPlayCourtFog`): each court's fog, read
  by voyages, invasions, work, diplomacy (DR-20261113-03); the observer's
  former human slot charts like any rival (#603).
- **Colonisation** (`AiColonisationPlanner`): dock, board, cross, land; the
  squadron returns empty (DR-20261111-05, DR-20261114-03).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): detach
  hulls, dock, board, cross, storm the coast (DR-20261114-03).
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest affordable
  tier keeping a peasant and the cash floor.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots;
  funding shifts with leader weight and a tech thief's +1 step
  (DR-20261111-27), above the money-goal reserve; when `none`, one Low study
  pays the cash floor (DR-20261113-24), priced on its own budget (#590).
- **Tribal courts** (`TribeContact`): first contact with every charted Tribe,
  then overtures and deeds (DR-20261111-14).
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  builders finish towns, engineers raise roads/ports/forts/hospitals,
  explorers prospect, merchants buy deeds (DR-20261111-16/10).
- **Spy** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above reserve,
  bid short inputs; merchants sail home (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading era; Tribes
  stay 1; rivals re-equip and pay to attack.
- **Rival muster** (`AiArmyReinforce`): a line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*` and its
  pattern's inputs (DR-20261111-04, DR-20261113-08); the wornest takes a train
  at war (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): Extraction → Riches → Consumption →
  Production; trade.
- **War footing** (`AiPhasePlanner`): `war`/`fronts`/`peace`; overstretch takes
  peace (DR-20261113-15). **Victory pressure** (`AiVictoryPressure`): bigger
  aims near the bar (DR-20261114-04).
- **Objective ledger** (`AiObjective*`, `MapPlayObjectivesAi`): rank then
  allocate a 0–100 utility ([`ai-objectives.md`](ai-objectives.md)); an
  unfundable study reads `blocked`, never 0-gold `funded` (#590).
- **Deferred aims** (`AiDeferral`): each aim's stall rides the save; a stalled
  war chest re-routes and a long stall reads `blocked` (#603).
- **Persistence:** agendas, cooldowns, ledgers, claims
  (`AiState.to_dict`), dossier.

## Deferred (REQ-P2-02)

New World colony; domain gating — [`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`;
suites `test_ai_*`, `test_military_parity` (`gd-tools test --coverage --min 80`).
