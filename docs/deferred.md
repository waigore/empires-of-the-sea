# Deferred features (ranked)

Audited against code, wiki and Design Records (2026-11-11, pass after
#287–#294: rival-on-rival raids, agenda beats, research goal). Decision list
for what to ship next (`REQ-P2-02`).

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
| Research goal in the save | `ResearchState.goal` / `ResearchSlots` (DR-20261111-21) |
| Regiment titles + service records | `RegimentNames` / `RegimentRecord` (DR-20261111-18), [`armies.md`](armies.md) |
| Raid hull losses + civilian hulls | `NavalRaid`/`NavalHullLoss` (DR-20261111-17) |
| Difficulty: rival naval strength | `Difficulty` / `NavalCombat` (DR-20261111-24) |
| Rival-on-rival raids + prize cargo | `MapPlayRaids` per-crown pass (DR-20261111-20) |
| Agenda dialogue beats + cadence | `DialogueAgenda` (DR-20261111-19), [`dialogue.md`](dialogue.md) |

## Remaining gaps (impact order)

| Rank | Gap | Why it matters | Notes |
|-----:|-----|----------------|-------|
| 1 | Difficulty layer extras | AI income per turn, victory thresholds, advisor | [`difficulty.md`](difficulty.md) |
| 2 | Minor/Tribe town development path | Offer code exists; towns stay level 1 in play | Wiki: no build/research for them |
| — | Era-change dialogue | Blocked | No era model (DR-20261111-08) |
| — | Hospital upkeep / field hospitals / heal-at-0 | Design polish on DR-20261111-12/16 | Not shippable without a DR |
| — | Battle honours beyond chevron; line preview | Immersion / convenience polish | DR-20261111-18 / 15 |

## Next pick

**Rank 1** is the remaining difficulty knobs, wiki-blocked today (AI income and
advisor toggles sit outside the layer; victory thresholds need a DR); rank 2
needs wiki design first. The layer now scales a rival's strength on the field
and the sea alike (DR-20261111-24), so what is left is AI income, victory
thresholds and the advisor.

## Out of scope / blocked footnotes

- Alternative victory types (Economic, Scientific, Peaceful, Score) —
  [victory](https://github.com/waigore/empires-of-the-sea/wiki/victory) Out of
  scope; military / defeat / calendar endings are live.
- Yarn runtime and localization — dialogue catalogue stays GDScript
  ([`dialogue.md`](dialogue.md)).
