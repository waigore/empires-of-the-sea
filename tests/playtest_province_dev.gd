extends SceneTree
## Headless free-playtest drive: develop a province's resources over several
## turns and link the estate to the capital (wiki: extraction-and-improvements,
## capital-and-connectivity, civilian-units).
##
## Plays the real flow (title -> setup -> capital chart -> map) and then acts
## only through the game's own helpers and rules: the estates ledger dispatches
## a Builder, the Engineer marches and lays road tile by tile, the Explorer
## prospects a mine. One line per step, so a run reads as a playtest diary.
## Not a CI gate — run it by hand:
##
##   godot --headless --path . --script res://tests/playtest_province_dev.gd
##   godot --headless --path . --script res://tests/playtest_province_dev.gd -- --start=turn0
##
## The default opens the turn-100 advanced start (multi-turn builds, a mine, a
## town upgrade); `turn0` opens the ordinary campaign and links an outlying
## estate that setup left without a road.

const Launch = preload("res://tests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]
const MAX_MARCH: int = 40
const MAX_TURN_ATTEMPTS: int = 6

var play: PlaySession = null
var _failures: int = 0
var _start: String = AdvancedStart.TURNS100
## True when a rival conquest took the estate or stranded the crew mid-run: the
## drive then narrates it instead of asserting a road the crown can no longer lay.
var _interrupted: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--start="):
			_start = AdvancedStart.normalize(arg.trim_prefix("--start="))
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(self, SEED_TEXT, 0, _start)
	if screen == null:
		_say("playtest: no map screen — the launch flow changed")
		quit(1)
		return
	play = screen.play
	_say("seed %s — %s, capital %s at %s, turn %d" % [
		SEED_TEXT, String(AdvancedStart.LABELS.get(_start, _start)),
		play.model.province_name(play.capital_province),
		str(play.capital_tile), play.turn,
	])
	_say("opening extraction %s" % str(play.economy.extraction()))
	var fields: Dictionary = _pick_estate(false)
	if fields.is_empty():
		_check("a farmable estate in an owned province", false, "none found")
	else:
		_raise_estate(fields, _attainable_level(fields["tile"]))
		_link_home(fields)
	# The mineral gate needs an Explorer's march and a prospect first, which is
	# many turns; the turn-0 run stops at the road so a rival war cannot outrun it.
	if _start == AdvancedStart.TURNS100:
		var mine: Dictionary = _pick_estate(true)
		if mine.is_empty():
			_check("a mineral estate in an owned province", false, "none found")
		else:
			_prospect(mine)
			_raise_estate(mine, _attainable_level(mine["tile"]))
			_link_home(mine)
		_upgrade_town()
	if _interrupted:
		_say("the road test was cut short by a rival war (see above)")
	_say("closing extraction %s" % str(play.economy.extraction()))
	_say("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)


# --- developing one estate --------------------------------------------------


## Highest improvement level this crown's tech allows on the tile, capped at 2
## so the drive never asks for a build the rules refuse.
func _attainable_level(tile: Vector2i) -> int:
	var resource: int = play.model.resource_at(tile.x, tile.y)
	var commodity: String = ImprovementCatalog.commodity(resource)
	var cap: int = ImprovementCatalog.tech_cap_for(commodity, play.tech_caps())
	return clampi(cap, 1, 2)


## Dispatches a Builder from the estates ledger and walks the build up to
## `target_level`, reporting each turn's countdown.
func _raise_estate(estate: Dictionary, target_level: int) -> void:
	var tile: Vector2i = estate["tile"]
	var province: int = int(estate["province"])
	_say("estate: %s %s at %s (%d tiles from the capital)" % [
		play.model.province_name(province), String(estate["name"]), str(tile),
		(estate["path"] as Array).size(),
	])
	var before: Dictionary = _row(province, tile)
	if before.is_empty():
		_check("the estate is still the crown's", false,
			"%s left the ledger before the build started" % str(tile))
		return
	if int(before["level"]) > 0:
		_say("  the estate already stands at level %d" % int(before["level"]))
	var level: int = int(before["level"])
	while level < target_level:
		var order: Dictionary = ImprovementOrders.build(
			play.model, play.civilian_layer.units, play.land_works,
			play.stockpile(), play.visibility, play.player_faction, tile,
			play.tech_caps(), play.tech_unlocked()
		)
		if not bool(order.get("ok", false)):
			_check("the ledger dispatches a Builder", false, String(order.get("message", "")))
			return
		_say("  ledger: %s" % String(order["message"]))
		var row: Dictionary = _row(province, tile)
		var expected: int = level + 1
		_check("the order reports its duration", int(row["total_turns"]) == expected,
			"%d turns for level %d" % [int(row["total_turns"]), expected])
		var saw_building: bool = false
		while String(row["status"]) == "building":
			saw_building = true
			var left: int = int(row["remaining"])
			if not _advance():
				_check("the turn closes while a Builder works", false,
					"turn stayed at %d" % play.turn)
				return
			row = _row(province, tile)
			_check("work progress counts down", int(row["remaining"]) < left,
				"%d -> %d" % [left, int(row["remaining"])])
		_check("the improvement lands at level %d" % expected,
			saw_building and int(row["level"]) == expected,
			"level %d" % int(row["level"]))
		level = int(row["level"])
		_say("  level %d complete on turn %d — %s" % [
			level, play.turn, String(row["status_text"]),
		])
	_check("a Builder is idle again", _idle_builder() != null, "no idle builder")


## Marches the Engineer along the shortest owned-land line from the estate to
## the crown's road network and lays a road on every tile in between, one turn
## per tile, until the estate is connected.
func _link_home(estate: Dictionary) -> void:
	var tile: Vector2i = estate["tile"]
	var province: int = int(estate["province"])
	var row: Dictionary = _row(province, tile)
	if row.is_empty():
		_interrupted = true
		_say("  the crown lost %s before the road began" % str(tile))
		return
	if bool(row["connected"]):
		_say("  already linked — %s" % String(row["status_text"]))
		return
	_say("  %s" % String(row["status_text"]))
	var engineer: CivilianState = _unit("engineer")
	if engineer == null:
		_check("an Engineer musters", false, "no engineer")
		return
	var resolved: Dictionary = LandConnectivity.resolve(
		play.model, play.land_works, play.player_faction, play.capital_tile
	)
	var network: Dictionary = resolved.get("network", {}) as Dictionary
	var route: Array[Vector2i] = _path_to_network(tile, network)
	if route.is_empty():
		_check("an owned-land line to the crown network exists", false,
			"no route from %s" % str(tile))
		return
	# route runs estate -> network; walk it the other way, from the nearest road.
	route.reverse()
	if not _road_march(engineer, route[0], tile, province):
		return
	var laid: int = 0
	for index in range(1, route.size()):
		var step: Vector2i = route[index]
		var live: Dictionary = _row(province, tile)
		if live.is_empty():
			_interrupted = true
			_say("  the crown lost %s while the road was being laid" % str(tile))
			return
		if bool(live["connected"]):
			break
		if play.land_works.transport_at(play.model, step) > 0:
			continue
		if play.land_works.has_port(play.model, step):
			continue
		if not _road_march(engineer, step, tile, province):
			return
		var order: Dictionary = CivilianWork.assign(
			play.model, engineer, "build_road", play.land_works,
			play.civilian_layer.units, play.stockpile(), play.visibility,
			CivilianState.NO_TILE, play.tech_caps(), play.tech_unlocked()
		)
		if not bool(order.get("ok", false)):
			_check("the Engineer may lay a road", false, String(order.get("reason", "")))
			return
		laid += 1
		if not _advance():
			return
		_check("the road lands on the tile after one turn",
			play.land_works.transport_at(play.model, step) >= 1,
			"transport %d" % play.land_works.transport_at(play.model, step))
	row = _row(province, tile)
	if row.is_empty():
		_interrupted = true
		_say("  the crown lost %s while the road was being laid" % str(tile))
		return
	if laid == 0:
		_say("  no road needed — the path was already paved")
	_check("the estate is linked to the capital", bool(row["connected"]),
		"status %s after %d road tiles" % [String(row["status"]), laid])
	_check("a linked estate produces", int(row["output"]) > 0,
		"output %d" % int(row["output"]))
	var extraction: Dictionary = play.economy.extraction()
	var commodity: String = String(row["commodity"])
	_check("its commodity reaches the stockpile", int(extraction.get(commodity, 0)) > 0,
		"%s in %s" % [commodity, str(extraction)])
	_say("  linked on turn %d after %d road tiles: %s — extraction %s" % [
		play.turn, laid, String(row["status_text"]), str(extraction),
	])


## Marches the Engineer to a road tile, or reports why the run stops: a rival
## conquest of the estate is narrated as an interruption, anything else is a
## failure of the drive.
func _road_march(
	engineer: CivilianState, goal: Vector2i, tile: Vector2i, province: int
) -> bool:
	if _march_to(engineer, goal):
		return true
	if _row(province, tile).is_empty():
		_interrupted = true
		_say("  the crown lost %s while the works were under way" % str(tile))
		return false
	_check("the Engineer reaches the road line", false, "stuck at %s" % str(engineer.tile))
	return false


## Marches one owned-land step at a time toward `goal`, re-planning every turn
## (a rival advance can strand the crew and move it). False when no route exists
## or the march stops making progress.
func _march_to(unit: CivilianState, goal: Vector2i) -> bool:
	var guard: int = 0
	while unit.tile != goal and guard < MAX_MARCH * 2:
		guard += 1
		if unit.moved:
			# The stranding pass or an earlier order spent this turn's move.
			if not _advance():
				return false
			continue
		var route: Array[Vector2i] = _owned_route(unit.tile, goal)
		if route.size() < 2:
			return false
		var moved: Dictionary = play.civilian_layer.apply_move(
			unit, route[1], play.visibility
		)
		if not bool(moved.get("ok", false)):
			if String(moved.get("reason", "")).contains("already moved"):
				if not _advance():
					return false
				continue
			return false
		if not _advance():
			return false
	return unit.tile == goal


## Breadth-first route over the crown's own land.
func _owned_route(from: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		if tile == goal:
			break
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if prev.has(next) or not play.model.in_bounds(next.x, next.y):
				continue
			if play.model.owner_at(next.x, next.y) != play.player_faction:
				continue
			if not play.model.is_land(next.x, next.y):
				continue
			prev[next] = tile
			queue.append(next)
	var route: Array[Vector2i] = []
	if not prev.has(goal):
		return route
	var cursor: Vector2i = goal
	while cursor != from:
		route.append(cursor)
		cursor = prev[cursor]
	route.append(from)
	route.reverse()
	return route


## Breadth-first line over the crown's own land from `from` to the nearest tile
## already on the road network.
func _path_to_network(from: Vector2i, network: Dictionary) -> Array[Vector2i]:
	var prev: Dictionary = {from: from}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		if network.has(play.model.index_of(tile.x, tile.y)):
			var path: Array[Vector2i] = []
			var cursor: Vector2i = tile
			while cursor != from:
				path.append(cursor)
				cursor = prev[cursor]
			path.append(from)
			path.reverse()
			return path
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if prev.has(next) or not play.model.in_bounds(next.x, next.y):
				continue
			if play.model.owner_at(next.x, next.y) != play.player_faction:
				continue
			if not play.model.is_land(next.x, next.y):
				continue
			prev[next] = tile
			queue.append(next)
	var empty: Array[Vector2i] = []
	return empty


# --- the mineral gate -------------------------------------------------------


## Marches the Explorer onto the mineral tile and prospects it before a mine.
func _prospect(estate: Dictionary) -> void:
	var tile: Vector2i = estate["tile"]
	var explorer: CivilianState = _unit("explorer")
	if explorer == null:
		_check("an Explorer musters", false, "no explorer")
		return
	if play.land_works.is_prospected(play.player_faction, play.model, tile):
		return
	var refused: Dictionary = ImprovementOrders.build(
		play.model, play.civilian_layer.units, play.land_works,
		play.stockpile(), play.visibility, play.player_faction, tile,
		play.tech_caps(), play.tech_unlocked()
	)
	_check("a mine is refused before prospecting", not bool(refused.get("ok", false)),
		String(refused.get("message", "")))
	var guard: int = 0
	while explorer.tile != tile and guard < MAX_MARCH:
		guard += 1
		var approach: Vector2i = _step_toward(explorer.tile, tile)
		if approach.x < 0:
			_check("the Explorer can reach the mineral", false,
				"stuck at %s" % str(explorer.tile))
			return
		var moved: Dictionary = play.civilian_layer.apply_move(
			explorer, approach, play.visibility
		)
		if not bool(moved.get("ok", false)):
			_check("the Explorer may march", false, String(moved.get("reason", "")))
			return
		if not _advance():
			return
	if explorer.tile != tile:
		_check("the Explorer reaches the mineral", false, "at %s" % str(explorer.tile))
		return
	var order: Dictionary = CivilianWork.assign(
		play.model, explorer, "prospect", play.land_works,
		play.civilian_layer.units, play.stockpile(), play.visibility,
		CivilianState.NO_TILE, play.tech_caps(), play.tech_unlocked()
	)
	if not bool(order.get("ok", false)):
		_check("the Explorer may prospect", false, String(order.get("reason", "")))
		return
	_advance()
	_check("the mineral is prospected",
		play.land_works.is_prospected(play.player_faction, play.model, tile),
		"not marked")


# --- town development -------------------------------------------------------


## The province dossier's Upgrade Town order: a multi-turn Builder job whose
## completion moves the province's town development up one level.
func _upgrade_town() -> void:
	var province: ProvinceState = _owned_non_capital()
	if province == null:
		return
	if not bool(play.tech_unlocked().get(CivilianWork.TOWN_TECH, false)):
		_check("National Bureaucracy is unlocked for a town upgrade", false, "locked")
		return
	var before: int = province.town_level()
	var result: Dictionary = ImprovementOrders.upgrade_town(
		play.model, play.civilian_layer.units, play.land_works, play.stockpile(),
		play.visibility, play.player_faction, province.town_tile, play.tech_unlocked()
	)
	if not bool(result.get("ok", false)):
		_check("the province dispatches a town upgrade", false, String(result.get("message", "")))
		return
	_say("  town: %s" % String(result["message"]))
	var guard: int = 0
	while province.town_level() == before and guard < 8:
		guard += 1
		if not _advance():
			break
	_check("the town development rises", province.town_level() > before,
		"level %d -> %d" % [before, province.town_level()])
	_say("  %s town is now level %d" % [province.name, province.town_level()])


func _owned_non_capital() -> ProvinceState:
	for province: ProvinceState in play.model.provinces:
		if province.owner == play.player_faction and not province.capital:
			if province.town_tile.x >= 0 and province.town_level() < CivilianWorkPlan.MAX_TOWN:
				return province
	return null


# --- helpers ----------------------------------------------------------------


## Developable resource tile in an owned province that still earns nothing,
## nearest the crown network first so the drive links it in a few turns
## (`mineral` picks the prospecting gate).
func _pick_estate(mineral: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = 1 << 30
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction or province.capital:
			continue
		for tile: Vector2i in province.tiles:
			var resource: int = play.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if ImprovementCatalog.needs_prospecting(resource) != mineral:
				continue
			var level: int = play.land_works.improvement_at(play.model, tile)
			var commodity: String = ImprovementCatalog.commodity(resource)
			var cap: int = mini(
				ImprovementCatalog.tech_cap_for(commodity, play.tech_caps()),
				ImprovementCatalog.MAX_LEVEL
			)
			if level >= cap:
				continue
			var path: Array[Vector2i] = _owned_path(tile)
			if path.is_empty():
				continue
			var row: Dictionary = _row(province.id, tile)
			var gap: int = maxi(int(row.get("link_distance", 0)), 0)
			# An unlinked estate is the one with road work to prove; a linked one
			# only serves when the start already paved every province.
			var score: int = (gap if gap > 0 else 1000) * 1000 + path.size()
			if best.is_empty() or score < best_score:
				best_score = score
				best = {
					"tile": tile,
					"province": province.id,
					"name": ImprovementCatalog.base_name(resource),
					"path": path,
				}
	return best


## Breadth-first path over the crown's own land from the capital to `target`.
func _owned_path(target: Vector2i) -> Array[Vector2i]:
	var start: Vector2i = play.capital_tile
	var prev: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		if tile == target:
			break
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if prev.has(next) or not play.model.in_bounds(next.x, next.y):
				continue
			if play.model.owner_at(next.x, next.y) != play.player_faction:
				continue
			if not play.model.is_land(next.x, next.y):
				continue
			prev[next] = tile
			queue.append(next)
	var path: Array[Vector2i] = []
	if not prev.has(target):
		return path
	var cursor: Vector2i = target
	while cursor != start:
		path.append(cursor)
		cursor = prev[cursor]
	path.reverse()
	return path


## One greedy step toward `to`, staying on land the Engineer may enter.
func _step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = absi(from.x - to.x) + absi(from.y - to.y)
	for offset: Vector2i in NEIGHBORS:
		var next: Vector2i = from + offset
		if not CivilianMovement.may_enter(play.model, "engineer", play.player_faction, next):
			continue
		var distance: int = absi(next.x - to.x) + absi(next.y - to.y)
		if distance < best_distance:
			best = next
			best_distance = distance
	return best


## Closes one turn, answering whatever consent decision a rival court raised
## (the player would answer the court plate). False when the turn stays shut.
func _advance() -> bool:
	for _attempt in MAX_TURN_ATTEMPTS:
		var before: int = play.turn
		MapPlayTurn.end_turn(play)
		if play.turn > before:
			return true
		if not _answer_pending():
			return false
		# Answering a consent decision runs the suspended turn to its end, so
		# the calendar moves after the answer, not inside end_turn().
		if play.turn > before:
			return true
	return false


func _answer_pending() -> bool:
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_call(play, false)
		return true
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		return true
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		# A cautious court takes the friendly overtures, so the road is not cut
		# by a war the player would have avoided.
		MapPlayTurn.answer_offer(play, true)
		return true
	return false


func _row(province: int, tile: Vector2i) -> Dictionary:
	var snapshot: Dictionary = ImprovementLedger.snapshot(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.player_faction, play.capital_tile, play.tech_caps()
	)
	for group: Dictionary in snapshot["groups"]:
		if int(group["id"]) != province:
			continue
		for row: Dictionary in group["rows"]:
			if Vector2i(row["tile"]) == tile:
				return row
	return {}


func _unit(type_id: String) -> CivilianState:
	for unit: CivilianState in play.civilian_layer.units:
		if unit.type_id == type_id and unit.owner == play.player_faction:
			return unit
	return null


func _idle_builder() -> CivilianState:
	for unit: CivilianState in play.civilian_layer.units:
		if unit.type_id == "builder" and unit.owner == play.player_faction and unit.is_idle():
			return unit
	return null


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok   %s" % label)
		return
	_failures += 1
	print("  FAIL %s — %s" % [label, detail])


func _say(line: String) -> void:
	print(line)
