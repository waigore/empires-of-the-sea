# Deferred features (ranked)

Audited through DR-20261113-25 (`REQ-P2-02`).

## Already live

| Was listed as deferred | Where it lives |
|------------------------|----------------|
| War research; war memory; ledger T1 | `research_floor`; `AiWarMemory`; `AiObjective*`, DR-24/25/#496 |
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

## Remaining gaps (impact order)

1. **Ledger T2 expedition** — hull + Explorer + peace window; New World landings (#497/#476).
2. **Ledger T5 naval build** — warships as objectives; no hulls laid (#500/#484).
3. **Ledger T3 claims** — reservations become ledger claims (#498).
4. **Ledger T4 posture weights** — soft priority + personality weights (#499).

## Next pick

Ledger T2 expedition package (colonise children → funded claims).

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
- Recipe gates, rows beyond steel/bronze, queue cap — wiki-deferred.
- Phase soft priority, domain gating, victory pressure — seed (DR-13-15); T4 may close soft priority.
- Growth coexistence flag — seed (DR-13-08).
- Per-hull / round naval plate; rival-fight plate — DR-13-17.
- Further tongues — out of scope (DR-13-12).
- Ledger T6 funded-share metric — #501.
