extends SceneTree
## Headless free-playtest drive for Quick Battle (wiki: quick-battle): declares
## war on a rival, seats a player army on a rival province, resolves the Combat
## phase through the real play helpers, and prints every despatch line the plate
## shows plus the plate's own outcome stamp. Two passes: a field battle and a
## siege with an emplaced battery. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://tests/playtest_quick_battle.gd
##
## Armies are seated by the harness (a scenario seat, the same one rules tests
## use); the battle itself is ordered and resolved by ArmyCombat/QuickBattle and
## presented by the real GameHud plate.

const Launch = preload("res://tests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await _open_game()
	if _screen == null:
		_finish()
		return
	var play: PlaySession = _screen.play
	var player: int = play.player_faction
	_say("seed %s — player %s, %d provinces" % [
		SEED_TEXT, FactionCatalog.name_of(player), play.model.province_count(),
	])
	var rival: int = _rival(play, player)
	if rival < 0:
		_say("no rival Great Power to fight")
		_finish()
		return
	var province: int = _rival_province(play, rival)
	if province < 0:
		_say("no rival province to attack")
		_finish()
		return
	var war: Dictionary = DiplomacyRules.declare_war(play.diplomacy, player, rival)
	_say("war on %s: %s" % [
		FactionCatalog.name_of(rival),
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused")),
	])
	play.battle_plan = "balanced"
	_field_pass(play, player, rival, province)
	_siege_pass(play, player, rival, province)
	_defend_pass(play, player, rival)
	_finish()


# --- passes -----------------------------------------------------------------


## A field battle: player army against a rival army in open country.
func _field_pass(play: PlaySession, player: int, rival: int, province: int) -> void:
	_say("")
	_say("--- field battle at %s ---" % play.model.province_name(province))
	play.model.province_data(province).fort_level = 0
	_seat(play, player, rival, province, 8, 4)
	_fight(play)


## A siege: fort 2, so the plate should field an emplaced battery.
func _siege_pass(play: PlaySession, player: int, rival: int, province: int) -> void:
	_say("")
	_say("--- siege of %s ---" % play.model.province_name(province))
	play.model.province_data(province).fort_level = 2
	_seat(play, player, rival, province, 12, 3)
	_fight(play)


## The rare branch: the player is the defender, so the plate speaks for a
## battle the player did not start and the plan the player set must still show.
func _defend_pass(play: PlaySession, player: int, rival: int) -> void:
	_say("")
	var province: int = -1
	for entry: ProvinceState in play.model.provinces:
		if entry.owner == player and not entry.capital:
			province = entry.id
			break
	if province < 0:
		_say("no player province to defend")
		return
	_say("--- defending %s, player plan aggressive ---" % play.model.province_name(province))
	play.battle_plan = "aggressive"
	play.model.province_data(province).fort_level = 1
	_seat(play, player, rival, province, 10, 4, true)
	_fight(play)


func _fight(play: PlaySession) -> void:
	var before: int = play.army_layer.regiment_count_all(play.player_faction)
	MapPlayArmies.resolve_battles(play)
	var overlay: QuickBattleOverlay = play.hud.quick_battle_overlay
	if overlay == null or not overlay.is_shown():
		_say("no plate was shown for this battle")
		return
	var battle: Dictionary = overlay.battle
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var names: Array = FactionCatalog.names()
	_say("plate: plan %s (enemy %s), %d v %d, %d guns, mode %s — label reads \"%s\"" % [
		String(quick.get("plan", "?")), String(quick.get("defender_plan", "?")),
		int(quick.get("attacker_start", 0)),
		int(quick.get("defender_start", 0)), int(quick.get("guns_start", 0)),
		String(battle.get("battle_mode", "?")), String(overlay._plan_label.text),
	])
	for index in (quick.get("rounds", []) as Array).size():
		var round: Dictionary = (quick["rounds"] as Array)[index] as Dictionary
		_say("round %d — %d v %d, %d guns" % [
			index + 1, int(round.get("attacker_count", 0)),
			int(round.get("defender_count", 0)), int(round.get("guns", 0)),
		])
		for action: Dictionary in round.get("actions", []):
			_say("  despatch: %s" % QuickBattleCopy.action_line(action, battle, names))
	overlay.skip()
	_say("outcome stamp: %s" % String(overlay._outcome.text))
	var reported: int = (battle.get("attacker_lost", []) as Array).size() \
		+ (battle.get("defender_lost", []) as Array).size()
	_say("losses applied: attacker %d, defender %d" % [
		(battle.get("attacker_lost", []) as Array).size(),
		(battle.get("defender_lost", []) as Array).size(),
	])
	_say("player regiments before/after: %d/%d (all losses %d)" % [
		before, play.army_layer.regiment_count_all(play.player_faction), reported,
	])
	overlay._on_continue()


## Seats one army a side in the province; the rival's is marked as defending
## unless the player is the one holding the province.
func _seat(
	play: PlaySession, player: int, rival: int, province: int,
	attackers: int, defenders: int, player_defends: bool = false
) -> void:
	play.army_layer.armies.clear()
	var atk_owner: int = rival if player_defends else player
	var def_owner: int = player if player_defends else rival
	play.model.province_data(province).owner = def_owner
	var defender: ArmyState = _muster(play, def_owner, province, defenders, 1)
	defender.moved = false
	var attacker: ArmyState = _muster(play, atk_owner, province, attackers, 0)
	attacker.moved = true
	play.army_layer.armies.append(defender)
	play.army_layer.armies.append(attacker)
	play.army_layer._rebuild_markers()


func _muster(
	play: PlaySession, owner: int, province: int, count: int, offset: int
) -> ArmyState:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return ArmyState.muster(
		play.army_layer.next_army + offset, owner, province, false, types,
		play.army_layer.next_regiment + offset
	)


# --- setup ------------------------------------------------------------------


func _open_game() -> MapScreen:
	return await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)


func _rival(play: PlaySession, player: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != player:
			return faction
	return -1


func _rival_province(play: PlaySession, rival: int) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner == rival and not province.capital:
			return province.id
	return -1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_quick_battle: %d steps ---" % _steps.size())
	quit()
