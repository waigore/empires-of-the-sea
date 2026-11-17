extends SceneTree
## Headless playtest drive for the court's pick on a waiting crew's sheet
## (wiki: civilian-build-planner § Deferred seed item; civilian-units
## § Work Order Summary; DR-20261117-06/07).
##
## A pick is advice the crown is expected to press, so the drive reads it the
## way a player does and then checks it against the surfaces the crown can
## press. Mid-game state comes from the turn-100 advanced start, where the
## crown holds several crews and estates: at turn 1 a court has three crews and
## one improvable tile, which is too thin to show what the pick promises.
##
##   godot --headless --path . --script res://playtests/playtest_civilian_pick.gd
##
## Every finding fails the drive (non-zero exit) instead of printing a number
## nobody compares. The drive plays **England**, not Spain: the catalog's player
## slot (0) is Spain, so a sheet that reads a defaulted faction instead of the
## crown the session resumed as is invisible in a Spain-only drive.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
## England: a Great Power that is not FactionCatalog.PLAYER_FACTION.
const NATION: int = 1
## The mid-game preset: estates, roads and a full roster of crews.
const PRESET: String = "turns100"

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, PRESET, NATION)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("%s (faction %d), preset %s, turn %d, lands %d" % [
		FactionCatalog.name_of(_play.player_faction), _play.player_faction, PRESET,
		_play.turn, _play.treasury(),
	])
	var picks: Dictionary = MapPlayCivilianPick.picks(_play, _play.player_faction)
	_say("the court's own pass names work for %d crews" % picks.size())
	_read_every_sheet(picks)
	_press_the_pick_doors(picks)
	_press_the_estate_pick(picks)
	await _turn_pass()
	_finish()


# --- the reading -------------------------------------------------------------


## Every idle crew of the crown, read the way a player reads it: the gold line,
## the status above the orders and every row the sheet prints.
func _read_every_sheet(picks: Dictionary) -> void:
	var idle: int = 0
	var named: int = 0
	var work: int = 0
	var marches: int = 0
	var off_tile: int = 0
	var no_advice: int = 0
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or unit.is_working():
			continue
		idle += 1
		MapPlayCivilians.select(_play, unit)
		var panel: CivilianPanel = _play.hud.panels.civilian_panel
		var pick: Dictionary = picks.get(unit.id, {})
		if pick.is_empty():
			# No advice is a reading too: the sheet must not tell the crown to
			# choose from a list where every row is refused.
			if _legal_orders(unit) == 0:
				no_advice += 1
				_say("crew %d %s at %s: no pick, no order" % [
					unit.id, unit.type_id, str(unit.tile),
				])
				_check(
					"a crew with nothing to take says so",
					panel._status.text.contains("no order can be taken")
				)
			continue
		named += 1
		var tile: Vector2i = pick["tile"]
		var action: String = String(pick["action"])
		_say("crew %d %s at %s: %s" % [unit.id, unit.type_id, str(unit.tile), String(pick["line"])])
		_check("the sheet prints the court's line", panel._pick.visible)
		_check(
			"the line reaches the sheet in its own words",
			panel._pick.text == _sentence(String(pick["line"]))
		)
		if action == MapPlayCivilianPick.KIND_MOVE:
			marches += 1
			# A march is pressed on the map: the step has to be one of the
			# glowing neighbours, or the arrow points nowhere.
			var steps: Array[Vector2i] = CivilianMovement.valid_tiles(
				_play.model, unit, _play.visibility
			)
			_check("the march is a legal step", steps.has(tile))
			continue
		work += 1
		if tile != unit.tile:
			off_tile += 1
			_check(
				"work away from the crew names its ground",
				panel._pick.text.contains("(%d, %d)" % [tile.x, tile.y])
			)
		# The advice must be an order the rules would take where it is named.
		var check: Dictionary = CivilianWork.validate(
			_play.model, unit, action, _play.land_works, _play.civilian_layer.units,
			_play.stockpile(), _play.visibility, tile, _play.tech_caps(),
			_play.tech_unlocked(), _context()
		)
		_check(
			"the court's order is legal at %s (%s)" % [str(tile), String(check.get("reason", ""))],
			bool(check.get("ok", false))
		)
		# And the chart rings that ground: the sheet's line and the map agree.
		var marks: Array[Dictionary] = CivicGlyphs.marks(
			{unit.id: pick}, _play.civilian_layer.units, _play.model, _play.visibility
		)
		_check("the chart rings the picked ground", marks.size() == 1 and marks[0]["tile"] == tile)
	_say("%d crews wait — %d carry the court's line (%d work, %d marches); %d of the work orders name ground away from the crew; %d crews have nothing to take" % [
		idle, named, work, marches, off_tile, no_advice,
	])
	_check("the crown's own crews carry picks", named > 0)


