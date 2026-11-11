class_name ImprovementLedger
extends RefCounted
## Estates overview rows for the management ledger (wiki:
## extraction-and-improvements). Pure projection of owned tiles, works and
## civilians; the UI only renders this and emits intents (REQ-P3-03).

const STATUS_ORDER: Dictionary = {
	"building": 0,
	"producing": 1,
	"disconnected": 2,
	"unprospected": 3,
	"vacant": 4,
	"maxed": 5,
}


## One row per owned resource tile, grouped by province, plus kingdom totals.
static func snapshot(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	owner: int,
	capital_tile: Vector2i,
	tech_caps: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"estates": [] as Array[Dictionary],
		"groups": [] as Array[Dictionary],
		"totals": {},
		"counts": {
			"estates": 0,
			"improved": 0,
			"producing": 0,
			"building": 0,
			"vacant": 0,
			"disconnected": 0,
			"unprospected": 0,
			"maxed": 0,
			"builders": 0,
			"idle_builders": 0,
		},
	}
	if model == null or works == null:
		return result
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	)
	var connected: Dictionary = resolved.get("tiles", {}) as Dictionary
	var idle: Array[CivilianState] = ImprovementOrders.idle_builders(units, owner)
	var gaps: Dictionary = LandConnectivity.network_gaps(
		model, owner, resolved.get("network", {}) as Dictionary
	)
	var groups: Array[Dictionary] = result["groups"]
	var tiles_by_province: Dictionary = {}
	for tile: Vector2i in model.ownership.owned_tiles(model, owner):
		if not model.is_land(tile.x, tile.y):
			continue
		# A mineral stays hidden until this court prospects the tile
		# (DR-20261111-26): no estate row exists for a deposit we have not seen.
		if not MineralSurvey.is_known(model, works, owner, tile):
			continue
		var province_id: int = model.province_at(tile.x, tile.y)
		if province_id == MapModel.NO_ID:
			continue
		if not tiles_by_province.has(province_id):
			tiles_by_province[province_id] = [] as Array[Vector2i]
		var province_tiles: Array[Vector2i] = tiles_by_province[province_id]
		province_tiles.append(tile)
	for province: ProvinceState in model.provinces:
		if not tiles_by_province.has(province.id):
			continue
		var province_id: int = province.id
		var rows: Array[Dictionary] = []
		for tile: Vector2i in tiles_by_province[province_id]:
			var resource: int = model.resource_at(tile.x, tile.y)
			var index: int = model.index_of(tile.x, tile.y)
			var entry: Dictionary = connected.get(index, {}) as Dictionary
			rows.append(_estate_row(
				model, works, units, stockpile, owner, tile, resource, province_id,
				entry, resolved, idle, tech_caps, gaps
			))
		if rows.is_empty():
			continue
		rows.sort_custom(_row_before)
		var group: Dictionary = {
			"id": province_id,
			"name": String(province.name),
			"rows": rows,
			"count": rows.size(),
			"producing": 0,
			"priority": int(STATUS_ORDER.get(String(rows[0]["status"]), 9)),
		}
		for row: Dictionary in rows:
			if int(row["output"]) > 0:
				group["producing"] = int(group["producing"]) + 1
		groups.append(group)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		return String(a["name"]) < String(b["name"])
	)
	var counts: Dictionary = result["counts"]
	counts["builders"] = idle.size() + _working_builders(units, owner)
	counts["idle_builders"] = idle.size()
	_summarise(result)
	return result


static func estate_row(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	owner: int,
	tile: Vector2i,
	capital_tile: Vector2i,
	tech_caps: Dictionary = {}
) -> Dictionary:
	if not MineralSurvey.is_known(model, works, owner, tile):
		return {}
	var resource: int = model.resource_at(tile.x, tile.y)
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	)
	var connected: Dictionary = resolved.get("tiles", {}) as Dictionary
	return _estate_row(
		model, works, units, stockpile, owner, tile, resource,
		model.province_at(tile.x, tile.y),
		connected.get(model.index_of(tile.x, tile.y), {}) as Dictionary,
		resolved,
		ImprovementOrders.idle_builders(units, owner),
		tech_caps,
		LandConnectivity.network_gaps(
			model, owner, resolved.get("network", {}) as Dictionary
		)
	)


# --- rows -------------------------------------------------------------------


