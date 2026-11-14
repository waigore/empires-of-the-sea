# Deferred features (ranked)

Audited through DR-20261114-14 + #616 (`REQ-P2-02`).

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research; war memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*`, #496–#501 |
| Difficulty; agendas; boycotts | `Difficulty`/`VictoryRules`; `AiAgenda`; `AiDiplomacyOffers` |
| Home-fleet; forts; civilian AI | `FleetHomeMerge`, `AiCivilianPlanner`, forts |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Counter-spy; court reports; fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner; GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals + rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal; fabric + works reserve | `ResearchSlots`; muster/works keep-back, DR-13-08/14 |
| Regiment records/rename; decorations | `RegimentRecord`, `RegimentDecorations` |
| Raid hulls; rival raids; naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2; gathering; path transport | `TechUnlocks` / `Extraction` |
| Advanced chart; Passage; rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing; money-first; victory pressure | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure` |
| Leader bonuses | `LeaderCatalog`, DR-13-18 |
| Tribe buy; landings; overseas conquest | `AiTribeColony`; `AiColonisationPlanner`, DR-14-02/03 |
| Tribe chain door study | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy` / `AiClaims.HULLS`, DR-14-06/09 |
| Worker tiers; slow luxury rows; bench cap | `min_tier`/`turns`, `QUEUE_CAP`, DR-14-07/10/12 |
| AI candidates respect worker-tier | `AiEconomyPlanner` / `AiRandomCourt`, #568 |
| War-time trade garrison (holds home) | `AiNavalPlanner.trade_garrison`, DR-14-08/#567 |
| Rival bench room | `AiEconomyPlanner._bench_room`, `AiRandomCourt`, DR-15-02 |

## Remaining gaps (impact order)

1. **New World colony founded** — landings, storm conquest, chain door,
   holds-at-seat live (DR-14-03/05/08); a stalled chest re-routes (DR-14-14).
   Rivals still wait on the purse: Join Empire
   (`5,000 + 2,000 × provinces`) outruns it (#489); the famine/income deadlock
   behind it is a rules call.
2. **Domain gating beyond the voyage** — the declare slot ships (DR-14-13): an
   overstretched court opens no war it cannot win. The rest stays seed
   (DR-13-15).
3. **Building gates / further rows** — worker tiers, the alloy + luxury four
   and the bench cap ship (DR-14-07/10/12); building-gated recipes and rows
   beyond remain (wiki).

## Next pick

The rival purse (#489): chain and holds are open (DR-14-05/08); Join Empire
still outruns it and the famine/income deadlock is a rules call.

## Blocked footnotes

- Predict-the-line — declined (combat / DR-12-02).
- Era dialogue — no era model (DR-11-08).
- Healing at 0 health; last-known OOB — DR-12-04/09.
- General-grade / sheltering trains — pending design (DR-12-07); L1 live.
- Alt victory, difficulty extras, Quick Battle lanes — out of scope.
- Loans — Money Lending floor live.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Growth coexistence — seed (DR-13-08); per-hull / rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12).
- Wiki drift (live): `civilian-units` still says Road L2/gathering deferred.
