class_name MapPlayExpeditionPick
extends RefCounted
## What the court's own staff would do with an expedition this turn: the step the
## published invasion policy takes with a squadron that carries a host — the water
## she sails, the Passage she crosses, the coast she marks, and the landing that
## opens (wiki: ships-and-naval § Missions and Movement, § Naval transport;
## ai-architecture § Naval policy; DR-20261122-20).
##
## The plan is not a second opinion: it is `AiBindCampaign.invasion_plan`, the
## call the rival pass and the Auto seat already make for a court, read for this
## crown on its own chart, its own relations and its own charted water — so the
## line can never name a step the rules would refuse (REQ-P2-03). The naval pick
## steps aside for a squadron carrying a host ("the invasion planner steers
## her"), and this module answers where that one leaves off. A squadron with no
## host aboard keeps the naval pick: boarding from the seat is a sail or a dock
## the naval policy already words.
##
## A reading only: nothing here sails, crosses, marks a coast or lands a host,
## and the crown still presses her own order (REQ-P3-03, REQ-P5-06).

const KIND_SAIL: String = AiInvasionPlanner.KIND_SAIL
const KIND_CROSS: String = AiInvasionPlanner.KIND_CROSS
const KIND_BEACHHEAD: String = AiInvasionPlanner.KIND_BEACHHEAD
const KIND_LAND: String = AiInvasionPlanner.KIND_LAND


## The pick for one squadron, as the sheet reads it: `{kind, zone, province,
## line, short}`. Empty when she carries no host, when the planner steers another
## squadron, when she has already sailed, when the session runs no planner, or
## when the policy would take no step she could press this turn.
static func pick(play: PlaySession, fleet: FleetState) -> Dictionary:
	if play == null or fleet == null or play.ship_layer == null:
		return {}
	if play.army_layer == null or play.diplomacy == null or play.world == null:
		return {}
	if fleet.owner != play.player_faction:
		return {}
	# This module answers an expedition alone: a squadron with no host aboard is
	# the naval pick's, and boarding is a sail or a dock that pick words.
	if fleet.embarked_army < 0:
		return {}
	# A squadron that has sailed keeps the step she was given; the pass plans her
	# again next turn, and a second step could not be pressed (one move a turn).
	if fleet.moved or play.campaign_over() or play.observer_mode:
		return {}
	var region: int = MapPlayFleetPick.region_of(play, fleet)
	var model: MapModel = MapPlayFleetPick.model_of(play, region)
	if model == null:
		return {}
	# The pass plans one expedition a court — the lowest-id squadron with a host
	# aboard (`AiInvasionPlanner._expedition`) — so a second one answers nothing
	# rather than naming the first one's step.
	if not _steered(play, fleet, region):
		return {}
	var court: Dictionary = AiControl.court(play, fleet.owner)
	if court.is_empty():
		return {}
	var kind: String = String(court["kind"])
	var config: Variant = court["config"]
	if config == null:
		return {}
	var plan: Dictionary = AiBindCampaign.invasion_plan(
		kind, config, play.diplomacy, play.world, region, model,
		MapPlayCourt.region_fleets(play, region), MapPlayCourt.visible_armies(play, region),
		play.turn, play.court_charts, MapPlaySeaStep.earning(play, fleet.owner, kind, config)
	)
	if plan.is_empty() or int(plan.get("fleet", -1)) != fleet.id:
		return {}
	var line: String = words(model, plan)
	if line.is_empty():
		return {}
	return {
		"kind": String(plan.get("kind", "")),
		"zone": int(plan.get("zone", MapModel.NO_ID)),
		"province": int(plan.get("province", MapModel.NO_ID)),
		"short": line,
		"line": line,
	}


## The sheet's line: the step's own sentence, or nothing when the court would take
## no step with this expedition this turn.
static func line(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayPickProse.sentence_of(pick(play, fleet))


## The hostile coast the step would mark, for the mission rows to lead with the
## counsel's mark; `-1` for every step that marks nothing. A landing names the
## site already marked, which is no row, so only a beachhead answers.
static func marked_coast(pick: Dictionary) -> int:
	if String(pick.get("kind", "")) != KIND_BEACHHEAD:
		return -1
	return int(pick.get("province", -1))


## One step, worded in the rule book's own names. Empty for a kind this module
## cannot say or a step whose place reads nothing (a chart with no such water).
static func words(model: MapModel, order: Dictionary) -> String:
	if model == null or order.is_empty():
		return ""
	match String(order.get("kind", "")):
		KIND_SAIL:
			return _zone(model, order, "the court would sail the expedition for the %s")
		KIND_CROSS:
			return "the court would cross the Passage with the host aboard"
		KIND_BEACHHEAD:
			return _at(
				model, order,
				"the court would mark a beachhead on the coast of %s — the landing opens next turn"
			)
		KIND_LAND:
			return _at(model, order, "the court would land the host at %s")
	return ""


## The step's province, named. A step with no province reads nothing, so its line
## is withheld rather than printed half said.
static func _at(model: MapModel, order: Dictionary, pattern: String) -> String:
	var province: int = int(order.get("province", MapModel.NO_ID))
	if province == MapModel.NO_ID:
		return ""
	return pattern % model.province_name(province)


## The step's water, named: the first leg toward the port, the Passage or the
## coast the policy is walking.
static func _zone(model: MapModel, order: Dictionary, pattern: String) -> String:
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return pattern % model.sea_zone_name(zone)


## True when this is the squadron the published pass would plan: no other crown
## squadron of a lower id in the same roster carries a host.
static func _steered(play: PlaySession, fleet: FleetState, region: int) -> bool:
	for raw: Variant in MapPlayCourt.region_fleets(play, region):
		var other: FleetState = raw
		if other == null or other.owner != fleet.owner or other.embarked_army < 0:
			continue
		if other.id < fleet.id:
			return false
	return true
