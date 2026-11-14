# Deferred features (ranked)

Audited through DR-20261114-10 (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| War research; war memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*`, #496–#501 |
| Difficulty; agendas; boycotts | `Difficulty`/`VictoryRules`; `AiAgenda`; `AiDiplomacyOffers` |
| Home-fleet; forts; civilian AI | `FleetHomeMerge`, `AiCivilianPlanner`, forts |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Counter-spy; court reports; fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner; GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals + rival builders/staff/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal; fabric + works reserve | `ResearchSlots`; muster/works keep-back, DR-13-08/14 |
| Regiment titles/records/rename; decorations | `RegimentRecord`, `RegimentDecorations` |
| Raid hulls; rival raids; naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2; gathering; path transport | `TechUnlocks` / `Extraction` |
| Advanced chart; Passage; rival OOB/fog | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing; money-first; victory pressure | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure` |
| Leader bonuses | `LeaderCatalog`, DR-13-18 |
| Tribe buy; landings; overseas conquest | `AiTribeColony`; `AiColonisationPlanner`, DR-14-02/03 |
| Tribe chain door study | `AiTribeColony.door`, research planner, DR-14-05/#554 |
| Hull chest + material row | `AiNavy` / `AiClaims.HULLS`, DR-14-06/09 |
| Worker-tier gates; slow luxury rows | `ProductionRecipes.min_tier`/`turns`, DR-14-07/10 |
| War-time trade garrison (holds home) | `AiNavalPlanner.trade_garrison`, DR-14-08/#567 |

## Remaining gaps (impact order)

1. **New World colony founded** — landings, storm conquest (DR-14-03), the
   chain door (DR-14-05), and holds-at-seat (DR-14-08) are live. Join Empire
   (`5,000 + 2,000 × provinces`) still outruns a rival purse (#489; #552 sheds
   mouths, not the price).
2. **Domain gating beyond the voyage** — last soft-priority seed (DR-13-15):
   every domain still runs; only the voyage gate is live.
3. **Building gates / queue cap** — worker-tier gates (DR-14-07) and the alloy
   + luxury four (DR-14-10) shipped; building gates, further rows, and the
   queue cap remain (wiki-deferred).
4. **AI recipe candidates ignore worker-tier** — planners still walk
   `available_ids` (tech only); phase refuses gated rows (DR-14-07
   follow-up; needs ai-bench re-bind).

## Next pick

A Tribe colony founded: the chain and holds are open (DR-14-05/08); the
blocker is the rival purse (#489).

## Blocked footnotes

- Predict-the-line — declined (combat / DR-12-02).
- Era dialogue — no era model (DR-11-08).
- Healing at health 0 — casualty list only (DR-12-04).
- General-grade / sheltering trains — pending design (DR-12-07); L1 live.
- Last-known OOB / stale figure — deferred (DR-12-09).
- Alt victory types — victory out of scope.
- Difficulty extras — ruleset-config.
- Quick Battle multi-lane / collapse — quick-battle.
- Borrowing / loans — Money Lending floor live.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Growth coexistence flag — seed (DR-13-08).
- Per-hull / round naval plate; rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12).
