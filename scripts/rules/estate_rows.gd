## One estate's ledger row (wiki: extraction-and-improvements): its level, caps,
## yield, the Builder's picture and the crown's Build gate. The figures and the
## gate are read here in named steps; the words the row prints are
## [EstateRowWords]' own. [ImprovementLedger] groups these rows by province and
## totals them (REQ-P3-01, REQ-P3-03).
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
	var facts: Dictionary = _caps(model, works, tile, resource, owner, tech_caps)
	facts.merge(
		_network(model, owner, tile, province, entry, resolved, gaps, blockaded), true
	)
	facts.merge(_crew(units, idle, owner, tile), true)
	facts["cost"] = _cost(model, tile, int(facts["level"]), stockpile)
	facts.merge(_yields(facts, owner), true)
	facts.merge(_gate(facts, stockpile), true)
	var status: String = status_for(
		int(facts["level"]), bool(facts["connected"]),
		facts["working"] as CivilianState, bool(facts["mineral"]),
		bool(facts["prospected"])
	)
	var row: Dictionary = _row(model, tile, province, resource, owner, facts, status)
	# The preview is read off the finished row so one home answers both the
	# per-estate figure and the words the ledger prints for it.
	row["preview_text"] = EstateRowWords.preview_text(row)
	return row


## A Builder at work outranks level; a surveyed mineral is vacant, an unseen
## deposit unprospected; a full estate maxed.
static func status_for(
	level: int, is_connected: bool, working: CivilianState, mineral: bool,
	prospected: bool
) -> String:
	if working != null:
		return "building"
	if level <= 0:
		return EstateRowWords.UNPROSPECTED if mineral and not prospected else "vacant"
	if not is_connected:
		return "disconnected"
	if level >= ImprovementCatalog.MAX_LEVEL:
		return "maxed"
	return "producing"


# --- facts -------------------------------------------------------------------


## The tile's own read: its level, what the catalog calls it and the three
## ceilings a raise meets (terrain, study, and the mineral survey gate).
static func _caps(
	model: MapModel, works: LandWorks, tile: Vector2i, resource: int, owner: int,
	tech_caps: Dictionary
) -> Dictionary:
	var commodity: String = ImprovementCatalog.commodity(resource)
	return {
		"level": works.improvement_at(model, tile),
		"commodity": commodity,
		"tech_cap": ImprovementCatalog.tech_cap_for(commodity, tech_caps),
		"terrain_cap": TerrainCaps.hard_cap(model.terrain_at(tile.x, tile.y), commodity),
		"mineral": ImprovementCatalog.needs_prospecting(resource),
		"prospected": works.is_prospected(owner, model, tile),
	}


## The crown's reach to this tile: whether the network walk reached it, the road
## gap when it is cut, and the two transport ceilings the yield reads.
static func _network(
	model: MapModel, owner: int, tile: Vector2i, province: int, entry: Dictionary,
	resolved: Dictionary, gaps: Dictionary, blockaded: bool
) -> Dictionary:
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
	return {
		"connected": is_connected,
		"gap": gap,
		"transport": int(entry.get("transport", 0)),
		"town_cap": LandTownRule.town_cap_for(
			model, resolved, province, model.index_of(tile.x, tile.y)
		),
		"blockaded": blockaded,
	}


## The crew that could raise the estate and the one already on it: the working
## Builder, the nearest idle one, and the tile-exclusivity refusal in the Build
## order's own words (wiki: civilian-units § Per-player tile exclusivity;
## REQ-P2-03).
static func _crew(
	units: Array[CivilianState], idle: Array[CivilianState], owner: int, tile: Vector2i
) -> Dictionary:
	var builder: CivilianState = _nearest(idle, tile)
	return {
		"working": _working_unit(units, owner, tile),
		"builder": builder,
		"busy": CivilianWorkRefusals.tile_busy(units, builder, tile),
	}


## The cost of the next raise. The H8 feedstock bootstrap may waive a level-1
## raise's inputs (wiki: extraction-and-improvements § H8 feedstock bootstrap;
## #878); a maxed tile shows the full table cost for its level.
static func _cost(
	model: MapModel, tile: Vector2i, level: int, stockpile: Dictionary
) -> Dictionary:
	var next_level: int = mini(level + 1, ImprovementCatalog.MAX_LEVEL)
	if next_level > level:
		return CivilianWorkPlan.bootstrap_cost(model, tile, stockpile, next_level)
	return CivilianWork.cost_for("build_improvement", next_level)


## What the estate gathers now and at the next level, read by the phase's own
## formula — the one the harvest pays by — so a crown prices a raise against the
## harvest it will actually gather and never against a level the caps hold flat
## (REQ-P2-03, REQ-P5-06). A gated estate (no road, no survey) gathers nothing at
## any level, though its caps still name the base the next level is measured
## against.
static func _yields(facts: Dictionary, owner: int) -> Dictionary:
	var level: int = int(facts["level"])
	var tech_cap: int = int(facts["tech_cap"])
	var terrain_cap: int = int(facts["terrain_cap"])
	var transport: int = int(facts["transport"])
	var town_cap: int = int(facts["town_cap"])
	var commodity: String = String(facts["commodity"])
	var next_level: int = mini(level + 1, ImprovementCatalog.MAX_LEVEL)
	var capped_now: int = _yield_at(
		level, tech_cap, terrain_cap, transport, town_cap, owner, commodity
	)
	var next_output: int = capped_now
	if level < ImprovementCatalog.MAX_LEVEL:
		next_output = _yield_at(
			next_level, tech_cap, terrain_cap, transport, town_cap, owner, commodity
		)
	var paid: bool = (
		level > 0 and bool(facts["connected"])
		and (not bool(facts["mineral"]) or bool(facts["prospected"]))
	)
	return {
		"next_level": next_level,
		"output": capped_now if paid else 0,
		# The per-level figure the extraction formula pays before a ration
		# estate's doubling. The cap note reads this one, because the multiplier
		# would otherwise hide the cap that holds the estate flat
		# (wiki: extraction-and-improvements § Ration estates).
		"effective": _level_yield(level, tech_cap, terrain_cap, transport, town_cap),
		"next_output": next_output,
		"gain": maxi(next_output - capped_now, 0),
	}


