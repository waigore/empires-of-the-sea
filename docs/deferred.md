# Deferred features (ranked)

Audited through DR-20261116-09 + #820 (REQ-P2-02).

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
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back, DR-13-08/14 |
| Regiment records/rename/decorations/leaders | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog`, DR-13-18 |
| Raid hulls/rival raids/naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory/soft weights | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`; `AiPosture` |
| Declare-war slot | `AiPhasePlanner.SLOT_DECLARE_WAR`, DR-14-13 |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner`, DR-14-02/03 |
| Tribe chain door | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy`/`AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers/slow luxury/bench + AI tiers | `min_tier`/`turns`, `QUEUE_CAP`, #568, DR-14-07/10/12 |
| War-time trade garrison + rival bench | `AiNavalPlanner.trade_garrison`; `_bench_room`, DR-14-08/15-02 |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k; DR-15-16 |
| Recipe gate + rival second-stage | `ProductionRecipes.min_town`; `TownIndustry.best_level`, #798 |
| Regiment dismiss | `ArmyDismiss`, DR-16-07/#809 |

## Gaps (impact order)

1. **Domain dispatch beyond voyage/declare-war** — `opens` ships those two;
   further slots stay seed (DR-13-15 / DR-16-09). Treasury-recovery reweight
   is designed (DR-16-09) and open as #821 — still Gap on main.
2. **Civilian-build seeds** — exotic mixes and per-tile previews stay seed
   (`civilian-build-planner`); polish.
3. **Quick Battle multi-lane / collapse** — one lane today; wider deployment
   and collapse need a design call (DR-10-24).

## Next pick

Domain dispatch beyond voyage/declare-war (DR-13-15). Leave #821 to land
treasury-recovery.

## Blocked footnotes

- Predict-the-line — declined (DR-12-02); era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade/sheltering trains — pending design (DR-12-07).
- Alt victory, difficulty extras, ruleset loaders, loans past the research
  floor, warehouse logistics, sea-zone names — out of scope.
- Join Empire cost table; rival purse (#489) — rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Further tongues out of scope (DR-13-12); 30% floor data-gated (DR-15-18).
- Resource-need phase reweight — no need reading (DR-16-09).

## Wiki drift

- `civilian-units` calls Road L2/gathering/transport deferred (live:
  `TechUnlocks`/`Extraction`).
- `phase-planner-*` cite DR-14-11 for declare-war (true: DR-14-13).
- `production-recipes` calls rival second-stage appetite deferred (live: #798).
- Wiki treasury-recovery prose ahead of main until #821 merges.
- DR-11-05 + DR-14-11 fleetless leg — live (`TribeContact`, `AiTribeColony`,
  `FleetMuster`).
- Ruleset loader / borrowing — out of scope.
