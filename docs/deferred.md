# Deferred features (ranked)

Audited: wiki / DRs / code through #1070 (REQ-P2-02).
Default: largest item here, then REQ/wiki.

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` |
| Home merge/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony/Join/voyage | `EconomyOverseas`, `FirstRight`; land DR-18-19/23 |
| Fleetless import; counter-spy/fog | `PORT_ALLOWANCE`; espionage; `CourtCharts` |
| Favoured partner/GP–Tribe contact | `MarketFavoured`; `TribeContact` |
| Hospitals/rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back |
| Regiment records/rename/decorations | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog` |
| Raid hulls/rival prizes/naval plate | `NavalRaid`, `MapPlayRaids`, `NavalPlate` |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Advanced chart/Passage/rival OOB | `AdvancedSeas`; `OobReadings`; `CourtCharts` |
| Yarn + consent | `DialogueYarn`, `ConsentCopy` |
| War footing/money-first/victory | `AiPhasePlanner`; `AiIncome`; `AiVictoryPressure` |
| Phoney front; college chest; pact lead | `holds_front`; `bank_chest`; `pact_break_leads` |
| Declare-war / Tribe-chain / crews | `SLOT_DECLARE_WAR`/`TRIBE_CHAIN`/`CREWS` |
| Tribe buy/landings/overseas conquest | `AiTribeColony`; `AiColonisationPlanner` |
| Tribe door; hull chest; worker tiers | `AiTribeColony.door`; `AiNavy`; `QUEUE_CAP` |
| War trade garrison + rival bench | `trade_garrison`; `_bench_room` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate + rival second-stage | `min_town`; `AiEconomyPlanner` |
| Workshop landing; regiment dismiss | `ground_appetite`; `ArmyDismiss` |
| Destitute; market + naval slot | ration ×2; `trade.market`/`navy.missions` |
| Archetype civilian mixes | `AiStaffTaste`, DR-17-04 |
| Raise/crew/yard/muster/workers/college | ledgers + Follow; hire/batch/`carries` |
| QB wings + handset plate | `QuickBattleWings`; `BattlePlateFrame` |
| Rail pick; observer sheet/feed/desk | `RailWorks`; `Observer*`; title #1045 |
| Capital Wood walls + fort lift | `FortCapital`, DR-17-13 |
| Yard batch; Bid/gift/larder/line | `queue_all`; `bid_block`; `DiplomacyGift` |
| Buy-out / pointless peace; re-field | `_buys_out`; `pointless`; `rotate_home` |
| Confirm-face matches the line | `RaiseBatchPress` carries, DR-18-21 |
| Opening muster; shared-station fan/stack | `FleetMuster` #1051; `FleetLanes` #1047 |

## Gaps (ranked)

None — both #1043 halves shipped (#1047 fan/stack, #1051 home fleet).

## Next pick

REQ/wiki.

## Blocked

- Predict-the-line (DR-12-02); era — no model (DR-11-08).
- Healing at 0; last-known OOB (DR-12-04/09); general-grade trains (DR-12-07).
- Soft priority weight — seed (DR-17-01); resource-need phase reweight —
  no need reading (DR-13-15; money-goal live DR-16-09).
- Alt victory, difficulty extras, ruleset loaders/borrowing, warehousing,
  loans, sea-zone names — out of scope; Join Empire cost — rules call.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Cross-station folds / passenger transfers — out of scope. Further tongues
  (DR-13-12); 30% floor data-gated (DR-15-18). QB placed figures / per-wing
  orders — out of scope (DR-17-08).

## Wiki drift

`DR-20261111-05` § Deferred still names rival Tribe contact and
fleetless crowns; both live (`TribeContact` / `AiTribeColony`,
`FleetMuster`). Soft weight seed stays blocked (`DR-20261117-01`).
