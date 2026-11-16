class_name MapPlayObjectivesAi
extends RefCounted
## Runs the objective ledger for every planning rival court and stamps it into
## the turn trace (docs/ai.md; issue #491 T1).
##
## Reads state only: T1 issues no order, so the same seed plays the same
## campaign and the ledger is a reading of the court, not a second planner
## (REQ-P2-03, REQ-P4-03). The pass runs before the expedition pass, because the
## voyage objectives are read from the hulls and the Explorer as they stand at
## the start of the turn (issue #491 T2).
##
## One ledger per court is kept in `play.objective_ledgers` for the turn log and
## the observer panel, and the claims are persisted on `AiState` so a save
## carries them (issue #491 T1 acceptance).


## Every planning court's ledger for this turn. Empty when the session has no
## world or diplomacy to read.
static func run(play: PlaySession) -> Dictionary:
	var ledgers: Dictionary = {}
	if play == null or play.world == null or play.diplomacy == null:
		return ledgers
	play.ensure_ai()
	for faction: int in FactionCatalog.great_power_ids():
		if not AiControl.plans(play, faction):
			continue
		ledgers[faction] = court(play, faction)
	return ledgers


## One court's ranked, allocated ledger plus the readings that made it.
static func court(play: PlaySession, faction: int) -> Dictionary:
	var economy: PlayerEconomy = play.ai.economy_for(faction)
	var config: AiConfig = AiConfig.build(faction, play.map_seed)
	var phase: Dictionary = AiPhasePlanner.plan(config, play.diplomacy)
	# The footing, the leader's weights and the court's distance to the bar
	# scale the rank without deleting an aim: a voyage at war is cheaper, not
	# gone (issue #491 T4; DR-20261114-04).
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	var readings: Dictionary = _readings(play, faction, config, economy, phase, pressure)
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), _pools(play, faction, economy, readings),
		AiPosture.modifiers(
			String(phase.get("phase", "")), config, int(pressure["boost_mille"]),
			String(readings["goal"])
		)
	)
	report["phase"] = String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN))
	report["goal"] = String(readings["goal"])
	report["treasury"] = int(readings["treasury"])
	report["reserve"] = int(readings["reserve"])
	# The deferred-aim escalations this reading applied (issue #603): the aims
	# stalled past the escalation bar, with their stall length.
	report["escalations"] = (readings["escalations"] as Dictionary).duplicate()
	report["pressure"] = pressure
	play.ai.note_objectives(faction, report, play.turn)
	return report


# --- readings ----------------------------------------------------------------


