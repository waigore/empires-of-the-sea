# AI courts

Deterministic stack
([AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles, courts** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): three profiles, seven archetypes,
  six agendas reaching peace, trade, war and research.
- **Power score** (`AiPower`): provinces × 10 + regiments + ships × 5;
  bands +30/+5/−25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire from base 50, power,
  relations, agenda. Declarations need relation ≤ ceiling (50; warmonger 70,
  peacemaker 30) and desire ≥ 51 off cooldown. At war, desire below
  `50 + peace_bias` (peacemaker 65, warmonger 40) offers peace; an envious court
  adds +20 against a leading crown. A deed resists it (`DeedProtection`).
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact, boycott,
  subsidy and aid are candidates. Friendly acts cost desire, retaliation
  standing (DR-20261110-15); an isolationist prices a pact 20 lower, a
  backstabber +25 against its ally (DR-20261111-27).
- **Turn pass** (`AiTurn`): one order per rival; consent asks queue; war first.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home Army regiment; field armies save, storm or stage.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron (DR-20261110-21), else a warship raids a hostile coast
  (DR-20261111-17); at peace it returns home (DR-20261110-30).
- **Minor / Tribe defence** (`AiDefensePlanner`): hold at peace, never attack;
  an invader draws a relief column.
- **Court charts** (`CourtCharts`, `MapPlayCourtFog`): each court holds its own
  fog; voyages, invasions, work and diplomacy read that chart (DR-20261113-03).
- **Colonisation** (`AiColonisationPlanner`, `MapPlayColonisationAi`): the
  squadron docks at the crown's harbour (seat first), the Explorer musters;
  board, cross, land (DR-20261111-05).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore; detach hulls, dock, board, cross; storm best coast.
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest
  affordable tier, keeping a peasant and `economy.min_treasury`.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots;
  funding shifts with the leader weight and a tech thief's +1 step
  (DR-20261111-27), then down to what the purse carries after its cash floor,
  at war its next muster (`AiArmyReinforce.muster_floor`).
- **Tribal courts** (`TribeContact`): rivals open first contact with every
  charted Tribe at the close, then overtures and deeds (DR-20261111-14).
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  builders finish towns, engineers connect and raise road/port/fort/hospital
  (DR-20261111-16), explorers prospect, rail builders upgrade roads; merchants
  buy deeds where embassy, peace, mineral and price allow (DR-20261111-10).
- **Spy planner** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above reserve,
  bid short inputs within the same war chest; merchants sail home, one hull
  more when tonnage outruns them (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading power's era,
  Tribes stay at 1; rivals re-equip and pay attack prices.
- **Rival muster** (`AiArmyReinforce`): one line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04) and its next pattern's inputs (DR-20261113-08); wornest field
  army takes a hospital train at war (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): civilians, Extraction → Riches →
  Consumption → Production, trade.
- **Persistence:** agendas, cooldowns, ledgers (`AiState.to_dict`), dossier
  ([`intel-dossier.md`](intel-dossier.md)).

## Deferred

Deferred: [`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`.

```bash
gd-tools test --coverage --min 80
```
