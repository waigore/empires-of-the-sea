# Deferred features (ranked)

Audited through DR-20261115-15 + #676 (REQ-P2-02).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research; war memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*`, #496–#501 |
| Difficulty; agendas; boycotts | `Difficulty`/`VictoryRules`; `AiAgenda`; `AiDiplomacyOffers`, DR-15-03 |
| Home-fleet; forts; civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Fleetless first-hull import | `TradeCargo.PORT_ALLOWANCE`, #606 |
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
| Tribe chain door | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy` / `AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers; slow luxury rows; bench cap | `min_tier`/`turns`, `QUEUE_CAP`, DR-14-07/10/12 |
| AI candidates respect worker-tier | `AiEconomyPlanner` / `AiRandomCourt`, #568 |
| War-time trade garrison | `AiNavalPlanner.trade_garrison`, DR-14-08/#567 |
| Rival bench room | `AiEconomyPlanner._bench_room`, `AiRandomCourt`, DR-15-02 |

## Remaining gaps (impact order)

1. **Rival purse / starved economy** — Join Empire waits on
   `5,000 + 2,000 × provinces` (#489) while landings grow them (DR-14-14);
   density and purse ship per DR-15-16; re-measure waits.
2. **Building gates / further rows** — worker tiers, alloy + luxury four and
   bench cap ship (DR-14-07/10/12); building gates remain.
3. **Domain dispatch beyond the voyage** — voyage/declare-war slots ship; soft
   weights and treasury recovery stay seed (DR-13-15).
4. **Civilian-build seeds** — exotic mixes and per-tile previews stay seed
   (`civilian-build-planner`); polish.

## Next pick

Rival purse / starved economy (#489) — re-measure after DR-15-16.

## Blocked footnotes

- Predict-the-line — declined (DR-12-02).
- Era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade/sheltering trains — pending design (DR-12-07).
- Alt victory, difficulty extras, ruleset loaders, loans outside the research
  floor, Quick Battle lanes/collapse, warehouse logistics — out of scope.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Growth coexistence — seed (DR-13-08); per-hull / rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12).

## Wiki drift

- `civilian-units` calls Road L2, gathering and transport caps deferred.
- `ai-architecture` seed list still names victory pressure (live, DR-15-04).
- `phase-planner-*` cite DR-14-11 for DR-14-13's declare slot.
- DR-14-11 fleetless leg — cleared by #606.
- `playtest-learnings` calls the boycott blocked deal unread; suite reads it
  (#629).
