class_name MapPlayFleetPick
extends RefCounted
## What the court's own admiral would order a squadron this turn: the order the
## published naval policy gives her — the water she would enter, the fight she
## would pick, the coast she would work, or the road home (wiki: ships-and-naval
## § Missions and Movement, ai-architecture § Naval policy; DR-20261120-04).
##
## The plan is not a second opinion: it is `AiBindCampaign.naval_orders`, the
## call the rival pass and the Auto seat already make for a court, read for this
## crown on its own chart, its own footing and the roster of the chart she sails
## on — so the line can never name a sail the rules would refuse (REQ-P2-03).
## A reading only: nothing here moves a hull, takes a station or rolls a die, and
## the crown still presses her own order (REQ-P3-03, REQ-P5-06).


## The pick for one squadron, as the sheet reads it: `{kind, zone, dock,
## province, threat, reason, line, short}`. Empty when the court would give her
## none — a rival's hull, a squadron that has already sailed, a squadron carrying
## an expedition (the invasion planner steers her), a session whose court runs no
## planner, or a chart with no model to read.
static func pick(play: PlaySession, fleet: FleetState) -> Dictionary:
	if play == null or fleet == null or play.ship_layer == null:
		return {}
	if play.diplomacy == null or fleet.owner != play.player_faction:
		return {}
	# A squadron that has sailed keeps the order she was given; the policy skips
	# her, and so does the sheet (wiki: ships-and-naval § Missions and Movement).
	if fleet.moved or play.campaign_over():
		return {}
	var region: int = region_of(play, fleet)
	var model: MapModel = model_of(play, region)
	if model == null:
		return {}
	var kind: String = AiControl.court_kind(play, fleet.owner)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(kind, fleet.owner, play.map_seed, play.ensure_ai().profiles)
	if config == null:
		return {}
	var plan: Dictionary = AiBindCampaign.naval_orders(
		kind, config, play.diplomacy, model, MapPlayCourt.region_fleets(play, region),
		play.court_charts
	)
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		if int(order.get("fleet_id", -1)) != fleet.id:
			continue
		return _words(model, order)
	return {}


## The sheet's line: the pick's own sentence, or nothing when the court would
## give this squadron no order this turn.
static func line(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayPickProse.sentence(String(pick(play, fleet).get("line", "")))


## One order, carried with the words the sheet prints. The kind, the water and
## the reason travel beside them so a caller can read the pick without parsing a
## sentence.
static func _words(model: MapModel, order: Dictionary) -> Dictionary:
	var line: String = MapPlayFleetPickWords.line(model, order)
	if line.is_empty():
		return {}
	return {
		"kind": String(order.get("kind", "")),
		"zone": int(order.get("zone", MapModel.NO_ID)),
		"dock": bool(order.get("dock", false)),
		"province": int(order.get("province", MapModel.NO_ID)),
		"threat": int(order.get("threat", 0)),
		"reason": String(order.get("reason", "")),
		"short": line,
		"line": line,
	}


## The chart this squadron sails on: the layer's live roster when she is drawn
## there, else the region table that stores her (the muster roll's own read).
static func region_of(play: PlaySession, fleet: FleetState) -> int:
	var layer: ShipLayer = play.ship_layer
	if layer.model != null and layer.fleets.has(fleet):
		return layer.model.region_id
	for index: int in layer.regions.region_ids():
		var roster: Array[FleetState] = []
		roster.assign(layer.regions.value(index, []))
		if roster.has(fleet):
			return index
	return -1


## The model of one region: the chart on screen when it is that region, else the
## world's own. Null when neither holds it, so no pick is worded off a wrong map.
static func model_of(play: PlaySession, region: int) -> MapModel:
	if region < 0:
		return null
	if play.model != null and play.model.region_id == region:
		return play.model
	if play.world == null:
		return null
	return play.world.region(region)
