# Deferred features (ranked)

Audited vs code, wiki and Design Records (2026-11-12, through #339). Decision
list for what to ship next (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Difficulty layer (stores, field, sea, crown's bar) | `Difficulty` / `VictoryRules`, DR-20261111-25/28, [`difficulty.md`](difficulty.md) |
| Every agenda's decision hooks | `AiAgenda` traits, DR-20261111-27, [`ai.md`](ai.md) |
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
| Hospitals, rival builders, staff upkeep | `HospitalRules` / `AiHospitalWork` / `EconomyConsumption` (DR-20261111-12/16, 12-04) |
| Research goal in the save | `ResearchState.goal` / `ResearchSlots` (DR-20261111-21) |
| Regiment titles, records, named commanders | `RegimentNames` / `RegimentRecord` / `GeneralNames` (DR-20261111-18, 12-03) |
| Raid hull losses + civilian hulls | `NavalRaid`/`NavalHullLoss` (DR-20261111-17) |
| Rival-on-rival raids + prize cargo | `MapPlayRaids` per-crown pass (DR-20261111-20) |
| Agenda dialogue beats + cadence | `DialogueAgenda` (DR-20261111-19), [`dialogue.md`](dialogue.md) |
| Road L2, gathering caps, path transport | `TechUnlocks` / `Extraction` |
| Minor/Tribe town development (deed raises town) | `MinorTownGrowth`, DR-20261112-01, [`civilians.md`](civilians.md) |
| Battle honours (province on the colours) | `RegimentRecord`, DR-20261112-02, [`armies.md`](armies.md) |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | A predict-the-line preview in the dossier | Convenience only | Declined by [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § The line and the reserve: the limit depends on the general bound at combat |

## Next pick

**Rank 1** is a live wiki decision, not a code gap: the page publishes that the
dossier does not predict the line. Nothing left on the list is a plain gap
against published rules.

## Out of scope / blocked footnotes

- Predict-the-line preview — declined ([combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
  / DR-20261112-02). Citations beyond the honour wait on that ship.
- Era-change dialogue — blocked: no era model (DR-20261111-08).
- Travelling field hospital deferred (DR-20261111-12 / 12-04); a regiment at 0
  is destroyed, so no ward heals it.
- Rival order-of-battle readings, rival-vs-rival fog, advanced-start rival
  inheritance — deferred (DR-20261110-21); AI uses published numbers.
- Alternative victory types — [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory)
  out of scope; military / defeat / calendar endings live.
- Difficulty extras (AI income, advisor toggles) —
  [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config)
  § Outside this layer; the crown's bar moves with the level (DR-20261111-28).
- Quick Battle multi-lane terrain and the collapse model — owner-confirmed
  deferral in [quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle).
- Multi-turn production recipes, Yarn runtime and localization — wiki-deferred
  ([`economy.md`](economy.md), [`dialogue.md`](dialogue.md)).
