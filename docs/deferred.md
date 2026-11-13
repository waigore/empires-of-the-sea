# Deferred features (ranked)

Audited through DR-20261114-02 (`REQ-P2-02`).

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
| Overseas cargo; colony profit; Join Empire | `EconomyOverseas`, `FirstRight`, `DiplomacyRules` |
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
| War footing; leader bonuses; money-first | `AiPhasePlanner`; `LeaderCatalog`; `AiIncome` |
| Tribe buy ambition (envoy over storm) | `AiTribeColony`, `colonise.tribe_chain`, DR-14-02 |
| New World landings; overseas conquest | `AiColonisationPlanner` return voyage, `AiCrossingForce`, DR-14-03 |

## Remaining gaps (impact order)

1. **New World colony founded** — voyages land and a court now takes New World
   provinces by storm (DR-14-03), but no court finishes Join Empire: the
   `5,000 + 2,000 × provinces` price is out of reach of a rival purse.
2. **Phase soft priority** — the weight vector and domain gating beyond the
   voyage stay seed (DR-13-15); posture/T4 and victory pressure are live
   (DR-14-04).
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
