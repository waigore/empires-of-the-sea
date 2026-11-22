class_name ImprovementOrders
extends RefCounted
## Estates-ledger intents: dispatch the nearest Builder to an estate and cancel
## an active improvement order. All gates, costs and the crew pick stay in
## CivilianWork (REQ-P2-03); this module only chooses the action and words the
## report.

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
			MoneyText.plural(int(result.get("duration", 1))),
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


## Why the province dossier's wall press cannot run now, or "" when it can: the
## fort table's level, study and stores, and the nearest idle Engineer the press
## sends, in the order's own words (wiki: siege-mechanics § Fort Levels;
## DR-20261116-01; REQ-P2-03). A press that reads "" is the one that can be
## filed. Two projects in one province may run, so a second crew on the town
## tile never refuses a wall.
static func wall_refusal(
	model: MapModel,
	units: Array[CivilianState],
	owner: int,
	province_id: int,
	tech_unlocked: Dictionary = {},
	stockpile: Variant = null
) -> String:
	var province: ProvinceState = model.province_data(province_id) if model != null else null
	if province == null:
		return "This province has no wall to raise."
	var why: String = CivilianWorkRefusals.fort(
		province.fort_level, tech_unlocked, stockpile
	)
	if not why.is_empty():
		return why
	var site: Vector2i = FortRules.site_tile(model, province_id)
	if site.x < 0:
		return "This province has no town to raise a wall on."
	# The step in hand reads as taken: a wall the crown has already ordered waits
	# on its Engineer, not on a second press (wiki: siege-mechanics § Fort Levels;
	# the walls ledger's AT WORK state).
	if CivilianWork.working_crew(units, owner, site, "engineer", "build_fort") != null:
		return "An Engineer is already at work on this wall."
	# Two projects in one province may run (the later one cannot leap a level),
	# so a second crew on the town tile never refuses a wall.
	return _crew_refusal(units, owner, site, false)


## Why the province dossier's ward press cannot run now, or "" when it can: the
## ward table's level, study and stores, the nearest idle Engineer, and the town
## tile the ward rises on — one crew builds it, so a crew already at work there
## refuses the order in the work order's own sentence (wiki: combat
## § Regiment condition; DR-20261116-02; civilian-units § Per-player tile
## exclusivity).
static func ward_refusal(
	model: MapModel,
	units: Array[CivilianState],
	owner: int,
	province_id: int,
	tech_unlocked: Dictionary = {},
	stockpile: Variant = null
) -> String:
	var province: ProvinceState = model.province_data(province_id) if model != null else null
	if province == null:
		return "This province has no ward to raise."
	var why: String = CivilianWorkRefusals.hospital(
		province.hospital_level, tech_unlocked, stockpile
	)
	if not why.is_empty():
		return why
	var site: Vector2i = HospitalRules.site_tile(model, province_id)
	if site.x < 0:
		return "This province has no town to raise a ward on."
	return _crew_refusal(units, owner, site, true)


## The crew the press sends: the nearest idle Engineer, else the order's own
## sentence, and — for a ward, which one crew builds on the town tile — the
## tile-exclusivity verdict when another crew already works the site.
static func _crew_refusal(
	units: Array[CivilianState], owner: int, site: Vector2i, one_crew: bool
) -> String:
	var engineer: CivilianState = nearest_engineer(units, owner, site)
	if engineer == null:
		return "No idle Engineer musters — train one at the capital."
	if not one_crew:
		return ""
	var exclusive: Dictionary = CivilianTransport.exclusive(units, engineer, site)
	return "" if bool(exclusive.get("ok", false)) else String(exclusive.get("reason", ""))


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
			MoneyText.plural(turns),
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
			MoneyText.plural(turns),
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
	return CivilianWork.working_crew(units, owner, tile, "builder", BUILD)


static func idle_builders(units: Array[CivilianState], owner: int) -> Array[CivilianState]:
	return CivilianWork.idle_crews(units, owner, "builder")


## Closest idle Builder by Manhattan distance; ties break on unit id.
static func nearest_builder(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return CivilianWork.nearest_crew(units, owner, tile, "builder")


## Closest idle Engineer by Manhattan distance; ties break on unit id.
static func nearest_engineer(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return CivilianWork.nearest_crew(units, owner, tile, "engineer")
