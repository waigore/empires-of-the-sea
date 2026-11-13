extends SceneTree
## Headless playtest drive for a court that loses its seat (wiki:
## capital-and-connectivity § Capital loss and reassignment; victory
## § Great Power defeat). Two passes read only what a player reads:
##
##   1. `_move_pass` — the crown still holds a province, so its court moves.
##      Reads the despatches the turn raised, the new seat's name, the old
##      seat's capital flag, the home squadron's port, the purse figure and the
##      Gazette's sheet for the turn.
##   2. `_fall_pass` — the crown is stripped to its seat and the seat is
##      stormed: reads the defeat plate, whether turns stay shut, and whether
##      the defeated campaign saves and loads back defeated.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_capital_move.gd
##
## Armies are seated by the harness (the same scenario seat the rules tests and
## `playtest_combat_chain` use); combat, capital verdicts, port settlement, the
## turn ladder and the save browser are the game's own.

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const DIR: String = "user://playtest_capital_move"
const SLOT: int = 1

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _main: Node = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_screen.save_dir = DIR
	_play = _screen.play
	_say("seed %s — %s, turn %d, %d provinces in %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		CapitalLoss.owned_provinces(_play.model, _play.player_faction).size(),
		FactionCatalog.region_label(_play.region_index),
	])
	_say("seat: %s; home squadron: %s" % [
		_seat_name(), _home_squadron(),
	])
	var rivals: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rivals.append(gp)
	if rivals.size() < 2:
		_say("need two rival Great Powers")
		_finish()
		return
	_move_pass(rivals[0])
	await _fall_pass(rivals[0])
	_finish()


# --- passes ----------------------------------------------------------------


## The common branch: the seat falls while the court still holds provinces, so
## the crown keeps playing from a new seat. Everything the move changes must be
## readable from the court's own surfaces.
func _move_pass(rival: int) -> void:
	_say("")
	var seat: int = _play.capital_province
	DiplomacyRules.declare_war(_play.diplomacy, rival, _play.player_faction)
	_say("--- capital loss, court survives: %s storms %s ---" % [
		FactionCatalog.name_of(rival), _play.model.province_name(seat),
	])
	_play.army_layer.armies.clear()
	_play.model.province_data(seat).fort_level = 0
	_seat(_play.player_faction, seat, 1, 210)
	_seat(rival, seat, 24, 215, true)
	# A second front in the same turn: two battles raise two despatches under
	# one plate, which is where the held-news cap starts spending lines.
	var other: int = _other_holdings(seat)
	if other >= 0:
		_play.model.province_data(other).fort_level = 0
		_seat(_play.player_faction, other, 1, 216)
		_seat(rival, other, 14, 217, true)
		_say("and a second front at %s" % _play.model.province_name(other))
	_say("before: own %d provinces; purse %d, %+d per turn; income promise %d" % [
		CapitalLoss.owned_provinces(_play.model, _play.player_faction).size(),
		_play.treasury(), _play.income, _play.economy.readings.projected_income(),
	])
	var seen: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen):
		_say("  · %s" % line)
	_say("after: seat %s (was %s); old seat owned by %s, capital flag %s; new seat capital %s, town level %d" % [
		_seat_name(), _play.model.province_name(seat),
		FactionCatalog.name_of(_play.model.province_owner(seat)),
		str(_play.model.province_data(seat).capital),
		str(_play.model.province_data(_play.capital_province).capital),
		_play.model.province_data(_play.capital_province).town_development,
	])
	_say("home squadron after the move: %s" % _home_squadron())
	_say("new seat's water: %s" % _seat_water())
	_say("purse after: %d, %+d per turn (promise %d)" % [
		_play.treasury(), _play.income, _play.economy.readings.projected_income(),
	])
	_say("gazette sheet for turn %d:" % _play.gazette.sheets.back().get("turn", -1))
	var sheet: Dictionary = {} if _play.gazette.sheets.is_empty() else _play.gazette.sheets.back()
	for item: Variant in sheet.get("items", []) as Array:
		_say("  · %s" % String((item as Dictionary).get("text", "")))
	_say("race line: %s" % MapPlayGazette.age_line(_play))


