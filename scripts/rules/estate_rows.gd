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
	gaps: Dictionary = {},
	blockaded: bool = false
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
		# The grouped ledger already walked the crown's network once for every
		# estate (`gaps`); a one-tile read passes none and walks it here. Reading
		# the shared walk keeps a full ledger from re-running the same BFS per
		# disconnected tile (docs/ai-observer.md § Performance budget).
		var index: int = model.index_of(tile.x, tile.y)
		gap = (
			int(gaps.get(index, -1))
			if not gaps.is_empty()
			else LandConnectivity.road_gap(
				model, owner, resolved.get("network", {}) as Dictionary, tile
			)
		)
	var transport: int = int(entry.get("transport", 0))
	var town_cap: int = LandTownRule.town_cap_for(
		model, resolved, province, model.index_of(tile.x, tile.y)
	)
	var output: int = 0
	if level > 0 and is_connected and (not mineral or prospected):
		# The phase's own arithmetic, ration estates doubled (issue #807).
		output = Extraction.effective_yield(
			level, mini(tech_cap, terrain_cap), transport, town_cap
		) * Extraction.estate_yield_per_level(owner, commodity)
	var next_level: int = mini(level + 1, ImprovementCatalog.MAX_LEVEL)
	# What one more level pays once the works stand: the phase's own formula read
	# at that level, so the crown prices a raise against the harvest it will
	# actually gather and never against a level the caps hold flat (REQ-P2-03,
	# REQ-P5-06). `capped_now` is the same read at today's level, which is the
	# base the next level is measured against even while a gate (no road, no
	# survey) is keeping the estate from paying at all.
	var capped_now: int = Extraction.effective_yield(
		level, mini(tech_cap, terrain_cap), transport, town_cap
	) * Extraction.estate_yield_per_level(owner, commodity)
	var next_output: int = capped_now
	if level < ImprovementCatalog.MAX_LEVEL:
		next_output = Extraction.effective_yield(
			next_level, mini(tech_cap, terrain_cap), transport, town_cap
		) * Extraction.estate_yield_per_level(owner, commodity)
	# The H8 feedstock bootstrap may waive a level-1 raise's inputs (wiki:
	# extraction-and-improvements § H8 feedstock bootstrap; #878). A maxed tile
	# shows the full table cost for its level.
	var cost: Dictionary = (
		CivilianWorkPlan.bootstrap_cost(model, tile, stockpile, next_level)
		if next_level > level
		else CivilianWork.cost_for("build_improvement", next_level)
	)
	var builder: CivilianState = _nearest(idle, tile)
	# The per-player tile exclusivity rule the Build order enforces, in the
	# order's own words: another crown crew already holds this tile — an
	# Engineer's road or harbour, a Merchant's deed — so the press would be
	# refused (wiki: civilian-units § Per-player tile exclusivity; REQ-P2-03).
	var busy: String = CivilianWorkRefusals.tile_busy(units, builder, tile)
	var status: String = status_for(level, is_connected, working, mineral, prospected)
	var status_text: String = _status_text(
		status, resource, level, output, tech_cap, terrain_cap, transport,
		town_cap, working, is_connected, blockaded
	)
	# How much road the crown still needs (wiki: capital-and-connectivity).
	if gap > 0:
		status_text += " · %d tile%s to the crown network" % [
			gap, "" if gap == 1 else "s"
		]
	var row: Dictionary = {
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
		"owner": owner,
		"output": output,
		"output_text": ImprovementCatalog.output_text(resource, output),
		"connected": is_connected,
		"blockaded": blockaded,
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
			cost, stockpile, busy
		),
		"build_reason": _build_reason(
			level, tech_cap, terrain_cap, mineral, prospected, working, builder,
			cost, stockpile, busy
		),
		"next_output": next_output,
		"gain": maxi(next_output - capped_now, 0),
	}
	# The preview is read off the finished row so one home answers both the
	# per-estate figure and the words the ledger prints for it.
	row["preview_text"] = preview_text(row)
	return row


