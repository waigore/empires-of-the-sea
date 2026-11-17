class_name ResourceSurvey
extends RefCounted
## Per-province read of the resource estates on the map, for the survey lens
## (wiki: extraction-and-improvements). Pure projection over province tiles,
## `LandWorks` and civilians: the lens only draws this and emits no rules
## (REQ-P3-03).
##
## Estate row status and yield live in [ResourceSurveyRows]; this module owns
## province aggregation and realm totals so each seam stays under the soft size
## bar (REQ-P3-01).

const BLOCKED_STATUSES: Array[String] = ["disconnected"]


## One entry per charted province that holds at least one resource tile we can
## see, plus realm totals. `visibility` may be null for isolated fixtures.
## `blockade` is the court's own sealed coasts: a blockaded port province is no
## landfall, so its estates reach the crown by road only and read as cut, the
## same harvest the Extraction phase withholds (wiki: capital-and-connectivity
## § Blockade). Omitted, the reading is the unsealed chart.
static func snapshot(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	visibility: VisibilityModel = null,
	capital_tile: Vector2i = CivilianState.NO_TILE,
	tech_caps: Dictionary = {},
	blockade: Blockades = null
) -> Dictionary:
	var result: Dictionary = {
		"provinces": [] as Array[Dictionary],
		"counts": _empty_counts(),
		"totals": {},
	}
	if model == null or works == null:
		return result
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile, blockade
	)
	for province: ProvinceState in model.provinces:
		var rows: Array[Dictionary] = ResourceSurveyRows.for_province(
			model, works, units, owner, resolved, province, visibility, tech_caps,
			blockade != null and blockade.cuts(model.region_id, province.id)
		)
		if rows.is_empty():
			continue
		var tile_owners: Dictionary = {}
		for row: Dictionary in rows:
			tile_owners[int(row["tile_owner"])] = true
		var entry: Dictionary = _province_entry(
			model, province, rows, tile_owners, visibility
		)
		# Ground still to survey: the lens marks it so a court knows where to dig
		# (wiki: fog-and-exploration § Prospecting; DR-20261111-26).
		entry["unsurveyed"] = MineralSurvey.unsurveyed_in_province(
			model, works, owner, province.id, visibility
		).size()
		# One row per resource type: the plate reads a province by the kinds it
		# holds, not by its first three tiles (issue #698).
		entry["types"] = ResourceTypes.rows(entry)
		entry["summary"] = summary_text(entry)
		result["provinces"].append(entry)
		_summarise(result, entry)
	return result


## One province's resource rows, in the same vocabulary the survey lens and the
## estates ledger use. The province dossier reads this so it can name every
## estate a province holds, not just the province's headline resource. `blockade`
## reads the crown's sealed coasts, so a sealed harbour's estates are cut here
## exactly as the phase cuts them.
static func province_rows(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	province_id: int,
	visibility: VisibilityModel = null,
	capital_tile: Vector2i = CivilianState.NO_TILE,
	tech_caps: Dictionary = {},
	blockade: Blockades = null
) -> Array[Dictionary]:
	if model == null or works == null:
		return [] as Array[Dictionary]
	var province: ProvinceState = model.province_data(province_id)
	if province == null:
		return [] as Array[Dictionary]
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile, blockade
	)
	return ResourceSurveyRows.for_province(
		model, works, units, owner, resolved, province, visibility, tech_caps,
		blockade != null and blockade.cuts(model.region_id, province_id)
	)


