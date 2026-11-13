extends SceneTree
## Headless playtest drive for land combat (wiki: combat § Multi-Attacker Chain,
## § Unopposed capture, § Garrison recovery; capital-and-connectivity § Capital
## loss and reassignment): stages rival provinces and resolves the real Combat
## phase, printing every battle report, the province's owner afterwards and the
## court's seat when it falls. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_combat_chain.gd
##
## Armies are seated by the harness (a scenario seat, the same one rules tests
## use); movement, war gates, the chain, Quick Battle and capital loss are the
## game's own helpers.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s — player %s, %d provinces in %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction),
		_play.model.province_count(), FactionCatalog.region_label(_play.region_index),
	])
	var rivals: Array[int] = []
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rivals.append(gp)
	if rivals.size() < 2:
		_say("need two rival Great Powers")
		_finish()
		return
	for gp: int in rivals.slice(0, 2):
		DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, gp)
	DiplomacyRules.declare_war(_play.diplomacy, rivals[1], rivals[0])
	_say("war: %s v %s, %s v %s" % [
		FactionCatalog.name_of(_play.player_faction), FactionCatalog.name_of(rivals[0]),
		FactionCatalog.name_of(rivals[1]), FactionCatalog.name_of(rivals[0]),
	])
	var province: int = _province_of(rivals[0])
	if province < 0:
		_say("no rival province to fight over")
		_finish()
		return
	_chain_pass(province, rivals)
	_unopposed_pass(province, rivals)
	_third_party_pass(province, rivals)
	_ai_turn_pass(rivals)
	_multi_defence_pass(rivals)
	_capital_pass(rivals)
	_finish()


# --- passes ----------------------------------------------------------------


## Two Great Powers fall on one rival province: the initiative order decides who
## fights first and the survivor meets the next attacker without healing.
func _chain_pass(province: int, rivals: Array[int]) -> void:
	_say("")
	_say("--- chain: %s held by %s, attacked by %s and %s ---" % [
		_play.model.province_name(province),
		FactionCatalog.name_of(rivals[0]),
		FactionCatalog.name_of(_play.player_faction),
		FactionCatalog.name_of(rivals[1]),
	])
	_reset(province, rivals[0])
	_seat(rivals[0], province, 6, 50)
	_seat(_play.player_faction, province, 6, 40, true)
	_seat(rivals[1], province, 5, 30, true)
	_say("before: %s" % _roster(province))
	_fight()
	_say("after: owner %s; %s" % [
		FactionCatalog.name_of(_play.model.province_owner(province)),
		_roster(province),
	])


## An empty province with two attackers: the lowest Great Power id takes it.
func _unopposed_pass(province: int, rivals: Array[int]) -> void:
	_say("")
	_say("--- unopposed: %s held by %s with no garrison ---" % [
		_play.model.province_name(province),
		FactionCatalog.name_of(rivals[0]),
	])
	_reset(province, rivals[0])
	_seat(_play.player_faction, province, 4, 60, true)
	_seat(rivals[1], province, 3, 55, true)
	_fight()
	_say("after: owner %s" % FactionCatalog.name_of(_play.model.province_owner(province)))


## The same empty province with a peaceful third army standing in it: nobody
## captures it (wiki: combat § Unopposed capture).
func _third_party_pass(province: int, rivals: Array[int]) -> void:
	_say("")
	_say("--- third party: a peaceful rival army stands in %s ---" % (
		_play.model.province_name(province)
	))
	_reset(province, rivals[0])
	var third: int = -1
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction and gp != rivals[0] and gp != rivals[1]:
			third = gp
			break
	if third < 0:
		_say("no third Great Power")
		return
	_seat(third, province, 2, 70)
	_seat(_play.player_faction, province, 4, 75, true)
	_seat(rivals[1], province, 3, 80, true)
	_fight()
	_say("after: owner %s" % FactionCatalog.name_of(_play.model.province_owner(province)))


