extends SceneTree
## Headless free-playtest drive for the crown's defeat: the turn that takes the
## capital, the plate it mounts, the seal, the news the archive keeps and the
## save that reopens it (wiki: victory § Great Power defeat, § Victory Screen
## § Content (defeat), § Persistence; capital-and-connectivity § Capital loss;
## the-gazette § When it appears).
##
## Terminal fall is the hardest state in the game to reach: it needs the crown's
## capital lost while it holds nothing else in its own region, so no hand play
## and no observer run ever arrives. The drive seats the state a player would
## arrive at — the capital is the crown's last province in its region — then lets
## a rival host at war take the seat in a real Combat phase and closes real turns
## through MapPlayTurn, reading only what the crown is shown: the despatches, the
## Quick Battle plate, the campaign-end plate, the end-turn seal and the sheets
## the Gazette keeps. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_defeat.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const SAVE_DIR: String = "user://playtest_defeat"
const SLOT: int = 1
## A host that can reach a capital's parapet: shot to break the wall, foot and
## horse to hold what is left.
const HOST: Array[String] = [
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"musketeers", "musketeers", "musketeers", "musketeers", "musketeers",
	"halberdiers", "halberdiers", "halberdiers", "halberdiers", "halberdiers",
	"halberdiers", "hussars", "hussars", "hussars", "hussars",
	"siege_guns", "siege_guns", "siege_guns", "field_artillery", "field_artillery",
]

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _main: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(SAVE_DIR)
	await _fall_pass()
	await _archive_pass()
	await _reload_pass()
	await _seal_pass()
	await _rival_race_pass()
	_finish()


# --- the fall ---------------------------------------------------------------


