extends SceneTree
## Headless free-playtest drive for the voyage's landing lines
## (wiki: civilian-units § Landing; DR-20261118-19): a squadron's passenger block
## reads one line per crew kind per coast, a coast with one ground lands in one
## press, a coast with several opens its grounds, and the press carries both the
## crew the crown read and the tile it named.
##
## It plays the block as a crown does — the real FleetCrewSection rows, pressed
## in order — and holds every press to the rules: the crew kind on the line is
## the crew that lands (not the first aboard), the tile is the ground the row
## named, the grounds print what the chart lets the crown read of them, and a
## landing charts the tile and its orthogonal neighbours. Not a CI gate — run it
## by hand:
##   godot --headless --path . --script res://playtests/playtest_voyage_grounds.gd
##
## The turn-100 advanced start is the only state with a squadron of several hulls
## and a bench of crews at the seat, so one run reaches the two-crew cases: an
## ordinary opening carries one hull and one crew.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _screen: MapScreen = null
var _play: PlaySession = null
var _steps: PackedStringArray = PackedStringArray()
var _fails: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if _screen == null:
		_say("no map screen — the launch flow changed")
		_finish()
		return
	_play = _screen.play
	var capital: int = _play.capital_province
	var fleet: FleetState = _play.ship_layer.home_fleet(capital)
	if fleet == null:
		_say("no home squadron at %s" % _play.model.province_name(capital))
		_finish()
		return
	_say("seed %s, turn %d — %s, home squadron of %d hulls, treasury %d" % [
		SEED_TEXT, _play.turn, _play.model.province_name(capital),
		fleet.ship_count(), _play.treasury(),
	])
	# The map's own click: the layer selects the marker and the screen reads the
	# selection; `MapPlayFleets.select` only redraws a dossier already selected.
	_play.ship_layer.select(_play.ship_layer.ship_for(fleet))

	_port_one_crew(fleet, capital)
	_port_named_coast(fleet, capital)
	_port_two_crews(fleet, capital)
	_sea_grounds(fleet)
	_finish()


# --- the port: one crew, the panel's own press -------------------------------


## One Explorer aboard in port: the coast line opens its grounds, each ground
## prints what the chart reads of it, and the ground's press lands the crew on
## that very tile.
func _port_one_crew(fleet: FleetState, capital: int) -> void:
	var unit: CivilianState = _crew_of("explorer", capital)
	if unit == null:
		_say("no Explorer at the seat — the port pass cannot start")
		return
	MapPlayCivilianVoyage.embark(_play, fleet, unit.id)
	if not fleet.has_civilian(unit.id):
		_say("the Explorer could not board: %s" % _toast())
		return
	var row: Dictionary = _coast_row(capital, "explorer")
	var grounds: Array[Vector2i] = CivilianVoyage.landing_tiles_in(
		_play.model, unit, fleet, capital
	)
	if row.is_empty():
		_fail("the capital coast is not offered to the Explorer aboard")
		return
	_check(
		int(row.get("tiles", []).size()) == grounds.size(),
		"the coast line reads the rules' every ground (%d read, %d legal)" % [
			int(row.get("tiles", []).size()), grounds.size(),
		]
	)
	_check(
		String(row.get("crew_name", "")) == "Explorer",
		"the line names the crew it lands (%s)" % String(row.get("crew_name", "?")),
	)
	var block: FleetCrewSection = _crew_block()
	if block == null:
		_fail("the fleet dossier has no passenger block")
		return
	var coast: Button = _button_starting(block, "Put the Explorer ashore at")
	if coast == null:
		_fail("the capital coast offers no press")
		return
	_say("the capital coast reads \"%s\"" % coast.text)
	if int(row.get("tiles", []).size()) > 1:
		coast.pressed.emit()
	var chosen: Vector2i = grounds[grounds.size() - 1]
	var ground_button: Button = _button_matching(block, "(%d, %d)" % [chosen.x, chosen.y])
	if int(row.get("tiles", []).size()) > 1:
		if ground_button == null:
			_fail("the opened coast lists no ground at %s" % str(chosen))
			return
		_say("the grounds open: \"%s\"" % ground_button.text)
		ground_button.pressed.emit()
	if unit.tile != chosen:
		_fail("the press named %s and the Explorer stands at %s" % [
			str(chosen), str(unit.tile),
		])
	else:
		_say("the Explorer lands on the ground the crown named (%d, %d), not the "
			% [chosen.x, chosen.y] + "first the coast reads %s" % str(grounds[0]))
	_say("the court hears: %s" % _toast())
	var rested: Dictionary = MapPlayCivilianVoyage.crew(_play, _fleet())
	_check(
		Array(rested.get("land", [])).is_empty(),
		"no crew aboard leaves no coast to press (\"%s\")" % String(rested.get("note", ""))
	)


