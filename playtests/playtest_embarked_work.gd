extends SceneTree
## Defect probe (hand run, not CI): can a crew that is ABOARD a squadron still
## take a civilian work order? A crew aboard is off the map (wiki: civilian-units
## § Overseas deployment: "Boarding … takes it off the map"), so no work order
## may be filed for it and no surface may offer one.
##
##   godot --headless --path . --script res://playtests/playtest_embarked_work.gd
##
## The court opens with one Builder. The probe boards him through the fleet's own
## press, then files an estate raise through the estates ledger's own door and
## prints what the rules did.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"

var _steps: PackedStringArray = PackedStringArray()
var _fails: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		_say("no map screen")
		_finish()
		return
	_play = _screen.play
	var faction: int = _play.player_faction
	var capital: int = _play.capital_province
	var fleet: FleetState = _play.ship_layer.home_fleet(capital)
	if fleet == null:
		_say("no home squadron at %s" % _play.model.province_name(capital))
		_finish()
		return
	var builders: Array[CivilianState] = _crews_of("builder")
	_say("turn %d - %s, home squadron of %d hulls, %d Builder(s)" % [
		_play.turn, _play.model.province_name(capital), fleet.ship_count(),
		builders.size(),
	])
	var boarded: int = 0
	for builder: CivilianState in builders:
		if _play.model.province_at(builder.tile.x, builder.tile.y) != capital:
			continue
		MapPlayCivilianVoyage.embark(_play, fleet, builder.id)
		if builder.is_embarked():
			boarded += 1
	if boarded == 0:
		_say("no Builder could board at the seat - the probe stops")
		_finish()
		return
	var crew: CivilianState = _first_embarked("builder")
	var stock: Dictionary = _play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	_play.ship_layer.select(_play.ship_layer.ship_for(fleet))
	_say("aboard: %d Builder(s); the one we follow has tile %s, embarked_fleet %d, fleet holds him %s" % [
		boarded, str(crew.tile), crew.embarked_fleet, str(fleet.has_civilian(crew.id)),
	])
	_check(crew.tile == CivilianState.NO_TILE, "an aboard crew has no map tile")

	# --- the crew's own sheet ------------------------------------------------
	var rows: Array[Dictionary] = CivilianWork.options(
		_play.model, crew, _play.land_works, _play.civilian_layer.units,
		_play.stockpile(), _play.visibility, _play.tech_caps(),
		_play.tech_unlocked(), {}
	)
	var open_rows: int = 0
	for row: Dictionary in rows:
		if bool(row.get("ok", false)):
			open_rows += 1
	_say("the aboard crew's own sheet offers %d row(s), %d open" % [
		rows.size(), open_rows,
	])

	# --- the estates ledger's own door --------------------------------------
	var estates: ImprovementPanel = _play.improvements
	estates.open()
	var ready: Array[Vector2i] = estates.ready_tiles()
	_say("the estates ledger prints %d ready estate(s); idle Builders counted: %d" % [
		ready.size(),
		ImprovementOrders.idle_builders(_play.civilian_layer.units, faction).size(),
	])
	estates.close()
	_check(
		ImprovementOrders.idle_builders(_play.civilian_layer.units, faction).is_empty(),
		"the ledger counts no idle Builder while the only one is aboard",
	)
	# A surface that names the ground still cannot book the crew: the work gate
	# reads the crew's own state, not the tile it is handed.
	var tile: Vector2i = _play.model.province_data(capital).town_site()
	var refused: Dictionary = CivilianWork.assign(
		_play.model, crew, "build_improvement", _play.land_works,
		_play.civilian_layer.units, _play.stockpile(), _play.visibility, tile,
		_play.tech_caps(), _play.tech_unlocked(), {}
	)
	_say("a raise filed straight at %s answered: %s" % [
		str(tile), String(refused.get("reason", "accepted")),
	])
	_check(not bool(refused.get("ok", true)), "the rules refuse a named ground too")
	_check(
		String(refused.get("reason", "")).contains("aboard"),
		"the refusal names the reason: the crew is aboard",
	)
	_check(not crew.is_working(), "the rules refuse work to a crew that is off the map")
	_check(crew.tile == CivilianState.NO_TILE, "an aboard crew keeps no map tile")

	# --- the readings: the roster row and the court's own line --------------
	var snapshot: Dictionary = CivilianRoster.snapshot(
		_play.world, _play.civilian_layer.regions, faction
	)
	for raw: Variant in snapshot.get("rows", []):
		var row: Dictionary = raw
		if int(row["unit_id"]) != crew.id:
			continue
		_say("the people roster prints Builder %d as '%s' (%s)" % [
			crew.id, String(row["status_text"]), String(row["status"]),
		])
		_check(String(row["status"]) == "aboard", "the row reads the crew aboard")
		_check(String(row["status_text"]).begins_with("Aboard"), "the words name the duty")
		_check(
			not CivilianRoster.status_matches(row, CivilianRoster.STATUS_IDLE),
			"an aboard crew does not answer the idle chip",
		)
	var waiting_has_crew: bool = false
	for row: Dictionary in CivilianRoster.idle_rows(snapshot):
		if int(row["unit_id"]) == crew.id:
			waiting_has_crew = true
	_check(not waiting_has_crew, "the find-the-next-crew walk never sends you to an aboard crew")
	var line_crews: Array = MapPlayPeoplePick.pick(_play, snapshot).get("crews", [])
	var named_crew: bool = false
	for raw: Variant in line_crews:
		var entry: Dictionary = raw
		if int(entry.get("unit_id", -1)) == crew.id:
			named_crew = true
	_check(not named_crew, "the court's line names no crew it cannot put to work")
	_finish()


# --- helpers -----------------------------------------------------------------


func _crews_of(type_id: String) -> Array[CivilianState]:
	var found: Array[CivilianState] = []
	for unit: CivilianState in _play.civilian_layer.units:
		if unit == null or unit.owner != _play.player_faction or unit.type_id != type_id:
			continue
		if unit.is_working() or unit.is_embarked() or unit.moved:
			continue
		found.append(unit)
	return found


func _first_embarked(type_id: String) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit != null and unit.owner == _play.player_faction:
			if unit.type_id == type_id and unit.is_embarked():
				return unit
	return null


func _check(ok: bool, what: String) -> void:
	_steps.append(what)
	if ok:
		_say("  ok   %s" % what)
		return
	_say("  FAIL %s" % what)
	_fails.append(what)


func _say(line: String) -> void:
	print("playtest: %s" % line)


func _finish() -> void:
	_say("")
	_say("--- playtest_embarked_work: %d steps, %d failure(s) ---" % [
		_steps.size(), _fails.size(),
	])
	for line: String in _fails:
		_say("FAILED: %s" % line)
	quit(1 if not _fails.is_empty() else 0)