## The planner-facing readings `AiObjectivesPlan` prices. A court with no army
## or fleet layer still reads (zeros), so a fixture never needs both.
static func _readings(
	play: PlaySession, faction: int, config: AiConfig, economy: PlayerEconomy,
	phase: Dictionary, pressure: Dictionary = {}
) -> Dictionary:
	var at_war: bool = AiIncome.at_war(play.diplomacy, faction)
	var regiments: int = MapPlayCourt.regiments(play, faction)
	# The hull this court means to lay: the yard row its money goal reserves
	# alongside the next muster (issue #484).
	var warships: int = MapPlayCourt.warships(play, faction)
	var hostile_warships: int = MapPlayCourt.hostile_warships(play, faction)
	var flown: Array[String] = MapPlayCourt.hull_types(play, faction)
	# The one chest every pass reads: the yard's row, re-routed when the court
	# has stalled on it past the escalation bar (issue #603, `MapPlayCourt`).
	var hull_chest: int = MapPlayCourt.navy_chest(play, faction)
	# The deferred-aim escalation readings (#603): how long each aim has been
	# deferred without its shortfall shrinking. A stalled war chest re-routes
	# (`AiIncome.reserve`); a stall past the blocked bar names its reason in the
	# trace instead of another silent deferred row.
	var records: Dictionary = AiDeferral.records_for(play.ai.deferrals, faction)
	var escalations: Dictionary = AiDeferral.escalated(
		records, maxi(config.parameter("ledger.escalate_turns"), 1)
	)
	var blockings: Dictionary = AiDeferral.escalated(
		records, maxi(config.parameter("ledger.blocked_turns"), 1)
	)
	var reserve: int = AiIncome.reserve(
		config, economy, at_war, regiments, hull_chest, warships,
		AiDeferral.stall(records, "muster.line")
	)
	var muster_floor: int = AiArmyReinforce.muster_floor(config, economy, regiments, at_war)
	# The material row the pattern the court is saving for needs. The muster
	# reserves it (`AiClaims.MUSTER`, #474) and the planner refuses without it, so
	# the ledger prices it too: a row that reads `funded` on the purse alone would
	# clear the escalation's stall and let the court bank a chest it can never
	# spend — the deadlock this ledger exists to end (#603, #474).
	var muster_row: Dictionary = AiArmyReinforce.muster_reserve(
		config, economy, regiments, at_war
	)
	var home: int = FactionCatalog.region_of(faction)
	var new_world: MapModel = play.world.region(WorldMap.NEW_WORLD)
	var funding: String = AiResearchPlanner.funding_for(config, economy, reserve)
	var standing: String = AiResearchPlanner.standing_funding(config, economy, reserve)
	var slots: int = economy.research.slots.size() if economy.research != null else 0
	# The Tribe this court is drawing into its empire: the envoy chain's target,
	# next step and price (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
	var colony_ambition: Dictionary = AiTribeColony.best(
		play.diplomacy, play.world, play.court_charts, faction,
		economy.treasury, economy.tech_unlocked
	)
	# The deed the court is saving toward: the cheapest Minor or Tribe tile it
	# could sign, charted and at peace with the seller (issue #724 task 3).
	var deed: Dictionary = AiMerchantWork.openable_deed(
		play.world.region(home), faction,
		{"diplomacy": play.diplomacy, "visibility": MapPlayCourtFog.view_for(play, faction, home)}
	)
	# The surplus ladder reads the money-goal reserve; the standing study is one
	# slot at the cheapest preset above half the cash floor, so the ledger prices
	# what the court will actually pay (issue #490).
	var funding_index: int = ResearchFunding.ORDER.find(funding)
	var research_cost: int = ResearchFunding.gold(funding) * maxi(slots, 0)
	# The study the purse cannot fund this turn: the ledger names the refusal
	# instead of reading a 0-gold study as funded (issue #590).
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
		"posture": String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN)),
		"at_war": at_war,
		"war_desire": _war_desire(play, config, faction, pressure),
		"regiments": regiments,
		"muster_floor": muster_floor,
		"muster_due": muster_floor > 0,
		"muster_row": muster_row,
		"escalations": escalations,
		"blockings": blockings,
		"ships": MapPlayCourt.ships(play, faction),
		"warships": warships,
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
		"navy_due": hull_chest > 0,
		"hostile_ships": MapPlayCourt.hostile_ships(play, faction),
		"hostile_warships": hostile_warships,
		"treasury": economy.treasury,
		"reserve": reserve,
		"goal": AiIncome.goal_for(
			config, economy, at_war, regiments, hull_chest, warships
		),
		"colony_target": home == WorldMap.OLD_WORLD and not VoyageRead.owns_land(
			new_world, faction
		),
		"harbour": home >= 0 and AiColonisationPlanner.harbour(
			play.world.region(home), faction
		) >= 0,
		"idle_hulls": _idle_hulls(play, faction),
		"explorer_ready": _explorer_ready(play, faction),
		"voyage_afloat": _voyage_afloat(play, faction),
		"voyage_abroad": _voyage_abroad(play, faction),
		"voyage_stranded": _voyage_stranded(play, faction),
		"research_slots": slots,
		"research_funding": funding_index,
		"research_cost": research_cost,
		"standing_study": standing_study,
		"research_refusal": research_refusal,
		"tribe_target": int(colony_ambition.get("target", -1)),
		"tribe_stage_cost": int(colony_ambition.get("cost", 0)),
		# The deed the court is saving toward, 0 when no charted seller offers
		# one (issue #724 task 3).
		"deed_price": int(deed.get("price", 0)),
		# The study that opens the chain's next link, so the trace names the door
		# the court is walking to (DR-20261114-05).
		"tribe_door": AiTribeColony.door(
			play.diplomacy, play.world, play.court_charts, faction,
			economy.tech_unlocked
		),
	}


## The pools the allocate pass draws on. A pool is a per-turn grant: one order,
## one train slot, one muster slot, and the purse as it stands. The hull's
## material row is bounded by the store, so a fleet claim short of cloth reads
## `deferred fabric 0/1` instead of funded against an unlimited pool (issue #484).
static func _pools(
	play: PlaySession, faction: int, economy: PlayerEconomy, readings: Dictionary
) -> Dictionary:
	var pools: Dictionary = {
		"treasury": maxi(economy.treasury, 0),
		"hull": int(readings["idle_hulls"]),
		"civilian": 1,
		"regiment": 1,
		"labour": economy.available_peasants(),
		"orders": 1,
	}
	for commodity: Variant in (readings.get("warship_row", {}) as Dictionary).keys():
		pools[String(commodity)] = maxi(economy.quantity(String(commodity)), 0)
	# The muster's own material row, bounded by the store: a line short of its
	# cloth reads `deferred fabric 0/1`, the row the planner actually refuses on
	# (#474), instead of a funded purse the muster never spends.
	for commodity: Variant in (readings.get("muster_row", {}) as Dictionary).keys():
		var id: String = String(commodity)
		pools[id] = maxi(economy.quantity(id), 0)
	return pools