## The crown's last province in its region is its capital; a rival host at war
## takes it in a real Combat phase. Everything after the battle is read as the
## crown reads it: the despatch, the plate, the seal and the sheets filed.
func _fall_pass() -> void:
	_say("")
	_say("=== the turn the capital falls ===")
	if not await _open(AdvancedStart.TURNS100):
		return
	var player: int = _play.player_faction
	_say("%s, turn %d, purse %d, %d Old World provinces" % [
		FactionCatalog.name_of(player), _play.turn, _play.treasury(),
		VictoryRules.old_world_holdings(_play.world, player),
	])
	_say("plate before the fall: up %s; seal \\\"%s\\\" disabled %s" % [
		str(_play.hud.is_victory_shown()), _play.hud._end_turn_button.text,
		str(_play.hud._end_turn_button.disabled),
	])
	_say("sheets filed before the fall: %s" % _sheet_turns())
	var seat: Dictionary = _strip_to_seat(player)
	if seat.is_empty():
		_say("the crown could not be seated on its last province")
		return
	var capital: int = int(seat["province"])
	_shrink_garrison(player, capital)
	_say("the crown's last province in its region: %s (fort %d, %d defenders)" % [
		_play.model.province_name(capital),
		FortRules.level_at(_play.model, capital),
		_defenders(capital),
	])
	var foe: ArmyState = _march_on_seat(capital, int(seat["rival"]))
	if foe == null:
		_say("no rival host could be brought onto the seat")
		return
	_say("the host on the seat: %d regiments (%s)" % [foe.count(), _types(foe)])
	await _clear_toasts()
	var closed: bool = _take_turn()
	_say("the turn %s; calendar at %d, defeat %s, victory %s" % [
		"closed" if closed else "never closed", _play.turn,
		str(_play.defeat != null), str(_play.victory != null),
	])
	_say("%s after the turn: held by %s; the crown holds %d in its region" % [
		_play.model.province_name(capital),
		FactionCatalog.name_of(_play.model.province_owner(capital)),
		_holdings_in(_play.model, player),
	])
	for text: String in _toasts():
		if text.contains("Madrid") or text.contains("falls") or text.contains("holds"):
			_say("despatch: %s" % text)
	if _play.defeat == null:
		_say("the crown did not fall: no defeat was recorded")
		_say("seal: \\\"%s\\\" disabled %s; campaign over %s" % [
			_play.hud._end_turn_button.text,
			str(_play.hud._end_turn_button.disabled),
			str(_play.campaign_over()),
		])
		for text: String in _toasts():
			_say("toast: %s" % text)
		return
	_say("defeat record: %s" % _play.defeat.summary())
	_say("conqueror's id %d, turn %d" % [
		_play.defeat.conqueror_player_id, _play.defeat.turn_number,
	])
	_say("campaign over %s, victory %s" % [
		str(_play.campaign_over()), str(_play.victory != null),
	])
	for text: String in _toasts():
		_say("toast: %s" % text)
	_say("sheets filed after the fall: %s" % _sheet_turns())
	_read_plate("the fallen crown")
	_say("seal: \\\"%s\\\" disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])
	_say("sheet's foot: %s" % MapPlayGazette.age_line(_play))
	_release_plate()


# --- the news the archive keeps --------------------------------------------


## The plate steps aside; the crown reads the Gazette for the turn that took its
## seat (wiki: the-gazette § When it appears; victory § Victory Screen).
func _archive_pass() -> void:
	_say("")
	_say("=== the archive after the fall ===")
	if _play == null or _play.defeat == null:
		_say("no fallen crown to read — the archive pass is skipped")
		return
	_say("plate up after View final state: %s" % str(_play.hud.victory_overlay.is_shown()))
	MapPlayGazette.open_archive(_play)
	if _play.hud.gazette_plate == null:
		_say("no Gazette plate to open")
		return
	_say("archive open %s; it holds %d sheet(s)" % [
		str(_play.hud.gazette_plate.is_shown()), _sheet_count(),
	])
	_play.hud.gazette_plate._go(GazettePlate.Mode.SHEET)
	_say("the last sheet, read after the plate steps aside:")
	var lines: PackedStringArray = _sheet_lines()
	if lines.is_empty():
		_say("  (no sheet at all)")
	for line: String in lines:
		_say("  sheet: %s" % line)
	_play.hud.gazette_plate.dismiss()


# --- the save that reopens it ----------------------------------------------


## A defeated campaign saved and loaded: the plate returns, the seal stays shut
## and the turn number is the one that fell (wiki: victory § Persistence).
func _reload_pass() -> void:
	_say("")
	_say("=== a fallen campaign, saved and loaded ===")
	if _screen == null or _play == null:
		_say("no campaign to save")
		return
	_screen.save_dir = SAVE_DIR
	_say("save: %s" % SaveDrive.save_slot(_screen, SLOT))
	var conquered: int = _play.defeat.conqueror_player_id if _play.defeat != null else -1
	var fallen_turn: int = _play.defeat.turn_number if _play.defeat != null else -1
	var sheets_before: String = _sheet_turns()
	var loaded: MapScreen = SaveDrive.load_slot(_screen, _main, SLOT)
	if loaded == null:
		_say("the load was refused")
		return
	_screen = loaded
	_play = loaded.play
	_say("after the load: turn %d, defeat %s, victory %s, campaign over %s" % [
		_play.turn, str(_play.defeat != null), str(_play.victory != null),
		str(_play.campaign_over()),
	])
	if _play.defeat != null:
		_say("the loaded record: %s (saved: %s falls to %s, turn %d)" % [
			_play.defeat.summary(),
			FactionCatalog.name_of(_play.defeat.fallen_player_id),
			FactionCatalog.name_of(conquered), fallen_turn,
		])
	_say("sheets filed: %s (before the save: %s)" % [_sheet_turns(), sheets_before])
	_read_plate("after the load")
	_say("seal: \\\"%s\\\" disabled %s" % [
		_play.hud._end_turn_button.text, str(_play.hud._end_turn_button.disabled),
	])


# --- the seal ---------------------------------------------------------------


## The fallen crown presses the seal again: the rules refuse the turn and the
## court is told why in words that name its own end (wiki: victory § Great
## Power defeat, § Victory Screen).
func _seal_pass() -> void:
	_say("")
	_say("=== the seal after the fall ===")
	if _play == null or _play.defeat == null:
		_say("no fallen crown — the seal pass is skipped")
		return
	_read_plate("before the press")
	await _clear_toasts()
	var before: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_release_plate()
	_say("a further press: turn %d (was %d), defeat %s" % [
		_play.turn, before, str(_play.defeat != null),
	])
	for text: String in _toasts():
		_say("toast: %s" % text)


# --- defeat before the race -------------------------------------------------


## A rival on the bar in the same turn the crown falls: the fall already closed
## the session, so no military-victory plate is opened for another crown (wiki:
## victory § Victory Check § Defeat interaction).
func _rival_race_pass() -> void:
	_say("")
	_say("=== a rival on the bar in the turn the crown falls ===")
	if not await _open(AdvancedStart.TURNS100):
		return
	var player: int = _play.player_faction
	var rival: int = _rival()
	var seat: Dictionary = _strip_to_seat(player)
	if seat.is_empty():
		_say("the crown could not be seated on its last province")
		return
	var capital: int = int(seat["province"])
	_shrink_garrison(player, capital)
	var held: int = _grant_rival(rival, VictoryRules.MILITARY_THRESHOLD)
	_say("%s seated at %d Old World provinces; the bar is %d" % [
		FactionCatalog.name_of(rival), held, VictoryRules.MILITARY_THRESHOLD,
	])
	var foe: ArmyState = _march_on_seat(capital, rival)
	if foe == null:
		_say("no rival host could be brought onto the seat")
		return
	await _clear_toasts()
	_take_turn()
	_say("calendar at %d: defeat %s, victory %s" % [
		_play.turn, str(_play.defeat != null), str(_play.victory != null),
	])
	_read_plate("the deciding turn")
	for text: String in _toasts():
		_say("toast: %s" % text)
	_release_plate()


# --- seating ----------------------------------------------------------------


## Leaves the crown holding only its capital in its own region, so losing the
## seat is terminal fall and not a reassignment (wiki: capital-and-connectivity
## § Capital loss; victory § Great Power defeat). Returns {province, rival}.
func _strip_to_seat(fallen: int) -> Dictionary:
	var model: MapModel = _play.world.region(FactionCatalog.region_of(fallen))
	if model == null:
		return {}
	var capital: int = CapitalLoss.seat_of(model, fallen)
	if capital < 0:
		return {}
	var stripped: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == fallen and province.id != capital:
			province.owner = MapModel.NO_ID
			stripped += 1
	var rival: int = _seat_rival(capital)
	if rival < 0:
		return {}
	_say("stripped %d province(s); the crown holds %d in its region" % [
		stripped, _holdings_in(model, fallen),
	])
	return {"province": capital, "rival": rival}


## The Great Power that borders the seat, or any rival when it borders none.
func _seat_rival(capital: int) -> int:
	var rival: int = -1
	for neighbour: int in MapGeo.province_neighbors(_play.model, capital):
		var owner: int = _play.model.province_owner(neighbour)
		if owner == _play.player_faction or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
			rival = owner
			break
	if rival >= 0:
		return rival
	return _rival()


## The court's own guard at the seat: reduced to a token levy so the pass reads
## a capital taken, not a wall that outlasts three rounds (a Quick Battle never
## captures in three rounds while the garrison still stands).
func _shrink_garrison(fallen: int, capital: int) -> void:
	var home: ArmyState = ArmyTraining.home_army(_play.army_layer.armies, fallen)
	if home == null:
		return
	var ids: Array[String] = ["guard_1"]
	var types: Dictionary = {"guard_1": "peasant_levies"}
	home.set_regiments(ids, types)
	home.province = capital
	_say("the seat's guard reduced to %d regiment (%s)" % [home.count(), _types(home)])


## A rival host parked next to the seat, at war, ordered onto it.
func _march_on_seat(capital: int, rival: int) -> ArmyState:
	var staging: int = _staging(capital, rival)
	if staging < 0:
		_say("no province next to the seat could be given to %s" % FactionCatalog.name_of(rival))
		return null
	if not DiplomacyRules.invadable(_play.diplomacy, rival, _play.player_faction):
		var war: Dictionary = DiplomacyRules.declare_war(
			_play.diplomacy, rival, _play.player_faction
		)
		_say("%s declares on the crown: %s" % [
			FactionCatalog.name_of(rival), str(bool(war.get("ok", false))),
		])
		if not bool(war.get("ok", false)):
			return null
	var host: ArmyState = _host(rival, staging)
	if host == null:
		return null
	var moved: Dictionary = _play.army_layer.order(host, capital, true)
	_say("the march onto %s: %s" % [
		_play.model.province_name(capital),
		"ok" if bool(moved.get("ok", false)) else String(moved.get("reason", "refused")),
	])
	return host


## The province the host stages on: a neighbour of the seat, handed to the rival
## when it owns none there (a fall needs the rival to own nothing else first).
func _staging(capital: int, rival: int) -> int:
	for neighbour: int in MapGeo.province_neighbors(_play.model, capital):
		if _play.model.province_owner(neighbour) == rival:
			return neighbour
	for neighbour: int in MapGeo.province_neighbors(_play.model, capital):
		var owner: int = _play.model.province_owner(neighbour)
		if owner == _play.player_faction:
			continue
		_play.model.province_data(neighbour).owner = rival
		return neighbour
	return -1


func _host(owner: int, province: int) -> ArmyState:
	var types: Array[String] = []
	types.assign(HOST)
	var host: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, owner, province, false, types, 1000
	)
	_play.army_layer.next_army += 1
	_play.army_layer.armies.append(host)
	_play.army_layer.prune_markers()
	return host