static func _estate_row(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	owner: int,
	tile: Vector2i,
	resource: int,
	province: int,
	entry: Dictionary,
	resolved: Dictionary,
	idle: Array[CivilianState],
	tech_caps: Dictionary,
	gaps: Dictionary = {}
) -> Dictionary:
	var level: int = works.improvement_at(model, tile)
	var commodity: String = ImprovementCatalog.commodity(resource)
	var tech_cap: int = ImprovementCatalog.tech_cap_for(commodity, tech_caps)
	var terrain_cap: int = TerrainCaps.hard_cap(model.terrain_at(tile.x, tile.y), commodity)
	var mineral: bool = ImprovementCatalog.needs_prospecting(resource)
	var prospected: bool = works.is_prospected(owner, model, tile)
	var working: CivilianState = _working_unit(units, owner, tile)
	var is_connected: bool = not entry.is_empty()
	var gap: int = 0
	if not is_connected:
		gap = LandConnectivity.road_gap(
			model, owner, resolved.get("network", {}) as Dictionary, tile
		)
	var transport: int = int(entry.get("transport", 0))
	var town_cap: int = LandConnectivity.town_cap_for(
		model, resolved, province, model.index_of(tile.x, tile.y)
	)
	var output: int = 0
	if level > 0 and is_connected and (not mineral or prospected):
		output = Extraction.effective_yield(
			level, mini(tech_cap, terrain_cap), transport, town_cap
		)
	var next_level: int = mini(level + 1, ImprovementCatalog.MAX_LEVEL)
	var cost: Dictionary = CivilianWork.cost_for("build_improvement", next_level)
	var builder: CivilianState = _nearest(idle, tile)
	var status: String = _status(level, is_connected, working)
	var status_text: String = _status_text(
		status, resource, level, output, tech_cap, terrain_cap, transport,
		town_cap, working, is_connected
	)
	# How much road the crown still needs (wiki: capital-and-connectivity).
	if gap > 0:
		status_text += " · %d tile%s to the crown network" % [
			gap, "" if gap == 1 else "s"
		]
	return {
		"tile": tile,
		"index": model.index_of(tile.x, tile.y),
		"province": province,
		"province_name": model.province_name(province),
		"resource": resource,
		"name": ImprovementCatalog.display_name(resource, level),
		"base_name": ImprovementCatalog.base_name(resource),
		"level": level,
		"max_level": ImprovementCatalog.MAX_LEVEL,
		"tech_cap": tech_cap,
		"terrain_cap": terrain_cap,
		"transport": transport,
		"town_cap": town_cap,
		"tech_limited": next_level > tech_cap and level < ImprovementCatalog.MAX_LEVEL,
		"terrain_limited": (
			next_level > terrain_cap and level < ImprovementCatalog.MAX_LEVEL
		),
		"commodity": commodity,
		"output": output,
		"output_text": ImprovementCatalog.output_text(resource, output),
		"connected": is_connected,
		"prospected": prospected,
		"needs_prospecting": mineral,
		"working": working != null,
		"working_id": working.id if working != null else -1,
		"remaining": working.remaining_turns() if working != null else 0,
		"total_turns": working.total_turns() if working != null else 0,
		"builder_id": builder.id if builder != null else -1,
		"builder_name": builder.display_name() if builder != null else "",
		"status": status,
		"status_text": status_text,
		"link_distance": gap,
		"next_level": next_level,
		"cost": cost,
		"cost_text": CivilianWork.cost_text(cost),
		"duration": next_level,
		"can_build": _can_build(
			level, tech_cap, terrain_cap, mineral, prospected, working, builder,
			cost, stockpile
		),
		"build_reason": _build_reason(
			level, tech_cap, terrain_cap, mineral, prospected, working, builder,
			cost, stockpile
		),
	}


static func _status(
	level: int, is_connected: bool, working: CivilianState
) -> String:
	if working != null:
		return "building"
	if level <= 0:
		return "vacant"
	if not is_connected:
		return "disconnected"
	if level >= ImprovementCatalog.MAX_LEVEL:
		return "maxed"
	return "producing"