## The rare branch: the player is the defender through a whole AI turn, with a
## rival army already standing on a player province and the player's plan set.
func _ai_turn_pass(rivals: Array[int]) -> void:
	_say("")
	var held: int = -1
	for entry: ProvinceState in _play.model.provinces:
		if entry.owner == _play.player_faction and not entry.capital:
			held = entry.id
			break
	if held < 0:
		_say("no player province to defend")
		return
	_say("--- full AI turn: %s holds %s, %s attacks ---" % [
		FactionCatalog.name_of(_play.player_faction),
		_play.model.province_name(held),
		FactionCatalog.name_of(rivals[0]),
	])
	_play.army_layer.armies.clear()
	_play.model.province_data(held).owner = _play.player_faction
	_play.model.province_data(held).fort_level = 1
	_seat(_play.player_faction, held, 5, 90)
	_seat(rivals[0], held, 7, 95, true)
	_play.battle_plan = "aggressive"
	_say("before the AI turn: %s" % _ownership())
	var guardian: int = 0
	while not _play.campaign_over() and guardian < 8:
		MapPlayTurn.end_turn(_play)
		_say("turn %d: %s, over %s, %s" % [
			_play.turn, _ownership(), str(_play.campaign_over()), _defeat_text(),
		])
		var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
		var pending: bool = CallToArms.has_pending(_play.diplomacy, _play.player_faction) \
			or Intervention.has_pending(_play.diplomacy, _play.player_faction) \
			or DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction)
		if overlay != null and overlay.is_shown():
			var battle: Dictionary = overlay.battle
			var quick: Dictionary = battle.get("quick", {}) as Dictionary
			_say("plate: plan %s (enemy %s), %d v %d, %d guns" % [
				String(quick.get("plan", "?")), String(quick.get("defender_plan", "?")),
				int(quick.get("attacker_start", 0)),
				int(quick.get("defender_start", 0)),
				int(quick.get("guns_start", 0)),
			])
			overlay.skip()
			overlay._on_continue()
		if not pending:
			break
		_say("turn suspended: %s — the court refuses" % _pending_kind())
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_offer(_play, false)
		guardian += 1
	_say("after %d turns: owner %s, player regiments %d, seat %s" % [
		_play.turn, FactionCatalog.name_of(_play.model.province_owner(held)),
		_play.army_layer.regiment_count_all(_play.player_faction),
		_play.model.province_name(_play.capital_province),
	])


## Two rival crowns fall on the same player province in one AI turn: the chain
## fights both, every battle gets its own plate, and whatever garrison survives
## must still stand on the map for the player to tap.
func _multi_defence_pass(rivals: Array[int]) -> void:
	_say("")
	var held: int = -1
	for entry: ProvinceState in _play.model.provinces:
		if entry.owner == _play.player_faction and not entry.capital:
			held = entry.id
			break
	if held < 0:
		_say("no player province to defend")
		return
	for rival: int in rivals.slice(0, 2):
		DiplomacyRules.declare_war(_play.diplomacy, rival, _play.player_faction)
	_say("--- one AI turn, two attackers: %s holds %s, %s and %s come for it ---" % [
		FactionCatalog.name_of(_play.player_faction), _play.model.province_name(held),
		FactionCatalog.name_of(rivals[0]), FactionCatalog.name_of(rivals[1]),
	])
	_play.army_layer.armies.clear()
	_play.army_layer._rebuild_markers()
	_play.model.province_data(held).owner = _play.player_faction
	_play.model.province_data(held).fort_level = 1
	_play.battle_plan = "defensive"
	_seat(_play.player_faction, held, 4, 130)
	_seat(rivals[0], held, 3, 131, true)
	_seat(rivals[1], held, 3, 132, true)
	_say("before the turn: %s" % _standards())
	## Every battle the rules resolve this turn, whether or not a plate shows.
	var seen: Array[Dictionary] = []
	var recorder := func(battles: Array[Dictionary]) -> void:
		for battle: Dictionary in battles:
			seen.append(battle)
	_play.host.battle_resolved.connect(recorder)
	_take_turn()
	_play.host.battle_resolved.disconnect(recorder)
	_say("%d battle%s resolved; %d plate%s queued behind the first" % [
		seen.size(), "" if seen.size() == 1 else "s",
		_play.hud._quick_queue.size(), "" if _play.hud._quick_queue.size() == 1 else "s",
	])
	_drain_plates()
	_say("after the turn: %s holds %s; %s" % [
		FactionCatalog.name_of(_play.model.province_owner(held)),
		_play.model.province_name(held), _standards(),
	])


