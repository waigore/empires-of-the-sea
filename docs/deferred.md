# Deferred features (ranked)

Audited through DR-20261114-04 (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| War research; war memory; ledger T1 | `research_floor`; `AiWarMemory`; `AiObjective*`, DR-24/25/#496 |
| Ledger T2–T5 (expedition, claims, posture, navy) | `AiObjectivesPlan`, `AiClaims`, `AiPosture`, `navy.build` #497–#500 |
| Ledger T6 funded-share metric | `funded_pct` / ai-bench guards, #501 |
| Difficulty layer | `Difficulty` / `VictoryRules`, DR-11-25/28 |
| Agenda + dialogue beats; boycotts | `AiAgenda`, `DialogueAgenda`, `AiDiplomacyOffers` |
| Home-fleet merge; forts; civilian AI | `FleetHomeMerge`, `AiCivilianPlanner`, forts |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyOvertures` |
| Counter-spy; court reports; fog/Passage | espionage; `CourtCharts`, DR-11-05 |
| Favoured partner; GP–Tribe contact | `MarketFavoured`; `TribeContact`, DR-11-11/14 |
| Hospitals + rival builders/staff/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal; fabric + works reserve | `ResearchSlots`; muster/works keep-back, DR-13-08/14 |
| Regiment titles/records/rename; decorations | `RegimentRecord`, `RegimentDecorations` |
| Raid hulls; rival raids; naval plate | `NavalRaid`, `NavalPlate`, DR-11-17/20/13-17 |
| Road L2; gathering; path transport | `TechUnlocks` / `Extraction` |
| Advanced rival chart + Passage lanes | `AdvancedSeas`, DR-12-06 |
| Rival OOB; rival-vs-rival fog | `OobReadings`; `CourtCharts`, DR-12-09/13-03 |
| Multi-turn recipes; stagger | `ProductionRecipes`, DR-12-11/13-02 |
| Yarn + consent keys | `DialogueYarn`, `ConsentCopy`, DR-13-10 |
| War footing; money-first; victory pressure | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure`, DR-13-19/14-04 |
| Leader bonuses | `LeaderCatalog`, DR-13-18 |
| Tribe buy ambition (envoy over storm) | `AiTribeColony`, `colonise.tribe_chain`, DR-14-02 |
| New World landings; overseas conquest | `AiColonisationPlanner` return voyage, `AiCrossingForce`, DR-14-03 |

## Remaining gaps (impact order)

1. **New World colony founded** — landings and storm conquest are live
   (DR-14-03); Join Empire (`5,000 + 2,000 × provinces`) still outruns a rival
   purse.
2. **Domain gating beyond the voyage** — last soft-priority seed (DR-13-15):
   every domain still runs; only the voyage gate is live. Weights, money-first
   and victory pressure ship.
3. **Recipe gates / queue** — building/tier gates, rows past steel/bronze,
   queue cap (wiki-deferred).

## Next pick

A Tribe colony founded: a court that can pay the Join Empire step after the buy
chain (DR-14-02), or a windfall that makes it affordable.

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
