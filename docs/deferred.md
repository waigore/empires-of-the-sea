# Deferred features (ranked)

Audited through DR-20261117-05; #846–#877 live (REQ-P2-02).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` #496–#501 |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` |
| Home-fleet/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony profit/Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Fleetless first-hull import | `TradeCargo.PORT_ALLOWANCE`, #606 |
| Counter-spy/court reports/fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner/GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals/rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back |
| Regiment records/rename/decorations/leaders | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog` |
| Raid hulls/rival prizes/naval plate | `NavalRaid`, `MapPlayRaids`, `NavalPlate` |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory/goal reweight | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`; `AiPosture` |
| Declare-war / Tribe-chain / crew slots | `SLOT_DECLARE_WAR`/`TRIBE_CHAIN`/`CREWS` |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner` |
| Tribe chain door | `AiTribeColony.door`, research planner, #554 |
| Hull chest + material row | `AiNavy`/`AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers/slow luxury/bench + AI tiers | `min_tier`/`turns`, `QUEUE_CAP`, #568 |
| War-time trade garrison + rival bench | `AiNavalPlanner.trade_garrison`; `_bench_room` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate + rival second-stage | `min_town`; `TownIndustry.best_level`, #798 |
| Regiment dismiss | `ArmyDismiss`, DR-16-07/#809 |
| Money-goal reweight | `goal_mille` #821 |
| Destitute-economy bundle | ration ×2; ward gate; muster un-latch |
| Market + naval dispatch | `trade.market`/`navy.missions`, DR-20261117-01 |
| Archetype civilian mixes | `AiStaffTaste`, DR-20261117-04 |
| Estate + walls/wards/transport previews | `EstateRows`/`WallLedger`/`HospitalLedger`; `CivilianWorkPlan`, DR-17-03/05 |

## Gaps (ranked)

1. **Planner on-chart per-tile preview** — ledger/order legs live
   (DR-17-03/05); court's next pick on chart stays seed.
2. **Quick Battle multi-lane/collapse** — one lane; design call
   (DR-10-24).


## Next pick

Planner on-chart per-tile preview seed.

## Blocked

- Predict-the-line declined (DR-12-02); era — no model (DR-11-08).
- Healing at 0 health; last-known OOB (DR-12-04/09); general-grade trains await
  design (DR-12-07).
- Soft priority weight vector — still seed (DR-17-01); posture/goal/victory
  live.
- Alt victory, difficulty extras, ruleset loaders/borrowing,
  warehousing, loans, sea-zone names — out of scope; Join Empire cost —
  rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Rival split/combine, cross-station folds, passenger transfers — out of
  scope (DR-16-12/13).
- Further tongues out of scope (DR-13-12); 30% floor data-gated (DR-15-18).
- Resource-need reweight — no need reading (DR-16-09).

## Wiki drift

- `civilian-build-planner`: raise previews live (DR-17-03/05); planner
  on-chart pick remains.
- `civilian-units`: Road L2/gathering → live (`TechUnlocks`).
- `phase-planner-*`: six slots live; soft weight vector still seed.
- `production-recipes`: rival second-stage → live #798.
- `ai-architecture`: goal reweight live (#821); soft weight still seed
  (DR-17-01); deed partner claimed.
- DR-11-17 prizes, fleetless leg — live (`MapPlayRaids`).
