extends SceneTree
## Headless free-playtest drive for sieges (wiki: siege-mechanics § Fort Levels,
## § Wall Protection, § Quick Battle lanes, § Gates and Sortie, § Emplaced
## Artillery): the wall a crown raises, and the two ways it meets one.
##
## Three passes, each reading only what a player reads:
##   1. `_raise_pass` — the Engineer's own order list at the seat: the caption a
##      player picks a fort from, what the stockpile pays, the turn's despatch,
##      the province sheet's Fort row and the military lens's band.
##   2. `_storm_pass` — a host of guns and firearms storms a rival's wall at
##      levels 1 and 3: the plate's stance, the battery, the lanes, the gates,
##      and the level the fort is left at when the last gun is silenced.
##   3. `_defend_pass` — the crown's own wall, attacked: the defender's plate,
##      the sortie line and the wall's share of the losses.
##
## The wall on a rival province is seated by the harness (a scenario seat is the
## shortest way to a siege: no rival raises one on demand), and so is the
## garrison that mans it; everything a player can do — the order, the march, the
## turn, the plate — is the game's own.
## Not a CI gate, run it by hand:
##   godot --headless --path . --script res://playtests/playtest_siege.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const DIR: String = "user://playtest_siege"
const WALL_TYPES: Array[String] = ["musketeers", "musketeers", "halberdiers", "hussars"]

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _fort_province: int = -1
var _rival: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("%s, turn %d, purse %d; stockpile %s" % [
		FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(), _stockpile(),
	])
	await _raise_pass()
	await _storm_pass()
	await _defend_pass()
	_finish()


# --- the passes -------------------------------------------------------------


## The Engineer's dossier at the seat: what the order says, what it costs, what
## the turn reports, and what the province sheet and the lens then read.
func _raise_pass() -> void:
	_say("")
	_say("--- the seat's wall: the order a player picks ---")
	var engineer: CivilianState = _civilian("engineer")
	if engineer == null:
		_say("no Engineer in the crown's roster — the order cannot be read")
		return
	var wall: int = _play.model.province_at(engineer.tile.x, engineer.tile.y)
	_fort_province = wall
	_play.civilian_layer.select(engineer)
	MapPlayCivilians.refresh_panel(_play)
	await process_frame
	_say("Engineer at %s (fort %d today)" % [
		_play.model.province_name(wall), FortRules.level_at(_play.model, wall),
	])
	_dump_panel(_play.hud.panels.civilian_panel, "the Engineer's orders")
	var button: Button = _fort_button(_play.hud.panels.civilian_panel)
	if button == null:
		_say("the dossier offers no fort order")
		return
	_say("order caption: \"%s\" (disabled %s)" % [button.text, str(button.disabled)])
	var before: Dictionary = _stockpile_counts()
	button.emit_signal("pressed")
	await process_frame
	_say("toast: %s" % _last_toast())
	_say("stockpile: %s -> %s" % [_counts_text(before), _stockpile()])
	_say("the sheet's Fort row before the turn: %s" % _fort_row())
	_say("the lens before the turn: %s" % _lens_line(wall))
	_say("")
	_say("--- the turn that finishes the wall ---")
	_clear_toasts()
	_take_turn()
	_say("despatches: %s" % _toast_text())
	_say("the sheet's Fort row: %s" % _fort_row())
	_say("the lens: %s" % _lens_line(wall))
	_say("the province's own reading: %s" % FortRules.describe(
		FortRules.level_at(_play.model, wall)
	))


