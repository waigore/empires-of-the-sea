class_name CrownRoadSurvey
extends RefCounted
## Crown-road projection for the connectivity lens (wiki:
## capital-and-connectivity § Connectivity, extraction-and-improvements
## § Extraction formula and town development cap).
##
## Pure read of the crown's own land: which tiles reach the capital along the
## road/rail/port network (`road`), which reach it only through their province
## town (`town`, so town development caps their yield), and which are cut off
## (`cut`). Every cut province also carries the shortest road the crown could
## lay over its own land to link the province town, so the lens can show the
## gap itself instead of the verdict (REQ-P3-03, REQ-P4-01).
##
## Runs are merged row-major so a 10k-tile map costs a few hundred rects, and
## unknown ground never contributes a run.

const STATE_ROAD: String = "road"
const STATE_TOWN: String = "town"
const STATE_CUT: String = "cut"
const STATES: Array[String] = [STATE_ROAD, STATE_TOWN, STATE_CUT]

const STATE_LABELS: Dictionary = {
	STATE_ROAD: "Road to the crown",
	STATE_TOWN: "Town road only",
	STATE_CUT: "No road to the crown",
}


## Runs per state in tile coordinates, the province readings, the routes to
## lay, and the tile/province counts each state holds. `blockade` is the court's
## own sealed coasts: a sealed harbour is no landfall, so the province it holds
## reads cut and its row names the seal instead of a road still to lay (wiki:
## capital-and-connectivity § Blockade; REQ-P2-03).
static func snapshot(
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i,
	visibility: VisibilityModel = null,
	blockade: Blockades = null
) -> Dictionary:
	var result: Dictionary = {
		"runs": _empty_runs(),
		"tiles": _empty_counts(),
		"provinces": [] as Array[Dictionary],
		"routes": [] as Array[Dictionary],
		"counts": {"linked": 0, "cut": 0, "gap": 0},
		"capital": capital_tile,
	}
	if model == null or works == null or owner < 0:
		return result
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile, blockade
	)
	var states: Dictionary = _tile_states(model, resolved, owner, visibility)
	_merge_runs(result, model, states)
	_collect_provinces(
		result, model, works, owner, capital_tile, resolved, states, visibility,
		blockade
	)
	return result


static func state_label(state: String) -> String:
	return String(STATE_LABELS.get(state, STATE_LABELS[STATE_CUT]))


## One hover line for a province row: what links it, or how many road tiles it
## still needs. `-1` means no owned-land route exists at all.
static func summary_text(entry: Dictionary) -> String:
	var state: String = String(entry.get("state", STATE_CUT))
	var cut: int = int(entry.get("cut_tiles", 0))
	if state == STATE_ROAD:
		if cut > 0:
			return "Crown road: linked by road · %s cut off" % _tiles(cut)
		return "Crown road: linked by road"
	if state == STATE_TOWN:
		return _town_text(entry)
	# A sealed harbour is a rule, not a missing road, so the row names the seal
	# first and the road still to lay beside it (REQ-P2-03).
	if bool(entry.get("blockaded", false)):
		var sealed_gap: int = int(entry.get("gap", -1))
		if sealed_gap > 0:
			return "Crown road: harbour blockaded · %d road tile%s from the crown" % [
				sealed_gap, "" if sealed_gap == 1 else "s"
			]
		return "Crown road: harbour blockaded, no sea path to the crown"
	var gap: int = int(entry.get("gap", -1))
	if gap < 0:
		return "Crown road: no owned-land route to the crown"
	if gap <= 1:
		return "Crown road: one road tile from the crown"
	return "Crown road: %d road tiles from the crown" % gap


## A Town-rule reading. Only a port town (or a capital province) caps yield, so
## a town-only province whose town carries no port says the cap does not apply
## (wiki: extraction-and-improvements § Extraction formula and town development
## cap) — the same predicate the yield itself reads.
static func _town_text(entry: Dictionary) -> String:
	var level: int = int(entry.get("town_level", 0))
	if level <= 0:
		return "Crown road: town only"
	if bool(entry.get("town_caps", false)):
		return "Crown road: town only — town level %d caps its yield" % level
	return "Crown road: town only — town development does not cap it"


## "1 tile" / "2 tiles": a reading never prints "1 tiles".
static func _tiles(count: int) -> String:
	return "%d tile%s" % [count, "" if count == 1 else "s"]


# --- tiles -------------------------------------------------------------------


## State of every own, charted land tile. Tiles the rules connect (on or beside
## a crown road, or through the Town rule) take their state from
## `LandConnectivity.resolve`; everything else the crown holds is cut off.
static func _tile_states(
	model: MapModel, resolved: Dictionary, owner: int, visibility: VisibilityModel
) -> Dictionary:
	var states: Dictionary = {}
	var connected: Dictionary = resolved.get("tiles", {}) as Dictionary
	for y in model.height:
		for x in model.width:
			if model.owner_at(x, y) != owner:
				continue
			if not model.is_land(x, y):
				continue
			if (
				visibility != null
				and visibility.level_at(x, y) == VisibilityModel.Level.UNKNOWN
			):
				continue
			var index: int = model.index_of(x, y)
			states[index] = _state_of(connected.get(index, {}))
	return states


