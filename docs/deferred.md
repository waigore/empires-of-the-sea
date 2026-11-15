# Deferred features (ranked)

Audited through DR-20261116-05 + #798 (REQ-P2-02).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` #496–#501 |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` (DR-15-03) |
| Home-fleet/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony profit/Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Fleetless first-hull import | `TradeCargo.PORT_ALLOWANCE`, #606 |
| Counter-spy/court reports/fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner/GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals/rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back (`MapPlayCivilianAi.work_rows`), DR-13-08/14 |
| Regiment records/rename/decorations/leader bonuses | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog`, DR-13-18 |
| Raid hulls/rival raids/naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory pressure | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`, DR-15-04 |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner`, DR-14-02/03 |
| Tribe chain door | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy`/`AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers/slow luxury rows/bench cap | `min_tier`/`turns`, `QUEUE_CAP`, DR-14-07/10/12 |
| AI candidates respect worker-tier | `AiEconomyPlanner`/`AiRandomCourt`, #568 |
| War-time trade garrison | `AiNavalPlanner.trade_garrison`, DR-14-08/#567 |
| Rival bench room | `AiEconomyPlanner._bench_room`, `AiRandomCourt`, DR-15-02 |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20,000; DR-15-16/#688/#676 |
| Recipe building gate | `ProductionRecipes.min_town`; garments/rum, DR-20261116-04 |
| Rival second-stage appetite | `TownIndustry.best_level` read by `AiEconomyPlanner`/`AiRandomCourt` plans and the rival phase, DR-20261116-04/#798 |

## Gaps (impact order)

1. **Domain dispatch beyond the voyage** — `AiPhasePlanner.opens` ships voyage
   and declare-war; soft weights, treasury recovery and more slots stay seed
   (DR-13-15).
2. **Civilian-build seeds** — exotic mixes and per-tile previews stay seed
   (`civilian-build-planner`); polish.
3. **Quick Battle multi-lane / collapse** — `QuickBattle` fights one lane;
   wider deployment and the collapse model need a design call (DR-10-24).

## Next pick

Domain dispatch beyond the voyage (DR-13-15).

## Blocked footnotes

- Predict-the-line — declined (DR-12-02); era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade/sheltering trains — pending design (DR-12-07).
- Alt victory, difficulty extras, ruleset loaders, loans past the research
  floor, warehouse logistics, sea-zone names — out of scope.
- Join Empire keeps its published cost table.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12); 30% floor — data-gated
  (DR-20261115-18).

## Wiki drift

- `civilian-units` calls Road L2, gathering and transport caps deferred (live:
  `TechUnlocks`/`Extraction`).
- `ai-architecture` seed list still names victory pressure (live, DR-15-04).
- `phase-planner-*` cite DR-14-11 for DR-14-13.
- `production-recipes` still calls the rival's second-stage appetite deferred
  (live: #798).
- DR-11-05 Deferred + DR-14-11 fleetless leg — live (`TribeContact`,
  `AiTribeColony`, `FleetMuster`).
- Ruleset loader and borrowing (`leader-bonuses`, `military-generals`) stay
  out of scope.