## A host of guns and firearms storms a rival's wall. Levels 1 and 3, because the
## battery, the gates and the wall's soak each change with the table row.
func _storm_pass() -> void:
	var used: Array[int] = []
	for level: int in [1, 3]:
		var target: int = _rival_wall(used)
		if target < 0:
			_say("")
			_say("no rival province borders the crown — no wall to march on")
			return
		used.append(target)
		_say("")
		_say("--- guns at a %s wall (%s) ---" % [
			FortRules.level_name(level), _play.model.province_name(target),
		])
		_reseed_wall(target, level)
		_say("the wall reads: %s · wall %d hp · %d%% spared" % [
			FortRules.describe(level), roundi(FortRules.wall_hp(level)),
			roundi(FortRules.damage_reduction(level) * 100.0),
		])
		_say("the lens: %s" % _lens_line(target))
		var army: ArmyState = _march_host(target, true)
		if army == null:
			return
		_clear_toasts()
		var battles: Array[Dictionary] = MapPlayLandTurn.resolve(_play)
		var fought: bool = false
		for battle: Dictionary in battles:
			var province: int = int(battle.get("province", -1))
			if province != target:
				continue
			fought = true
			_say("despatch: %s" % BattleReport.describe_land(
				battle, _play.model.province_name(province), FactionCatalog.names()
			))
			_read_quick(battle)
		if not fought:
			_say("no battle was fought at the wall this pass")
		_release_plate()
		_say("the crown's host %s; %s holds %d regiments" % [
			"%d regiments" % army.count() if army.count() > 0 else "is gone",
			FactionCatalog.name_of(_play.model.province_owner(target)),
			_regiments_at(target, _play.model.province_owner(target)),
		])
		_say("the fort after the storm: %s" % FortRules.describe(
			FortRules.level_at(_play.model, target)
		))
		_say("the sheet's Fort row: %s" % _sheet_row(target))
		_take_turn()


## The crown's own wall on a frontier province, marched on by a rival at war.
## The seat has no rival border, so the crew walks to the frontier (fixture: the
## Engineer's own order does the raising, and the walk would spend the turns the
## pass exists to read) and raises the wall there.
func _defend_pass() -> void:
	_say("")
	_say("--- the crown's own wall, attacked ---")
	var seat: Dictionary = await _frontier_wall()
	if seat.is_empty():
		_say("no quiet crown province borders a rival — no frontier wall to defend")
		return
	var wall: int = int(seat["province"])
	# A wall with nobody behind it is not a siege: the crown's own host mans it.
	var guard: ArmyState = _crown_garrison(wall)
	if guard == null:
		_say("no crown host can man the wall — the rival would meet an empty town")
		return
	_say("the crown's garrison at the wall: %d regiments (%s)" % [
		guard.count(), _types(guard),
	])
	var foe: ArmyState = _seat_rival_besieger(wall, int(seat["rival"]))
	if foe == null:
		_say("no rival host could be brought onto the crown's wall")
		return
	_clear_toasts()
	var battles: Array[Dictionary] = MapPlayLandTurn.resolve(_play)
	var read: bool = false
	for battle: Dictionary in battles:
		if int(battle.get("province", -1)) != wall:
			continue
		read = true
		_say("despatch: %s" % BattleReport.describe_land(
			battle, _play.model.province_name(wall), FactionCatalog.names()
		))
		_read_quick(battle)
	if not read:
		_say("no battle at the crown's wall this pass — the rival never closed")
	_release_plate()
	_say("the crown's wall after the assault: %s" % FortRules.describe(
		FortRules.level_at(_play.model, wall)
	))
	_say("the crown holds %s: %s" % [
		_play.model.province_name(wall),
		"yes" if _play.model.province_owner(wall) == _play.player_faction else "no",
	])


## A crown host standing behind the wall: a field standard if the crown keeps
## one, else a detachment of the Home Army.
func _crown_garrison(wall: int) -> ArmyState:
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.owner != _play.player_faction or army.is_embarked():
			continue
		if army.home:
			continue
		army.province = wall
		army.moved = false
		return army
	var home: ArmyState = ArmyTraining.home_army(
		_play.army_layer.armies, _play.player_faction
	)
	if home == null or home.count() < 3:
		return null
	var made: Dictionary = _play.army_layer.split(
		home, home.regiments.slice(0, mini(3, home.count() - 1))
	)
	var host: ArmyState = made.get("army", null) as ArmyState
	if host == null:
		return null
	host.province = wall
	host.moved = false
	return host