## The phase's own arithmetic at one level, ration estates doubled (issue #807).
## One home for the formula the row reads four times.
static func _yield_at(
	level: int, tech_cap: int, terrain_cap: int, transport: int, town_cap: int,
	owner: int, commodity: String
) -> int:
	return _level_yield(level, tech_cap, terrain_cap, transport, town_cap) \
		* Extraction.estate_yield_per_level(owner, commodity)


## The extraction formula's yield for one level, before a ration estate's
## doubling: min(level, tech, terrain, transport, town).
static func _level_yield(
	level: int, tech_cap: int, terrain_cap: int, transport: int, town_cap: int
) -> int:
	return Extraction.effective_yield(
		level, mini(tech_cap, terrain_cap), transport, town_cap
	)


## The Build press and the words that explain it, read as one gate: a row that
## can build carries no refusal, so `can_build` and `build_reason` can never
## disagree (REQ-P2-03, RUB-P2-03).
static func _gate(facts: Dictionary, stockpile: Dictionary) -> Dictionary:
	var level: int = int(facts["level"])
	var working: CivilianState = facts["working"] as CivilianState
	var builder: CivilianState = facts["builder"] as CivilianState
	var busy: String = String(facts["busy"])
	var reason: String = ""
	if working != null:
		reason = "A Builder is already at work here."
	elif level >= ImprovementCatalog.MAX_LEVEL:
		reason = "This estate is fully improved."
	elif level + 1 > int(facts["terrain_cap"]):
		reason = "This terrain hard-caps the estate at level %d." % int(
			facts["terrain_cap"]
		)
	elif bool(facts["mineral"]) and not bool(facts["prospected"]):
		reason = "An Explorer must prospect the tile first."
	elif level + 1 > int(facts["tech_cap"]):
		reason = "Requires extraction tech (cap %d) to raise this estate." % int(
			facts["tech_cap"]
		)
	elif builder == null:
		reason = "No idle Builder — train one at the capital."
	elif not busy.is_empty():
		reason = busy
	else:
		var short: Dictionary = ImprovementSystem.short_inputs(
			facts["cost"] as Dictionary, stockpile
		)
		if not short.is_empty():
			reason = "Stores are short of %s." % CivilianWork.cost_text(short)
	return {"can_build": reason.is_empty(), "build_reason": reason}


# --- row ---------------------------------------------------------------------


## The row the ledger groups and the sheet prints: every fact the reading
## gathered, plus the one line its status earned.
static func _row(
	model: MapModel, tile: Vector2i, province: int, resource: int, owner: int,
	facts: Dictionary, status: String
) -> Dictionary:
	var level: int = int(facts["level"])
	var working: CivilianState = facts["working"] as CivilianState
	var builder: CivilianState = facts["builder"] as CivilianState
	var status_text: String = EstateRowWords.status_text(
		status, resource, level, int(facts["output"]), int(facts["tech_cap"]),
		int(facts["terrain_cap"]), int(facts["transport"]), int(facts["town_cap"]),
		working, bool(facts["connected"]), bool(facts["blockaded"]),
		int(facts["effective"])
	)
	# How much road the crown still needs (wiki: capital-and-connectivity).
	var gap: int = int(facts["gap"])
	if gap > 0:
		status_text += " · %d tile%s to the crown network" % [
			gap, MoneyText.plural(gap)
		]
	var next_level: int = int(facts["next_level"])
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
		"tech_cap": int(facts["tech_cap"]),
		"terrain_cap": int(facts["terrain_cap"]),
		"transport": int(facts["transport"]),
		"town_cap": int(facts["town_cap"]),
		"tech_limited": next_level > int(facts["tech_cap"])
			and level < ImprovementCatalog.MAX_LEVEL,
		"terrain_limited": next_level > int(facts["terrain_cap"])
			and level < ImprovementCatalog.MAX_LEVEL,
		"commodity": String(facts["commodity"]),
		"owner": owner,
		"output": int(facts["output"]),
		"output_text": ImprovementCatalog.output_text(resource, int(facts["output"])),
		"connected": bool(facts["connected"]),
		"blockaded": bool(facts["blockaded"]),
		"prospected": bool(facts["prospected"]),
		"needs_prospecting": bool(facts["mineral"]),
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
		"cost": facts["cost"],
		"cost_text": CivilianWork.cost_text(facts["cost"] as Dictionary),
		"duration": next_level,
		"can_build": bool(facts["can_build"]),
		"build_reason": String(facts["build_reason"]),
		"next_output": int(facts["next_output"]),
		"gain": int(facts["gain"]),
	}


# --- helpers ----------------------------------------------------------------


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