# --- the port: a coast named without a tile ----------------------------------


## A caller that names only the coast (a script, the smoke flow) lands on the
## first legal ground — the published meaning of `crew:land:<province>`.
func _port_named_coast(fleet: FleetState, capital: int) -> void:
	var unit: CivilianState = _crew_of("merchant", capital)
	if unit == null:
		_say("no Merchant at the seat — the named-coast pass cannot start")
		return
	MapPlayCivilianVoyage.embark(_play, fleet, unit.id)
	if not fleet.has_civilian(unit.id):
		_say("the Merchant could not board: %s" % _toast())
		return
	var first: Vector2i = CivilianVoyage.landing_tile_in(
		_play.model, unit, fleet, capital
	)
	MapPlayCivilianVoyage.on_action(_play, "crew:land:%d" % capital)
	_check(unit.tile == first, "a coast named without a tile lands the first ground %s "
		% str(first) + "(the crew stands at %s)" % str(unit.tile))
	_say("the named coast lands the Merchant at (%d, %d)" % [unit.tile.x, unit.tile.y])


# --- the port: two crews, two lines ------------------------------------------


## Two crews of different kinds aboard: the block reads one line per crew kind,
## so the crown picks the crew as well as the ground — the press lands the kind
## it read, though the other crew stood first aboard.
func _port_two_crews(fleet: FleetState, capital: int) -> void:
	var builder: CivilianState = _crew_of("builder", capital)
	var explorer: CivilianState = _crew_of("explorer", capital)
	if builder == null or explorer == null:
		_say("the seat no longer holds a Builder and an Explorer")
		return
	MapPlayCivilianVoyage.embark(_play, fleet, builder.id)
	MapPlayCivilianVoyage.embark(_play, fleet, explorer.id)
	if not fleet.has_civilian(builder.id) or not fleet.has_civilian(explorer.id):
		_say("two crews could not board: %s" % _toast())
		return
	var data: Dictionary = MapPlayCivilianVoyage.crew(_play, fleet)
	_say("two aboard reads: \"%s\"" % String(data.get("note", "")))
	var builder_row: Dictionary = _coast_row(capital, "builder")
	var explorer_row: Dictionary = _coast_row(capital, "explorer")
	_check(
		not builder_row.is_empty() and not explorer_row.is_empty(),
		"a Builder and an Explorer aboard read one line each on the same coast",
	)
	if builder_row.is_empty() or explorer_row.is_empty():
		return
	_check(
		String(builder_row.get("crew_name", "")) == "Builder"
		and String(explorer_row.get("crew_name", "")) == "Explorer",
		"each line names its own crew (%s · %s)" % [
			String(builder_row.get("crew_name", "?")),
			String(explorer_row.get("crew_name", "?")),
		],
	)
	var block: FleetCrewSection = _crew_block()
	if block == null:
		return
	var coast: Button = _button_starting(block, "Put the Explorer ashore at")
	if coast == null:
		_fail("the Explorer's line on the capital coast is missing")
		return
	_say("with a Builder and an Explorer aboard the Explorer reads \"%s\"" % coast.text)
	if coast.text.contains("grounds"):
		coast.pressed.emit()
	var grounds: Array[Vector2i] = CivilianVoyage.landing_tiles_in(
		_play.model, explorer, fleet, capital
	)
	var pick: Vector2i = grounds[grounds.size() - 1]
	var ground_button: Button = _button_matching(block, "(%d, %d)" % [pick.x, pick.y])
	if ground_button == null:
		_fail("the Explorer's grounds list no ground at %s" % str(pick))
		return
	_say("the ground row reads \"%s\"" % ground_button.text)
	_check(
		ground_button.text.length() > ("Madrid (%d, %d)" % [pick.x, pick.y]).length(),
		"the ground row names what the chart reads of the tile",
	)
	ground_button.pressed.emit()
	_check(
		explorer.tile == pick,
		"the Explorer takes the press at (%d, %d), not the Builder first aboard"
		% [pick.x, pick.y],
	)
	_check(builder.is_embarked(), "the Builder stays aboard his own line")


