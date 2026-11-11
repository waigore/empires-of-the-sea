# Deferred features (ranked)

Stale “Deferred” lines across domain docs were audited against code (2026-11-11).
This page is the decision list for what to ship next (`REQ-P2-02`).

## Already live (remove from backlog)

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Rival boycotts | `AiDiplomacyOffers`, [`ai.md`](ai.md) |
| Home-fleet merge | `NavalMovement.merge_into_home`, [`fleets.md`](fleets.md) |
| Forts + rival/AI builders | [`forts.md`](forts.md), `AiCivilianPlanner` |
| Rival civilian AI | `AiCivilianPlanner` / `MapPlayCivilianAi` |
| Minor/Tribe town offers + overseas town bonus | `MinorMarket`, `TownIndustry`, [`economy.md`](economy.md) |
| Merchant overseas cargo | `EconomyOverseas` |
| Colony profit share (deed R8) + near-defeat Join Empire | `FirstRight`, `DiplomacyRules.nearly_defeated` |
| Counter-spy + court reports | [`espionage.md`](espionage.md) |
| Rival fog / Passage colonisation | `CourtCharts`, DR-20261111-05 |
| Colony Tribe favoured-partner override | `MarketFavoured` (R7.1), DR-20261111-11 |
| Raid hull losses | **Out of scope** by DR-20261110-13 (cargo only) |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | Rival GP–Tribe first contact + colonial claims | Rivals chart the New World but cannot open court, Consulate, Embassy or deeds | DR-20261111-05 deferred; human-only `sync_first_contact` |
| 2 | Hospitals / depot rest | Speeds regiment recovery; campaign longevity | DR-20261110-19 |
| 3 | Per-regiment names / history | Immersion parity with `ShipNames` | DR-20261110-19 |
| 4 | Agenda dialogue beats + cadence | Hidden-agenda voice every ~7 turns | Yarn/localization still polish-only |
| 5 | Difficulty layer extras | Naval strength, AI income, victory thresholds, advisor | [`difficulty.md`](difficulty.md) |
| 6 | Research goal in the save | Goal is a view preference today | [`technology.md`](technology.md) |
| 7 | Minor/Tribe town development path | Offer code exists; towns stay level 1 in play | Wiki: no build/research for them |
| — | Era-change dialogue | Blocked | No era model (DR-20261111-08) |
| — | Raid civilian hull model | Design-deferred | DR-20261110-13 |

## Next pick

**Rank 1** unlocks the New World for rival courts end-to-end (diplomacy → deeds →
claims). Ranks 2–5 deepen mid/late land, army and trade fidelity. Ranks 6–7 are
polish or optional knobs.
