class_name MapPlayFleetPickWords
extends RefCounted
## How one naval pick is worded (wiki: ships-and-naval § Missions and Movement,
## ai-architecture § Naval policy; DR-20261120-04): the order the published
## policy would give the squadron, in the rule book's own names — the water she
## would enter, the harbour she would dock at, the reason she turns for home. A
## reading, never an order; every figure is one the planner actually decided on.

const KIND_SORTIE: String = AiNavalPlanner.KIND_SORTIE
const KIND_PURSUE: String = AiNavalPlanner.KIND_PURSUE
const KIND_RAID: String = AiNavalPlanner.KIND_RAID
const KIND_HOME: String = AiNavalPlanner.KIND_HOME
## A merchant hull's sail names itself: a convoy, not a war sortie (issue #1258).
const KIND_CONVOY: String = AiNavalPlanner.KIND_CONVOY
const REASON_TRADE: String = AiNavalPlanner.REASON_TRADE
const REASON_FRONTS: String = AiNavalPlanner.REASON_FRONTS

## One order, worded for the crown's sheet. Empty when the planner's order names
## nothing this module can say (an unknown kind, or a chart with no such water).
static func line(model: MapModel, order: Dictionary) -> String:
	if model == null or order.is_empty():
		return ""
	var kind: String = String(order.get("kind", ""))
	var said: String = ""
	match kind:
		KIND_SORTIE:
			said = _hunt(model, order, "sortie into")
		KIND_PURSUE:
			said = _hunt(model, order, "pursue into")
		KIND_RAID:
			said = _raid(model, order)
		KIND_CONVOY:
			said = _convoy(model, order)
		KIND_HOME:
			said = _home(model, order)
		_:
			return ""
	if said.is_empty():
		return ""
	var reason: String = _reason(String(order.get("reason", "")))
	return said if reason.is_empty() else "%s — %s" % [said, reason]

## A fight the court means to pick: the zone it sails into and the strength it
## counted there. The figure is the planner's own reading (`threat`), so the line
## can never promise a fight the caution margin declined (REQ-P2-03).
static func _hunt(model: MapModel, order: Dictionary, verb: String) -> String:
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	var threat: int = int(order.get("threat", 0))
	if threat <= 0:
		return "the court would %s the %s" % [verb, model.sea_zone_name(zone)]
	return "the court would %s the %s — a hostile squadron there, counted at %d strength" % [
		verb, model.sea_zone_name(zone), threat
	]

## The trade leg: a warship with no squadron to fight works a hostile coast, and
## this turn's sail is the first step toward it (DR-20261111-17).
static func _raid(model: MapModel, order: Dictionary) -> String:
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return "the court would sail for the %s — the first leg toward a hostile coast, to work its trade" % model.sea_zone_name(zone)

## A merchant hull's leg home is a convoy, not a war move: the trace and the
## sheet say so, and the holds ride the same road back (issue #1258).
static func _convoy(model: MapModel, order: Dictionary) -> String:
	if bool(order.get("dock", false)):
		var port: int = int(order.get("province", MapModel.NO_ID))
		if port == MapModel.NO_ID:
			return ""
		return "the court would convoy her home to %s" % model.province_name(port)
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return "the court would convoy her toward the %s — the first leg home with the holds" % model.sea_zone_name(zone)

## Home: she docks when the harbour borders her water, else she takes the first
## leg of the road back (DR-20261110-30).
static func _home(model: MapModel, order: Dictionary) -> String:
	if bool(order.get("dock", false)):
		var port: int = int(order.get("province", MapModel.NO_ID))
		if port == MapModel.NO_ID:
			return ""
		return "the court would dock her at %s" % model.province_name(port)
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone == MapModel.NO_ID:
		return ""
	return "the court would sail for the %s — the first leg home" % model.sea_zone_name(zone)

## Why she is going home, in the policy's own two reasons: the holds the crown
## keeps nowhere else, or a court at war on two fronts opening no new station.
static func _reason(reason: String) -> String:
	if reason == REASON_TRADE:
		return "the holds come first, and the crown keeps none ashore"
	if reason == REASON_FRONTS:
		return "two fronts, so the court opens no new raid"
	return ""