## What one more level buys, in the ledger's own words. The figure is the
## phase's arithmetic at the next level (`gain`, `next_output`), so a crown is
## never told a raise pays when a cap holds the estate flat; the line names the
## cap instead, and names the gate a raise still waits on (REQ-P2-03, REQ-P5-06).
## Empty for a finished estate and while a Builder is on it: there is no raise to
## price.
static func preview_text(row: Dictionary) -> String:
	if bool(row.get("working", false)):
		return ""
	var level: int = int(row.get("level", 0))
	if level >= int(row.get("max_level", ImprovementCatalog.MAX_LEVEL)):
		return ""
	var next_level: int = int(row.get("next_level", level + 1))
	# Ground no road reaches gathers nothing at any level, so the raise is priced
	# by the wait rather than by a figure the harvest cannot pay. A deposit no
	# Explorer has read is the same wait, named after the level it would buy. A
	# sealed harbour is a wait the crown cannot road away, so it is named too.
	if not bool(row.get("connected", false)):
		if bool(row.get("blockaded", false)):
			return "Harbour blockaded — L%d pays nothing until the sea path opens" % (
				next_level
			)
		return "No road yet — L%d pays nothing until one reaches it" % next_level
	if int(row.get("gain", 0)) <= 0:
		return "L%d adds nothing — %s holds this estate" % [
			next_level, binding_cap(row)
		]
	var text: String = "L%d pays %s (+%d)" % [
		next_level,
		ImprovementCatalog.output_text(
			int(row.get("resource", -1)), int(row.get("next_output", 0))
		),
		int(row.get("gain", 0)),
	]
	if bool(row.get("needs_prospecting", false)) and not bool(row.get("prospected", false)):
		return text + " once an Explorer prospects it"
	return text


## The cap that stops the next level from paying more, in the row's own words:
## the tightest of the four the phase's formula reads (road transport, town,
## terrain, study). The estate's own output names the same four.
static func binding_cap(row: Dictionary) -> String:
	var limits: Array[Array] = [
		["the road's transport", int(row.get("transport", 0))],
		["the town", int(row.get("town_cap", 0))],
		["the terrain", int(row.get("terrain_cap", 0))],
		["the crown's study", int(row.get("tech_cap", 0))],
	]
	var cap: String = "the terrain"
	var lowest: int = 1 << 30
	for spec: Array in limits:
		if int(spec[1]) < lowest:
			lowest = int(spec[1])
			cap = String(spec[0])
	return cap


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
	is_connected: bool, blockaded: bool = false
) -> String:
	match status:
		"building":
			var left: int = working.remaining_turns() if working != null else 0
			return "Builder at work · %d turn%s left" % [left, "" if left == 1 else "s"]
		"vacant":
			var vacant: String = (
				"Vacant — a Builder can raise a %s" % ImprovementCatalog.base_name(resource)
			)
			if blockaded:
				vacant += " · harbour blockaded, no sea path to the crown"
			elif not is_connected:
				vacant += " · no road to the crown yet"
			return vacant
		UNPROSPECTED:
			return "Prospect this tile before a %s can rise" % ImprovementCatalog.base_name(resource)
		"disconnected":
			# A sealed harbour is a rule, not a missing road: say which one, so
			# the crown never lays a road it does not need (REQ-P2-03).
			if blockaded:
				return "Harbour blockaded — no sea path to the crown"
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
	stockpile: Dictionary, busy: String = ""
) -> bool:
	return (
		level < ImprovementCatalog.MAX_LEVEL
		and level + 1 <= tech_cap
		and level + 1 <= terrain_cap
		and (not mineral or prospected)
		and working == null
		and builder != null
		and busy.is_empty()
		and ImprovementSystem.short_inputs(cost, stockpile).is_empty()
	)


static func _build_reason(
	level: int, tech_cap: int, terrain_cap: int, mineral: bool, prospected: bool,
	working: CivilianState, builder: CivilianState, cost: Dictionary,
	stockpile: Dictionary, busy: String = ""
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
	if not busy.is_empty():
		return busy
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