static func _state_of(entry: Variant) -> String:
	if entry == null:
		return STATE_CUT
	var tile: Dictionary = entry as Dictionary
	if tile.is_empty():
		return STATE_CUT
	if bool(tile.get("road", false)):
		return STATE_ROAD
	return STATE_TOWN


## Row-major run merge: consecutive tiles of one state become one Rect2, so the
## lens draws a few hundred rects rather than ten thousand.
static func _merge_runs(
	result: Dictionary, model: MapModel, states: Dictionary
) -> void:
	var runs: Dictionary = result["runs"]
	var tiles: Dictionary = result["tiles"]
	for y in model.height:
		var x: int = 0
		while x < model.width:
			var state: String = String(states.get(model.index_of(x, y), ""))
			if state.is_empty():
				x += 1
				continue
			var start: int = x
			x += 1
			while x < model.width:
				if String(states.get(model.index_of(x, y), "")) != state:
					break
				x += 1
			var span: int = x - start
			(runs[state] as Array).append(Rect2(float(start), float(y), float(span), 1.0))
			tiles[state] = int(tiles[state]) + span


# --- provinces ---------------------------------------------------------------


## One row per own, charted province: its town's state, the gap in road tiles,
## and the route to lay. The route is the shortest owned-land path from the
## crown network to the province town, the town itself excluded because the
## town extracts as soon as it stands beside the road.
static func _collect_provinces(
	result: Dictionary,
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i,
	resolved: Dictionary,
	states: Dictionary,
	visibility: VisibilityModel,
	blockade: Blockades = null
) -> void:
	var provinces: Array = result["provinces"]
	var routes: Array = result["routes"]
	var counts: Dictionary = result["counts"]
	var network: Dictionary = resolved.get("network", {}) as Dictionary
	var gaps: Dictionary = LandConnectivity.network_gaps(model, owner, network)
	for province: ProvinceState in model.provinces:
		if province.owner != owner:
			continue
		var charted: int = VisibilityModel.Level.FULLY_VISIBLE
		if visibility != null:
			charted = visibility.province_visibility(province.id)
		if charted == VisibilityModel.Level.UNKNOWN:
			continue
		var town: Vector2i = ImprovementSystem.town_tile(
			model, works, province.id, capital_tile
		)
		var town_index: int = -1 if town.x < 0 else model.index_of(town.x, town.y)
		var state: String = String(states.get(town_index, STATE_CUT))
		var sealed: bool = blockade != null and blockade.cuts(model.region_id, province.id)
		var gap: int = 0 if state != STATE_CUT else int(gaps.get(town_index, -1))
		var entry: Dictionary = {
			"id": province.id,
			"name": province.name,
			"state": state,
			"linked": state != STATE_CUT,
			"blockaded": sealed,
			"gap": gap,
			"town": town,
			"town_level": province.town_development,
			"town_caps": LandTownRule.town_caps_province(model, resolved, province.id),
			"anchor": _anchor(model, province, town, states),
			"cut_tiles": _cut_tiles(model, province, states),
			"charted": charted,
		}
		provinces.append(entry)
		if state == STATE_CUT:
			counts["cut"] = int(counts["cut"]) + 1
			if gap > 0:
				counts["gap"] = int(counts["gap"]) + gap
				routes.append({
					"province": province.id,
					"town": town,
					"gap": gap,
					"tiles": _route(model, owner, network, town),
				})
		else:
			counts["linked"] = int(counts["linked"]) + 1


## Own tiles of one province that no road reaches, so the province row can say
## how much of its land is still cut off.
static func _cut_tiles(
	model: MapModel, province: ProvinceState, states: Dictionary
) -> int:
	var cut: int = 0
	for tile: Vector2i in province.tiles:
		if String(states.get(model.index_of(tile.x, tile.y), "")) == STATE_CUT:
			cut += 1
	return cut


## A known land tile to hang a reading on: the town when the province has one,
## else the first surveyed tile of the province.
static func _anchor(
	model: MapModel, province: ProvinceState, town: Vector2i, states: Dictionary
) -> Vector2i:
	if town.x >= 0 and states.has(model.index_of(town.x, town.y)):
		return town
	for tile: Vector2i in province.tiles:
		if states.has(model.index_of(tile.x, tile.y)):
			return tile
	return Vector2i(-1, -1)


## Tiles the crown must road before `target` stands beside the crown network:
## the BFS path over owned land minus the network tile it starts from and the
## target tile itself. Empty when no owned-land route exists. The route has one
## home (RoadWorks), so the lens and the dossier's Build road control agree.
static func _route(
	model: MapModel, owner: int, network: Dictionary, target: Vector2i
) -> Array[Vector2i]:
	return RoadWorks.route(model, owner, network, target)


# --- helpers -----------------------------------------------------------------


static func _empty_runs() -> Dictionary:
	var runs: Dictionary = {}
	for state: String in STATES:
		runs[state] = [] as Array[Rect2]
	return runs


static func _empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for state: String in STATES:
		counts[state] = 0
	return counts