# --- at sea: several coasts, a foreign ground, the chart ----------------------


## The squadron sorts with two crews: the Explorer's lines carry every coast and
## the Builder's only the crown's own. A foreign ground lands the Explorer, a
## crown ground lands the Builder, and the landing charts the tile and its
## orthogonal neighbours and never the province.
func _sea_grounds(fleet: FleetState) -> void:
	var builder: CivilianState = _crew_of_type("builder")
	var explorer: CivilianState = _crew_of_type("explorer")
	if builder == null or explorer == null:
		_say("no Builder and Explorer left to board for the sea pass")
		return
	MapPlayCivilianVoyage.embark(_play, fleet, builder.id)
	MapPlayCivilianVoyage.embark(_play, fleet, explorer.id)
	if not fleet.has_civilian(builder.id) or not fleet.has_civilian(explorer.id):
		_say("the sea pass could not board both crews: %s" % _toast())
		return
	if not _sortie(fleet):
		return
	var coasts: Array = MapPlayCivilianVoyage.crew(_play, fleet)["land"]
	_say("at sea in %s the block reads %d landing line%s" % [
		_play.model.sea_zone_name(fleet.sea_zone), coasts.size(),
		"" if coasts.size() == 1 else "s",
	])
	var lines: PackedStringArray = PackedStringArray()
	for raw: Variant in coasts:
		var row: Dictionary = raw as Dictionary
		lines.append("%s · %s · %d grounds" % [
			String(row.get("crew_name", "?")), String(row.get("name", "?")),
			int(row.get("tiles", []).size()),
		])
	if not lines.is_empty():
		_say("  " + " | ".join(lines))
	if coasts.is_empty():
		_fail("no coast is offered with two crews aboard at sea")
		return
	var foreign: Dictionary = _foreign_coast(coasts)
	var crown: Dictionary = _crown_coast(coasts)
	_check(not foreign.is_empty(), "the Explorer reads a foreign coast at sea")
	_check(not crown.is_empty(), "the Builder reads the crown's own coast")
	if foreign.is_empty() or crown.is_empty():
		return

	var tile: Vector2i = _last_tile(foreign)
	var before: int = _charted_around(tile)
	var block: FleetCrewSection = _crew_block()
	var coast: Button = _button_starting(
		block, "Put the Explorer ashore at %s" % String(foreign.get("name", ""))
	)
	if coast == null:
		_fail("the foreign coast %s is not offered to the Explorer"
			% String(foreign.get("name", "")))
		return
	if coast.text.contains("grounds"):
		coast.pressed.emit()
	var ground_button: Button = _button_matching(block, "(%d, %d)" % [tile.x, tile.y])
	if ground_button == null:
		_fail("the foreign coast lists no ground at (%d, %d)" % [tile.x, tile.y])
		return
	_say("the foreign ground reads \"%s\"" % ground_button.text)
	ground_button.pressed.emit()
	_check(
		explorer.tile == tile,
		"the Explorer takes the foreign ground at (%d, %d)" % [tile.x, tile.y],
	)
	_check(builder.is_embarked(), "the Builder stays aboard a foreign coast")
	var after: int = _charted_around(tile)
	_check(
		after == 5,
		"the landing charts the tile and its four neighbours (was %d, now %d)"
		% [before, after],
	)
	var province: int = _play.model.province_at(tile.x, tile.y)
	_check(
		not _play.visibility.is_province_fully_visible(province),
		"the landing charts the ring and never the province",
	)
	_say("the court hears: %s" % _toast())

	var crown_tile: Vector2i = _first_tile(crown)
	var crown_coast: Button = _button_starting(
		block, "Put the Builder ashore at %s" % String(crown.get("name", ""))
	)
	if crown_coast == null:
		_fail("the crown's own coast %s is not offered to the Builder"
			% String(crown.get("name", "")))
		return
	if crown_coast.text.contains("grounds"):
		crown_coast.pressed.emit()
	var crown_ground: Button = _button_matching(
		block, "(%d, %d)" % [crown_tile.x, crown_tile.y]
	)
	if crown_ground == null:
		_fail("the Builder's coast lists no ground at (%d, %d)"
			% [crown_tile.x, crown_tile.y])
		return
	crown_ground.pressed.emit()
	# Two Builders aboard read one line (which of them steps off is no choice the
	# crown can tell apart), so the press lands the first able one.
	var landed_builder: CivilianState = _builder_at(crown_tile)
	_check(
		landed_builder != null,
		"a Builder lands on the crown ground at (%d, %d)" % [crown_tile.x, crown_tile.y],
	)
	# A press that names a crew the ground refuses says the crew's name.
	MapPlayCivilianVoyage.land(_play, fleet, tile, "builder")
	_say("a Builder press on the foreign ground hears: %s" % _toast())


