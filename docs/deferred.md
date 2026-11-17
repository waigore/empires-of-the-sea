# Deferred features (ranked)

Audited: DR-20261117-11 vs code through #914 (REQ-P2-02).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` |
| Home-fleet/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony/Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Fleetless first-hull import | `TradeCargo.PORT_ALLOWANCE` |
| Counter-spy/court reports/fog/Passage | espionage; `CourtCharts` |
| Favoured partner/GP–Tribe contact | `MarketFavoured`; `TribeContact` |
| Hospitals/rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back |
| Regiment records/rename/decorations/leaders | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog` |
| Raid hulls/rival prizes/naval plate | `NavalRaid`, `MapPlayRaids`, `NavalPlate` |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory/goal | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`; `AiPosture` |
| Declare-war / Tribe-chain / crew slots | `SLOT_DECLARE_WAR`/`TRIBE_CHAIN`/`CREWS` |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner` |
| Tribe chain door; hull chest | `AiTribeColony.door`; `AiNavy`/`AiClaims.HULLS` |
| Worker tiers/slow luxury/bench | `min_tier`/`turns`, `QUEUE_CAP` |
| War-time trade garrison + rival bench | `AiNavalPlanner.trade_garrison`; `_bench_room` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate + rival second-stage | `min_town`; `TownIndustry.best_level` |
| Regiment dismiss; money-goal reweight | `ArmyDismiss`; `goal_mille` |
| Destitute-economy bundle | ration ×2; ward gate; muster un-latch |
| Market + naval dispatch | `trade.market`/`navy.missions`, DR-17-01 |
| Archetype civilian mixes | `AiStaffTaste`, DR-17-04 |
| Estate/wall/ward/transport/crew previews | ledgers + `MapPlayCivilianPick`/`MapPlayCivilianFollow` + chart mark, DR-17-03/05/06/07/09 |
| QB wings, lane targeting, collapse | `QuickBattleWings`, DR-17-08 |
| Rail pick's door; dossier rail block | `RailWorks`; `ProvinceRailBlock`, DR-17-10 |
| Observatory province sheet | `ObserverProvince`; `ObserverProvinceSheet`, DR-17-11/#914 |

## Gaps (ranked)

None open: the observatory reads a province (DR-17-11/#914).

## Next pick

P5 polish: observer order-feed depth (`FEED_TURNS`=2); re-audit wiki.

## Blocked

- Predict-the-line (DR-12-02); era — no model (DR-11-08).
- Healing at 0 health; last-known OOB (DR-12-04/09); general-grade trains
  (DR-12-07).
- Soft priority weight — still seed (DR-17-01); posture/goal/victory live.
- Alt victory, difficulty extras, ruleset loaders/borrowing, warehousing,
  loans, sea-zone names — out of scope; Join Empire cost — rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Rival split/combine, cross-station folds, passenger transfers — out of
  scope (DR-16-12/13).
- Further tongues (DR-13-12); 30% floor data-gated (DR-15-18).
- Resource-need reweight — no need reading (DR-16-09).
- QB placed figures / per-wing orders — out of scope (DR-17-08).

## Wiki drift

- `playtest-learnings`: "no province sheet" stale — live DR-17-11/#914;
  feed still two turns; railroad Follow live DR-17-10/#902.
- `civilian-build-planner`: pick family closed (DR-17-03/05/06/07/09/10).
- `quick-battle`: terrain + wings live (`SiegeLanes`, `QuickBattleWings`).
- `phase-planner-*`: six slots live; soft weight seed (DR-17-01).
- `production-recipes`: still marks rival second-stage deferred; live #798.
- DR-11-17 prizes, fleetless leg — live (`MapPlayRaids`).