## Raises a Wood wall on the first quiet crown province that borders another
## crown, through the Engineer's own order. "Quiet" means no neighbour at war
## with the crown there, so the turn that finishes the wall is not also a turn a
## neighbour storms it. Returns {province, rival}, or {}.
func _frontier_wall() -> Dictionary:
	var engineer: CivilianState = _civilian("engineer")
	if engineer == null:
		return {}
	var tried: int = 0
	for province in _play.model.province_count():
		if tried >= 3:
			break
		if _play.model.province_owner(province) != _play.player_faction:
			continue
		var data: ProvinceState = _play.model.province_data(province)
		if data == null or not data.has_town():
			continue
		var rival: int = -1
		for neighbour: int in MapGeo.province_neighbors(_play.model, province):
			var owner: int = _play.model.province_owner(neighbour)
			if owner == _play.player_faction or owner == MapModel.NO_ID:
				continue
			# Only a Great Power fields an army that may storm a crown (a minor
			# nation never attacks — ArmyCombat.ordered_attackers).
			if FactionCatalog.type_of(owner) != FactionCatalog.Type.GREAT_POWER:
				continue
			if rival < 0:
				rival = owner
		if rival < 0:
			continue
		tried += 1
		engineer.tile = data.town_tile
		engineer.clear_work()
		_play.civilian_layer.sync()
		_play.civilian_layer.select(engineer)
		MapPlayCivilians.refresh_panel(_play)
		await process_frame
		var button: Button = _fort_button(_play.hud.panels.civilian_panel)
		if button == null:
			_say("the frontier dossier offers no fort order")
			return {}
		_say("the frontier order at %s: \"%s\"" % [
			_play.model.province_name(province), button.text,
		])
		button.emit_signal("pressed")
		await process_frame
		_say("toast: %s" % _last_toast())
		# The turn's own Build/Work pass, without the land battles a whole turn
		# would also fight: the despatch is the thing being read, and a battle
		# plate's held-news cap can spend it.
		MapPlayCivilians.resolve_work(_play)
		var level: int = FortRules.level_at(_play.model, province)
		_say("the wall the turn left at %s: %s" % [
			_play.model.province_name(province), FortRules.describe(level),
		])
		if level > 0 and _play.model.province_owner(province) == _play.player_faction:
			return {"province": province, "rival": rival}
	return {}



# --- the plate --------------------------------------------------------------


## Everything the court can read on a siege plate: the stance line it opens with,
## each round's action, and the aftermath block.
func _read_quick(battle: Dictionary) -> void:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	if quick.is_empty():
		_say("  the battle carried no Quick Battle plate (auto-resolve only)")
		return
	_say("  the plate opens with: %s" % QuickBattleCopy.plan_text(battle))
	_say("  the wall block: %s" % QuickBattleCopy.siege_line(battle))
	_say("  the ground: %s" % (
		QuickBattleCopy.terrain_line(battle) if not QuickBattleCopy.terrain_line(battle).is_empty()
		else "open field (no line)"
	))
	var lanes: Dictionary = quick.get("lanes", {}) as Dictionary
	_say("  the lanes opened %d on the wall, %d behind (%d guns)" % [
		int(lanes.get("wall", 0)), int(lanes.get("behind", 0)),
		int(quick.get("guns_start", 0)),
	])
	for raw: Variant in quick.get("rounds", []) as Array:
		var round: Dictionary = raw as Dictionary
		for action: Dictionary in round.get("actions", []):
			_say("    round action: %s" % QuickBattleCopy.action_line(
				action, battle, FactionCatalog.names()
			))
	_say("  the battery: %d of %d %s silenced; gates %d of %d" % [
		int(quick.get("guns_lost", 0)), int(quick.get("guns_start", 0)),
		String(quick.get("gun_type", "—")),
		int(quick.get("breaches", 0)), int((quick.get("gates", {}) as Dictionary).get("max", 0)),
	])


## The plate's own labels, as the court reads them.
func _plate_text() -> String:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	if overlay == null or not overlay.is_shown():
		return "no plate"
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(overlay, "", labels)
	return " | ".join(labels)


## Dismisses whatever plate the pass raised.
func _release_plate() -> void:
	var overlay: QuickBattleOverlay = _play.hud.quick_battle_overlay
	var guard: int = 0
	while overlay != null and overlay.is_shown() and guard < 4:
		if guard == 0:
			_say("  the plate reads: %s" % _plate_text())
		overlay.skip()
		overlay._on_continue()
		guard += 1


# --- seating ----------------------------------------------------------------


