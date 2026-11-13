# AI courts

Deterministic ([AI architecture](https://github.com/waigore/empires-of-the-sea/wiki/ai-architecture)).

## Implemented

- **Registry, profiles** (`AiParameterRegistry`, `AiProfile`, `AiConfig`,
  `AiPersonality`, `AiAgenda`): three profiles, seven archetypes, six agendas.
- **Money goal** (`AiIncome`): at war the reserve is the muster under
  `army.regiment_target` (+`army.war_extra`), at peace `economy.min_treasury`;
  on `earn` research and the auction keep it back, but a Passage voyage may
  open (DR-20261113-19/22).
- **Power** (`AiPower`): provinces × 10 + regiments + ships × 5; bands
  +30/+5/−25.
- **Diplomacy planner** (`AiDiplomacyPlanner`): desire: base 50, power,
  relations, agenda. Declarations need relation ≤ ceiling (50; warmonger 70,
  peacemaker 30) and desire ≥ 51 off cooldown; goals `round(desire/25)`.
  At war, desire below `50 + peace_bias` offers peace; envy adds +20 against
  the leader, a deed resists. Weariness and truces (#475) lower it.
- **Court menu** (`AiDiplomacyOffers`): overtures, alliance, trade pact,
  boycott, subsidy, aid; friendly acts cost desire and standing
  (DR-20261110-15), and an isolationist prices a pact 20 lower, a backstabber
  +25 (DR-20261111-27).
- **Turn pass** (`AiTurn`): one order per rival, wars first.
- **Land planner** (`AiMilitaryPlanner`): at border war, detach all but one
  Home regiment; field armies save or storm.
- **Naval planner** (`AiNavalPlanner`): at war sortie/pursue the weakest
  squadron (DR-20261110-21), else raid a hostile coast (DR-20261111-17,
  DR-20261109-17); at peace, home (DR-20261110-30).
- **Minor/Tribe defence** (`AiDefensePlanner`): hold; invaders draw relief.
- **Court charts** (`CourtCharts`/`MapPlayCourtFog`): each court's own fog;
  voyages, invasions, work and diplomacy read it (DR-20261113-03).
- **Colonisation** (`AiColonisationPlanner`): the squadron docks at the crown's
  harbour; board, cross, land (DR-20261111-05).
- **Overseas invasions** (`AiInvasionPlanner`, `MapPlayInvasionAi`): detach
  hulls, dock, board, cross; storm the best coast.
- **Economy** (`AiEconomyPlanner`): recipes by stock deficit; highest affordable
  tier keeping a peasant and `economy.min_treasury`.
- **Research planner** (`AiResearchPlanner`): fill `ResearchState` slots;
  funding shifts with the leader weight and a tech thief's +1 step
  (DR-20261111-27), then down to what the purse carries after its floor —
  at war, its muster.
- **Tribal courts** (`TribeContact`): rivals open first contact with every
  charted Tribe, then overtures and deeds (DR-20261111-14).
- **Civilian planner** (`AiCivilianPlanner`/`MapPlayCivilianAi`, `AiMerchantWork`):
  builders finish towns, engineers raise roads/ports/forts/hospitals
  (DR-20261111-16), explorers prospect, merchants buy deeds (DR-20261111-10).
- **Spy** (`AiSpyPlanner`): station abroad, screen at war.
- **Market & cargo** (`AiMarketPlanner`, `AiCargoPlanner`): sell above reserve,
  bid short inputs above that floor; merchants sail home, one hull more when
  tonnage outruns them (DR-20261110-26).
- **Regiment parity** (`MilitaryParity`): Minors match the leading era; Tribes
  stay 1; rivals re-equip and pay attack prices.
- **Rival muster** (`AiArmyReinforce`): a line regiment a turn under
  `army.regiment_target` (+`army.war_extra`), keeping `army.min_*`
  (DR-20261111-04) and its pattern's inputs (DR-20261113-08); seat moves recall
  it. At war the wornest army takes a train (DR-20261112-08).
- **Rival turn** (`MapPlayEconomyAi`): civilians, Extraction → Riches →
  Consumption → Production, trade.
- **War footing** (`AiPhasePlanner`): `war`/`fronts`/`peace`; overstretch takes
  any peace (DR-20261113-15).
- **Objective ledger** (`AiObjective*`, `MapPlayObjectivesAi`): rank then
  allocate in a 0–100 utility ([`ai-objectives.md`](ai-objectives.md)).
- **Persistence:** agendas, cooldowns, ledgers, claims
  (`AiState.to_dict`), dossier ([`intel-dossier.md`](intel-dossier.md)).

## Deferred (REQ-P2-02)

Phase soft priority — [`deferred.md`](deferred.md).

## Architecture & tests

Planners live in `scripts/ai/` (`REQ-P3-03`), wired by `scripts/map/map_play_*`;
suites `test_ai_*`, `test_military_parity`, `test_espionage`, `test_visibility`.

```bash
gd-tools test --coverage --min 80
```