## The pick's door: a pick naming ground the crew's own sheet cannot press
## carries one press to the surface that can — the estates ledger for an estate,
## the province dossier for a road (wiki: playtest-learnings § next targets).
func _press_the_pick_doors(picks: Dictionary) -> void:
	var pressed: int = 0
	for unit: CivilianState in _play.civilian_layer.units:
		var pick: Dictionary = picks.get(unit.id, {})
		var door: String = String(pick.get("door", ""))
		if door.is_empty() or int(pick.get("region", -1)) != _play.region_index:
			continue
		var tile: Vector2i = pick["tile"]
		var province: int = _play.model.province_at(tile.x, tile.y)
		MapPlayCivilians.select(_play, unit)
		var panel: CivilianPanel = _play.hud.panels.civilian_panel
		_say("crew %d %s: the pick at %s carries the %s door" % [
			unit.id, unit.type_id, str(tile), door,
		])
		_check("a pick on other ground carries its door", panel._follow.visible)
		panel._follow.pressed.emit()
		_check("the door frames the ground it names", _play.selected_province == province)
		if door == MapPlayCivilianPick.DOOR_ESTATES:
			_check("the estates ledger opens at the pick", _play.improvements.is_open())
			_play.improvements.close()
		else:
			_check("the province dossier opens at the pick", _play.hud.panels.is_panel_open())
		pressed += 1
		if pressed >= 2:
			break
	_say("%d pick door(s) pressed" % pressed)


## The one press the pick's advice has off the crew's own tile: the estates
## ledger raises the estate the line names, whichever Builder is free.
func _press_the_estate_pick(picks: Dictionary) -> void:
	for unit: CivilianState in _play.civilian_layer.units:
		var pick: Dictionary = picks.get(unit.id, {})
		if pick.is_empty() or String(pick["action"]) != "build_improvement":
			continue
		var tile: Vector2i = pick["tile"]
		var before: Dictionary = ImprovementOrders.build(
			_play.model, _play.civilian_layer.units, _play.land_works, _play.stockpile(),
			_play.visibility, _play.player_faction, tile, _play.tech_caps(),
			_play.tech_unlocked()
		)
		_say("")
		_say("estates ledger raises %s: %s" % [str(tile), String(before.get("message", ""))])
		_check("the estate the pick names can be raised", bool(before.get("ok", false)))
		if not bool(before.get("ok", false)):
			return
		var worker: CivilianState = _working_at(tile)
		_check("a Builder takes the picked estate", worker != null)
		if worker == null:
			return
		_check("the crew works the ground the line named", worker.work_tile() == tile)
		MapPlayCivilians.select(_play, worker)
		var panel: CivilianPanel = _play.hud.panels.civilian_panel
		_check("a working crew carries no pick", not panel._pick.visible)
		var marks: Array[Dictionary] = CivicGlyphs.marks(
			MapPlayCivilianPick.picks(_play, _play.player_faction),
			_play.civilian_layer.units, _play.model, _play.visibility
		)
		_check("the chart drops the ring once the work is taken", not _rings(marks, tile))
		_check(
			"the sheet says what it is doing",
			panel._status.text.contains("Build improvement")
		)
		return
	_say("no estate pick to press")


