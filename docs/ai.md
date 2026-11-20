# AI courts

Deterministic ([wiki](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles** (`AiParameterRegistry`, `AiConfig`, `AiPersonality`,
  `AiAgenda`): 3 profiles, 7 archetypes, 6 agendas.
- **Money goal** (`AiIncome`): reserve is the next muster or hull chest
  (`AiNavy`), else `economy.min_treasury`; on `earn` the auction holds it
  (DR-20261113-19/22, DR-20261114-06/11).
- **Power** (`AiPower`): provinces×10 + regiments + ships×5; bands
  +30/+5/−25.
- **War desire** (`AiDiplomacyDesire`): base 50, power, relations, agenda;
  goals `round(desire/25)`. Envy +20; a deed resists; weariness, erosion
  and truces lower it (DR-20261113-25/14-01/18-27).
- **Diplomacy planner** (`AiDiplomacyPlanner`): one order from that tally.
  Declarations need relation ≤ ceiling (50; warmonger 70, peacemaker 30) and
  desire ≥ 51; at war, below `50 + peace_bias` peace is offered, each refusal
  doubling the wait (DR-20261115-01). A buyable Tribe
  lifts its envoy chain, not war (DR-20261114-02).
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact,
  boycott, subsidy, aid; friendly acts cost desire and standing
  (DR-20261110-15); isolationist −20, backstabber +25 (DR-20261111-27).
  One order per rival, wars first (`AiTurn`).
- **Land planner** (`AiMilitaryPlanner`): at border war detach all but one
  Home regiment; armies save or storm.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron (DR-20261110-21), else raid a hostile coast (DR-20261111-17); at
  peace, home (DR-20261110-30).
- **Minor/Tribe defence** (`AiDefensePlanner`): hold; invaders draw relief.
- **Court charts**: each court's fog, read by voyages, invasions, diplomacy
  (DR-20261113-03).
- **Colonisation** (`AiColonisationPlanner`): docks, boards, crosses, lands,
  returns empty (DR-20261111-05/14-03); the crew is an Explorer, a Builder on
  crown ground, or the claim's Merchant (#1127).
- **Overseas invasions** (`AiInvasionPlanner`): detach hulls, dock, board,
  cross, storm the coast (DR-20261114-03); the earn lift stands down while
  pressing (DR-20261119-14).
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; the highest
  affordable tier keeping a peasant and cash floor.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots
  above the money-goal reserve (DR-20261111-27); when `none`, one Low study
  pays the cash floor (DR-20261113-24) and, while banking, the
  ration-estate cap study (#1059).
- **Civilian planner** (`AiCivilianPlanner`, `MapPlayCivilianAi`,
  `AiMerchantWork`): builders finish towns, engineers raise roads/ports/
  forts/hospitals (DR-20261111-16), explorers prospect, merchants buy deeds
  (DR-20261111-10); one crew more of the archetype's type (`AiStaffTaste`).
- **Spy** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above
  reserve, bid short inputs; merchants sail home, a hull more when tonnage
  outruns (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the era; Tribes stay
  1; rivals re-equip, pay to attack.
- **Rival muster** (`AiArmyReinforce`, `MapPlayArmyMusterAi`): a line regiment a
  turn under `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04) and pattern inputs (DR-20261113-08); at war the wornest
  trains (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): civilians; Extraction → Riches →
  Consumption → Production; trade.
- **War footing** (`AiPhasePlanner`): `war`/`fronts`/`peace`; overstretch
  takes peace but its border front (`AiBorderFronts`), no peer war
  (DR-20261113-15/11/19-16); at war no new voyage or Tribe
  chain (DR-20261116-11). **Victory pressure** (`AiVictoryPressure`): bigger
  aims near the bar (DR-20261114-04).
- **Objective ledger** (`AiObjective*`, `MapPlayObjectivesAi`): rank, then
  allocate a 0–100 utility.
- **Persistence:** agendas, cooldowns, ledgers, claims
  (`AiState.to_dict`), dossier. Bank (#995/#1059): the chest kept at peace.

## Deferred (REQ-P2-02)
None; ranked gaps: [`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`;
suites `test_ai_*`.

```bash
gd-tools test --coverage --min 80
```
