class_name FleetSplit
extends RefCounted
## Detaching one hull into a squadron of her own (wiki: ships-and-naval
## § Ship instances — split partitions instances by id; § Home Fleet — only the
## home fleet may lie in port at the capital). Pure rules: the roster surgery is
## here, markers and toasts belong to [ShipLayer] and MapPlayFleetSplit
## (REQ-P3-03).
##
## A detached hull keeps her instance id, her catalog type and the name she flew,
## and stands in the same water (or the same port) as the squadron she left. The
## squadron that keeps the station keeps her passengers: one hull carries one
## regiment or colonist, so a hull only leaves when the rest can still hold them.

## The rule the sheet prints, so a phone never has to hover for it (REQ-P1-07).
const NOTE: String = (
	"Detach a hull into a squadron of her own: she keeps her name and her "
	+ "station, and the passengers stay aboard this one."
)


## Every hull of the squadron with the verdict on detaching her, in roster
## order. A caller with no squadron gets no rows.
static func rows(model: MapModel, fleet: FleetState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fleet == null or not fleet.is_afloat():
		return rows
	for hull_id: String in fleet.hulls:
		var check: Dictionary = can_detach(model, fleet, hull_id)
		var type_id: String = fleet.type_of(hull_id)
		rows.append({
			"hull": hull_id,
			"type": type_id,
			"name": ShipNames.of(fleet, hull_id),
			"type_name": ShipStats.display_name(type_id),
			"ok": bool(check["ok"]),
			"reason": String(check["reason"]),
		})
	return rows


## Whether one hull may leave: own colours, a hull that is aboard, a squadron
## that keeps at least one hull, a squadron that is not the home fleet, and a
## deck the passengers still fit on.
static func can_detach(
	model: MapModel, fleet: FleetState, hull_id: String
) -> Dictionary:
	if fleet == null:
		return OrderVerdict.deny("There is no squadron to split.")
	if not fleet.hulls.has(hull_id):
		return OrderVerdict.deny("That hull is not aboard this squadron.")
	if fleet.ship_count() < 2:
		return OrderVerdict.deny("A squadron of one hull has nothing to detach.")
	if model != null and NavalMovement.is_home_fleet(model, fleet):
		return OrderVerdict.deny("The home squadron keeps your seat — put to sea first.")
	if fleet.embarked_army >= 0:
		return OrderVerdict.deny("Land the troops before splitting the squadron.")
	var aboard: int = fleet.civilian_count()
	if fleet.ship_count() - 1 < aboard:
		return OrderVerdict.deny(
			"The squadron cannot detach a hull while it carries %d passengers."
			% aboard
		)
	return OrderVerdict.allow()


## Detaches one hull into a new squadron in the same station and appends her to
## the roster. Returns the new squadron, the hull's id, type and name, or the
## gate's own refusal with nothing moved.
static func detach(
	model: MapModel,
	fleets: Array[FleetState],
	fleet: FleetState,
	hull_id: String,
	new_id: int
) -> Dictionary:
	var check: Dictionary = can_detach(model, fleet, hull_id)
	if not bool(check.get("ok", false)):
		return _refused(String(check.get("reason", "")))
	var type_id: String = fleet.type_of(hull_id)
	var hull_name: String = ShipNames.of(fleet, hull_id)
	fleet.remove_hull(hull_id)
	var split: FleetState = _stand(fleet, new_id, hull_id, type_id, hull_name)
	fleets.append(split)
	return {
		"ok": true,
		"reason": "",
		"fleet": split,
		"hull": hull_id,
		"type": type_id,
		"name": hull_name,
	}


## The new command: the source's station, one hull, the name she flew, and the
## source's readiness — a hull that has already sailed does not sail again.
static func _stand(
	source: FleetState, new_id: int, hull_id: String, type_id: String, hull_name: String
) -> FleetState:
	var split: FleetState
	if source.is_at_sea():
		split = FleetState.at_sea(
			new_id, source.owner, source.sea_zone, [hull_id], {hull_id: type_id}
		)
	else:
		split = FleetState.in_port(
			new_id, source.owner, source.province, [hull_id], {hull_id: type_id}
		)
	split.hull_names[hull_id] = hull_name
	split.moved = source.moved
	return split


static func _refused(reason: String) -> Dictionary:
	return OrderVerdict.deny(reason, {
		"fleet": null, "hull": "", "type": "", "name": "",
	})