## Marches a crown host onto `target`, so the next land pass fights where the
## harness parked it. `guns` asks for a host that can reach a parapet.
func _march_host(target: int, guns: bool) -> ArmyState:
	var army: ArmyState = _host_for(target, guns)
	if army == null:
		_say("no host %s can be spared" % ("with guns" if guns else "with no firearm"))
		return null
	_say("host: %d regiments (%s)" % [army.count(), _types(army)])
	var owner: int = _play.model.province_owner(target)
	if not DiplomacyRules.invadable(_play.diplomacy, _play.player_faction, owner):
		DiplomacyRules.declare_war(_play.diplomacy, _play.player_faction, owner)
		_say("war declared on %s" % FactionCatalog.name_of(owner))
	var moved: Dictionary = _play.army_layer.order(army, target, true)
	if not bool(moved.get("ok", false)):
		_say("the march was refused: %s" % String(moved.get("reason", "")))
		return null
	_say("marched into %s (fort %d, %d defenders)" % [
		_play.model.province_name(target), FortRules.level_at(_play.model, target),
		_regiments_at(target, owner),
	])
	return army


## A crown host parked on the province next to `target` (fixture: the turn-100
## start keeps every standard at home, and a march from the seat would spend the
## turns this pass exists to read). Grafted from the Home Army when the crown has
## no standard meeting the rule the pass needs.
func _host_for(target: int, guns: bool) -> ArmyState:
	var staging: int = _crown_neighbour(target)
	if staging < 0:
		return null
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.owner != _play.player_faction or army.is_embarked():
			continue
		if army.home:
			continue
		if _reaches(army, guns):
			army.province = staging
			army.moved = false
			return army
	var home: ArmyState = ArmyTraining.home_army(
		_play.army_layer.armies, _play.player_faction
	)
	if home == null:
		return null
	var picks: Array[String] = []
	for regiment_id: String in home.regiments:
		var type_id: String = home.type_of(regiment_id)
		if guns:
			if RegimentCatalog.is_artillery(type_id) or \
					RegimentCatalog.stat(type_id, "rng") >= SiegeLanes.FIREARM_RNG:
				picks.append(regiment_id)
		elif RegimentCatalog.stat(type_id, "rng") < SiegeLanes.FIREARM_RNG:
			picks.append(regiment_id)
		if picks.size() >= 4:
			break
	if picks.size() < 2:
		return null
	var made: Dictionary = _play.army_layer.split(home, picks)
	if not bool(made.get("ok", false)):
		return null
	var host: ArmyState = made["army"] as ArmyState
	host.province = staging
	host.moved = false
	return host


## Can this host do what the pass needs: reach the parapet, and (for the storm)
## drop shot behind it.
func _reaches(army: ArmyState, guns: bool) -> bool:
	var side: Array[ArmyState] = [army]
	if not SiegeLanes.can_reach_wall(side):
		return false
	return SiegeLanes.can_reach_behind(side) if guns else true


## The crown province bordering `target`, or -1.
func _crown_neighbour(target: int) -> int:
	for province: int in MapGeo.province_neighbors(_play.model, target):
		if _play.model.province_owner(province) == _play.player_faction:
			return province
	return -1


## Puts a wall of `level` on `target` with a garrison behind it: infantry on the
## parapet and horse under cover, which is the lane split the plate reports.
func _reseed_wall(target: int, level: int) -> void:
	var owner: int = _play.model.province_owner(target)
	var data: ProvinceState = _play.model.province_data(target)
	data.fort_level = level
	var garrison: ArmyState = _garrison(owner, target)
	if garrison == null:
		return
	_say("the garrison: %d regiments (%s)" % [garrison.count(), _types(garrison)])
	_say("the lanes it mans: %s" % SiegeLanes.describe([garrison]))


## A garrison minted for the wall: musketeers on the parapet, a halberd with
## them and a troop of horse behind it. Minted rather than borrowed so both
## levels are read against the same defenders.
func _garrison(owner: int, province: int) -> ArmyState:
	var types: Array[String] = []
	types.assign(WALL_TYPES)
	var made: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, owner, province, false, types, 1000
	)
	_play.army_layer.next_army += 1
	_play.army_layer.armies.append(made)
	_play.army_layer.prune_markers()
	return made


