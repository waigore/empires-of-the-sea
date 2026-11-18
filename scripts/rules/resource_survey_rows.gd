class_name ResourceSurveyRows
extends RefCounted
## Per-tile estate rows for the resource survey (wiki: extraction-and-
## improvements). Pure projection: status, yield and working-crew facts for one
## charted resource tile, so [ResourceSurvey] only aggregates provinces and
## realm totals (REQ-P3-01, REQ-P3-03).
##
## Ours carry the same status vocabulary as the estates ledger; foreign rows
## still say whether the tile is worked, so the player can read rival
## exploitation at a glance without pretending to know its yield.

const STATUS_ORDER: Dictionary = {
	"building": 0,
	"vacant": 1,
	"unprospected": 2,
	"disconnected": 3,
	"foreign": 4,
	"producing": 5,
	"maxed": 6,
	"foreign_building": 7,
	"foreign_worked": 8,
}


## Every charted resource tile in one province, in reading order. `sealed` is
## the province's own harbour held by a hostile squadron, so its estates read the
## cut the phase pays (wiki: capital-and-connectivity § Blockade).
static func for_province(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	resolved: Dictionary,
	province: ProvinceState,
	visibility: VisibilityModel,
	tech_caps: Dictionary,
	sealed: bool = false
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [] as Array[Dictionary]
	for tile: Vector2i in province.tiles:
		# A mineral is hidden until this court prospects it (DR-20261111-26):
		# the survey never names a deposit the crown has not uncovered.
		var resource: int = MineralSurvey.known_resource(
			model, works, owner, tile, visibility
		)
		if resource < 0:
			continue
		rows.append(
			one(model, works, units, owner, resolved, tile, resource, tech_caps, sealed)
		)
	rows.sort_custom(_before)
	return rows


static func one(
	model: MapModel,
	works: LandWorks,
	units: Array[CivilianState],
	owner: int,
	resolved: Dictionary,
	tile: Vector2i,
	resource: int,
	tech_caps: Dictionary,
	sealed: bool = false
) -> Dictionary:
	var tile_owner: int = model.owner_at(tile.x, tile.y)
	var level: int = works.improvement_at(model, tile)
	var mineral: bool = ImprovementCatalog.needs_prospecting(resource)
	var ours: bool = tile_owner == owner
	var prospected: bool = ours and works.is_prospected(owner, model, tile)
	var index: int = model.index_of(tile.x, tile.y)
	var province_id: int = model.province_at(tile.x, tile.y)
	var connection: Dictionary = (resolved.get("tiles", {}) as Dictionary).get(index, {})
	var is_connected: bool = not connection.is_empty()
	var working: CivilianState = _working_unit(units, tile)
	var status: String = status_for(ours, level, is_connected, working)
	# A sealed coast is not a missing road: the row names the rule that cut it
	# rather than the road the crown would still have to lay (REQ-P2-03).
	var blockaded: bool = ours and sealed and not is_connected
	var output: int = 0
	if status == "producing" or status == "maxed":
		# The same arithmetic Extraction runs, so the lens never prices an estate
		# at a yield the phase would not pay: the path's transport cap (not the
		# tile's own road), the town cap only where the Town rule is the whole
		# link, and the terrain hard cap after the tech cap (wiki:
		# extraction-and-improvements § Extraction formula and town development
		# cap, § Terrain extraction hard caps). A Great Power's ration estates
		# pay double per level, so the lens prints what the phase pays (issue
		# #807).
		var commodity: String = ImprovementCatalog.commodity(resource)
		var cap: int = TerrainCaps.extraction_cap(
			model.terrain_at(tile.x, tile.y), commodity,
			ImprovementCatalog.tech_cap_for(commodity, tech_caps)
		)
		output = Extraction.effective_yield(
			level, cap, int(connection.get("transport", 0)),
			LandTownRule.town_cap_for(model, resolved, province_id, index)
		) * Extraction.estate_yield_per_level(tile_owner, commodity)
	var remaining: int = working.remaining_turns() if working != null else 0
	var total_turns: int = working.total_turns() if working != null else 0
	return {
		"tile": tile,
		"index": model.index_of(tile.x, tile.y),
		"resource": resource,
		"commodity": ImprovementCatalog.commodity(resource),
		"base_name": ImprovementCatalog.base_name(resource),
		"icon": ImprovementCatalog.icon_kind(resource),
		"level": level,
		"max_level": ImprovementCatalog.MAX_LEVEL,
		"output": output,
		"status": status,
		"tile_owner": tile_owner,
		"ours": ours,
		"prospected": prospected,
		"needs_prospecting": mineral,
		"connected": is_connected,
		"blockaded": blockaded,
		"working": working != null,
		"remaining": remaining,
		"total_turns": total_turns,
	}


static func status_for(
	ours: bool,
	level: int,
	is_connected: bool,
	working: CivilianState
) -> String:
	if not ours:
		if working != null:
			return "foreign_building"
		return "foreign_worked" if level > 0 else "foreign"
	if working != null:
		return "building"
	if level <= 0:
		return "vacant"
	if not is_connected:
		return "disconnected"
	if level >= ImprovementCatalog.MAX_LEVEL:
		return "maxed"
	return "producing"


static func _working_unit(
	units: Array[CivilianState], tile: Vector2i
) -> CivilianState:
	for unit: CivilianState in units:
		if unit == null or not unit.is_working():
			continue
		if unit.work_action() == "build_improvement" and unit.work_tile() == tile:
			return unit
	return null


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = int(STATUS_ORDER.get(String(a["status"]), 9))
	var sb: int = int(STATUS_ORDER.get(String(b["status"]), 9))
	if sa != sb:
		return sa < sb
	if String(a["commodity"]) != String(b["commodity"]):
		return String(a["commodity"]) < String(b["commodity"])
	var ta: Vector2i = a["tile"]
	var tb: Vector2i = b["tile"]
	return ta.y < tb.y or (ta.y == tb.y and ta.x < tb.x)