## Runs one calendar turn, answering whatever consent decision it raises, and
## leaves the plates for the caller to read.
func _take_turn() -> void:
	var guardian: int = 0
	while not _play.campaign_over() and guardian < 4:
		MapPlayTurn.end_turn(_play)
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for a call to arms — refused")
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for an intervention — stood aside")
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			_say("turn stopped for a rival proposal — refused")
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
		guardian += 1
	_say("turn %d, %s; player regiments %d" % [
		_play.turn, _ownership(),
		_play.army_layer.regiment_count_all(_play.player_faction),
	])


## Reads every plate the turn queued, in the order the court sees them.
func _drain_plates() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guardian: int = 0
	while overlay != null and overlay.is_shown() and guardian < 6:
		var battle: Dictionary = overlay.battle
		var quick: Dictionary = battle.get("quick", {}) as Dictionary
		overlay.skip()
		_say("plate %d: %s v %s at %s — \"%s\", plan %s / enemy %s, %d v %d, %d guns" % [
			guardian + 1,
			FactionCatalog.name_of(int(battle.get("attacker", -1))),
			FactionCatalog.name_of(int(battle.get("defender", -1))),
			overlay.province_name, String(overlay._outcome.text),
			String(quick.get("plan", "?")), String(quick.get("defender_plan", "?")),
			int(quick.get("attacker_start", 0)), int(quick.get("defender_start", 0)),
			int(quick.get("guns_start", 0)),
		])
		_say("  plate stance: %s" % QuickBattleCopy.plan_text(battle))
		_say("  court news: %d raised, %d waiting for the plate" % [
			_toast_count(), _play.hud._toast_queue.size()])
		for round: Dictionary in quick.get("rounds", []) as Array:
			for action: Dictionary in round.get("actions", []) as Array:
				_say("  despatch: %s" % QuickBattleCopy.action_line(
					action, battle, FactionCatalog.names()))
		overlay._on_continue()
		guardian += 1


## Toast plates the court has raised and not yet retired.
func _toast_count() -> int:
	return _play.hud._toast_box.get_child_count() if _play.hud._toast_box != null else -1


## Every standing army with the standard the map draws for it: an army without
## one cannot be seen, tapped, or ordered.
func _standards() -> String:
	var parts: PackedStringArray = []
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.count() <= 0:
			continue
		var marker: ArmyMarker = _play.army_layer.marker_for(army)
		parts.append("%s %d at %s (%s)" % [
			FactionCatalog.name_of(army.owner), army.count(),
			_play.model.province_name(army.province),
			"standard" if marker != null else "NO STANDARD",
		])
	return ", ".join(parts) if not parts.is_empty() else "no armies"


