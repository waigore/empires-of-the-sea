# Deferred features (ranked)

Audited through DR-20261113-03 (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Difficulty (stores, field, sea, crown's bar) | `Difficulty` / `VictoryRules`, DR-20261111-25/28 |
| Agenda decision hooks + dialogue beats | `AiAgenda`, `DialogueAgenda`, DR-20261111-27/19 |
| Rival boycotts | `AiDiplomacyOffers`, [`ai.md`](ai.md) |
| Home-fleet merge | `FleetHomeMerge` / `NavalMovement.merge_into_home` |
| Forts + rival civilian AI | [`forts.md`](forts.md), `AiCivilianPlanner` |
| Minor/Tribe town offers + overseas town bonus | `MinorMarket`, `TownIndustry` |
| Merchant overseas cargo | `EconomyOverseas` |
| Colony profit share + near-defeat Join Empire | `FirstRight`, `DiplomacyRules` |
| Counter-spy + court reports | [`espionage.md`](espionage.md) |
| Rival fog / Passage colonisation | `CourtCharts`, DR-20261111-05 |
| Colony Tribe favoured-partner override | `MarketFavoured` (R7.1), DR-20261111-11 |
| Rival GP–Tribe first contact (+ deeds) | `TribeContact`, `AiMerchantWork`, DR-20261111-14 |
| Hospitals, rival builders, staff upkeep | `HospitalRules` / `AiHospitalWork` / `EconomyConsumption` |
| Research goal in the save | `ResearchState.goal` / `ResearchSlots` (DR-20261111-21) |
| Regiment titles, records, named commanders | `RegimentNames` / `RegimentRecord` / `GeneralNames` |
| Raid hull losses; rival-on-rival raids | `NavalRaid` / `MapPlayRaids`, DR-20261111-17/20 |
| Road L2, gathering caps, path transport | `TechUnlocks` / `Extraction` |
| Minor/Tribe town development (deed raises town) | `MinorTownGrowth`, DR-20261112-01 |
| Battle honours (province on the colours) | `RegimentRecord`, DR-20261112-02 |
| Advanced-start rival chart + Passage lanes | `AdvancedSeas`, DR-20261112-06 |
| Field-hospital trains (player + rival) | `HospitalTrain` / `AiHospitalTrainWork`, DR-20261112-07/08 |
| Rival order-of-battle readings | `OobReadings`, DR-20261112-09 |
| Citations, decoration ladder, despatch history | `RegimentDecorations`, DR-20261112-10 |
| Multi-turn recipes (two-turn alloys) | `ProductionRecipes.turns` / `PlayerEconomy.production_wip`, DR-20261112-11 |
| Per-unit staggered completion | `ProductionRecipes.landing` / `plan`, DR-20261113-02 |
| Yarn runtime + locale keys | `DialogueYarn` / `DialogueLocale`, DR-20261113-01 |
| Rival-vs-rival fog for diplomacy | `CourtCharts` in the planner context, DR-20261113-03 |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | A decoration that buys something | Rules depth | Wiki DR-20261113-04 (`×1.05`/`×1.10`); code omits |
| 2 | Translation content | Localization | Keys live; needs words |

## Next pick

**Rank 1** — Decoration: wiki numbers exist; main still display-only
(`RegimentDecorations` / `ArmyModifiers`).

## Out of scope / blocked footnotes

- Predict-the-line preview — declined ([combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) / DR-20261112-02).
- Era-change dialogue — blocked: no era model (DR-20261111-08).
- Healing at health 0 — casualty list only (DR-20261112-04).
- General-grade / sheltering trains — pending design (DR-20261112-07); L1 live.
- Last-known OOB / stale figure — deferred (DR-20261112-09).
- Alternative victory types — [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory) out of scope.
- Difficulty extras — [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config) § Outside this layer.
- Quick Battle multi-lane / collapse — [quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle).
- General borrowing / loans — Money Lending floor live; rest deferred.
- Per-region prospected table — deferred (DR-20261110-21).
- Recipe gates; more multi-turn rows; queue caps; muster of the dead — DR-20261112-10/11/13-02.
