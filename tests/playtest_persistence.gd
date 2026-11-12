extends SceneTree
## Headless playtest drive for campaign persistence: the player sets the crown's
## battle plan and issues orders, saves from the pause menu, loads the slot back,
## and then walks the endings a save must carry (decided, defeated, halted) plus
## the slots that cannot be read (wiki: campaign-persistence). Not a CI gate —
## run it by hand:
##   godot --headless --path . --script res://tests/playtest_persistence.gd
##
## Every pass goes through the game's own paths: the pause menu's save/load
## browser writes and picks the slot, the router rebuilds the screen, and the
## reads are the labels the player sees (army dossier, victory plate, end-turn
## seal, slot rows).

const Launch = preload("res://tests/playtest_launch.gd")
const SaveDrive = preload("res://tests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
## A directory of its own, so a hand run never touches the player's slots.
const DIR: String = "user://playtest_persistence"
const SLOT: int = 1
const SLOT_ENDING: int = 2
const SLOT_UNREADABLE: int = 3
const SLOT_CORRUPT: int = 4

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_clean_dir()
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_screen.save_dir = DIR
	_play = _screen.play
	_say("seed %s — %s, turn %d, %d provinces in %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.model.province_count(), FactionCatalog.region_label(_play.region_index),
	])
	await _orders_pass()
	_ending_pass("a decided campaign", "victory")
	_ending_pass("a defeated campaign", "defeat")
	_ending_pass("a halted campaign", "halted")
	_unreadable_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## The crown's plan and the orders already issued this turn: the plan is set
## with the dossier's own tap, a civilian is put to work, and a squadron is
## sent; the save must bring all of it back (wiki: campaign-persistence
## § Load and resume, § Snapshot contract — crown battle plan).
func _orders_pass() -> void:
	_say("")
	_say("--- the plan and the orders: save, then load the slot ---")
	var army: ArmyState = _player_army()
	if army == null:
		_say("no player army to open the dossier on")
		return
	MapPlayArmies.cycle_plan(_play, army)
	await process_frame
	_say("after the dossier tap: %s (toast: %s)" % [_play.battle_plan, _last_toast()])
	_say("dossier reads: %s" % _plan_line())
	var unit: CivilianState = _player_civilian()
	var order: String = ""
	var work_id: int = -1
	if unit != null:
		work_id = unit.id
		# The marker tap: the layer owns the selection and the screen answers it.
		_play.civilian_layer.select(unit)
		order = _legal_work(unit)
		if not order.is_empty():
			MapPlayCivilians.on_action(_play, order)
		await process_frame
		_say("civilian order: %s %s — working %s for %d turn(s) (toast: %s)" % [
			unit.display_name(),
			CivilianWork.label(order) if not order.is_empty() else "has no legal order",
			str(unit.is_working()), unit.remaining_turns(), _last_toast(),
		])
	var fleet: FleetState = _player_fleet()
	if fleet != null:
		fleet.moved = true
		_say("squadron %d sent: moved %s" % [fleet.id, str(fleet.moved)])
	var treasury: int = _play.treasury()
	_say("before the save: turn %d, treasury %d, plan %s" % [
		_play.turn, treasury, _play.battle_plan,
	])

	_save(SLOT)
	_load(SLOT)
	if _screen == null:
		_say("the load replaced the screen with something else")
		return
	_play = _screen.play
	_say("after the load: turn %d, treasury %d, plan %s" % [
		_play.turn, _play.treasury(), _play.battle_plan,
	])
	MapPlayArmies.show_panel(_play, _player_army())
	_say("dossier reads: %s" % _plan_line())
	var loaded_unit: CivilianState = _civilian_by_id(work_id)
	_say("the same civilian after the load: %s — working %s, %d turn(s) left" % [
		loaded_unit.display_name() if loaded_unit != null else "missing",
		str(loaded_unit.is_working()) if loaded_unit != null else "—",
		loaded_unit.remaining_turns() if loaded_unit != null else -1,
	])
	var loaded_fleet: FleetState = _player_fleet()
	_say("squadron order: moved %s" % (
		str(loaded_fleet.moved) if loaded_fleet != null else "no squadron"
	))


