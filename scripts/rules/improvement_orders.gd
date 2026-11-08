class_name ImprovementOrders
extends RefCounted
## Estates-ledger intents: dispatch the nearest Builder to an estate and cancel
## an active improvement order. All gates and costs stay in CivilianWork
## (REQ-P2-03); this module only chooses the civilian and words the report.

const BUILD: String = "build_improvement"


## Returns {ok, message}. `action` is "build" or "cancel".
static func apply(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	action: String,
	tile: Vector2i,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	match action:
		"build":
			return build(
				model, units, works, stockpile, visibility, owner, tile, tech_caps,
				tech_unlocked
			)
		"cancel":
			return cancel(model, units, owner, tile)
	return {"ok": false, "message": "Unknown estate order."}


static func build(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	tile: Vector2i,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var active: CivilianState = working_builder(units, owner, tile)
	if active != null:
		return {
			"ok": false,
			"message": "A Builder is already at work on this estate.",
		}
	var builder: CivilianState = nearest_builder(units, owner, tile)
	if builder == null:
		return {
			"ok": false,
			"message": "No idle Builder musters — train one at the capital.",
		}
	var result: Dictionary = CivilianWork.assign(
		model, builder, BUILD, works, units, stockpile, visibility, tile, tech_caps,
		tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	var resource: int = model.resource_at(tile.x, tile.y)
	var level: int = works.improvement_at(model, tile)
	return {
		"ok": true,
		"message": "%s takes the estate in %s — %s, %d turn%s." % [
			builder.display_name(),
			model.province_name(model.province_at(tile.x, tile.y)),
			ImprovementCatalog.display_name(resource, level + 1),
			int(result.get("duration", 1)),
			"" if int(result.get("duration", 1)) == 1 else "s",
		],
	}


static func cancel(
	model: MapModel, units: Array[CivilianState], owner: int, tile: Vector2i
) -> Dictionary:
	var builder: CivilianState = working_builder(units, owner, tile)
	if builder == null:
		return {"ok": false, "message": "No Builder is at work on this estate."}
	builder.cancel_work()
	var province: int = model.province_at(tile.x, tile.y)
	var place: String = model.province_name(province) if province >= 0 else "the wilds"
	return {
		"ok": true,
		"message": "The Builder abandons the works in %s; the materials are lost." % place,
	}


static func working_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == BUILD and unit.work_tile() == tile:
			return unit
	return null


static func idle_builders(units: Array[CivilianState], owner: int) -> Array[CivilianState]:
	var result: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner and unit.type_id == "builder" and unit.is_idle():
			result.append(unit)
	return result


## Closest idle Builder by Manhattan distance; ties break on unit id.
static func nearest_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in idle_builders(units, owner):
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best
