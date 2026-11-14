## Estates overview for the management ledger (wiki:
## extraction-and-improvements): groups [EstateRows] rows by province and
## totals the kingdom's yield. Pure projection of owned tiles, works and
## civilians; the UI only renders this and emits intents (REQ-P3-03).
class_name ImprovementLedger
extends RefCounted


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
	var tiles_by_province: Dictionary = _tiles_by_province(model, works, owner)
	var groups: Array[Dictionary] = result["groups"]
	for province: ProvinceState in model.provinces:
		var tiles: Array[Vector2i] = tiles_by_province.get(
			province.id, [] as Array[Vector2i]
		)
		if tiles.is_empty():
			continue
		var rows: Array[Dictionary] = []
		for tile: Vector2i in tiles:
			rows.append(EstateRows.project(
				model, works, units, stockpile, owner, tile,
				model.resource_at(tile.x, tile.y), province.id,
				connected.get(model.index_of(tile.x, tile.y), {}) as Dictionary,
				resolved, idle, tech_caps, gaps
			))
		rows.sort_custom(_row_before)
		groups.append(_group(province, rows))
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


## One tile's row, read against the crown's whole network so its road gap and
## Build gate are the same numbers the grouped snapshot prints.
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
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	)
	var connected: Dictionary = resolved.get("tiles", {}) as Dictionary
	return EstateRows.project(
		model, works, units, stockpile, owner, tile,
		model.resource_at(tile.x, tile.y), model.province_at(tile.x, tile.y),
		connected.get(model.index_of(tile.x, tile.y), {}) as Dictionary,
		resolved, ImprovementOrders.idle_builders(units, owner), tech_caps,
		LandConnectivity.network_gaps(
			model, owner, resolved.get("network", {}) as Dictionary
		)
	)


# --- grouping ---------------------------------------------------------------


## Every estate tile the court knows of, by province. A mineral stays hidden
## until this court prospects the tile (DR-20261111-26): no deposit we have not
## seen, no row.
static func _tiles_by_province(
	model: MapModel, works: LandWorks, owner: int
) -> Dictionary:
	var tiles_by_province: Dictionary = {}
	for tile: Vector2i in model.ownership.owned_tiles(model, owner):
		if not model.is_land(tile.x, tile.y):
			continue
		if not MineralSurvey.is_known(model, works, owner, tile):
			continue
		var province_id: int = model.province_at(tile.x, tile.y)
		if province_id == MapModel.NO_ID:
			continue
		if not tiles_by_province.has(province_id):
			tiles_by_province[province_id] = [] as Array[Vector2i]
		var province_tiles: Array[Vector2i] = tiles_by_province[province_id]
		province_tiles.append(tile)
	return tiles_by_province


static func _group(province: ProvinceState, rows: Array[Dictionary]) -> Dictionary:
	var producing: int = 0
	for row: Dictionary in rows:
		if int(row["output"]) > 0:
			producing += 1
	return {
		"id": province.id,
		"name": String(province.name),
		"rows": rows,
		"count": rows.size(),
		"producing": producing,
		"priority": EstateRows.priority(String(rows[0]["status"])),
	}


static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = EstateRows.priority(String(a["status"]))
	var sb: int = EstateRows.priority(String(b["status"]))
	if sa != sb:
		return sa < sb
	if String(a["base_name"]) != String(b["base_name"]):
		return String(a["base_name"]) < String(b["base_name"])
	var ta: Vector2i = a["tile"]
	var tb: Vector2i = b["tile"]
	return ta.y < tb.y or (ta.y == tb.y and ta.x < tb.x)


## Rolls the grouped rows into the flat estate list and the counts/totals. Only
## the status counter is keyed off the row's own status, so `producing` counts
## once (from its yield) and each other status counts where its key names it.
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
			var status: String = String(row["status"])
			if status != "producing" and counts.has(status):
				counts[status] = int(counts[status]) + 1


# --- helpers ----------------------------------------------------------------


static func _working_builders(units: Array[CivilianState], owner: int) -> int:
	var total: int = 0
	for unit: CivilianState in units:
		if unit != null and unit.owner == owner and unit.type_id == "builder" and unit.is_working():
			total += 1
	return total
