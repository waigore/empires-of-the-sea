extends SceneTree
## Headless playtest drive for an army's field hospital train (wiki: combat
## § Regiment condition; DR-20261112-07, DR-20261112-08). Six passes read only
## what a player reads:
##
##   1. `_offer_pass` — the dossier's order: its caption, the price it names,
##      what the stockpile pays, and the strength line afterwards.
##   2. `_rest_pass` — a mauled host on bare ground: the train's 40% against the
##      field's 25% over one real turn.
##   3. `_ward_pass` — the better-of rule: a General hospital beats the tents
##      while its staff is fed, and an unfed ward's nurses are not the tents'.
##   4. `_travel_pass` — a split, a combine, boarding a squadron, and the save.
##   5. `_blocked_pass` — the order's refusal on another crown's land.
##   6. `_rival_pass` — rival courts at war, and what the crown can see of their
##      trains.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_field_train.gd
##
## The harness seats the ground (two field armies detached from the Home Army,
## a mauled host, a General hospital) because the turn-100 start opens with
## every army at home and no wards; the rest tick, rations, split/combine, the
## turn ladder and the save browser are the game's own.

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const DIR: String = "user://playtest_field_train"
const SLOT: int = 1
const MAULED: float = 0.30

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _main: Node = null
var _play: PlaySession = null
var _army: ArmyState = null
var _plain: ArmyState = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_screen.save_dir = DIR
	_play = _screen.play
	_say("seed %s — %s, turn %d, purse %d; stockpile %s" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.treasury(), _stockpile(),
	])
	if not _field_armies():
		_finish()
		return
	await _offer_pass()
	await _rest_pass()
	await _ward_pass()
	await _travel_pass()
	await _blocked_pass()
	await _rival_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## The dossier's own order: the caption a player reads, the materials the
## stockpile pays, and the strength line that must change with it.
func _offer_pass() -> void:
	_say("")
	_say("--- the dossier's order at the seat (bare ground, no ward) ---")
	_play.army_layer.select(_army)
	await process_frame
	_dump_panel("before pitching")
	var before: Dictionary = _stockpile_counts()
	var button: Button = _button("Pitch a field hospital")
	if button == null:
		_say("no pitch order in the dossier — the rest of the pass cannot read it")
		return
	_say("order caption: \"%s\" (disabled %s)" % [button.text, str(button.disabled)])
	button.emit_signal("pressed")
	await process_frame
	_say("toast: %s" % _last_toast())
	_say("stockpile: %s -> %s" % [_counts_text(before), _stockpile()])
	_dump_panel("after pitching")
	_say("the upkeep the rules count: %d food (panel reads the same line)" % [
		ArmyRoster.food_upkeep_of([_army], _army.owner),
	])
	_say("pitch again pressed: %s" % _press("Pitch a field hospital"))


## The train's whole point: a mauled host mends in the field without going home.
## Two hosts on the same bare province, one carrying tents, one not, over one
## real turn.
func _rest_pass() -> void:
	_say("")
	_say("--- a mauled host on bare ground: the tents against the field ---")
	var province: int = _army.province
	_play.model.province_data(province).hospital_level = 0
	_maul(_army)
	_maul(_plain)
	_say("both hosts mauled to %d%% at %s (hospital %d)" % [
		roundi(MAULED * 100.0), _play.model.province_name(province),
		HospitalRules.level_at(_play.model, province),
	])
	_say("before: with train %s; without %s" % [_health(_army), _health(_plain)])
	var rest: Dictionary = HospitalRules.feed(_play.world, _play.player_faction, 999)
	_say("the wards fed: %s" % str(rest))
	_take_turn()
	_say("after one turn: with train %s; without %s" % [_health(_army), _health(_plain)])


## The better-of rule: a General hospital out-heals the tents while its staff
## is fed; an unfed ward loses its nurses but the tents keep theirs.
func _ward_pass() -> void:
	_say("")
	_say("--- a province ward against the tents ---")
	var province: int = _army.province
	var data: ProvinceState = _play.model.province_data(province)
	data.hospital_level = 2
	data.hospital_staffed = true
	_maul(_army)
	_maul(_plain)
	_play.army_layer.select(_army)
	await process_frame
	_dump_panel("General hospital, staffed, with a train")
	_play.army_layer.select(_plain)
	await process_frame
	_dump_panel("General hospital, staffed, no train")
	var fed: Dictionary = HospitalRules.feed(_play.world, _play.player_faction, 999)
	_say("the ward fed: %s" % str(fed))
	var starved: Dictionary = HospitalRules.feed(_play.world, _play.player_faction, 0)
	_say("the larder empty: %s" % str(starved))
	_play.army_layer.select(_army)
	await process_frame
	_dump_panel("General hospital, unfed, with a train")
	_play.army_layer.select(_plain)
	await process_frame
	_dump_panel("General hospital, unfed, no train")
	_maul(_army)
	_maul(_plain)
	_say("before the unfed tick: with train %s; without %s" % [
		_health(_army), _health(_plain),
	])
	_play.army_layer.begin_turn(_play.world)
	_say("after the unfed tick: with train %s; without %s" % [
		_health(_army), _health(_plain),
	])


