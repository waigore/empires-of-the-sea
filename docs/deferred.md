# Deferred features (ranked)

Audited vs code, wiki and Design Records (2026-11-12, through DR-20261112-11).
What to ship next (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Difficulty (stores, field, sea, crown's bar) | `Difficulty` / `VictoryRules`, DR-20261111-25/28 |
| Every agenda's decision hooks | `AiAgenda`, DR-20261111-27, [`ai.md`](ai.md) |
| Rival boycotts | `AiDiplomacyOffers`, [`ai.md`](ai.md) |
| Home-fleet merge | `FleetHomeMerge` / `NavalMovement.merge_into_home` |
| Forts + rival/AI builders | [`forts.md`](forts.md), `AiCivilianPlanner` |
| Rival civilian AI | `AiCivilianPlanner` / `MapPlayCivilianAi` |
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
| Raid hull losses + civilian hulls | `NavalRaid`/`NavalHullLoss` (DR-20261111-17) |
| Rival-on-rival raids + prize cargo | `MapPlayRaids` (DR-20261111-20) |
| Agenda dialogue beats + cadence | `DialogueAgenda` (DR-20261111-19) |
| Road L2, gathering caps, path transport | `TechUnlocks` / `Extraction` |
| Minor/Tribe town development (deed raises town) | `MinorTownGrowth`, DR-20261112-01 |
| Battle honours (province on the colours) | `RegimentRecord`, DR-20261112-02 |
| Advanced-start rival chart + Passage lanes | `AdvancedSeas`, DR-20261112-06 |
| Travelling field hospital train | `HospitalTrain`, DR-20261112-07 |
| Rival field-hospital trains | `AiHospitalTrainWork`, DR-20261112-08 |
| Rival order-of-battle readings | `OobReadings`, `MapPlayCourtFog.oob_readings`, DR-20261112-09 |
| Citations, decoration ladder, despatch history | `RegimentDecorations`, DR-20261112-10 |
| Multi-turn recipes (two-turn alloys) | `ProductionRecipes.turns` / `PlayerEconomy.production_wip`, DR-20261112-11 |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | Yarn runtime and localization | Dialogue authorship | [`dialogue.md`](dialogue.md) |
| 2 | A decoration that buys something | Rules depth | DR-20261112-10; needs published numbers |
| 3 | Staggered per-unit completion | Economy depth | DR-20261112-11 deferred |

## Next pick

**Rank 1** — Yarn runtime and localization ([`dialogue.md`](dialogue.md)):
dialogue is authored in data today; a runtime is the next gap.

## Out of scope / blocked footnotes

- Predict-the-line preview — declined ([combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) / DR-20261112-02).
- Era-change dialogue — blocked: no era model (DR-20261111-08).
- Healing at health 0 — casualty list only (DR-20261112-04).
- General-grade / sheltering trains — pending design (DR-20261112-07); L1 rest-only live.
- Alternative victory types — [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory) out of scope.
- Difficulty extras — [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config) § Outside this layer (DR-20261111-28).
- Quick Battle multi-lane / collapse — [quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle).
- General borrowing / loans — Money Lending floor live; rest deferred ([tech-tree-labour-economy](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-labour-economy)).
- Per-region prospected table for discovery — still deferred (DR-20261110-21).