# --- helpers ----------------------------------------------------------------


func _sortie(fleet: FleetState) -> bool:
	var zones: Array[int] = FleetSortie.zones(_play.model, fleet)
	for zone: int in zones:
		var result: Dictionary = _play.ship_layer.sortie(fleet, zone)
		if bool(result.get("ok", false)):
			_say("the squadron sorties into %s" % _play.model.sea_zone_name(zone))
			MapPlayFleets.show_dossier(_play, fleet)
			return true
		_say("the sortie into %s is refused: %s" % [
			_play.model.sea_zone_name(zone), String(result.get("reason", "")),
		])
	# The harness seats the zone: a coast out of this turn's reach is a scenario
	# gap, not a rules defect.
	var seat: int = zones[0] if not zones.is_empty() else -1
	if seat < 0:
		return false
	fleet.location = FleetState.Location.AT_SEA
	fleet.sea_zone = seat
	fleet.province = MapModel.NO_ID
	fleet.moved = true
	_say("the harness seats the squadron in %s" % _play.model.sea_zone_name(seat))
	MapPlayFleets.show_dossier(_play, fleet)
	return true


func _coast_row(province: int, crew: String) -> Dictionary:
	for raw: Variant in MapPlayCivilianVoyage.crew(_play, _fleet())["land"]:
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == province \
			and String(row.get("crew", "")) == crew:
			return row
	return {}


## A coast the crown does not hold (a foreign shore only an Explorer may take).
func _foreign_coast(coasts: Array) -> Dictionary:
	for raw: Variant in coasts:
		var row: Dictionary = raw as Dictionary
		for tile_raw: Variant in row.get("tiles", []):
			var tile: Dictionary = tile_raw as Dictionary
			var owner: int = _play.model.owner_at(
				int(tile.get("x", -1)), int(tile.get("y", -1))
			)
			if owner != _play.player_faction:
				return row
	return {}


