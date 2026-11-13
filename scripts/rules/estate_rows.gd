## One estate's ledger row (wiki: extraction-and-improvements): its level, caps,
## yield, the Builder's picture and the crown's Build gate. [ImprovementLedger]
## groups these rows by province and totals them (REQ-P3-01, REQ-P3-03).
class_name EstateRows
extends RefCounted

const STATUS_ORDER: Dictionary = {
	"building": 0,
	"producing": 1,
	"disconnected": 2,
	"unprospected": 3,
	"vacant": 4,
	"maxed": 5,
}
## A known mineral nobody has surveyed: the row names the Explorer's work to do.
const UNPROSPECTED: String = "unprospected"


## Where a row's status sits in the ledger's grouping; unknown reads last.
static func priority(status: String) -> int:
	return int(STATUS_ORDER.get(status, 9))


## Reads one tile into a row. `entry` is the tile's record from
## [LandConnectivity]; `resolved` is the crown's network and `gaps` its road gaps
## (omit `gaps` when reading one tile, so no gap is attached).
static func project(
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
	var status: String = status_for(level, is_connected, working, mineral, prospected)
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


## A Builder at work outranks level; a surveyed mineral is vacant, an unseen
## deposit unprospected; a full estate maxed.
static func status_for(
	level: int, is_connected: bool, working: CivilianState, mineral: bool,
	prospected: bool
) -> String:
	if working != null:
		return "building"
	if level <= 0:
		return UNPROSPECTED if mineral and not prospected else "vacant"
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
		UNPROSPECTED:
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


static func _working_unit(
	units: Array[CivilianState], owner: int, tile: Vector2i
) -> CivilianState:
	return ImprovementOrders.working_builder(units, owner, tile)


static func _nearest(units: Array[CivilianState], tile: Vector2i) -> CivilianState:
	var best: CivilianState = null
	var best_distance: int = 1 << 30
	for unit: CivilianState in units:
		var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
		if distance < best_distance or (distance == best_distance and unit.id < best.id):
			best = unit
			best_distance = distance
	return best