## The court's seat is stormed: with only the capital left the crown falls and
## its holdings pass to the conqueror (wiki: capital-and-connectivity).
func _capital_pass(rivals: Array[int]) -> void:
	_say("")
	var old_seat: int = _play.capital_province
	_say("--- capital loss: %s holds the seat at %s, %s storms it ---" % [
		FactionCatalog.name_of(_play.player_faction),
		_play.model.province_name(old_seat),
		FactionCatalog.name_of(rivals[0]),
	])
	_play.army_layer.armies.clear()
	_play.model.province_data(old_seat).fort_level = 0
	_seat(_play.player_faction, old_seat, 2, 120)
	_seat(rivals[0], old_seat, 24, 125, true)
	_say("before the storm: %d owned in region, seat flag %s" % [
		CapitalLoss.owned_provinces(_play.model, _play.player_faction).size(),
		str(_play.model.province_data(old_seat).capital),
	])
	var guardian: int = 0
	while not _play.campaign_over() and guardian < 8:
		MapPlayTurn.end_turn(_play)
		var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
		if overlay != null and overlay.is_shown():
			overlay.skip()
			overlay._on_continue()
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
		guardian += 1
	_say("old seat now owned by %s; campaign over: %s (%s)" % [
		FactionCatalog.name_of(_play.model.province_owner(old_seat)),
		str(_play.campaign_over()), _defeat_text(),
	])
	_say("owned in region after: %d; the lost province keeps its capital flag: %s" % [
		CapitalLoss.owned_provinces(_play.model, _play.player_faction).size(),
		str(_play.model.province_data(old_seat).capital),
	])


# --- seating ---------------------------------------------------------------


func _reset(province: int, owner: int) -> void:
	_play.army_layer.armies.clear()
	_play.model.province_data(province).owner = owner
	_play.model.province_data(province).fort_level = 0
	_play.army_layer._rebuild_markers()


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


func _fight() -> void:
	var battles: Array[Dictionary] = _play.army_layer.resolve_battles(
		_play.world, MapPlayLandTurn.battle_context(_play)
	)
	if battles.is_empty():
		_say("no battle was fought")
		return
	for battle: Dictionary in battles:
		_say("battle: %s v %s at %s — %s, captured %s, garrison %d %s" % [
			FactionCatalog.name_of(int(battle["attacker"])),
			FactionCatalog.name_of(int(battle["defender"])),
			_play.model.province_name(int(battle["province"])),
			ArmyCombat.Outcome.keys()[int(battle["outcome"])],
			str(battle.get("captured", false)),
			int(battle.get("garrison", 0)),
			String(battle.get("recovered_type", "")),
		])
		_say("  lost: attacker %d, defender %d" % [
			(battle.get("attacker_lost", []) as Array).size(),
			(battle.get("defender_lost", []) as Array).size(),
		])
		var quick: Dictionary = battle.get("quick", {}) as Dictionary
		if not quick.is_empty():
			_say("  quick: %d v %d, %d/%d guns, plan %s / enemy %s" % [
				int(quick.get("attacker_start", 0)),
				int(quick.get("defender_start", 0)),
				int(quick.get("guns_start", 0)),
				int(quick.get("guns_left", 0)),
				String(quick.get("plan", "?")),
				String(quick.get("defender_plan", "?")),
			])


func _roster(province: int) -> String:
	var parts: PackedStringArray = []
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.province != province:
			continue
		parts.append("%s %d" % [FactionCatalog.name_of(army.owner), army.count()])
	return ", ".join(parts) if not parts.is_empty() else "empty"


func _ownership() -> String:
	var parts: PackedStringArray = []
	for gp: int in FactionCatalog.great_power_ids():
		parts.append("%s %d" % [
			FactionCatalog.name_of(gp),
			CapitalLoss.owned_provinces(_play.model, gp).size(),
		])
	return ", ".join(parts)


func _defeat_text() -> String:
	if _play.defeat == null:
		return "none"
	return _play.defeat.summary()


func _pending_kind() -> String:
	if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
		return "call to arms"
	if Intervention.has_pending(_play.diplomacy, _play.player_faction):
		return "intervention"
	return "rival proposal"


func _province_of(faction: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == faction and not province.capital:
			return province.id
	return -1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_combat_chain: %d steps ---" % _steps.size())
	quit()