## A rival host parked on the province next to the crown's wall, at war.
func _seat_rival_besieger(wall: int, rival: int) -> ArmyState:
	for neighbour: int in MapGeo.province_neighbors(_play.model, wall):
		var owner: int = _play.model.province_owner(neighbour)
		if owner != rival:
			continue
		var foe: ArmyState = _garrison(owner, neighbour)
		if foe == null:
			continue
		if not DiplomacyRules.invadable(_play.diplomacy, owner, _play.player_faction):
			var war: Dictionary = DiplomacyRules.declare_war(
				_play.diplomacy, owner, _play.player_faction
			)
			if not bool(war.get("ok", false)):
				_say("%s will not declare: %s" % [
					FactionCatalog.name_of(owner), String(war.get("reason", "refused")),
				])
				continue
			_say("%s declares on the crown" % FactionCatalog.name_of(owner))
		foe.moved = false
		var moved: Dictionary = _play.army_layer.order(foe, wall, true)
		if not bool(moved.get("ok", false)):
			_say("the rival's march was refused: %s" % String(moved.get("reason", "")))
			continue
		_say("%s marched %d regiments from %s onto the wall" % [
			FactionCatalog.name_of(owner), foe.count(),
			_play.model.province_name(neighbour),
		])
		return foe
	return null


## A rival province a crown host can reach, skipping the ones already stormed:
## each level is read on its own wall.
func _rival_wall(used: Array[int] = []) -> int:
	for province in _play.model.province_count():
		var owner: int = _play.model.province_owner(province)
		if owner == _play.player_faction or owner == MapModel.NO_ID:
			continue
		if used.has(province):
			continue
		if _crown_neighbour(province) < 0:
			continue
		return province
	return -1


# --- reads ------------------------------------------------------------------


func _fort_row() -> String:
	return _sheet_row(_fort_province)


## The province sheet's Fort row, which is the number the crown is told about.
func _sheet_row(province: int) -> String:
	if province < 0:
		return "no province"
	MapPlayInput.select_province(_play, province, Vector2.INF)
	var grid: ProvinceFactsGrid = _play.hud.panels.panel._grid
	if grid == null or grid.fort == null:
		return "no Fort row"
	return grid.fort.text


func _lens_line(province: int) -> String:
	_play.defence_lens.refresh()
	for entry: Variant in _play.defence_lens.survey.get("provinces", []):
		var row: Dictionary = entry as Dictionary
		if int(row.get("id", -1)) != province:
			continue
		return "%s · %s" % [String(row.get("band", "")), String(row.get("summary", ""))]
	return "the lens does not chart it"


func _regiments_at(province: int, owner: int) -> int:
	var count: int = 0
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.owner == owner and army.province == province:
			count += army.count()
	return count


func _types(army: ArmyState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for regiment_id: String in army.regiments:
		parts.append(army.type_of(regiment_id))
	return ", ".join(parts) if not parts.is_empty() else "none"


func _civilian(type_id: String) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit != null and unit.owner == _play.player_faction and unit.type_id == type_id:
			return unit
	return null


func _stockpile() -> String:
	return _counts_text(_stockpile_counts())


func _stockpile_counts() -> Dictionary:
	var economy: PlayerEconomy = _play.economy.economy
	return economy.stockpile.duplicate() if economy != null else {}


func _counts_text(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		parts.append("%s %d" % [String(key), int(counts[key])])
	return " · ".join(parts)


func _dump_panel(node: Node, label: String) -> void:
	var lines: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(node, "", lines)
	_say("%s:" % label)
	for line: String in lines:
		_say("  · %s" % line)


## The dossier's own fort order: the one work whose name carries the level it
## would raise ("Build wood fort · 3 lumber + 3 bronze · 1 turn").
func _fort_button(node: Node) -> Button:
	for child: Node in _visible(node):
		if child is Button and (child as Button).text.contains("fort"):
			return child as Button
	return null


func _visible(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node == null:
		return out
	if node.visible:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_visible(child))
	return out


func _toast_text() -> String:
	if _play.hud._toast_box == null:
		return "none"
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud._toast_box, "", labels)
	return " | ".join(labels) if not labels.is_empty() else "none"


func _last_toast() -> String:
	var text: String = _toast_text()
	if text == "none":
		return "none"
	var parts: PackedStringArray = text.split(" | ")
	return parts[parts.size() - 1]


func _clear_toasts() -> void:
	for child: Node in _play.hud._toast_box.get_children():
		child.queue_free()


func _take_turn() -> void:
	var guardian: int = 0
	var was: int = _play.turn
	while guardian < 8:
		MapPlayTurn.end_turn(_play)
		_release_plate()
		if _play.turn != was or _play.campaign_over():
			return
		if not SaveDrive.answer_pending(_play):
			return
		guardian += 1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	SaveDrive.clean_dir(DIR)
	print("\n--- playtest_siege: %d steps ---" % _steps.size())
	quit()
