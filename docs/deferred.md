# Deferred features (ranked)

Audited through DR-20261116-11 + #825 (REQ-P2-02).

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
| Raid hulls/rival raids/naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory/soft weights | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`; `AiPosture` |
| Declare-war slot | `SLOT_DECLARE_WAR`, DR-14-13 |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner` |
| Tribe chain door | `AiTribeColony.door`, research planner, #554 |
| Hull chest + material row | `AiNavy`/`AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers/slow luxury/bench + AI tiers | `min_tier`/`turns`, `QUEUE_CAP`, #568 |
| War-time trade garrison + rival bench | `AiNavalPlanner.trade_garrison`; `_bench_room` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate + rival second-stage | `min_town`; `TownIndustry.best_level`, #798 |
| Regiment dismiss | `ArmyDismiss`, DR-16-07/#809 |
| Money-goal reweight + Tribe-chain slot | `goal_mille` #821; `SLOT_TRIBE_CHAIN` #825 |
| Destitute-economy bundle | ration ×2; ward gate; muster un-latch; #823 |

## Gaps (impact order)

1. **Domain dispatch beyond the three live slots** — voyage, declare-war,
   Tribe-chain ship in `opens`; civilian, market, naval stay seed
   (DR-13-15 / DR-16-11).
2. **Civilian-build seeds** — exotic mixes / per-tile previews
   (`civilian-build-planner`).
3. **Quick Battle multi-lane / collapse** — one lane; wider deployment /
   collapse need a design call (DR-10-24).

## Next pick

Domain dispatch beyond voyage/declare-war/Tribe-chain — civilian, market,
naval (DR-13-15 / DR-16-11).

## Blocked footnotes

- Predict-the-line — declined (DR-12-02); era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade/sheltering trains — pending design (DR-12-07).
- Alt victory, difficulty extras, ruleset loaders, loans past the research
  floor, warehouse logistics, sea-zone names — out of scope.
- Join Empire cost table — rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Further tongues out of scope (DR-13-12); 30% floor data-gated (DR-15-18).
- Resource-need phase reweight — no need reading (DR-16-09).

## Wiki drift

- `civilian-units`: Road L2/gathering/transport deferred → live
  (`TechUnlocks`/`Extraction`).
- `phase-planner-*`: DR-14-11 for declare-war → true DR-14-13.
- `production-recipes`: rival second-stage deferred → live #798.
- `ai-architecture`: soft weights + treasury-recovery seed → live
  (`AiPosture`/`goal_mille` #821; tribe-chain #825).
- DR-11-05 + DR-14-11 fleetless leg — live (`TribeContact`,
  `AiTribeColony`, `FleetMuster`).
- Ruleset loader / borrowing — out of scope.