## Hands `faction` Old World provinces until it holds `target`.
func _grant_rival(faction: int, target: int) -> int:
	var model: MapModel = _play.world.region(WorldMap.OLD_WORLD)
	var held: int = VictoryRules.old_world_holdings(_play.world, faction)
	for province: ProvinceState in model.provinces:
		if held >= target:
			break
		if province.owner == faction or province.owner == _play.player_faction:
			continue
		province.owner = faction
		held += 1
	return VictoryRules.old_world_holdings(_play.world, faction)


func _holdings_in(model: MapModel, faction: int) -> int:
	var held: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == faction:
			held += 1
	return held


# --- reads ------------------------------------------------------------------


func _open(advanced: String) -> bool:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, advanced)
	if _screen == null:
		_say("the map never opened")
		return false
	_main = _screen.get_parent()
	_play = _screen.play
	return true


## One turn through the seal, answering whatever the courts raise and clearing
## whatever plate a battle raises. True when the calendar moved or the campaign
## ended.
func _take_turn() -> bool:
	for _attempt in SaveDrive.MAX_TURN_ATTEMPTS:
		var before: int = _play.turn
		MapPlayTurn.end_turn(_play)
		_release_plate()
		if _play.turn != before or _play.campaign_over():
			return true
		if not SaveDrive.answer_pending(_play):
			return false
	return false