## The train belongs to the standard: a split, a combine, a boarding and a save.
func _travel_pass() -> void:
	_say("")
	_say("--- the train travels with its standard ---")
	var where: int = _army.province
	var before: int = _play.army_layer.armies.size()
	MapPlayArmyMuster.detach(_play, _army, [_army.regiments[0]])
	var detached: ArmyState = _play.army_layer.selected_army
	if detached == null or detached == _army or _play.army_layer.armies.size() == before:
		_say("the split was refused")
		return
	_say("the split's toast: %s" % _last_toast())
	_play.army_layer.select(_army)
	await process_frame
	_dump_panel("the parent after the split")
	_play.army_layer.select(detached)
	await process_frame
	_dump_panel("the detachment after the split")
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, where)
	_say("%s borders %d sea zones; squadrons here: %s" % [
		_play.model.province_name(where), zones.size(), _squadrons_at(where),
	])
	if not _squadrons_at(where).is_empty():
		_play.army_layer.select(_army)
		MapPlayArmies.on_action(_play, "embark")
		await process_frame
		if not _army.is_embarked():
			_say("the boarding was refused: %s" % _last_toast())
		else:
			_say("aboard: province %d, upkeep %d food" % [
				_army.province, _food_upkeep(_army),
			])
			var fleet: FleetState = _port_fleet(where)
			_say("the fleet dossier reads: %s" % _fleet_line(fleet))
			# A player lands from the fleet's own dossier; the row needs the
			# squadron selected, so tap its standard first.
			_play.ship_layer.select(_ship_of(fleet))
			await process_frame
			MapPlayFleets.land(_play, where)
			await process_frame
			_say("after landing: province %d (%s)" % [
				_army.province, _play.model.province_name(_army.province),
			])
			_play.army_layer.select(_army)
			await process_frame
			_dump_panel("after landing")
	_play.army_layer.select(_army)
	MapPlayArmyMuster.merge(_play, _army)
	await process_frame
	_say("the combine's toast: %s" % _last_toast())
	_say("after the combine: %s" % _standards(where))
	var carrier: ArmyState = _train_standard()
	if carrier != null:
		_say("the train now rides: %s at %s%s" % [
			FactionCatalog.name_of(carrier.owner),
			_play.model.province_name(carrier.province),
			" (the Home Army)" if carrier.home else " (a field standard)",
		])
		_play.army_layer.select(carrier)
		await process_frame
		_dump_panel("the combined standard")
	_say("save: %s" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_say("the load replaced the screen with something else")
		return
	_play = _screen.play
	await process_frame
	_army = _train_standard()
	_say("after the load: %s" % _standards(_play.capital_province))
	if _army != null:
		_play.army_layer.select(_army)
		await process_frame
		_dump_panel("the train after a save and load")


## The order's refusal: an army standing on another crown's land is shown the
## rules' own reason, disabled, instead of a hidden order (DR-20261112-07).
func _blocked_pass() -> void:
	_say("")
	_say("--- the order on another crown's land ---")
	var army: ArmyState = _field_standard()
	if army == null:
		var home: ArmyState = ArmyTraining.home_army(
			_play.army_layer.armies, _play.player_faction
		)
		if home == null or home.count() < 3:
			_say("no standard can be spared for the march")
			return
		var made: Dictionary = _play.army_layer.split(home, home.regiments.slice(0, 2))
		if not bool(made.get("ok", false)):
			_say("the detachment was refused")
			return
		army = made["army"] as ArmyState
	# A detachment inherits its parent's march, so a fresh standard may have to
	# wait for the next turn like any other host.
	if army.moved:
		_say("the detached standard has already marched; the calendar moves first")
		_take_turn()
		_play.army_layer.select(army)
	var frontier: Array[int] = _frontier(army.province)
	if frontier.is_empty():
		_say("no foreign land borders this crown's provinces — the refusal cannot be read")
		return
	var border: int = frontier[0]
	var target: int = frontier[1]
	_say("marching %d regiments from %s to %s, then into %s (owned by %s)" % [
		army.count(), _play.model.province_name(army.province),
		_play.model.province_name(border), _play.model.province_name(target),
		FactionCatalog.name_of(_play.model.province_owner(target)),
	])
	_play.army_layer.select(army)
	var first: Dictionary = _play.army_layer.order(army, border, true)
	await process_frame
	_say("the march to the border: %s" % _verdict(first))
	_take_turn()
	_play.army_layer.select(army)
	var owner: int = _play.model.province_owner(target)
	if not DiplomacyRules.invadable(_play.diplomacy, _play.player_faction, owner):
		DiplomacyRules.declare_war(_play.diplomacy, owner, _play.player_faction)
		_say("declared war on %s" % FactionCatalog.name_of(owner))
	var marched: Dictionary = _play.army_layer.order(army, target, true)
	await process_frame
	if not bool(marched.get("ok", false)):
		_say("the march was refused: %s" % String(marched.get("reason", "")))
		return
	_say("the army stands in %s (owned by %s)" % [
		_play.model.province_name(army.province),
		FactionCatalog.name_of(_play.model.province_owner(army.province)),
	])
	_dump_panel("on another crown's land")
	var button: Button = _button("Tents are pitched")
	if button != null:
		_say("the order reads: \"%s\" (disabled %s)" % [button.text, str(button.disabled)])


## An own province that has a neighbour held by another crown, and that
## neighbour: `[own, foreign]`, or empty.
func _frontier(from: int) -> Array[int]:
	var first: Array[int] = []
	for province in _play.model.province_count():
		if _play.model.province_owner(province) != _play.player_faction:
			continue
		for neighbour: int in MapGeo.province_neighbors(_play.model, province):
			var owner: int = _play.model.province_owner(neighbour)
			if owner == MapModel.NO_ID or owner == _play.player_faction:
				continue
			if province == from:
				return [province, neighbour]
			if first.is_empty():
				first = [province, neighbour]
	return first


## The first field standard of the crown, or null when every regiment is home.
func _field_standard() -> ArmyState:
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.owner != _play.player_faction or army.home:
			continue
		if army.province == MapModel.NO_ID or army.is_embarked():
			continue
		return army
	return null


## Rival courts at war: does a rival pitch, and can the crown see it?
func _rival_pass() -> void:
	_say("")
	_say("--- rivals at war: their surgeons, and what the crown sees ---")
	var rival: int = -1
	for gp: int in FactionCatalog.great_power_ids():
		if gp != _play.player_faction:
			rival = gp
			break
	if rival < 0:
		_say("no rival Great Power to declare on")
		return
	DiplomacyRules.declare_war(_play.diplomacy, rival, _play.player_faction)
	_say("war declared on %s; closing turns" % FactionCatalog.name_of(rival))
	var pitches: int = 0
	for _index in 6:
		_play.ai_trace.clear()
		_take_turn()
		for record: Dictionary in _play.ai_trace:
			if String(record.get("kind", "")) != MapPlayArmyAi.KIND_HOSPITAL:
				continue
			pitches += 1
			_say("  turn %d: %s pitches at %s (army %d)" % [
				_play.turn, FactionCatalog.name_of(int(record.get("faction", -1))),
				String(record.get("province_name", "")), int(record.get("army", -1)),
			])
	_say("rival trains pitched over six turns: %d" % pitches)
	if pitches == 0:
		_say("the policy needs a worn FIELD army on its own ground; no rival host")
		_say("lost a fight in six quiet turns, so the rule was never offered")
	var seen: Array[ArmyState] = []
	for army: ArmyState in _play.army_layer.armies:
		if army != null and army.owner != _play.player_faction and army.field_hospital:
			seen.append(army)
	_say("rival standards carrying a train in this region: %d" % seen.size())
	if not seen.is_empty():
		_play.army_layer.select(seen[0])
		await process_frame
		_dump_panel("a rival standard with a train")


# --- seating ---------------------------------------------------------------


## Two field hosts at the seat: one will carry the tents, one is the control.
func _field_armies() -> bool:
	var home: ArmyState = ArmyTraining.home_army(
		_play.army_layer.armies, _play.player_faction
	)
	if home == null or home.count() < 7:
		_say("the Home Army cannot spare two field hosts (%d regiments)" % (
			home.count() if home != null else 0
		))
		return false
	var first: Dictionary = _play.army_layer.split(home, home.regiments.slice(0, 4))
	var second: Dictionary = _play.army_layer.split(home, home.regiments.slice(0, 3))
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		_say("the detachments were refused")
		return false
	_army = first["army"] as ArmyState
	_plain = second["army"] as ArmyState
	_say("two field hosts detached at %s: %d and %d regiments" % [
		_play.model.province_name(_army.province), _army.count(), _plain.count(),
	])
	return true


## Wounds a host the way a break does: a share of every regiment's pool, floored
## at one point (a wound never destroys a regiment — DR-20261110-19).
func _maul(army: ArmyState) -> void:
	for regiment_id: String in army.regiments:
		var top: int = RegimentCondition.max_health(army.type_of(regiment_id))
		army.regiment_health[regiment_id] = maxi(1, roundi(float(top) * MAULED))


# --- reads -----------------------------------------------------------------


func _dump_panel(label: String) -> void:
	var lines: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud.panels.army_panel, "", lines)
	_say("dossier %s:" % label)
	for line: String in lines:
		if line.begins_with("Detach") or line.begins_with("Tercio"):
			continue
		_say("  · %s" % line)


