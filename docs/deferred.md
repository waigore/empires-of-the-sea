# Deferred features (ranked)

Audited against code, wiki and Design Records (2026-11-11, pass after
#276 hospitals / #277 rival Tribe contact). Decision list for what to ship
next (`REQ-P2-02`).

## Already live (remove from backlog)

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Rival boycotts | `AiDiplomacyOffers`, [`ai.md`](ai.md) |
| Home-fleet merge | `FleetHomeMerge` / `NavalMovement.merge_into_home`, [`fleets.md`](fleets.md) |
| Forts + rival/AI builders | [`forts.md`](forts.md), `AiCivilianPlanner` |
| Rival civilian AI | `AiCivilianPlanner` / `MapPlayCivilianAi` |
| Minor/Tribe town offers + overseas town bonus | `MinorMarket`, `TownIndustry`, [`economy.md`](economy.md) |
| Merchant overseas cargo | `EconomyOverseas` |
| Colony profit share (deed R8) + near-defeat Join Empire | `FirstRight`, `DiplomacyRules.nearly_defeated` |
| Counter-spy + court reports | [`espionage.md`](espionage.md) |
| Rival fog / Passage colonisation | `CourtCharts`, DR-20261111-05 |
| Colony Tribe favoured-partner override | `MarketFavoured` (R7.1), DR-20261111-11 |
| Rival GP–Tribe first contact (+ deeds via overtures) | `TribeContact`, `AiMerchantWork`, DR-20261111-14 |
| Hospitals / depot rest (owner) | `HospitalRules` (DR-20261111-12), [`armies.md`](armies.md) |
| Rival hospitals | `AiHospitalWork` (DR-20261111-16), [`ai.md`](ai.md) |
| Raid hull losses + civilian hulls | `NavalRaid`/`NavalHullLoss` (DR-20261111-17) |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | Per-regiment names / history | Immersion parity with `ShipNames` | DR-20261110-19 |
| 2 | Agenda dialogue beats + cadence | Hidden-agenda voice every ~7 turns | Yarn/localization still polish-only |
| 3 | Difficulty layer extras | Naval strength, AI income, victory thresholds, advisor | [`difficulty.md`](difficulty.md) |
| 4 | Research goal in the save | Goal is a view preference today | [`technology.md`](technology.md) |
| 5 | Minor/Tribe town development path | Offer code exists; towns stay level 1 in play | Wiki: no build/research for them |
| — | Era-change dialogue | Blocked | No era model (DR-20261111-08) |
| — | Hospital upkeep / field hospitals / heal-at-0 | Design polish on DR-20261111-12 | Not shippable without a DR |

## Next pick

**Rank 1** is the last immersion gap of the land war: a regiment's own name and
history. Rank 2 is voice; 3–5 are knobs or need wiki design first.
