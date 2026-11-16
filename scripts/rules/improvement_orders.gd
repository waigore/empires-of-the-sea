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
		"upgrade_town":
			return upgrade_town(
				model, units, works, stockpile, visibility, owner, tile, tech_unlocked
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


## Dispatch the nearest idle Builder to the province's town tile and start an
## upgrade_town order. All gates and costs stay in CivilianWork.
static func upgrade_town(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	tile: Vector2i,
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
		return {"ok": false, "message": "This province has no town to upgrade."}
	var town: Vector2i = province.town_site()
	if town.x < 0:
		return {"ok": false, "message": "This province has no town to upgrade."}
	if working_builder(units, owner, town) != null:
		return {"ok": false, "message": "A Builder is already at work on this town."}
	var builder: CivilianState = nearest_builder(units, owner, town)
	if builder == null:
		return {
			"ok": false,
			"message": "No idle Builder musters — train one at the capital.",
		}
	var result: Dictionary = CivilianWork.assign(
		model, builder, "upgrade_town", works, units, stockpile, visibility, town,
		{}, tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	return {
		"ok": true,
		"message": "%s raises the town of %s to level %d." % [
			builder.display_name(),
			model.province_name(province.id),
			CivilianWorkPlan.town_upgrade_level(model, town),
		],
	}


## Dispatch the nearest idle Engineer to the province's wall and start a
## build_fort order. The site, the price, the wait and every gate stay in
## `FortRules`/`CivilianWork`; this only chooses the crew and words the report,
## so the walls ledger's Raise press is the Engineer's own order
## (REQ-P2-03; DR-20261116-01).
static func build_fort(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	province_id: int,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return {"ok": false, "message": "This province has no wall to raise."}
	if province.owner != owner:
		return {"ok": false, "message": "This province is not held by your crown."}
	# The wall rises on the province's town tile (wiki: siege-mechanics
	# § Fort Levels). A hand-built chart with neither a town nor a seat keeps the
	# old any-land rule, so the crew's own ground takes the order.
	var site: Vector2i = FortRules.site_tile(model, province_id)
	var target: Vector2i = site if site.x >= 0 else CivilianState.NO_TILE
	var engineer: CivilianState = nearest_engineer(units, owner, site)
	if engineer == null:
		return {
			"ok": false,
			"message": "No idle Engineer musters — train one at the capital.",
		}
	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_fort", works, units, stockpile, visibility, target,
		tech_caps, tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	var ordered: int = FortRules.next_level(FortRules.level_at(model, province_id))
	var turns: int = int(result.get("duration", FortRules.turns(ordered)))
	return {
		"ok": true,
		"message": "%s raises the wall of %s — %s, %d turn%s." % [
			engineer.display_name(),
			model.province_name(province_id),
			FortRules.describe(ordered),
			turns,
			"" if turns == 1 else "s",
		],
	}


## Dispatch the nearest idle Engineer to the province's ward and start a
## build_hospital order. The site, the price, the wait and every gate stay in
## `HospitalRules`/`CivilianWork`; this only chooses the crew and words the
## report, so the hospitals ledger's Raise press is the Engineer's own order
## (REQ-P2-03; DR-20261116-02).
static func build_hospital(
	model: MapModel,
	units: Array[CivilianState],
	works: LandWorks,
	stockpile: Dictionary,
	visibility: VisibilityModel,
	owner: int,
	province_id: int,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {}
) -> Dictionary:
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return {"ok": false, "message": "This province has no ward to raise."}
	if province.owner != owner:
		return {"ok": false, "message": "This province is not held by your crown."}
	# The ward rises on the province's town tile, like the wall (wiki: combat
	# § Regiment condition). A hand-built chart with neither a town nor a seat
	# keeps the old any-land rule, so the crew's own ground takes the order.
	var site: Vector2i = HospitalRules.site_tile(model, province_id)
	var target: Vector2i = site if site.x >= 0 else CivilianState.NO_TILE
	var engineer: CivilianState = nearest_engineer(units, owner, site)
	if engineer == null:
		return {
			"ok": false,
			"message": "No idle Engineer musters — train one at the capital.",
		}
	var result: Dictionary = CivilianWork.assign(
		model, engineer, "build_hospital", works, units, stockpile, visibility, target,
		tech_caps, tech_unlocked
	)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": String(result.get("reason", ""))}
	var ordered: int = HospitalRules.next_level(HospitalRules.level_at(model, province_id))
	var turns: int = int(result.get("duration", HospitalRules.turns(ordered)))
	return {
		"ok": true,
		"message": "%s raises the ward of %s — %s, %d turn%s." % [
			engineer.display_name(),
			model.province_name(province_id),
			HospitalRules.level_name(ordered).to_lower(),
			turns,
			"" if turns == 1 else "s",
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
	return idle_crews(units, owner, "builder")


## Every idle crew of one trade, so a sheet can ask who is free without owning
## the roster's type ids (the towns read a Builder, the walls an Engineer).
static func idle_crews(
	units: Array[CivilianState], owner: int, type_id: String
) -> Array[CivilianState]:
	var result: Array[CivilianState] = []
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner and unit.type_id == type_id and unit.is_idle():
			result.append(unit)
	return result


## Closest idle Builder by Manhattan distance; ties break on unit id.
static func nearest_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return nearest_crew(units, owner, tile, "builder")


## Closest idle Engineer by Manhattan distance; ties break on unit id.
static func nearest_engineer(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return nearest_crew(units, owner, tile, "engineer")


static func nearest_crew(
	units: Array[CivilianState], owner: int, tile: Vector2i, type_id: String
) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in idle_crews(units, owner, type_id):
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best