static func _status_text(
	status: String, resource: int, level: int, output: int, tech_cap: int,
	terrain_cap: int, transport: int, town_cap: int, working: CivilianState,
	is_connected: bool
) -> String:
	match status:
		"building":
			var left: int = working.remaining_turns() if working != null else 0
			return "Builder at work · %d turn%s left" % [left, "" if left == 1 else "s"]
		"vacant":
			var vacant: String = (
				"Vacant — a Builder can raise a %s" % ImprovementCatalog.base_name(resource)
			)
			if not is_connected:
				vacant += " · no road to the crown yet"
			return vacant
		"unprospected":
			return "Prospect this tile before a %s can rise" % ImprovementCatalog.base_name(resource)
		"disconnected":
			return "No road or port to the crown — no yield yet"
		"maxed":
			return "Fully improved · %s" % ImprovementCatalog.output_text(resource, output)
	var text: String = "Yields %s" % ImprovementCatalog.output_text(resource, output)
	if level > output and output > 0:
		if output == transport:
			text += " · transport cap %d" % transport
		elif terrain_cap < tech_cap:
			text += " · terrain cap %d" % terrain_cap
		elif output == tech_cap:
			text += " · tech cap %d" % tech_cap
		else:
			text += " · town cap %d" % town_cap
	return text


static func _can_build(
	level: int, tech_cap: int, terrain_cap: int, mineral: bool, prospected: bool,
	working: CivilianState, builder: CivilianState, cost: Dictionary,
	stockpile: Dictionary
) -> bool:
	return (
		level < ImprovementCatalog.MAX_LEVEL
		and level + 1 <= tech_cap
		and level + 1 <= terrain_cap
		and (not mineral or prospected)
		and working == null
		and builder != null
		and ImprovementSystem.short_inputs(cost, stockpile).is_empty()
	)


static func _build_reason(
	level: int, tech_cap: int, terrain_cap: int, mineral: bool, prospected: bool,
	working: CivilianState, builder: CivilianState, cost: Dictionary,
	stockpile: Dictionary
) -> String:
	if working != null:
		return "A Builder is already at work here."
	if level >= ImprovementCatalog.MAX_LEVEL:
		return "This estate is fully improved."
	if level + 1 > terrain_cap:
		return "This terrain hard-caps the estate at level %d." % terrain_cap
	if mineral and not prospected:
		return "An Explorer must prospect the tile first."
	if level + 1 > tech_cap:
		return "Requires extraction tech (cap %d) to raise this estate." % tech_cap
	if builder == null:
		return "No idle Builder — train one at the capital."
	var short: Dictionary = ImprovementSystem.short_inputs(cost, stockpile)
	if not short.is_empty():
		return "Stores are short of %s." % CivilianWork.cost_text(short)
	return ""


static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = int(STATUS_ORDER.get(String(a["status"]), 9))
	var sb: int = int(STATUS_ORDER.get(String(b["status"]), 9))
	if sa != sb:
		return sa < sb
	if String(a["base_name"]) != String(b["base_name"]):
		return String(a["base_name"]) < String(b["base_name"])
	var ta: Vector2i = a["tile"]
	var tb: Vector2i = b["tile"]
	return ta.y < tb.y or (ta.y == tb.y and ta.x < tb.x)


static func _summarise(result: Dictionary) -> void:
	var counts: Dictionary = result["counts"]
	var totals: Dictionary = result["totals"]
	var estates: Array[Dictionary] = result["estates"]
	var groups: Array[Dictionary] = result["groups"]
	for group: Dictionary in groups:
		for row: Dictionary in group["rows"]:
			estates.append(row)
			counts["estates"] = int(counts["estates"]) + 1
			if int(row["level"]) > 0:
				counts["improved"] = int(counts["improved"]) + 1
			if int(row["output"]) > 0:
				counts["producing"] = int(counts["producing"]) + 1
				var id: String = String(row["commodity"])
				totals[id] = int(totals.get(id, 0)) + int(row["output"])
			if bool(row["working"]):
				counts["building"] = int(counts["building"]) + 1
			if String(row["status"]) == "vacant":
				counts["vacant"] = int(counts["vacant"]) + 1
			if String(row["status"]) == "disconnected":
				counts["disconnected"] = int(counts["disconnected"]) + 1
			if String(row["status"]) == "unprospected":
				counts["unprospected"] = int(counts["unprospected"]) + 1
			if int(row["level"]) >= ImprovementCatalog.MAX_LEVEL:
				counts["maxed"] = int(counts["maxed"]) + 1


# --- helpers ----------------------------------------------------------------


static func _working_unit(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner or not unit.is_working():
			continue
		if unit.work_action() == "build_improvement" and unit.work_tile() == tile:
			return unit
	return null


static func _working_builders(units: Array[CivilianState], owner: int) -> int:
	var total: int = 0
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner and unit.type_id == "builder" and unit.is_working():
			total += 1
	return total


static func _nearest(units: Array[CivilianState], tile: Vector2i) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in units:
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best
