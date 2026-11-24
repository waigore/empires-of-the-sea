# Deferred features (ranked)

Audited through #1462 (REQ-P2-02). Largest gap, then REQ/wiki.

## Already live

| Was deferred | Where it lives |
|--------------|----------------|
| War research/memory; ledger T1–T6 | `research_floor`; `AiWarMemory`; `AiObjective*` |
| Difficulty/agendas/boycotts | `Difficulty`/`VictoryRules`, `AiAgenda`, `AiDiplomacyOffers` |
| Home merge/forts/civilian AI | `FleetHomeMerge`, `AiCivilianPlanner` |
| Minor/Tribe market + town growth | `MinorMarket`, `TownIndustry`, `MinorTownGrowth` |
| Overseas cargo/colony/Join/voyage | `EconomyOverseas`, `FirstRight`; land DR-18-19/23 |
| Join Empire sized cost | `DiplomacyCatalog.stage_cost` (base + per province) |
| Fleetless import; counter-spy/fog | `PORT_ALLOWANCE`; espionage; `CourtCharts` |
| Favoured partner/GP–Tribe contact | `MarketFavoured`; `TribeContact` |
| Hospitals/rival builders/trains | `HospitalRules`, `AiHospitalWork`, `HospitalTrain` |
| Research goal/fabric + works reserve | `ResearchSlots`; muster/works keep-back |
| Regiment records/rename/decorations | `RegimentRecord`, `RegimentDecorations`, `LeaderCatalog` |
| Raid hulls/rival prizes/naval plate | `NavalRaid`, `MapPlayRaids`, `NavalPlate` |
| Road L2/gathering/path transport | `TechUnlocks`/`Extraction` |
| Chart/Passage/OOB/Hosts | `AdvancedSeas`; `OobReadings`; `ProvinceHosts` |
| Sea-zone names; yarn + consent | `MapNaming`; `DialogueYarn`, `ConsentCopy` |
| War footing/money/victory/need | `AiPhasePlanner`; `AiIncome`; `AiDiplomacyDesire` |
| Phoney front; college chest; pact lead | `holds_front`; `bank_chest`; `pact_break_leads` |
| Declare-war / Tribe-chain / crews | `SLOT_DECLARE_WAR`/`TRIBE_CHAIN`/`CREWS` |
| Tribe buy/landings/deed/overseas | `AiTribeColony`; `deed_ground`; colonisation |
| Hull chest; worker tiers; war garrison | `AiNavy`; `QUEUE_CAP`; `trade_garrison` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate; workshop landing; dismiss | `min_town`; `ground_appetite`; `ArmyDismiss` |
| Destitute; market/naval; auto household | ration ×2; `trade.market`/`navy.missions`; `MapPlayAuto` |
| Archetype civilian mixes | `AiStaffTaste`, DR-17-04 |
| Raise/crew/yard/muster/workers/college | ledgers + Follow; hire/batch/`carries` |
| QB; rail; observer; fort ladder 5 | `QuickBattleWings`; `RailWorks`; `FortRules`/`FortCapital` |
| Yard batch; Bid/gift/larder/line | `queue_all`; `bid_block`; `DiplomacyGift` |
| Buy-out / pointless peace; re-field | `_buys_out`; `pointless`; `rotate_home` |
| Confirm-face; muster; fan; capital chart | `RaiseBatchPress`; `FleetMuster`/`FleetLanes`; `CapitalChoiceScreen` |
| Rival priced overtures; AI win/front | `DiplomacyProposals`; `AiBorderFronts` |
| Passengers; raid/catch prices | `EmbarkBatch`; `NavalRaid`/`NavalInterception` |
| Harbour hulls + aboard | `ProvinceHarbour` (+`.aboard`, DR-14/18) |
| Wall storm; fee; riches; bank | `WallRead`; `ArmyAttackCost`; `ground_appetite`; `AiIncome.invests` |
| Harvest; college turns; Engineer port | `MapPlayProvinceHarvest`; `ResearchSlotPrice`; `VoyageRead.needs_port` |

## Gaps (ranked)

None.

## Next pick

None; see `docs/rubric.md` / wiki.

## Blocked

- Predict-the-line (DR-12-02); era — no model (DR-11-08).
- Healing at 0; last-known OOB (DR-12-04/09); general-grade trains (DR-12-07).
- Soft priority weight — seed (DR-13-15). Money-goal live (DR-16-09).
- Alt victory, difficulty extras, ruleset loaders/borrowing, warehousing,
  loans — out of scope.
- Per-region prospected; muster of the dead — DR-10-21/12-10.
- Per-hull damage; rival-fight plate — DR-13-17.
- Cross-station folds / passenger transfers; further tongues (DR-13-12);
  30% floor data-gated (DR-15-18); QB placed figures / per-wing orders
  (DR-17-08); building-gated recipes (DR-14-12) — out of scope.

## Wiki drift

`DR-20261111-05` still names Tribe contact and fleetless crowns (both live).
`capital-choice-phase` “UI deferred” — stale. Soft weight / treasury seed
(DR-13-15 / DR-16-09) — stale. #1444–#1462 not backlog (#1462 prices live
intervention answers). #1382 / #1422 closed (riches + Engineer port live).
Open defects: #1429, #1383, #1432–#1435 (not ranked gaps).
