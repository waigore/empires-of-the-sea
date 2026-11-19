class_name MapPlayObjectiveReadings
extends RefCounted
## What a rival court's objective ledger reads before it prices an aim: its
## force, its purse, the yard's hull, the college's study, the Tribe it is
## drawing in and the expedition it has afloat (docs/ai.md; issue #491 T1).
##
## One reading per domain, each domain read once: the same figures feed the
## ledger's rank, the allocate pass's pools and the turn trace, so a court never
## prices an aim against a number the planner would not spend (REQ-P2-03,
## REQ-P3-01).
##
## Reads state only: no order is issued here, so the same seed plays the same
## campaign and the ledger stays a reading of the court, not a second planner
## (REQ-P4-03). Voyage answers live on [MapPlayObjectiveVoyage]; war desire on
## [MapPlayObjectiveWar].


## Every reading `AiObjectivesPlan` prices, gathered domain by domain. The host
## readings are taken once and handed down, because the purse, the yard and the
## college all price against the same counts.
static func readings(
	play: PlaySession, faction: int, config: AiConfig, economy: PlayerEconomy,
	phase: Dictionary, pressure: Dictionary = {}
) -> Dictionary:
	var host: Dictionary = _host(play, faction, economy)
	# The win-bar reading the bank rides on (issue #995): the submission
	# surface banks for the army its conquest needs; a baseline court keeps
	# its published reserve, so the ledger must not stamp a bank it does not
	# hold.
	host["conquest_gap"] = (
		AiControl.court_kind(play, faction) != AiControl.KIND_BASELINE
		and not pressure.is_empty() and int(pressure.get("need", 0)) > 0
	)
	var readings: Dictionary = _force(play, config, faction, economy, pressure, host)
	readings.merge(_navy(economy, host))
	var purse: Dictionary = _purse(config, economy, host, pressure)
	readings.merge(purse)
	readings.merge(_study(config, economy, purse))
	readings.merge(_court(play, faction, economy, phase))
	readings.merge(MapPlayObjectiveVoyage.reading(play, faction))
	return readings


# --- host --------------------------------------------------------------------


## The counts every other reading prices against: the footing, the men on the
## field, the hulls afloat and the chest the yard has banked, plus the deferral
## records the escalation bar is read from (issue #603).
static func _host(play: PlaySession, faction: int, economy: PlayerEconomy) -> Dictionary:
	return {
		"at_war": AiIncome.at_war(play.diplomacy, faction),
		"regiments": MapPlayCourt.regiments(play, faction),
		"ships": MapPlayCourt.ships(play, faction),
		"warships": MapPlayCourt.warships(play, faction),
		"hostile_ships": MapPlayCourt.hostile_ships(play, faction),
		"hostile_warships": MapPlayCourt.hostile_warships(play, faction),
		"flown": MapPlayCourt.hull_types(play, faction),
		"hull_chest": MapPlayCourt.navy_chest(play, faction),
		"records": AiDeferral.records_for(play.ai.deferrals, faction),
		"treasury": economy.treasury,
	}


# --- domains ----------------------------------------------------------------


## The court's force and its footing: the men it fields, the muster it owes, and
## the aims it has deferred past the escalation bar (issue #603). The muster
## reserves the material row the pattern it is saving for needs (`AiClaims.MUSTER`,
## #474), so the ledger prices that row too: a line that read `funded` on the
## purse alone would clear the escalation's stall and let the court bank a chest
## it can never spend — the deadlock this ledger exists to end.
static func _force(
	play: PlaySession, config: AiConfig, faction: int, economy: PlayerEconomy,
	pressure: Dictionary, host: Dictionary
) -> Dictionary:
	var at_war: bool = bool(host["at_war"])
	var regiments: int = int(host["regiments"])
	var records: Dictionary = host["records"]
	var muster_floor: int = AiArmyReinforce.muster_floor(config, economy, regiments, at_war)
	return {
		"at_war": at_war,
		"war_desire": MapPlayObjectiveWar.desire(play, config, faction, pressure),
		"regiments": regiments,
		"muster_floor": muster_floor,
		"muster_due": muster_floor > 0,
		"muster_row": AiArmyReinforce.muster_reserve(config, economy, regiments, at_war),
		"escalations": AiDeferral.escalated(
			records, maxi(config.parameter("ledger.escalate_turns"), 1)
		),
		"blockings": AiDeferral.escalated(
			records, maxi(config.parameter("ledger.blocked_turns"), 1)
		),
	}


## The navy: the hull the court means to lay, its price and its material row,
## and the hostile sail it must answer (issue #484).
static func _navy(economy: PlayerEconomy, host: Dictionary) -> Dictionary:
	var flown: Array[String] = host["flown"]
	return {
		"ships": int(host["ships"]),
		"warships": int(host["warships"]),
		"warship_price": AiNavy.price(economy, flown),
		"warship_row": AiNavy.saving_row(economy, flown),
		# False while the court still studies the unlock: the build keeps its
		# chest and cloth reserved but will not fund a launch the yard refuses
		# (issue #484). A type the court already flies counts as open.
		"warship_open": (
			not AiNavy.saving_type(economy, flown).is_empty()
			and ShipEconomy.buildable(
				AiNavy.saving_type(economy, flown), economy.tech_unlocked, flown
			)
		),
		"navy_due": int(host["hull_chest"]) > 0,
		"hostile_ships": int(host["hostile_ships"]),
		"hostile_warships": int(host["hostile_warships"]),
	}


