extends SceneTree
## Headless free-playtest drive for the campaign's end: the calendar's close, the
## plate it mounts, the race the crown is warned by, and the last turn's news
## (wiki: victory § Victory Check, § Victory Screen, § Calendar campaign end;
## turn-time-mapping § Campaign calendar cap; the-gazette § When it appears).
##
## The endgame is the hardest state in the game to reach: the calendar cap is
## turn 201 and the military bar is 31 Old World provinces, so no hand play and
## no observer run ever arrives. The drive seats the state the way a player would
## arrive at it — the turn number, the holdings — and then closes real turns
## through MapPlayTurn, reading only what the player is shown: the Gazette's age
## tab, the turn's toasts, the campaign-end plate, the end-turn seal and the
## sheets the archive keeps. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_campaign_end.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const SAVE_DIR: String = "user://playtest_campaign_end"
const SLOT: int = 1
const CAP: int = 201

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(SAVE_DIR)
	await _race_pass()
	await _warning_pass()
	await _calendar_pass()
	await _reload_pass()
	await _endless_pass()
	await _victory_pass()
	_finish()


# --- the race as the crown reads it ----------------------------------------


## Turn 0: the Gazette's age tab and the sheet's foot, before anything is at
## stake. Every number here is the read the end-of-turn check acts on.
func _race_pass() -> void:
	_say("")
	_say("=== the age's table, turn 0 ===")
	if not await _open(""):
		return
	_say("seed %s — %s, turn %d, %d Old World provinces" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		VictoryRules.old_world_holdings(_play.world, _play.player_faction),
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	_read_age_tab("turn 0")


## Three provinces short of the bar: the turn's close must name the race, so the
## endgame is never a surprise (wiki: victory § Victory Check).
func _warning_pass() -> void:
	_say("")
	_say("=== three provinces short of the bar ===")
	if not await _open(""):
		return
	var bar: int = VictoryRules.threshold_for(
		_play.player_faction, _play.human_faction_id(), _play.difficulty
	)
	var seated: int = _seat_holdings(_play.player_faction, bar - 3)
	_say("seated %s at %d of %d Old World provinces" % [
		FactionCatalog.name_of(_play.player_faction), seated, bar,
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	if not SaveDrive.advance(_play):
		_say("the calendar never moved — the turn stayed shut")
		return
	_say("turn %d closed; victory %s, halted %s" % [
		_play.turn, str(_play.victory != null), str(_play.campaign_halted),
	])
	for text: String in _toasts():
		_say("toast: %s" % text)
	_say("sheet's foot after the close: %s" % MapPlayGazette.age_line(_play))


# --- the calendar's close ---------------------------------------------------


## Turn 200 closes, then turn 201 — the cap — closes the age. The plate, the
## seal, the toast and the sheets the archive keeps are read at each step.
func _calendar_pass() -> void:
	_say("")
	_say("=== the calendar's close (turn %d) ===" % CAP)
	if not await _open(""):
		return
	_play.turn = CAP - 1
	_say("seated the calendar at turn %d (%d)" % [
		_play.turn, TurnTime.year_for_turn(_play.turn),
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	if not SaveDrive.advance(_play):
		_say("the calendar never moved — the turn stayed shut")
		return
	_say("turn %d closed (%d); halted %s" % [
		_play.turn, TurnTime.year_for_turn(_play.turn), str(_play.campaign_halted),
	])
	_say("sheets filed: %s" % _sheet_turns())
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	if not SaveDrive.advance(_play) and not _play.campaign_halted:
		_say("the cap turn never closed — the turn stayed shut")
		return
	_say("turn %d closed (%d); halted %s, victory %s" % [
		_play.turn, TurnTime.year_for_turn(_play.turn),
		str(_play.campaign_halted), str(_play.victory != null),
	])
	_say("sheets filed: %s" % _sheet_turns())
	for text: String in _toasts():
		_say("toast: %s" % text)
	_read_plate("the calendar's close")
	_say("end-turn seal: %s, disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	_read_age_tab("at the close")
	# A closed campaign takes no more turns; the seal's own press says why.
	var before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_say("a further press: turn %d (was %d)" % [_play.turn, before])
	for text: String in _toasts():
		_say("toast: %s" % text)
	# The plate steps aside and the final turn's sheet is still there to read.
	_play.hud.victory_overlay.dismiss()
	_say("plate after View final state: up %s" % str(_play.hud.victory_overlay.is_shown()))
	MapPlayGazette.open_archive(_play)
	_play.hud.gazette_plate._go(GazettePlate.Mode.SHEET)
	_say("the last sheet, read after the plate steps aside:")
	for line: String in _sheet_lines():
		_say("  sheet: %s" % line)
	_play.hud.gazette_plate.dismiss()


## The halted campaign saved and loaded: the plate returns, the seal stays shut
## and the archive still holds the last turn's sheet (wiki: victory § Persistence).
func _reload_pass() -> void:
	_say("")
	_say("=== a halted campaign, saved and loaded ===")
	if _screen == null or _play == null:
		_say("no halted campaign to save")
		return
	_screen.save_dir = SAVE_DIR
	_say("save: %s" % SaveDrive.save_slot(_screen, SLOT))
	var sheets_before: String = _sheet_turns()
	var loaded: MapScreen = SaveDrive.load_slot(_screen, _main, SLOT)
	if loaded == null:
		_say("the load was refused")
		return
	_screen = loaded
	_play = loaded.play
	_say("after the load: turn %d, halted %s, victory %s" % [
		_play.turn, str(_play.campaign_halted), str(_play.victory != null),
	])
	_say("sheets filed: %s (before the save: %s)" % [_sheet_turns(), sheets_before])
	_read_plate("after the load")
	_say("end-turn seal: %s, disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])


## An Endless campaign sails past the cap: no plate, no halt, and the age tab
## says the calendar never closes (wiki: victory § Endless campaign).
func _endless_pass() -> void:
	_say("")
	_say("=== an endless campaign at the cap ===")
	if not await _open(""):
		return
	_play.infinite_mode = true
	_play.turn = CAP
	_say("seated the calendar at turn %d, endless %s" % [
		_play.turn, str(_play.infinite_mode),
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	if not SaveDrive.advance(_play):
		_say("the calendar never moved — the turn stayed shut")
		return
	_say("turn %d closed (%d); halted %s, plate up %s" % [
		_play.turn, TurnTime.year_for_turn(_play.turn),
		str(_play.campaign_halted), str(_play.hud.is_victory_shown()),
	])
	_say("end-turn seal: %s, disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])
	_read_age_tab("endless, past the cap")


# --- the military plate -----------------------------------------------------


## A rival on the bar: the military plate names the winner, the holdings and the
## turn, and the crown's own sheet says who took the age.
func _victory_pass() -> void:
	_say("")
	_say("=== a rival on the bar ===")
	if not await _open(""):
		return
	var rival: int = _rival()
	var seated: int = _seat_holdings(rival, VictoryRules.MILITARY_THRESHOLD)
	_say("seated %s at %d Old World provinces" % [
		FactionCatalog.name_of(rival), seated,
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	if not SaveDrive.advance(_play):
		_say("the calendar did not advance: turn %d, victory %s, halted %s" % [
			_play.turn, str(_play.victory != null), str(_play.campaign_halted),
		])
		if _play.victory == null:
			_say("nothing was decided and nothing waits on the court")
			return
	_say("turn %d closed; victory %s, halted %s" % [
		_play.turn, str(_play.victory != null), str(_play.campaign_halted),
	])
	_say("sheets filed: %s" % _sheet_turns())
	for text: String in _toasts():
		_say("toast: %s" % text)
	_read_plate("a rival on the bar")
	_say("end-turn seal: %s, disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])
	# The winning turn's own news, read once the plate steps aside.
	_play.hud.victory_overlay.dismiss()
	MapPlayGazette.open_archive(_play)
	_play.hud.gazette_plate._go(GazettePlate.Mode.SHEET)
	_say("the winning turn's sheet:")
	for line: String in _sheet_lines():
		_say("  sheet: %s" % line)
	_play.hud.gazette_plate.dismiss()


# --- reads ------------------------------------------------------------------


func _open(advanced: String) -> bool:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, advanced)
	if _screen == null:
		_say("the map never opened")
		return false
	_main = _screen.get_parent()
	_play = _screen.play
	return true


## The campaign-end plate as the player reads it: every visible line, top down.
func _read_plate(label: String) -> void:
	var plate: VictoryOverlay = _play.hud.victory_overlay
	if plate == null:
		_say("%s: no plate" % label)
		return
	_say("%s: plate up %s" % [label, str(plate.is_shown())])
	if not plate.is_shown():
		return
	for line: String in _plate_lines(plate):
		_say("  plate: %s" % line)


func _plate_lines(plate: VictoryOverlay) -> Array[String]:
	var out: Array[String] = []
	for node: Node in [plate._title, plate._winner, plate._detail, plate._tagline, plate._continue]:
		if node is Label:
			out.append((node as Label).text)
		elif node is Button:
			out.append("[%s]" % (node as Button).text)
	return out


## The Gazette's age tab, opened the way the cartouche seal opens it.
func _read_age_tab(label: String) -> void:
	MapPlayGazette.open_archive(_play)
	_play.hud.gazette_plate._go(GazettePlate.Mode.AGE)
	var room: AgeRoom = _play.hud.gazette_plate._age_room
	_say("%s: the age tab (rows %d, calendar '%s')" % [
		label, room.rows.size(), room.calendar,
	])
	for line: String in _room_lines(room):
		_say("  age: %s" % line)
	_play.hud.gazette_plate.dismiss()


func _room_lines(room: AgeRoom) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(room, "", out)
	return out


## The Gazette plate's visible lines — the sheet the crown actually reads.
func _sheet_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud.gazette_plate == null:
		return out
	SaveDrive.collect_text(_play.hud.gazette_plate._body, "", out)
	return out


func _toasts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud == null or _play.hud.despatches == null:
		return out
	SaveDrive.collect_text(_play.hud.despatches, "", out)
	return out


func _sheet_turns() -> String:
	if _play == null or _play.gazette == null:
		return "no gazette"
	var turns: PackedStringArray = PackedStringArray()
	for sheet: Dictionary in _play.gazette.history():
		turns.append(str(int(sheet.get("turn", 0))))
	return ", ".join(turns) if not turns.is_empty() else "none"


# --- seating ----------------------------------------------------------------


## Hands `faction` Old World provinces until it holds `target`, taking them from
## whoever holds them now. Returns the holdings it ends on.
func _seat_holdings(faction: int, target: int) -> int:
	var model: MapModel = _play.world.region(WorldMap.OLD_WORLD)
	var held: int = VictoryRules.old_world_holdings(_play.world, faction)
	for province: ProvinceState in model.provinces:
		if held >= target:
			break
		if province.owner == faction:
			continue
		province.owner = faction
		held += 1
	return VictoryRules.old_world_holdings(_play.world, faction)


func _rival() -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != _play.player_faction:
			return faction
	return _play.player_faction


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_campaign_end: %d steps ---" % _steps.size())
	quit()