## A coast the crown holds (a Builder's ground).
func _crown_coast(coasts: Array) -> Dictionary:
	for raw: Variant in coasts:
		var row: Dictionary = raw as Dictionary
		for tile_raw: Variant in row.get("tiles", []):
			var tile: Dictionary = tile_raw as Dictionary
			var owner: int = _play.model.owner_at(
				int(tile.get("x", -1)), int(tile.get("y", -1))
			)
			if owner == _play.player_faction:
				return row
	return {}


func _first_tile(row: Dictionary) -> Vector2i:
	var tiles: Array = row.get("tiles", [])
	if tiles.is_empty():
		return Vector2i(-1, -1)
	var tile: Dictionary = tiles[0] as Dictionary
	return Vector2i(int(tile.get("x", -1)), int(tile.get("y", -1)))


func _last_tile(row: Dictionary) -> Vector2i:
	var tiles: Array = row.get("tiles", [])
	if tiles.is_empty():
		return Vector2i(-1, -1)
	var tile: Dictionary = tiles[tiles.size() - 1] as Dictionary
	return Vector2i(int(tile.get("x", -1)), int(tile.get("y", -1)))


## How many of the five tiles (the ground and its orthogonal neighbours) are
## fully charted.
func _charted_around(tile: Vector2i) -> int:
	var charted: int = 0
	for next: Vector2i in [
		tile, tile + Vector2i.RIGHT, tile + Vector2i.LEFT,
		tile + Vector2i.DOWN, tile + Vector2i.UP,
	]:
		if not _play.model.in_bounds(next.x, next.y):
			continue
		if _play.visibility.level_at(next.x, next.y) >= VisibilityModel.Level.FULLY_VISIBLE:
			charted += 1
	return charted


func _crew_block() -> FleetCrewSection:
	for node: Node in get_root().find_children("*", "", true, false):
		if node is FleetCrewSection:
			return node as FleetCrewSection
	return null


func _button_starting(block: FleetCrewSection, prefix: String) -> Button:
	for node: Node in block.find_children("", "Button", true, false):
		var button: Button = node as Button
		if button.text.begins_with(prefix):
			return button
	return null


func _button_matching(block: FleetCrewSection, needle: String) -> Button:
	for node: Node in block.find_children("", "Button", true, false):
		var button: Button = node as Button
		if button.text.contains(needle):
			return button
	return null


func _fleet() -> FleetState:
	return _play.ship_layer.fleet_of(_play.ship_layer.selected())


func _crew_of(type_id: String, province: int) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or unit.type_id != type_id:
			continue
		if unit.is_embarked() or unit.is_working() or unit.moved:
			continue
		if _play.model.province_at(unit.tile.x, unit.tile.y) != province:
			continue
		return unit
	return null


## A player's crew of one kind standing on a tile (the press lands the first able
## one, so the harness reads the ground, not the instance).
func _builder_at(tile: Vector2i) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or unit.type_id != "builder":
			continue
		if unit.tile == tile:
			return unit
	return null


func _crew_of_type(type_id: String) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or unit.type_id != type_id:
			continue
		if unit.is_embarked() or unit.is_working() or unit.moved:
			continue
		return unit
	return null


func _toast() -> String:
	var despatches: HudDespatches = _play.hud.despatches
	if despatches == null:
		return "(no despatches)"
	if not despatches._queue.is_empty():
		return String(despatches._queue[despatches._queue.size() - 1])
	if despatches.lane != null and despatches.lane.get_child_count() > 0:
		var last: Node = despatches.lane.get_child(despatches.lane.get_child_count() - 1)
		return String(last.get_meta("toast_text", "(no text)"))
	return "(no toast)"


func _check(ok: bool, line: String) -> void:
	if ok:
		_say("ok — " + line)
	else:
		_fail(line)


func _fail(line: String) -> void:
	_fails.append(line)
	print("playtest: FAIL — ", line)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_voyage_grounds: %d steps, %d failures ---" % [
		_steps.size(), _fails.size(),
	])
	for line: String in _fails:
		print("  fail: ", line)
	quit()