## An ending a save must carry: the state is set, the slot written, the screen
## rebuilt from it, and the plate plus the end-turn seal read back (wiki:
## campaign-persistence § Load and resume; victory).
func _ending_pass(label: String, kind: String) -> void:
	_say("")
	_say("--- %s: save, then load ---" % label)
	_reset_ending()
	match kind:
		"victory":
			_play.victory = VictoryState.military(_play.player_faction, _play.turn)
		"defeat":
			_play.defeat = DefeatState.terminal_fall(_play.player_faction, 2, _play.turn)
		"halted":
			_play.campaign_halted = true
	_say("saved as: %s; campaign over %s" % [kind, str(_play.campaign_over())])
	_save(SLOT_ENDING)
	_load(SLOT_ENDING)
	if _screen == null:
		_say("the load replaced the screen with something else")
		return
	_play = _screen.play
	_say("after the load: victory %s, defeat %s, halted %s" % [
		str(_play.victory != null), str(_play.defeat != null), str(_play.campaign_halted),
	])
	var plate: VictoryOverlay = _play.hud.victory_overlay
	_say("plate up: %s; title: %s" % [
		str(plate != null and plate.is_shown()),
		_plate_title(plate) if plate != null else "—",
	])
	_say("end-turn seal: %s, disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])


## Slots that cannot be read: one written by a newer build, one whose file is
## not a save at all. The browser must not call either of them empty, and a
## refused load must leave the running campaign where it was (wiki:
## campaign-persistence § Load and resume — announced, never silent).
func _unreadable_pass() -> void:
	_say("")
	_say("--- slots that cannot be read ---")
	_reset_ending()
	var data: Dictionary = SaveCodec.capture(_play)
	data["version"] = SaveCodec.VERSION + 1
	SaveStore.write(SaveStore.path_for(SLOT_UNREADABLE, DIR), data)
	var file := FileAccess.open(SaveStore.path_for(SLOT_CORRUPT, DIR), FileAccess.WRITE)
	if file != null:
		file.store_string("not a save at all")
		file.close()
	_say("slots on disk: newer-build %s, corrupt %s" % [
		str(SaveStore.has_slot(SLOT_UNREADABLE, DIR)),
		str(SaveStore.has_slot(SLOT_CORRUPT, DIR)),
	])
	var turn_before: int = _play.turn
	_screen.game_menu.open()
	_screen.game_menu.open_load()
	_read_rows("in-game load browser")
	var newer: Button = _row(SLOT_UNREADABLE)
	if newer != null:
		_say("pressing the newer-build slot: \"%s\"" % newer.text.replace("\n", " / "))
		newer.emit_signal("pressed")
		_say("browser says: \"%s\"" % _screen.game_menu.browser._status.text)
	var corrupt: Button = _row(SLOT_CORRUPT)
	if corrupt != null:
		_say("pressing the corrupt slot: \"%s\"" % corrupt.text.replace("\n", " / "))
		corrupt.emit_signal("pressed")
		_say("browser says: \"%s\"" % _screen.game_menu.browser._status.text)
	_say("the player is still in the campaign: %s (screen %s)" % [
		str(_main.current_screen != null),
		"map" if _main.current_screen != null else "title screen",
	])
	if _main.current_screen != null:
		_say("turn unchanged: %d -> %d" % [turn_before, _main.current_screen.play.turn])
	# A save into the corrupt slot must not silently lose the file it holds.
	_screen.game_menu.open_save()
	var save_row: Button = _row(SLOT_CORRUPT)
	if save_row != null:
		_say("save browser row over the corrupt file: \"%s\"" % save_row.text.replace("\n", " / "))
		save_row.emit_signal("pressed")
		_say("save browser after one press: \"%s\"" % _screen.game_menu.browser._status.text)
	_screen.game_menu.close()


# --- save and load through the pause menu ----------------------------------


func _save(slot: int) -> void:
	var status: String = SaveDrive.save_slot(_screen, slot)
	_say("save: \"%s\" (slot on disk: %s)" % [
		status, str(SaveStore.has_slot(slot, DIR)),
	])


func _load(slot: int) -> void:
	var button: Button = SaveDrive.row(_screen, slot)
	if button != null:
		_say("load row: \"%s\" (disabled %s)" % [
			button.text.replace("\n", " / "), str(button.disabled),
		])
	_screen = SaveDrive.load_slot(_screen, _main, slot)


func _row(slot: int) -> Button:
	return SaveDrive.row(_screen, slot)


func _read_rows(label: String) -> void:
	var browser: SaveBrowser = _screen.game_menu.browser
	_say("%s:" % label)
	for button: Button in browser.slot_buttons:
		_say("  \"%s\"%s" % [
			button.text.replace("\n", " / "), " (disabled)" if button.disabled else "",
		])


## Clears whatever ending the previous pass left, so the next case starts from
## a campaign whose calendar is open again. The save/load under test already
## happened; this only reaches the next case.
func _reset_ending() -> void:
	_play.victory = null
	_play.defeat = null
	_play.campaign_halted = false
	_play.hud.set_campaign_over(false)
	if _play.hud.victory_overlay != null and _play.hud.victory_overlay.is_shown():
		_play.hud.victory_overlay.dismiss()


# --- reads -----------------------------------------------------------------


## The dossier line the player taps to cycle the crown's plan.
func _plan_line() -> String:
	var parts: PackedStringArray = []
	_collect_text(_play.hud.panels.army_panel, "Crown battle plan:", parts)
	return parts[0] if not parts.is_empty() else "no plan line"


func _plate_title(plate: VictoryOverlay) -> String:
	var parts: PackedStringArray = []
	_collect_text(plate, "", parts)
	return " / ".join(parts.slice(0, 4)) if not parts.is_empty() else "no title"


func _collect_text(node: Node, prefix: String, into: PackedStringArray) -> void:
	SaveDrive.collect_text(node, prefix, into)


# --- fixtures --------------------------------------------------------------


func _player_army() -> ArmyState:
	for army: ArmyState in _play.army_layer.armies:
		if army.owner == _play.player_faction and army.is_home_army():
			return army
	for army: ArmyState in _play.army_layer.armies:
		if army.owner == _play.player_faction:
			return army
	return null


func _player_civilian() -> CivilianState:
	var fallback: CivilianState = null
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.owner != _play.player_faction or unit.is_working():
			continue
		if fallback == null:
			fallback = unit
		if not _legal_work(unit).is_empty():
			return unit
	return fallback


func _civilian_by_id(id: int) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit.id == id:
			return unit
	return null


func _player_fleet() -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction:
			return fleet
	return null


## The first work order this unit could legally start right now, chosen with the
## same options the dossier lists (wiki: civilian-units § Work Order Summary).
func _legal_work(unit: CivilianState) -> String:
	for option: Dictionary in CivilianWork.options(
		_play.model, unit, _play.land_works, _play.civilian_layer.units,
		_play.stockpile(), _play.visibility, _play.tech_caps(), _play.tech_unlocked()
	):
		if bool(option.get("ok", false)):
			return String(option.get("action", ""))
	return ""


func _last_toast() -> String:
	if _play.hud._toast_box == null:
		return "none"
	var parts: PackedStringArray = []
	_collect_text(_play.hud._toast_box, "", parts)
	return parts[parts.size() - 1] if not parts.is_empty() else "none"


func _clean_dir() -> void:
	SaveDrive.clean_dir(DIR)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_persistence: %d steps ---" % _steps.size())
	_clean_dir()
	quit()
