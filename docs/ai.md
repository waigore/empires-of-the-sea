# AI courts

Deterministic ([AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles** (`AiParameterRegistry`, `AiProfile`,
  `AiConfig`, `AiPersonality`, `AiAgenda`): three profiles, seven archetypes,
  six agendas.
- **Power** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30/+5/−25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): war desire: base 50, power,
  relations, agenda. Declarations need relation ≤ ceiling (50; warmonger 70,
  peacemaker 30) and desire ≥ 51 off cooldown; goals `round(desire / 25)`.
  At war, desire below `50 + peace_bias` offers peace; an envious court adds
  +20 against a leading crown. A deed resists (`DeedProtection`).
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact,
  boycott, subsidy, aid. Friendly acts cost desire and standing
  (DR-20261110-15); an isolationist prices a pact 20 lower, a backstabber +25
  against its ally (DR-20261111-27).
- **Turn pass** (`AiTurn`): one order per rival; consent asks queue; wars
  first.
- **Land planner** (`AiMilitaryPlanner`): at war on its border detach all but
  one Home regiment; field armies save, storm or stage.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron (DR-20261110-21), else a warship raids a hostile coast
  (DR-20261111-17); at peace it returns home (DR-20261110-30).
- **Minor/Tribe defence** (`AiDefensePlanner`): hold at peace; an invader draws
  relief.
- **Court charts** (`CourtCharts`/`MapPlayCourtFog`): each court's own fog;
  voyages, invasions, work and diplomacy read it (DR-20261113-03).
- **Colonisation** (`AiColonisationPlanner`): the squadron docks at the crown's
  harbour, the Explorer musters; board, cross, land (DR-20261111-05).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): no border
  war and a far shore; detach hulls, dock, board, cross; storm best coast.
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest affordable
  tier, keeping a peasant and `economy.min_treasury`.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots;
  funding shifts with the leader weight and a tech thief's +1 step
  (DR-20261111-27), then down to what the purse carries after its floor —
  at war, its next muster (`AiArmyReinforce.muster_floor`).
- **Tribal courts** (`TribeContact`): rivals open first contact with every
  charted Tribe, then overtures and deeds
  (DR-20261111-14).
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  builders finish towns, engineers connect and raise road/port/fort/hospital
  (DR-20261111-16), explorers prospect, rail builders upgrade roads; merchants
  buy deeds where embassy, peace, mineral and price allow (DR-20261111-10).
- **Spy** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above reserve,
  bid short inputs above that same floor; merchants sail home, one hull more
  when tonnage outruns them (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading power's era;
  Tribes stay 1; rivals re-equip and pay attack prices.
- **Rival muster** (`AiArmyReinforce`): one line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04) and its next pattern's inputs (DR-20261113-08); at war its
  wornest field army takes a hospital train (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): civilians, Extraction → Riches →
  Consumption → Production, trade.
- **War footing** (`AiPhasePlanner`): `war` / `fronts` / `peace`; no new voyage
  at war; overstretch takes any white peace (DR-20261113-15).
- **Persistence:** agendas, cooldowns, ledgers (`AiState.to_dict`), the dossier
  ([`intel-dossier.md`](intel-dossier.md)).

## Deferred (REQ-P2-02)

Money-first / `AiIncome` (DR-19); phase seed —
[`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`;
suites `test_ai_*`, `test_military_parity`, `test_espionage`, `test_visibility`.

```bash
gd-tools test --coverage --min 80
```