## Short line for the hover tooltip while the lens is on: every type with its
## badge, then the ground still to read.
static func summary_text(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var types: Array = entry.get("types", [] as Array)
	if types.is_empty():
		types = ResourceTypes.rows(entry)
	var parts: PackedStringArray = PackedStringArray()
	for raw: Variant in types:
		var type_row: Dictionary = raw
		parts.append("%s %s" % [String(type_row["name"]), String(type_row["badge"])])
	var unsurveyed: int = int(entry.get("unsurveyed", 0))
	if unsurveyed > 0:
		parts.append("%d unsurveyed" % unsurveyed)
	if parts.is_empty():
		return ""
	return " · ".join(parts)


static func _province_entry(
	model: MapModel,
	province: ProvinceState,
	rows: Array[Dictionary],
	tile_owners: Dictionary,
	visibility: VisibilityModel
) -> Dictionary:
	var counts: Dictionary = {
		"estates": rows.size(),
		"worked": 0,
		"developed": 0,
		"linked": 0,
		"producing": 0,
		"building": 0,
		"vacant": 0,
		"blocked": 0,
		"foreign": 0,
	}
	var output: Dictionary = {}
	for row: Dictionary in rows:
		var status: String = String(row["status"])
		if int(row["level"]) > 0:
			counts["worked"] = int(counts["worked"]) + 1
		# Developed and linked are the crown's own facts: a foreign estate is
		# never "linked to our capital", however worked it looks.
		if bool(row["ours"]) and int(row["level"]) > 0:
			counts["developed"] = int(counts["developed"]) + 1
			if bool(row["connected"]):
				counts["linked"] = int(counts["linked"]) + 1
		if status == "producing" or status == "maxed":
			counts["producing"] = int(counts["producing"]) + 1
			var commodity: String = String(row["commodity"])
			if int(row["output"]) > 0 and not commodity.is_empty():
				output[commodity] = int(output.get(commodity, 0)) + int(row["output"])
		elif status == "building" or status == "foreign_building":
			counts["building"] = int(counts["building"]) + 1
		elif status == "vacant":
			counts["vacant"] = int(counts["vacant"]) + 1
		elif BLOCKED_STATUSES.has(status):
			counts["blocked"] = int(counts["blocked"]) + 1
		elif status == "foreign":
			counts["foreign"] = int(counts["foreign"]) + 1
	var charted: int = VisibilityModel.Level.FULLY_VISIBLE
	if visibility != null:
		charted = visibility.province_visibility(province.id)
	return {
		"id": province.id,
		"name": province.name,
		"center": province.center,
		"anchor": _anchor_tile(model, province, rows, visibility),
		"owner": province.owner,
		"capital": province.capital,
		"charted": charted,
		"rows": rows,
		"counts": counts,
		"output": output,
		"output_text": ImprovementSystem.output_text(output),
		"tile_owners": tile_owners.keys(),
	}


static func _empty_counts() -> Dictionary:
	return {
		"provinces": 0,
		"estates": 0,
		"worked": 0,
		"developed": 0,
		"linked": 0,
		"producing": 0,
		"building": 0,
		"vacant": 0,
		"blocked": 0,
		"foreign": 0,
	}


static func _summarise(result: Dictionary, entry: Dictionary) -> void:
	var counts: Dictionary = result["counts"]
	counts["provinces"] = int(counts["provinces"]) + 1
	for key: String in [
		"estates", "worked", "developed", "linked", "producing", "building",
		"vacant", "blocked", "foreign",
	]:
		counts[key] = int(counts[key]) + int(entry["counts"][key])
	var totals: Dictionary = result["totals"]
	for commodity: Variant in entry["output"].keys():
		var id: String = String(commodity)
		totals[id] = int(totals.get(id, 0)) + int(entry["output"][commodity])


## The plaque sits on charted land: the province centre when it is known, else
## the surveyed resource tile nearest that centre (so a slip never lands on
## unknown ground or in a bay).
static func _anchor_tile(
	model: MapModel,
	province: ProvinceState,
	rows: Array[Dictionary],
	visibility: VisibilityModel
) -> Vector2:
	var center: Vector2 = province.center
	var guess := Vector2i(roundi(center.x), roundi(center.y))
	var known: bool = model.is_land(guess.x, guess.y)
	if known and visibility != null:
		known = visibility.level_at(guess.x, guess.y) != VisibilityModel.Level.UNKNOWN
	if known:
		return Vector2(guess)
	var best: Vector2i = guess
	var best_distance: float = INF
	for row: Dictionary in rows:
		var tile: Vector2i = row["tile"]
		var distance: float = Vector2(tile).distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return Vector2(best)
