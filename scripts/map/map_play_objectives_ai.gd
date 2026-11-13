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
	var readings: Dictionary = _readings(play, faction, config, economy, phase)
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), _pools(play, faction, economy, readings)
	)
	report["phase"] = String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN))
	report["goal"] = String(readings["goal"])
	report["treasury"] = int(readings["treasury"])
	report["reserve"] = int(readings["reserve"])
	play.ai.note_objectives(faction, report, play.turn)
	return report


# --- readings ----------------------------------------------------------------


## The planner-facing readings `AiObjectivesPlan` prices. A court with no army
## or fleet layer still reads (zeros), so a fixture never needs both.
static func _readings(
	play: PlaySession, faction: int, config: AiConfig, economy: PlayerEconomy,
	phase: Dictionary
) -> Dictionary:
	var at_war: bool = AiIncome.at_war(play.diplomacy, faction)
	var regiments: int = _regiments(play, faction)
	var reserve: int = AiIncome.reserve(config, economy, at_war, regiments)
	var muster_floor: int = AiArmyReinforce.muster_floor(config, economy, regiments, at_war)
	var home: int = FactionCatalog.region_of(faction)
	var new_world: MapModel = play.world.region(WorldMap.NEW_WORLD)
	var funding: String = AiResearchPlanner.funding_for(config, economy, reserve)
	var standing: String = AiResearchPlanner.standing_funding(config, economy)
	var slots: int = economy.research.slots.size() if economy.research != null else 0
	# The standing study is one slot at the cheapest preset, priced beside the
	# surplus preset so the ledger reads what the court will actually pay
	# (issue #490). It never lifts the index above the surplus preset.
	var funding_index: int = ResearchFunding.ORDER.find(funding)
	var research_cost: int = ResearchFunding.gold(funding) * maxi(slots, 0)
	if not standing.is_empty():
		research_cost += ResearchFunding.gold(standing)
		funding_index = maxi(funding_index, ResearchFunding.ORDER.find(standing))
	return {
		"posture": String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN)),
		"at_war": at_war,
		"war_desire": _war_desire(play, config, faction),
		"regiments": regiments,
		"muster_floor": muster_floor,
		"muster_due": muster_floor > 0,
		"ships": _ships(play, faction),
		"hostile_ships": _hostile_ships(play, faction),
		"treasury": economy.treasury,
		"reserve": reserve,
		"goal": AiIncome.goal_for(config, economy, at_war, regiments),
		"colony_target": home == WorldMap.OLD_WORLD and not _owns_land(new_world, faction),
		"harbour": home >= 0 and AiColonisationPlanner.harbour(
			play.world.region(home), faction
		) >= 0,
		"idle_hulls": _idle_hulls(play, faction),
		"voyage_afloat": _voyage_afloat(play, faction),
		"research_slots": slots,
		"research_funding": funding_index,
		"research_cost": research_cost,
	}


## The pools the allocate pass draws on. A pool is a per-turn grant: one order,
## one train slot, one muster slot, and the purse as it stands.
static func _pools(
	play: PlaySession, faction: int, economy: PlayerEconomy, readings: Dictionary
) -> Dictionary:
	return {
		"treasury": maxi(economy.treasury, 0),
		"hull": int(readings["idle_hulls"]),
		"civilian": 1,
		"regiment": 1,
		"labour": economy.available_peasants(),
		"orders": 1,
	}


## War desire against the court's enemy, else against the weakest Great Power —
## the same score the diplomacy planner weighs, read once per turn for the trace.
static func _war_desire(play: PlaySession, config: AiConfig, faction: int) -> int:
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
		"regiments": {faction: _regiments(play, faction), target: _regiments(play, target)},
		"ships": {faction: _ships(play, faction), target: _ships(play, target)},
	}
	return int(
		AiDiplomacyPlanner.war_desire(
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
		play.world, faction, _regiments(play, faction), _ships(play, faction)
	)


# --- state reads -------------------------------------------------------------


static func _regiments(play: PlaySession, faction: int) -> int:
	if play.army_layer == null:
		return 0
	return play.army_layer.regiment_count_all(faction)


static func _ships(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	return play.ship_layer.hull_count_all(faction)


## Hulls of every court at war with this one: the threat the navy objective
## prices.
static func _hostile_ships(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	var total: int = 0
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record == null or not record.at_war:
			continue
		total += _ships(play, record.other(faction))
	return total


## Squadrons that could take an expedition: afloat, un-moved, no troops and no
## colonists aboard. The same hull reading the colonisation planner sails.
static func _idle_hulls(play: PlaySession, faction: int) -> int:
	if play.ship_layer == null:
		return 0
	var total: int = 0
	for region: int in play.ship_layer.regions.region_ids():
		for raw: Variant in play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet == null or fleet.owner != faction or fleet.moved:
				continue
			if not fleet.is_afloat() or fleet.embarked_army >= 0:
				continue
			if fleet.carries_civilians():
				continue
			total += 1
	return total


## True while an expedition of this court is already at sea (a protected claim
## in T2, #497).
static func _voyage_afloat(play: PlaySession, faction: int) -> bool:
	if play.ship_layer == null:
		return false
	for region: int in play.ship_layer.regions.region_ids():
		for raw: Variant in play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet != null and fleet.owner == faction and fleet.carries_civilians():
				return true
	return false


static func _owns_land(model: MapModel, faction: int) -> bool:
	if model == null:
		return false
	for province: ProvinceState in model.provinces:
		if province.owner == faction:
			return true
	return false
