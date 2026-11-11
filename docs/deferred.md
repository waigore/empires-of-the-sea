# Deferred features (ranked)

Audited vs code, wiki and Design Records (2026-11-12, through #316 /
DR-20261111-28). Decision list for what to ship next (`REQ-P2-02`).

## Already live (remove from backlog)

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| Difficulty layer, complete (stores, field, sea, crown's bar) | `Difficulty` / `VictoryRules`, DR-20261111-12/25/28, [`difficulty.md`](difficulty.md) |
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
| Rival GP–Tribe first contact (+ deeds via overtures) | `TribeContact`, `AiMerchantWork`, DR-20261111-14 |
| Hospitals / depot rest (owner) | `HospitalRules` (DR-20261111-12), [`armies.md`](armies.md) |
| Rival hospitals | `AiHospitalWork` (DR-20261111-16), [`ai.md`](ai.md) |
| Research goal in the save | `ResearchState.goal` / `ResearchSlots` (DR-20261111-21) |
| Regiment titles + service records | `RegimentNames` / `RegimentRecord` (DR-20261111-18), [`armies.md`](armies.md) |
| Raid hull losses + civilian hulls | `NavalRaid`/`NavalHullLoss` (DR-20261111-17) |
| Rival-on-rival raids + prize cargo | `MapPlayRaids` per-crown pass (DR-20261111-20) |
| Agenda dialogue beats + cadence | `DialogueAgenda` (DR-20261111-19), [`dialogue.md`](dialogue.md) |
| Road L2, gathering caps, path transport | `TechUnlocks` / `Extraction` |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | Minor/Tribe town development path | Towns stay level 1, so manufacture offers rarely fire | Wiki has no build/research path for them — DR first |
| 2 | Battle honours beyond the chevron; line preview | Immersion and convenience; no rules payoff | Needs a DR: what an honour would read or do |

## Next pick

**Rank 1** needs a wiki call on whether Minor/Tribe towns develop at all.
**Rank 2** needs a design record for what an honour or a preview is.
Nothing on the list is a plain code gap against published rules.

## Out of scope / blocked footnotes

- Era-change dialogue — blocked: no era model (DR-20261111-08).
- Hospital upkeep / travelling field hospitals / heal-at-0 — needs a DR
  (DR-20261111-12/16 leftovers).
- Rival order-of-battle readings, rival-vs-rival fog, advanced-start rival
  inheritance — still deferred (DR-20261110-21); AI uses published numbers.
- Alternative victory types (Economic, Scientific, Peaceful, Score) —
  [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory) out of
  scope; military / defeat / calendar endings are live.
- Difficulty extras (per-turn AI income, advisor toggles) —
  [ruleset-config](https://github.com/waigore/empires-of-the-sea/wiki/ruleset-config)
  § Outside this layer; the crown's bar itself moves with the level
  (DR-20261111-28).
- Quick Battle multi-lane terrain and the full collapse model — owner-confirmed
  deferral in [quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle).
- Multi-turn production recipes, Yarn runtime and localization — wiki-deferred
  ([`economy.md`](economy.md), [`dialogue.md`](dialogue.md)).
