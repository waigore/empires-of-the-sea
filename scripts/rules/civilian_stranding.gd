class_name CivilianStranding
extends RefCounted
## Crown-land crews caught on land their crown no longer holds (conquest takes
## the province out from under a Builder, Engineer or Rail Builder). Mirrors
## `NavalPortLoss.evict_stranded`: the crew withdraws to an adjacent tile its
## kind may enter, and a crew with nowhere to stand is lost with the province.
## Explorers, Merchants and Spies live off foreign land, so they stay put.
## Pure rules over map data and unit state (REQ-P3-03).

const CROWN_LAND_TYPES: Array[String] = ["builder", "engineer", "rail_builder"]


## Withdraws every stranded crown-land unit in `units` (mutating the roster in
## place for losses) and returns one report per affected crew.
static func withdraw(model: MapModel, units: Array[CivilianState]) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if model == null:
		return reports
	for unit: CivilianState in units.duplicate():
		if unit == null or not CROWN_LAND_TYPES.has(unit.type_id):
			continue
		if CivilianMovement.may_enter(model, unit.type_id, unit.owner, unit.tile):
			continue
		var from: Vector2i = unit.tile
		var target: Vector2i = _legal_neighbour(model, unit)
		# The crown lost the ground under the order; work on it cannot continue.
		unit.clear_work()
		if target.x < 0:
			units.erase(unit)
			reports.append({
				"unit": unit.id,
				"owner": unit.owner,
				"type": unit.type_id,
				"from": from,
				"lost": true,
			})
			continue
		unit.tile = target
		unit.moved = true
		reports.append({
			"unit": unit.id,
			"owner": unit.owner,
			"type": unit.type_id,
			"from": from,
			"to": target,
			"lost": false,
		})
	return reports


## Deterministic first legal orthogonal neighbour (north, east, south, west).
static func _legal_neighbour(model: MapModel, unit: CivilianState) -> Vector2i:
	for offset: Vector2i in [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
	]:
		var tile: Vector2i = unit.tile + offset
		if CivilianMovement.may_enter(model, unit.type_id, unit.owner, tile):
			return tile
	return CivilianState.NO_TILE
