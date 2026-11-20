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
## despatch's medal credit to the roster and to the ledger's own row. Pass four
## runs a whole phase of four attacks and a defence against a pool of three: the
## distinct binds, the army left on the leader's fallback medals, and the count
## each despatch line prints for its own win.

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
	await _phase_pass()
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


# --- pass four: a phase with more attacks than commanders -------------------


## The phase's own cap: four attacks and one defence against a pool of three.
## The wiki binds one commander per attacking army, never the same one twice in
## a phase, and hands any further army the leader's fallback medals; a defending
## army draws from the same pool without spending an attacker's commander
## (wiki: military-generals § Assignment, § Medal effects).
func _phase_pass() -> void:
	_say("")
	_say("=== a phase with four attacks and three commanders ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		return
	_play = _screen.play
	var player: int = _play.player_faction
	# A crown whose fallback is not zero, so an army left without a free
	# commander fights on a medal count the despatch can be held to: France's
	# leader is the land apex (wiki: leader-bonuses § Bonus Table). Any
	# campaign that sails as France opens in exactly this state.
	_play.leaders[player] = "napoleon"
	_play.army_layer.armies.clear()
	var rivals: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != player:
			rivals.append(gp)
	if rivals.size() < 2:
		_say("no two rivals to fight")
		return
	var first: int = rivals[0]
	var second: int = rivals[1]
	DiplomacyRules.declare_war(_play.diplomacy, player, first)
	DiplomacyRules.declare_war(_play.diplomacy, player, second)
	var targets: Array[int] = _provinces_of(first, 3) + _provinces_of(second, 1)
	if targets.size() < 4:
		_say("only %d provinces to attack" % targets.size())
		return
	var home: Array[int] = _provinces_of(player, 1)
	if home.is_empty():
		_say("no province of the crown's own to defend")
		return
	var offset: int = 10
	for province: int in targets:
		_play.model.province_data(province).fort_level = 0
		_seat(_play.model.province_data(province).owner, province, 3, offset)
		_seat(player, province, 8, offset + 4, true)
		offset += 20
	# One more front, on the crown's own land: an enemy army marches in and the
	# crown's garrison holds the wall, so a defender's commander is drawn too.
	var held: int = home[0]
	_play.model.province_data(held).fort_level = 0
	_seat(first, held, 3, offset, true)
	_seat(player, held, 8, offset + 4)
	_play.army_layer._rebuild_markers()
	var attacks: Array[ArmyState] = []
	for army: ArmyState in _play.army_layer.armies:
		if army.owner == player and army.moved:
			attacks.append(army)
	_say("attacking armies: %s; defending armies: %s" % [
		str(attacks.size()), str(_play.army_layer.armies.size() - attacks.size()),
	])
	# The phase's binding read on its own, before a blow lands: a pure read that
	# moves no state, so the fight below must draw the same commanders.
	var bindings: Dictionary = GeneralBinding.bind_phase(
		_play.world, {_play.model.region_id: _play.army_layer.armies},
		_play.army_layer.generals, _play.turn, MapPlayLandTurn._war_query(_play)
	)
	var drawn: Dictionary = bindings.get("army_general", {}) as Dictionary
	_say("pool: %d commanders, cap %d" % [
		_play.army_layer.generals.count(player),
		GeneralRoster.cap_for(_play.tech_unlocked()),
	])
	for army: ArmyState in _play.army_layer.armies:
		if army.owner != player:
			continue
		var general_id: String = String(drawn.get(army.id, ""))
		_say("  army %d (%s, %d regiments): %s" % [
			army.id, "attacking" if army.moved else "defending", army.count(),
			(
				"%s, %d medals" % [
					_play.army_layer.generals.label(player, general_id),
					_play.army_layer.generals.medals(player, general_id),
				]
			) if not general_id.is_empty() else "no commander — leader fallback %d" % (
				ArmyModifiers.fallback_medals(String(_play.leaders.get(player, "")), army.moved)
			),
		])
	var battles: Array[Dictionary] = MapPlayLandTurn.resolve(_play)
	_say("battles fought: %d" % battles.size())
	for battle: Dictionary in battles:
		_say("  %s at %s — %s · attacker medals %d, defender medals %d · medal_gain %s" % [
			FactionCatalog.name_of(int(battle["attacker"])),
			_play.model.province_name(int(battle["province"])),
			ArmyCombat.Outcome.keys()[int(battle["outcome"])],
			int(battle.get("attacker_medals", 0)), int(battle.get("defender_medals", 0)),
			str(battle.get("medal_gain", "")),
		])
	_say("the despatch lane:")
	for line: String in _despatch_lines():
		_say("  | %s" % line)
	_say("pool after: %s" % _pool_text())
	await _open_ledger()
	_read_ledger("after the phase")


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


## Provinces a court holds this turn, in id order, capped at `limit`; the seat
## is left out when another province is on offer, so a march does not open on
## the enemy's whole government.
func _provinces_of(faction: int, limit: int) -> Array[int]:
	var found: Array[int] = []
	for province: ProvinceState in _play.model.provinces:
		if province.owner != faction:
			continue
		found.append(province.id)
	found.sort()
	while found.size() > limit:
		found.pop_back()
	return found


## The despatch lane as the court reads it: what the board is holding and what
## it has raised, in the lane's own order.
func _despatch_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _play == null or _play.hud == null or _play.hud.despatches == null:
		return out
	var lane: HudDespatches = _play.hud.despatches
	out.append_array(lane.waiting())
	for label: Label in lane.find_children("*", "Label", true, false):
		if not label.text.strip_edges().is_empty():
			out.append(label.text)
	return out


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