## War desire against the court's enemy, else against the weakest Great Power —
## the same score the diplomacy planner weighs, read once per turn for the trace.
## The victory press rides the same reading, so the ledger's war aim and the
## planner's declaration price the same war (DR-20261115-04).
static func _war_desire(
	play: PlaySession, config: AiConfig, faction: int, pressure: Dictionary = {}
) -> int:
	var target: int = _war_target(play, faction)
	if target < 0:
		target = _weakest_rival(play, faction)
	if target < 0 or play.diplomacy.relation(faction, target) == null:
		return 0
	var powers: Dictionary = {
		faction: _power(play, faction), target: _power(play, target),
	}
	var context: Dictionary = {
		"power": powers,
		"victory_press": int(pressure.get("war_press", 0)),
		"regiments": {
			faction: MapPlayCourt.regiments(play, faction),
			target: MapPlayCourt.regiments(play, target),
		},
		"ships": {
			faction: MapPlayCourt.ships(play, faction),
			target: MapPlayCourt.ships(play, target),
		},
	}
	return int(
		AiDiplomacyDesire.war_desire(
			config, play.diplomacy, play.world, faction, target, context
		).get("score", 0)
	)


## The first Great Power this court is at war with, or -1.
static func _war_target(play: PlaySession, faction: int) -> int:
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record == null or not record.at_war:
			continue
		var other: int = record.other(faction)
		if FactionCatalog.type_of(other) == FactionCatalog.Type.GREAT_POWER:
			return other
	return -1


## Weakest rival by the published power score; the id breaks a tie, so the same
## chart always reads the same target.
static func _weakest_rival(play: PlaySession, faction: int) -> int:
	var best: int = -1
	var best_score: int = 0
	for rival: int in FactionCatalog.great_power_ids():
		if rival == faction:
			continue
		var score: int = _power(play, rival)
		if best < 0 or score < best_score:
			best = rival
			best_score = score
	return best


static func _power(play: PlaySession, faction: int) -> int:
	return AiPower.score(
		play.world, faction, MapPlayCourt.regiments(play, faction),
		MapPlayCourt.ships(play, faction)
	)


# --- state reads -------------------------------------------------------------


## Squadrons that could take an expedition: afloat, un-moved, no troops and no
## colonists aboard. The same hull reading the colonisation planner sails.
static func _idle_hulls(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	var total: int = 0
	for region: int in play.ship_layer.regions.region_ids():
		total += VoyageRead.free_count(
			MapPlayCourt.region_fleets(play, region), faction
		)
	return total


## An idle Explorer of this court at home: the colonist the next train slot
## musters (issue #491 T2).
static func _explorer_ready(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	return VoyageRead.idle_colonist(
		play.civilian_layer.regions.value(home, []), faction, "explorer"
	) != null


## True while an expedition of this court is already at sea (a protected claim
## in T2, #497).
static func _voyage_afloat(play: PlaySession, faction: int) -> bool:
	if play.ship_layer == null:
		return false
	for region: int in play.ship_layer.regions.region_ids():
		if VoyageRead.carrying(
			MapPlayCourt.region_fleets(play, region), faction
		) != null:
			return true
	return false


## True while a colonist of this court already stands on the far shore (its
## landing is the voyage's own progress, not a missing Explorer): the child that
## musters a new one is not blocked, and the parent prices the voyage instead
## (#497). A court with a civilian in the other region has nothing left to
## muster either — `MapPlayCivilianAi._muster_port` holds the gate shut until
## that colonist leaves or works.
static func _voyage_abroad(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	for region: int in play.civilian_layer.regions.region_ids():
		if region == home:
			continue
		for raw: Variant in play.civilian_layer.regions.value(region, []):
			var unit: CivilianState = raw
			if unit != null and unit.owner == faction:
				return true
	return false


## True while an Explorer of this court stands ashore in a region its crown does
## not own. It founds nothing (a Builder needs crown land) and cannot board again
## — boarding needs a squadron in port and docking needs a crown port — so the
## expedition can never sail on: the ledger reads the aim blocked with that
## reason instead of funding a voyage the planner will not order (issue #602).
## A Merchant ashore is left to #497's reading: it buys the deeds that found the
## colony, so its voyage is still progress.
static func _voyage_stranded(play: PlaySession, faction: int) -> bool:
	if play.civilian_layer == null or play.world == null:
		return false
	var home: int = FactionCatalog.region_of(faction)
	if home < 0:
		return false
	for region: int in play.civilian_layer.regions.region_ids():
		if region == home:
			continue
		var model: MapModel = play.world.region(region)
		if model == null or VoyageRead.owns_land(model, faction):
			continue
		for raw: Variant in play.civilian_layer.regions.value(region, []):
			var unit: CivilianState = raw
			if unit == null or unit.owner != faction:
				continue
			if unit.type_id == "explorer" and not unit.is_embarked():
				return true
	return false