func _release_plate() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guard: int = 0
	while overlay != null and overlay.is_shown() and guard < 6:
		if guard == 0:
			var labels: PackedStringArray = PackedStringArray()
			SaveDrive.collect_text(overlay, "", labels)
			_say("  the battle plate reads: %s" % " | ".join(labels))
		overlay.skip()
		overlay._on_continue()
		guard += 1


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


func _sheet_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud.gazette_plate == null:
		return out
	SaveDrive.collect_text(_play.hud.gazette_plate._body, "", out)
	return out


func _sheet_count() -> int:
	if _play == null or _play.gazette == null:
		return 0
	return _play.gazette.history().size()


func _sheet_turns() -> String:
	if _play == null or _play.gazette == null:
		return "no gazette"
	var turns: PackedStringArray = PackedStringArray()
	for sheet: Dictionary in _play.gazette.history():
		turns.append(str(int(sheet.get("turn", 0))))
	return ", ".join(turns) if not turns.is_empty() else "none"


func _toasts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud == null or _play.hud.despatches == null:
		return out
	SaveDrive.collect_text(_play.hud.despatches, "", out)
	return out


func _clear_toasts() -> void:
	if _play == null or _play.hud == null or _play.hud.despatches.box == null:
		return
	for child: Node in _play.hud.despatches.box.get_children():
		child.queue_free()
	await process_frame


func _defenders(province: int) -> int:
	var count: int = 0
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.province == province:
			count += army.count()
	return count


func _types(army: ArmyState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for regiment_id: String in army.regiments:
		parts.append(army.type_of(regiment_id))
	return ", ".join(parts) if not parts.is_empty() else "none"


func _rival() -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != _play.player_faction:
			return faction
	return _play.player_faction


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	SaveDrive.clean_dir(SAVE_DIR)
	print("\n--- playtest_defeat: %d steps ---" % _steps.size())
	quit()
