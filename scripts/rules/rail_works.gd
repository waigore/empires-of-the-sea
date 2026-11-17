class_name RailWorks
extends RefCounted
## The crown's rail works (wiki: civilian-units § Rail Builder work;
## extraction-and-improvements § Road / Railroad Costs): which of the crown's
## road tiles can still go rail, and the Rail Builder dispatch that lays it.
## Pure rules — the province dossier reads `plan` and emits the intent,
## CivilianWork gates and charges the order (REQ-P2-03, REQ-P3-03).
##
## A railroad upgrades an existing road to transport 4, so only a tile that
## already carries a road and whose terrain tech the crown has studied is
## offered. The gate is [method CivilianTransport.check]'s own, read here so the
## dossier can never offer a press the crew's sheet would refuse (REQ-P3-02).

const RAIL_BUILDER: String = "rail_builder"
const RAIL: String = "build_rail"


## What the dossier reads for one tile: whether it can still go rail, whether an
## idle Rail Builder can take the order, and why not when it cannot. `needed`
## is false for ground that is not the crown's, carries no road, already carries
## a railroad, or waits on a study — the block prints only what can be pressed.
static func plan(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	tile: Vector2i,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var plan_out: Dictionary = {"needed": false, "rail_builder": false, "reason": ""}
	if model == null or works == null or owner < 0 or tile.x < 0:
		return plan_out
	if model.owner_at(tile.x, tile.y) != owner:
		return plan_out
	var level: int = works.transport_at(model, tile)
	if level < LandWorks.TRANSPORT_ROAD or level >= LandWorks.TRANSPORT_RAIL:
		return plan_out
	var needed: String = CivilianTransport.rail_tech_for(model.terrain_at(tile.x, tile.y))
	if not bool(tech_unlocked.get(needed, false)):
		return plan_out
	# A crew already on the tile has the order in hand: a second press would only
	# spend a second Rail Builder's materials on the same ground.
	if _working_rail_builder(units, owner, tile) != null:
		return plan_out
	plan_out["needed"] = true
	plan_out["rail_builder"] = not idle_rail_builders(units, owner).is_empty()
	if not bool(plan_out["rail_builder"]):
		plan_out["reason"] = "No idle Rail Builder musters — train one at the capital."
	return plan_out


## Every road tile of one province that can still go rail, in tile order, each
## with the plan the block prints. One read for the whole dossier, so a province
## of twenty road tiles costs one pass (REQ-P4-01).
static func province_plans(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	province_id: int,
	tech_unlocked: Dictionary = {}
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] as Array[Dictionary]
	if model == null or works == null or owner < 0:
		return rows
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return rows
	for tile: Vector2i in province.tiles:
		var plan_out: Dictionary = plan(model, works, units, owner, tile, tech_unlocked)
		if not bool(plan_out["needed"]):
			continue
		rows.append({
			"tile": tile,
			"transport": works.transport_at(model, tile),
			"estate": _estate_name(model, works, tile),
			"plan": plan_out,
		})
	return rows


## Dispatch the nearest idle Rail Builder onto the tile. Returns {ok, message}.
## Every gate and cost stays in CivilianWork.
static func dispatch(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	tile: Vector2i,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var plan_out: Dictionary = plan(model, works, units, owner, tile, tech_unlocked)
	if not bool(plan_out["needed"]):
		return {"ok": false, "message": "This tile cannot take a railroad."}
	if not bool(plan_out["rail_builder"]):
		return {"ok": false, "message": String(plan_out["reason"])}
	var crew: CivilianState = nearest_rail_builder(units, owner, tile)
	var result: Dictionary = CivilianWork.assign(
		model, crew, RAIL, works, units, stockpile, visibility, tile, {},
		tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	return {
		"ok": true,
		"message": "%s lays a railroad at (%d, %d)." % [
			crew.display_name(), tile.x, tile.y
		],
	}


static func idle_rail_builders(
	units: Array[CivilianState], owner: int
) -> Array[CivilianState]:
	var result: Array[CivilianState] = [] as Array[CivilianState]
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner and unit.type_id == RAIL_BUILDER and unit.is_idle():
			result.append(unit)
	return result


## Closest idle Rail Builder by Manhattan distance; ties break on unit id, as
## the estates ledger's Builder dispatch does.
static func nearest_rail_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in idle_rail_builders(units, owner):
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best


static func _working_rail_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or unit.type_id != RAIL_BUILDER:
			continue
		if unit.is_working() and unit.work_tile() == tile:
			return unit
	return null


## The estate the tile carries, in the catalog's own words; empty for a bare
## road tile, which the block prints as plain ground.
static func _estate_name(model: MapModel, works: LandWorks, tile: Vector2i) -> String:
	var level: int = works.improvement_at(model, tile)
	if level <= 0:
		return ""
	return ImprovementCatalog.display_name(model.resource_at(tile.x, tile.y), level)