## The chest and the aim it is banked for: the reserve the other claims leave,
## the money goal the court is walking toward (issue #484, #603). A court short
## of the bar banks at peace too (issue #995) — on the submission surface,
## which stamps the gap on the host — so the ledger reads the same chest the
## economy pass plans with; a caller that hands no pressure keeps the
## published behaviour.
static func _purse(
	config: AiConfig, economy: PlayerEconomy, host: Dictionary,
	pressure: Dictionary = {}
) -> Dictionary:
	var at_war: bool = bool(host["at_war"])
	var regiments: int = int(host["regiments"])
	var hull_chest: int = int(host["hull_chest"])
	var warships: int = int(host["warships"])
	var conquest_gap: bool = bool(host.get("conquest_gap", false))
	return {
		"treasury": int(host["treasury"]),
		"reserve": AiIncome.reserve(
			config, economy, at_war, regiments, hull_chest, warships,
			AiDeferral.stall(host["records"], "muster.line"), conquest_gap
		),
		"goal": AiIncome.goal_for(
			config, economy, at_war, regiments, hull_chest, warships, conquest_gap
		),
	}


## The college: the study the purse can fund, the standing study it may still
## dip into the chest for, and the refusal the ledger names instead of reading a
## 0-gold study as funded (issue #490, #590).
static func _study(
	config: AiConfig, economy: PlayerEconomy, purse: Dictionary
) -> Dictionary:
	var reserve: int = int(purse["reserve"])
	var funding: String = AiResearchPlanner.funding_for(config, economy, reserve)
	var standing: String = AiResearchPlanner.standing_funding(config, economy, reserve)
	var slots: int = economy.research.slots.size() if economy.research != null else 0
	var funding_index: int = ResearchFunding.ORDER.find(funding)
	var research_cost: int = ResearchFunding.gold(funding) * maxi(slots, 0)
	var research_refusal: String = ""
	var standing_study: int = 0
	if not standing.is_empty():
		# The standing study is the bounded exception that may dip into the
		# chest the muster claims, so it prices its own one-slot budget beside
		# the chest rather than against the purse the chest consumes (#590).
		standing_study = 1
		funding_index = maxi(funding_index, ResearchFunding.ORDER.find(standing))
	elif funding == ResearchFunding.ORDER[0]:
		research_refusal = AiResearchPlanner.standing_refusal(config, economy, reserve)
		research_cost = ResearchFunding.gold(AiResearchPlanner.STANDING_FUNDING)
	return {
		"research_slots": slots,
		"research_funding": funding_index,
		"research_cost": research_cost,
		"standing_study": standing_study,
		"research_refusal": research_refusal,
	}


## The court's court: the Tribe it is drawing into its empire (wiki: diplomacy
## § GP–Tribe Rules; DR-20261114-02), the deed it is saving toward (issue #724),
## and the colony its own chart no longer offers. A war footing opens no new
## chain; the stake it already holds keeps its step (DR-20261116-11).
static func _court(
	play: PlaySession, faction: int, economy: PlayerEconomy, phase: Dictionary
) -> Dictionary:
	var posture: String = String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN))
	var home: int = FactionCatalog.region_of(faction)
	var new_world: MapModel = play.world.region(WorldMap.NEW_WORLD)
	var colony_ambition: Dictionary = AiTribeColony.best(
		play.diplomacy, play.world, play.court_charts, faction,
		economy.treasury, economy.tech_unlocked, posture
	)
	var deed: Dictionary = AiMerchantWork.openable_deed(
		play.world.region(home), faction,
		{"diplomacy": play.diplomacy, "visibility": MapPlayCourtFog.view_for(play, faction, home)}
	)
	return {
		"posture": posture,
		"colony_target": home == WorldMap.OLD_WORLD and not VoyageRead.owns_land(
			new_world, faction
		),
		"harbour": home >= 0 and AiColonisationPlanner.harbour(
			play.world.region(home), faction
		) >= 0,
		"tribe_target": int(colony_ambition.get("target", -1)),
		"tribe_stage_cost": int(colony_ambition.get("cost", 0)),
		# The deed the court is saving toward, 0 when no charted seller offers
		# one (issue #724 task 3).
		"deed_price": int(deed.get("price", 0)),
		# The study that opens the chain's next link, so the trace names the door
		# the court is walking to (DR-20261114-05). A chain the footing holds
		# shut has no door (DR-20261116-11).
		"tribe_door": AiTribeColony.door(
			play.diplomacy, play.world, play.court_charts, faction,
			economy.tech_unlocked, posture
		),
		# Why the footing holds a new chain shut this turn, "" when it opens one:
		# the ledger prints the closed aim with this reason instead of dropping
		# the row (DR-20261116-11).
		"tribe_closed": AiTribeColony.closed_reason(posture),
	}
