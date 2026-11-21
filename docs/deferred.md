# Deferred features (ranked)

Audited: wiki / DRs / code through #1218 (REQ-P2-02).
Default pick: largest gap here, then REQ/wiki.

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
| Tribe buy/landings/door/overseas | `AiTribeColony`; `AiColonisationPlanner` |
| Hull chest; worker tiers; war garrison | `AiNavy`; `QUEUE_CAP`; `trade_garrison` |
| Starved plot + opening purse | `resource_seeder` 30%; `START_TREASURY` 20k |
| Recipe gate; workshop landing; dismiss | `min_town`; `ground_appetite`; `ArmyDismiss` |
| Destitute; market + naval slot | ration ×2; `trade.market`/`navy.missions` |
| Archetype civilian mixes | `AiStaffTaste`, DR-17-04 |
| Raise/crew/yard/muster/workers/college | ledgers + Follow; hire/batch/`carries` |
| QB wings; rail; observer; capital fort | `QuickBattleWings`; `RailWorks`; `Observer*`; `FortCapital` |
| Yard batch; Bid/gift/larder/line | `queue_all`; `bid_block`; `DiplomacyGift` |
| Buy-out / pointless peace; re-field | `_buys_out`; `pointless`; `rotate_home` |
| Confirm-face; opening muster; fan/stack | `RaiseBatchPress`; `FleetMuster`; `FleetLanes` |
| Rival priced overtures | `DiplomacyProposals` queue + the asking court's ledger |
| AI win / border front (#995) | `AiBorderFronts`; bench win t101 (DR-19-16, #1095) |
| Passengers whole-berth press | `EmbarkBatch` (DR-19-18, #1104) |
| Station raid/catch dossier prices | `NavalRaid`/`NavalInterception` preview (DR-20-01/02) |

## Gaps (ranked)

None.

## Next pick

None ranked; audit `docs/rubric.md` / wiki for the next gap.

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

`DR-20261111-05` § Deferred still names rival Tribe contact and fleetless
crowns; both live (`TribeContact`/`AiTribeColony`, `FleetMuster`).
`DR-20261112-09` fog closed by DR-13-03. Soft weight seed blocked
(DR-17-01). Learnings gaps none; #1213–#1218 counsel/fix, not backlog.
