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
## idle Rail Builder can take the order, what the order spends and how long it
## waits, and why not when it cannot — so the press prints its own step rather
## than a hover (DR-20261125-08). `needed` is false for ground that is not the
## crown's, carries no road, already carries a railroad, or waits on a study, so
## the block prints only what can be pressed. `stockpile` is the crown's live
## purse when the caller knows it; null leaves the money gate to the order that
## charges it (REQ-P2-03).
static func plan(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	tile: Vector2i,
	tech_unlocked: Dictionary = {},
	stockpile: Variant = null
) -> Dictionary:
	var plan_out: Dictionary = {
		"needed": false, "rail_builder": false, "reason": "", "cost": {}, "turns": 0,
	}
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
	# The step the press prints: the Rail Builder's own price and wait for this
	# tile, read off the order that charges it (DR-20261125-08).
	plan_out["cost"] = CivilianWorkPlan.cost_for(RAIL)
	plan_out["turns"] = CivilianWorkPlan.duration_for(model, RAIL, tile, works)
	# The stores are the order's gate too, so a press never offers a step the
	# crown cannot pay (REQ-P2-03; DR-20261125-08). Rail Builders are exempt from
	# the per-tile exclusivity rule, so the crew gate is the only other one.
	var short: String = CivilianWorkRefusals.known_stores(plan_out["cost"], stockpile)
	if not bool(plan_out["rail_builder"]):
		plan_out["reason"] = "No idle Rail Builder musters — train one at the capital."
	elif not short.is_empty():
		plan_out["reason"] = short
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
	tech_unlocked: Dictionary = {},
	stockpile: Variant = null
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] as Array[Dictionary]
	if model == null or works == null or owner < 0:
		return rows
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return rows
	for tile: Vector2i in province.tiles:
		var plan_out: Dictionary = plan(
			model, works, units, owner, tile, tech_unlocked, stockpile
		)
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
	var plan_out: Dictionary = plan(
		model, works, units, owner, tile, tech_unlocked, stockpile
	)
	if not bool(plan_out["needed"]):
		return {"ok": false, "message": "This tile cannot take a railroad."}
	# The plan stays `needed` (the row still names its ground) and carries the
	# gate that shuts the press — a missing crew, or a purse that is short.
	if not String(plan_out["reason"]).is_empty():
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
	return CivilianWork.idle_crews(units, owner, RAIL_BUILDER)


## Closest idle Rail Builder by Manhattan distance; ties break on unit id, as
## the estates ledger's Builder dispatch does.
static func nearest_rail_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return CivilianWork.nearest_crew(units, owner, tile, RAIL_BUILDER)


static func _working_rail_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return CivilianWork.working_crew(units, owner, tile, RAIL_BUILDER, RAIL)


## The estate the tile carries, in the catalog's own words; empty for a bare
## road tile, which the block prints as plain ground.
static func _estate_name(model: MapModel, works: LandWorks, tile: Vector2i) -> String:
	var level: int = works.improvement_at(model, tile)
	if level <= 0:
		return ""
	return ImprovementCatalog.display_name(model.resource_at(tile.x, tile.y), level)
