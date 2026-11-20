extends SceneTree
## Headless playtest drive for the crown's command: the general pool, its
## tech-gated cap, the medals a battle pays and the ledger that reads them
## (wiki: military-generals § Generals, § Count and tech-gated cap, § Medals,
## § The crown's command). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_command.gd
##
## Pass one reads the opening pool and the ledger a turn-0 crown opens. Pass two
## opens the turn-100 advanced start, where the cap-raising studies have landed,
## and reads the road again. Pass three fights a real land battle and holds the
## despatch's medal credit to the roster and to the ledger's own row.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _opening_pass()
	await _advanced_pass()
	await _battle_pass()
	_finish()


# --- pass one: the opening pool ---------------------------------------------


func _opening_pass() -> void:
	_say("")
	_say("=== the crown's command at turn 0 ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	_say("seed %s — %s, turn %d, leader %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		String(_play.leaders.get(_play.player_faction, "")),
	])
	_say("techs unlocked: %s" % str(_play.tech_unlocked().keys()))
	_read_pool("turn 0")
	await _open_ledger()
	_read_ledger("turn 0")


# --- pass two: the advanced start -------------------------------------------


func _advanced_pass() -> void:
	_say("")
	_say("=== the crown's command at the turn-100 advanced start ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		return
	_play = _screen.play
	_say("turn %d — %s, leader %s" % [
		_play.turn, FactionCatalog.name_of(_play.player_faction),
		String(_play.leaders.get(_play.player_faction, "")),
	])
	var techs: Array = _play.tech_unlocked().keys()
	techs.sort()
	_say("techs unlocked: %s" % str(techs))
	_read_pool("turn 100")
	await _open_ledger()
	_read_ledger("turn 100")


# --- pass three: a battle pays a medal --------------------------------------


func _battle_pass() -> void:
	_say("")
	_say("=== a land battle and the medal it pays ===")
	if _play == null:
		return
	var rival: int = -1
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rival = gp
			break
	if rival < 0:
		_say("no rival Great Power to fight")
		return
	DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, rival)
	var province: int = _province_of(rival)
	if province < 0:
		_say("no rival province to fight over")
		return
	_play.army_layer.armies.clear()
	_play.model.province_data(province).owner = rival
	_play.model.province_data(province).fort_level = 0
	_play.army_layer._rebuild_markers()
	_seat(rival, province, 4, 50)
	_seat(_play.player_faction, province, 8, 40, true)
	_say("before: %s" % _roster(province))
	_say("pool before: %s" % _pool_text())
	var battles: Array[Dictionary] = _play.army_layer.resolve_battles(
		_play.world, MapPlayLandTurn.battle_context(_play)
	)
	if battles.is_empty():
		_say("no battle was fought")
		return
	for battle: Dictionary in battles:
		_say("battle: %s v %s at %s — %s" % [
			FactionCatalog.name_of(int(battle["attacker"])),
			FactionCatalog.name_of(int(battle["defender"])),
			_play.model.province_name(int(battle["province"])),
			ArmyCombat.Outcome.keys()[int(battle["outcome"])],
		])
		_say("  medal_gain %s · medal_owner %d" % [
			str(battle.get("medal_gain", "")), int(battle.get("medal_owner", -1)),
		])
	_say("pool after: %s" % _pool_text())
	await _open_ledger()
	_read_ledger("after the battle")


# --- readings ---------------------------------------------------------------


func _read_pool(label: String) -> void:
	var roster: GeneralRoster = _play.army_layer.generals
	var owner: int = _play.player_faction
	_say("pool %s: %d held, cap %d, ids %s, names %s" % [
		label, roster.count(owner), GeneralRoster.cap_for(_play.tech_unlocked()),
		str(roster.ids(owner)), str(roster.names(owner)),
	])
	for gp: int in FactionCatalog.great_power_ids():
		_say("  %s: %d commander(s)" % [
			FactionCatalog.name_of(gp), roster.count(gp),
		])


func _open_ledger() -> void:
	# A door press toggles, so a sheet already standing is set down first —
	# otherwise the second press closes it and the labels go stale.
	var panel: CommandLedgerPanel = _play.hud.command_ledger
	if panel != null and panel.is_open():
		panel.close()
		await process_frame
	_play.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	for _frame in 3:
		await process_frame


func _read_ledger(label: String) -> void:
	var panel: CommandLedgerPanel = _play.hud.command_ledger
	if panel == null:
		_say("command ledger %s: no sheet" % label)
		return
	_say("command ledger %s:" % label)
	for text: String in _labels(panel):
		_say("  | %s" % text)


func _pool_text() -> String:
	var roster: GeneralRoster = _play.army_layer.generals
	var parts: PackedStringArray = []
	for gp: int in FactionCatalog.great_power_ids():
		var names: Array[String] = roster.names(gp)
		var medals: PackedStringArray = []
		for general_id: String in roster.ids(gp):
			medals.append("%d" % roster.medals(gp, general_id))
		parts.append("%s %d [%s] medals [%s]" % [
			FactionCatalog.name_of(gp), names.size(), ", ".join(names),
			", ".join(medals),
		])
	return " · ".join(parts)


func _roster(province: int) -> String:
	var parts: PackedStringArray = []
	for army: ArmyState in _play.army_layer.armies:
		if army.province != province:
			continue
		parts.append("%s %d" % [FactionCatalog.name_of(army.owner), army.count()])
	return ", ".join(parts)


func _province_of(faction: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == faction:
			return province.id
	return -1


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


# --- printing ---------------------------------------------------------------


func _labels(node: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if node == null:
		return out
	for label: Label in node.find_children("*", "Label", true, false):
		if not label.text.strip_edges().is_empty():
			out.append(label.text)
	return out


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_command: %d steps ---" % _steps.size())
	quit()