## The defeat branch: only the seat is left, so the storm ends the campaign.
func _fall_pass(rival: int) -> void:
	_say("")
	var seat: int = _play.capital_province
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction and province.id != seat:
			province.owner = rival
	_say("--- terminal fall: %s left holding only %s ---" % [
		FactionCatalog.name_of(_play.player_faction), _play.model.province_name(seat),
	])
	_play.army_layer.armies.clear()
	_play.model.province_data(seat).fort_level = 0
	_seat(_play.player_faction, seat, 1, 220)
	_seat(rival, seat, 24, 225, true)
	var seen_before: int = _toast_count()
	_take_turn()
	_say("court news raised this turn:")
	for line: String in _toasts_since(seen_before):
		_say("  · %s" % line)
	_say("campaign over: %s; defeat: %s" % [
		str(_play.campaign_over()), _defeat_text(),
	])
	var overlay: VictoryOverlay = _play.hud.victory_overlay
	if overlay != null:
		var plate: PackedStringArray = PackedStringArray()
		SaveDrive.collect_text(overlay, "", plate)
		_say("defeat plate: %s" % " | ".join(plate))
	var before_turn: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_say("pressing Next Turn after defeat: turn %d (was %d)" % [_play.turn, before_turn])
	_say("save: %s" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_say("the load replaced the screen with something else")
		return
	_say("loaded a screen; reading it")
	_play = _screen.play
	await process_frame
	_say("a frame later")
	_say("after the load: turn %d, campaign over %s, defeat %s" % [
		_play.turn, str(_play.campaign_over()), _defeat_text(),
	])
	overlay = _play.hud.victory_overlay
	if overlay != null:
		var plate: PackedStringArray = PackedStringArray()
		SaveDrive.collect_text(overlay, "", plate)
		_say("plate after the load: %s" % " | ".join(plate))
	var before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_say("Next Turn after the load: turn %d (was %d)" % [_play.turn, before])


# --- turn ladder -----------------------------------------------------------


## One calendar turn through MapPlayTurn, reading every battle plate the turn
## raises and answering whatever consent decision it stops on.
func _take_turn() -> void:
	var guardian: int = 0
	var was: int = _play.turn
	while guardian < 8:
		MapPlayTurn.end_turn(_play)
		var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
		while overlay != null and overlay.is_shown() and guardian < 12:
			overlay.skip()
			overlay._on_continue()
			guardian += 1
		if _play.turn != was or _play.campaign_over():
			return
		if not SaveDrive.answer_pending(_play):
			return
		guardian += 1


func _toasts_since(start: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var box: VBoxContainer = _play.hud._toast_box
	if box != null:
		for index in range(start, box.get_child_count()):
			SaveDrive.collect_text(box.get_child(index), "", lines)
	lines.append_array(_play.hud.despatches.waiting())
	return lines


func _toast_count() -> int:
	var box: VBoxContainer = _play.hud._toast_box
	return box.get_child_count() if box != null else 0


## The sea zones the crown's seat borders, or "inland" — the water a re-moored
## home squadron would lie in.
func _seat_water() -> String:
	if _play.capital_province < 0:
		return "no seat"
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, _play.capital_province)
	if zones.is_empty():
		return "inland"
	var names: PackedStringArray = PackedStringArray()
	for zone: int in zones:
		names.append(_play.model.sea_zone_name(zone))
	return ", ".join(names)


## Another province the crown holds in this region, or -1.
func _other_holdings(seat: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction and province.id != seat:
			return province.id
	return -1


func _seat_name() -> String:
	if _play.capital_province < 0:
		return "none"
	return _play.model.province_name(_play.capital_province)


## The crown's in-port squadrons and where they lie.
func _home_squadron() -> String:
	var parts: PackedStringArray = []
	if _play.ship_layer == null:
		return "no fleet layer"
	var roster: Array = _play.ship_layer.regions.value(_play.region_index, [])
	for raw: Variant in roster:
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != _play.player_faction:
			continue
		parts.append("%s %d hulls in port" % [
			_play.model.province_name(fleet.province) if fleet.is_in_port()
			else _play.model.sea_zone_name(fleet.sea_zone),
			fleet.ship_count(),
		])
	return ", ".join(parts) if not parts.is_empty() else "no squadron"


func _defeat_text() -> String:
	return "none" if _play.defeat == null else _play.defeat.summary()


# --- seating ---------------------------------------------------------------


func _seat(owner: int, province: int, count: int, offset: int, moved: bool = false) -> void:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army + offset,
		owner,
		province,
		false,
		types,
		_play.army_layer.next_regiment + offset
	)
	army.moved = moved
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_capital_move: %d steps ---" % _steps.size())
	quit()