## One turn later: the order is still the crew's, and the sheet it was pressed
## from still reads one.
func _turn_pass() -> void:
	_say("")
	var before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	await process_frame
	await process_frame
	_drain_plates()
	# A waiting consent holds the calendar until it is answered; the crown's own
	# choice is another drive's surface (playtest_court_proposal), so this one
	# takes the cheapest answer each banner offers. A war can raise two offers
	# for one court — an embassy and the deeds — so the press repeats.
	var answered: int = 0
	while _play.turn_suspended and _answer_consent() and answered < 4:
		answered += 1
		await process_frame
		await process_frame
		_drain_plates()
	_say("after a turn: turn %d -> %d, suspended %s, %d decision(s) answered" % [
		before, _play.turn, str(_play.turn_suspended), answered,
	])
	_check("the turn runs", _play.turn > before)
	var picks: Dictionary = MapPlayCivilianPick.picks(_play, _play.player_faction)
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or not unit.is_working():
			continue
		_check("a working crew is not offered a pick", not picks.has(unit.id))


## Answers the court's waiting decision, if one is up: the cheapest answer the
## banner offers, so the calendar runs. The crown's own choice is another
## drive's surface (playtest_court_proposal).
func _answer_consent() -> bool:
	var panel: DiplomacyPanel = _play.hud._diplomacy_panel
	if panel == null or panel._call_box == null or not panel._call_box.visible:
		return false
	var buttons: Array[Button] = []
	_collect_buttons(panel._call_box, buttons)
	if buttons.is_empty():
		return false
	var pick: Button = buttons[0]
	for wanted: String in ["Stand aside", "Refuse", "Accept"]:
		for button: Button in buttons:
			if button.text == wanted:
				pick = button
				break
	pick.emit_signal("pressed")
	return true


func _collect_buttons(node: Node, into: Array[Button]) -> void:
	if node is Button:
		into.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, into)


## Skips the battle plates a turn can raise, as a player would.
func _drain_plates() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guardian: int = 0
	while overlay != null and overlay.is_shown() and guardian < 6:
		overlay.skip()
		overlay._on_continue()
		guardian += 1


# --- reads -------------------------------------------------------------------


## How many of the crew's printed orders can be taken here.
func _legal_orders(unit: CivilianState) -> int:
	var count: int = 0
	for option: Dictionary in CivilianWork.options(
		_play.model, unit, _play.land_works, _play.civilian_layer.units,
		_play.stockpile(), _play.visibility, _play.tech_caps(),
		_play.tech_unlocked(), _context()
	):
		if bool(option["ok"]):
			count += 1
	return count


func _working_at(tile: Vector2i) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or not unit.is_working():
			continue
		if unit.work_tile() == tile:
			return unit
	return null


func _rings(marks: Array[Dictionary], tile: Vector2i) -> bool:
	for mark: Dictionary in marks:
		if Vector2i(mark["tile"]) == tile:
			return true
	return false


func _context() -> Dictionary:
	return {"treasury": _play.treasury(), "diplomacy": _play.diplomacy}


## The panel's own rendering of a pick line: first word capitalised, one full
## stop — the sheet prints the court's words, it does not invent them.
func _sentence(line: String) -> String:
	if line.is_empty():
		return line
	return line.substr(0, 1).to_upper() + line.substr(1) + "."


# --- plumbing ----------------------------------------------------------------


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _check(label: String, held: bool) -> void:
	if held:
		_say("  ok   %s" % label)
		return
	_failures += 1
	_say("  FAIL %s" % label)


func _finish() -> void:
	print("\n--- playtest_civilian_pick: %d steps ---" % _steps.size())
	print("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)