## "30% · 30% ..." — the share of its pool every regiment in the host carries.
## Shares, not points: the re-equip pass swaps a host's types on the first turn,
## so a maximimum read before the turn is not the one read after it.
func _health(army: ArmyState) -> String:
	if army == null:
		return "no host"
	var parts: PackedStringArray = PackedStringArray()
	var total: float = 0.0
	for regiment_id: String in army.regiments:
		var share: float = RegimentCondition.fraction(army, regiment_id)
		total += share
		parts.append("%d%%" % roundi(share * 100.0))
	var average: int = roundi(total / float(maxi(army.regiments.size(), 1)) * 100.0)
	return "mean %d%% (%s)" % [average, " · ".join(parts)]


## Every standard standing at `province`, with the train each carries.
func _standards(province: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.province != province:
			continue
		parts.append("army %d (%s, %d regiments, train %s)" % [
			army.id, FactionCatalog.name_of(army.owner), army.count(),
			str(army.field_hospital),
		])
	return ", ".join(parts) if not parts.is_empty() else "none"


## The crown's standard carrying the tents, Home Army included: a combine at the
## seat merges into the Home Army, and the train must survive it.
func _train_standard() -> ArmyState:
	for army: ArmyState in _play.army_layer.armies:
		if army == null or army.owner != _play.player_faction:
			continue
		if army.field_hospital:
			return army
	return null


## The crown's squadron moored at `province`, or null.
func _port_fleet(province: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or fleet.owner != _play.player_faction:
			continue
		if fleet.is_in_port() and fleet.province == province:
			return fleet
	return null


## The map standard that stands for `fleet`; the fleet dossier is opened by
## selecting it, as a tap on the squadron does.
func _ship_of(fleet: FleetState) -> Ship:
	if fleet == null:
		return null
	for ship: Ship in _play.ship_layer.ships:
		if ship != null and ship.fleet_id == fleet.id:
			return ship
	return null


## The fleet dossier's own line for the troops it carries, if any.
func _fleet_line(fleet: FleetState) -> String:
	if fleet == null:
		return "no squadron"
	var lines: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud._fleet_panel, "", lines)
	for line: String in lines:
		if line.contains("carrying") or line.contains("regiments"):
			return line
	return "%d hulls, no soldiers named" % fleet.ship_count()


func _squadrons_at(province: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or fleet.owner != _play.player_faction:
			continue
		if fleet.is_in_port() and fleet.province == province:
			parts.append("%d hulls" % fleet.ship_count())
	return ", ".join(parts)


func _verdict(result: Dictionary) -> String:
	if bool(result.get("ok", false)):
		return "marched"
	return String(result.get("reason", "refused"))


func _food_upkeep(army: ArmyState) -> int:
	return ArmyRoster.food_upkeep_of([army], army.owner)


func _stockpile() -> String:
	var counts: Dictionary = _stockpile_counts()
	return _counts_text(counts)


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


func _button(prefix: String) -> Button:
	var found: Button = null
	for node: Node in _visible(_play.hud.panels.army_panel):
		if node is Button and (node as Button).text.begins_with(prefix):
			found = node
	return found


func _press(prefix: String) -> String:
	var button: Button = _button(prefix)
	if button == null:
		return "no such order in the dossier"
	if button.disabled:
		return "blocked: \"%s\"" % button.text
	button.emit_signal("pressed")
	return "pressed \"%s\"" % button.text


func _visible(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node == null:
		return out
	if node.visible:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_visible(child))
	return out


func _last_toast() -> String:
	if _play.hud._toast_box == null:
		return "none"
	var labels: PackedStringArray = PackedStringArray()
	SaveDrive.collect_text(_play.hud._toast_box, "", labels)
	return labels[labels.size() - 1] if not labels.is_empty() else "none"


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


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_field_train: %d steps ---" % _steps.size())
	quit()
