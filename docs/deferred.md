# Deferred features (ranked)

Audited: DR-20261119-04 vs code through #1026 (REQ-P2-02).
Default: largest item here, then REQ/wiki.

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` |
| Home-fleet/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony/Join/voyage | `EconomyOverseas`, `FirstRight`; land DR-18-19/23 |
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
| Recipe gate + rival second-stage | `min_town`; `AiEconomyPlanner`/`town_level` |
| Regiment dismiss; money-goal reweight | `ArmyDismiss`; `AiPosture.goal_mille` |
| Destitute-economy bundle | ration ×2; ward gate; muster un-latch |
| Market + naval dispatch | `trade.market`/`navy.missions`, DR-17-01 |
| Archetype civilian mixes | `AiStaffTaste`, DR-17-04 |
| Raise/crew/yard/muster/workers/college/deed/town | ledgers + Follow; hire/batch/`carries`/fund-all |
| QB wings + handset plate | `QuickBattleWings`; `BattlePlateFrame`, DR-17-08/14 |
| Rail pick door; dossier rail | `RailWorks`; `ProvinceRailBlock`, DR-17-10 |
| Observatory sheet + feed | `ObserverProvince*`; `ObserverTurnFeed`, DR-17-11/12 |
| Capital Wood walls + fort lift | `FortCapital`, DR-17-13/#926 |
| Yard/shipyard one-press batch | `queue_all`; `RaiseBatchSum`, DR-18-07/08/11 |
| Dead Bid; gift; larder; production line | `bid_block`; `DiplomacyGift`; `LarderRead`; `ProductionBatch` |
| Buy-out / pointless peace; AI re-field | `_buys_out`; `pointless`; `rotate_home` DR-18-20/22/27 |

## Gaps (ranked)

- None (through #1026).

## Next pick

REQ/wiki.

## Blocked

- Predict-the-line (DR-12-02); era — no model (DR-11-08).
- Healing at 0 health; last-known OOB (DR-12-04/09); general-grade trains
  (DR-12-07).
- Soft priority weight — seed (DR-17-01); resource-need phase reweight —
  no need reading (DR-13-15; money-goal live DR-16-09).
- Alt victory, difficulty extras, ruleset loaders/borrowing, warehousing,
  loans, sea-zone names — out of scope; Join Empire cost — rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Cross-station folds / passenger transfers — out of scope (AI
  split/combine live). Further tongues (DR-13-12); 30% floor data-gated
  (DR-15-18). QB placed figures / per-wing orders — out of scope (DR-17-08).

## Wiki drift

- `civilian-units` Road L2/gathering live; `production-recipes` second-stage live.
- `phase-planner-*`: six slots live; soft weight seed. Through DR-19-04;
  confirm-face intentional (DR-18-11/12).
