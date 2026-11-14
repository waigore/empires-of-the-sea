# Deferred features (ranked)

Audited through DR-20261115-04 + #631 (`REQ-P2-02`).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research; war memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*`, #496–#501 |
| Difficulty; agendas; boycotts (deal bar) | `Difficulty`/`VictoryRules`; `AiAgenda`; `AiDiplomacyOffers`, DR-15-03 |
| Home-fleet; forts; civilian AI | `FleetHomeMerge`, `AiCivilianPlanner`, forts |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Counter-spy; court reports; fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner; GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals; rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal; fabric + works reserve | `ResearchSlots`; muster/works keep-back, DR-13-08/14 |
| Regiment records/rename; decorations; leader bonuses | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog`, DR-13-18 |
| Raid hulls; rival raids; naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2; gathering; path transport | `TechUnlocks` / `Extraction` |
| Advanced chart; Passage; rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing; money-first; victory pressure | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`, DR-15-04 |
| Tribe buy; landings; overseas conquest | `AiTribeColony`; `AiColonisationPlanner`, DR-14-02/03 |
| Tribe chain door study | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy` / `AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers; slow luxury rows; bench cap | `min_tier`/`turns`, `QUEUE_CAP`, DR-14-07/10/12 |
| AI candidates respect worker-tier | `AiEconomyPlanner` / `AiRandomCourt`, #568 |
| War-time trade garrison (holds home) | `AiNavalPlanner.trade_garrison`, DR-14-08/#567 |
| Rival bench room | `AiEconomyPlanner._bench_room`, `AiRandomCourt`, DR-15-02 |

## Remaining gaps (impact order)

1. **Rival purse behind Join Empire** — the colony waits on
   `5,000 + 2,000 × provinces` (#489) while landings and storms grow colonies
   (DR-14-14); the famine/income deadlock is a rules call.
2. **Fleetless import leg** — no hull means no holds, so the cloth for a first
   hull cannot be imported (#530/#484); a rules question (DR-14-11).
3. **Building gates / further rows** — worker tiers, the alloy + luxury four and
   the bench cap ship (DR-14-07/10/12); building-gated recipes remain.
4. **Domain dispatch beyond the voyage** — voyage/declare-war slots ship;
   the soft priority weight vector and treasury-recovery reweighting stay seed
   (DR-13-15) — internal knobs.

## Next pick

The rival purse (#489); the fleetless import leg (#530) is the rules call.

## Blocked footnotes

- Predict-the-line — declined (combat / DR-12-02).
- Era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade/sheltering trains — pending design (DR-12-07); L1 live.
- Alt victory, difficulty extras, ruleset loaders, loans past the research debt
  floor, Quick Battle lanes — out of scope.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Growth coexistence — seed (DR-13-08); per-hull / rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12).
- Wiki drift (read-only): `civilian-units` calls Road L2/gathering deferred;
  `ai-architecture`'s seed list names victory pressure; `phase-planner-*` cite
  DR-14-11 for DR-14-13's declare slot.
