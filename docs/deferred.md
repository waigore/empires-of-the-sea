# Deferred features (ranked)

Audited through DR-20261113-21 (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Difficulty (stores, field, sea, bar) | `Difficulty` / `VictoryRules`, DR-20261111-25/28 |
| Agenda hooks + dialogue beats | `AiAgenda`, `DialogueAgenda`, DR-20261111-27/19 |
| Rival boycotts | `AiDiplomacyOffers`, [`ai.md`](ai.md) |
| Home-fleet merge | `FleetHomeMerge` / `NavalMovement.merge_into_home` |
| Forts + rival civilian AI | [`forts.md`](forts.md), `AiCivilianPlanner` |
| Minor/Tribe town offers, overseas bonus | `MinorMarket`, `TownIndustry` |
| Merchant overseas cargo | `EconomyOverseas` |
| Colony profit share + near-defeat Join Empire | `FirstRight`, `DiplomacyRules` |
| Counter-spy + court reports | [`espionage.md`](espionage.md) |
| Rival fog / Passage colonisation | `CourtCharts`, DR-20261111-05 |
| Colony Tribe favoured-partner override | `MarketFavoured`, DR-20261111-11 |
| Rival GP–Tribe first contact | `TribeContact`, `AiMerchantWork`, DR-20261111-14 |
| Hospitals, rival builders, staff upkeep | `HospitalRules`, `AiHospitalWork` |
| Research goal in the save | `ResearchState.goal` / `ResearchSlots` |
| Regiment titles, records, commanders, renaming | `RegimentRecord` kit, DR-20261113-05 |
| Raid hull losses; rival raids | `NavalRaid` / `MapPlayRaids`, DR-20261111-17/20 |
| Road L2, gathering caps, path transport | `TechUnlocks` / `Extraction` |
| Minor/Tribe town development | `MinorTownGrowth`, DR-20261112-01 |
| Honours; citations; decoration weight | `RegimentDecorations`, DR-20261112-02/10/13-04 |
| Advanced-start rival chart + Passage lanes | `AdvancedSeas`, DR-20261112-06 |
| Field-hospital trains | `HospitalTrain` / `AiHospitalTrainWork` |
| Rival OOB readings | `OobReadings`, DR-20261112-09 |
| Multi-turn recipes; per-unit stagger | `ProductionRecipes`, DR-20261112-11/13-02 |
| Yarn runtime + locale keys | `DialogueYarn` / `DialogueLocale` |
| Rival-vs-rival fog for diplomacy | `CourtCharts`, DR-20261113-03 |
| Military fabric reservation | `AiArmyReinforce.muster_reserve` |
| Works' reservation | `MapPlayCivilianAi.work_rows`, DR-20261113-14 |
| Consent prompt catalogue | `ConsentCopy`, DR-20261113-10 |
| Sea battles on a plate | `NavalPlate` / `NavalDispatch`, DR-20261113-17 |
| War footing (voyage hold + overstretch peace) | `AiPhasePlanner`, DR-20261113-15 |
| Per-leader primary bonuses | `LeaderCatalog`, DR-20261113-18 |
| Money-first / `AiIncome` | `AiIncome`, DR-20261113-19 |

## Remaining gaps (impact order)

None ranked through DR-20261113-19: money-first / `AiIncome` shipped.

## Next pick

Re-audit; no ranked gap.

## Blocked footnotes

- Predict-the-line — declined ([combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) / DR-20261112-02).
- Era-change dialogue — no era model (DR-20261111-08).
- Healing at health 0 — casualty list only (DR-20261112-04).
- General-grade / sheltering trains — pending design (DR-20261112-07); L1 live.
- Last-known OOB / stale figure — deferred (DR-20261112-09).
- Alternative victory types — [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory) out of scope.
- Difficulty extras — [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config).
- Quick Battle multi-lane / collapse — [quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle).
- General borrowing / loans — Money Lending floor live.
- Per-region prospected table; muster of the dead — DR-20261110-21/12-10.
- Recipe gates, rows beyond steel/bronze, queue cap — wiki-deferred.
- Phase soft priority, extra domain gating, victory pressure — seed (DR-20261113-15).
- Growth-stage coexistence flag — seed (DR-20261113-08).
- Per-hull / round naval plate; rival-fight plate — DR-20261113-17.
- Further tongues — out of scope (DR-20261113-12).
