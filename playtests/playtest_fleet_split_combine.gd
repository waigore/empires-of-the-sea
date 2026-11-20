extends SceneTree
## Headless free-playtest drive for the squadron's split and combine (wiki:
## ships-and-naval § Ship instances; DR-20261116-12/13): the two commands the
## crown opens with, the combine that folds them into one, the troops that hold
## a split back, the hull that leaves with her name and station, the army a
## combine carries, and the refusals the sheet prints. Every order goes through
## the game's own play helpers (MapPlayFleets.on_action, MapPlayArmies,
## MapPlayTurn) and every line the court reads is printed as it is, so the drive
## falsifies what the wiki promises against what the map shows. Not a CI gate —
## run it by hand:
##   godot --headless --path . --script res://playtests/playtest_fleet_split_combine.gd
##
## A carried army is seated where a boarding would have put it (the crown holds
## no port but its seat, so no second harbour exists to sail into); the split,
## the combine, the roster surgery, the markers and the receipts are real.

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const SAVE_DIR: String = "user://playtest_split_combine"

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _zone: int = -1
var _combined: int = -1
var _split: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	var player: int = _play.player_faction
	_say("seed %s · turn %d · player %s · capital %s (%d)" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(player),
		_play.model.province_name(_play.capital_province), _play.capital_province,
	])
	_roster_pass(player)
	_home_pass(player)
	_combine_pass(player)
	_troops_pass(player)
	_split_pass(player)
	_refusal_pass(player)
	_army_combine_pass(player)
	_ledger_pass(player)
	_persist_pass(player)
	_finish()


# --- passes -----------------------------------------------------------------


## What the crown floats at the opening, and what the dossier says about the
## home squadron.
func _roster_pass(player: int) -> void:
	_say("")
	_say("--- roster: the crown's squadrons ---")
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != player:
			continue
		_say("  fleet %d at %s — %s" % [fleet.id, _station(fleet), _named_hulls(fleet)])


## The home squadron keeps the seat: whatever it may or may not split, the sheet
## has to say why, and the combine drawer must not offer the home fleet.
func _home_pass(player: int) -> void:
	_say("")
	_say("--- home fleet: the seat ---")
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home == null:
		_say("  no home fleet at the capital")
		return
	_select(home)
	_print_dossier()
	_print_split_rows(home)
	_print_combine_rows(home)
	_clear_toasts()
	MapPlayFleets.on_action(_play, "split:%s" % home.hulls[0])
	_my_toasts()
	_say("  after the press: fleet %d holds %d hulls" % [home.id, home.ship_count()])


## The combine the opening actually needs: the crown floats single hulls in one
## water, so the pair is folded into one squadron before anything can split.
func _combine_pass(player: int) -> void:
	_say("")
	_say("--- combine: the opening's two commands ---")
	var source: FleetState = _first_with(player, 1)
	var target: FleetState = null
	if source != null:
		target = _other_in_station(player, source)
	if source == null or target == null:
		_say("  the crown floats no pair in one station")
		return
	_zone = source.sea_zone if source.is_at_sea() else _zone_beside(source.province)
	_select(source)
	_print_combine_rows(source)
	var hulls_before: int = target.ship_count()
	var joined: String = _named_hulls(source)
	var moved_before: bool = source.moved or target.moved
	_clear_toasts()
	MapPlayFleets.on_action(_play, "combine:%d" % target.id)
	_my_toasts()
	_say("  target fleet %d: %d -> %d hulls" % [
		target.id, hulls_before, target.ship_count(),
	])
	_say("  joined: %s" % joined)
	_say("  target now: %s at %s, moved %s (either had moved: %s)" % [
		_named_hulls(target), _station(target), str(target.moved), str(moved_before),
	])
	_say("  the emptied command is still on the roster: %s" % str(
		_fleet_by_id(source.id) != null
	))
	_combined = target.id
	_select(target)
	_print_dossier()


## Troops aboard hold the split back; the landing opens it, and one hull leaves
## with her name, her type and her station.
func _troops_pass(player: int) -> void:
	_say("")
	_say("--- troops: the army that holds the split ---")
	var fleet: FleetState = _fleet_by_id(_combined)
	if fleet == null:
		_say("  the combined squadron is gone")
		return
	var army: ArmyState = _seat_carried(player, fleet)
	_say("  seated a %d-regiment army aboard fleet %d (the state boarding makes)" % [
		army.count(), fleet.id,
	])
	_select(fleet)
	_print_dossier()
	_print_split_rows(fleet)
	_clear_toasts()
	MapPlayFleets.on_action(_play, "split:%s" % fleet.hulls[0])
	_my_toasts()
	_say("  after the press: fleet %d holds %d hulls, army aboard fleet %d" % [
		fleet.id, fleet.ship_count(), army.embarked_fleet,
	])
	var rows: Array[Dictionary] = MapPlayFleets.landing_rows(_play, fleet)
	if rows.is_empty():
		_say("  no crown coast in this zone to land the troops on")
		return
	var destination: int = int(rows[0]["province"])
	_clear_toasts()
	MapPlayFleets.on_action(_play, "land:%d" % destination)
	_my_toasts()
	_say("  landed at %s: fleet carries %d, fleet embarked_army %d" % [
		_play.model.province_name(destination), MapPlayFleets.carried(_play, fleet),
		fleet.embarked_army,
	])


## One hull leaves the squadron she was folded into.
func _split_pass(player: int) -> void:
	_say("")
	_say("--- split: one hull into a command of her own ---")
	var fleet: FleetState = _fleet_by_id(_combined)
	if fleet == null or fleet.ship_count() < 2:
		_say("  no squadron of two hulls to split")
		return
	_select(fleet)
	_print_split_rows(fleet)
	var hull_id: String = fleet.hulls[0]
	var hull_name: String = ShipNames.of(fleet, hull_id)
	var hull_type: String = fleet.type_of(hull_id)
	var before: int = _play.ship_layer.fleets.size()
	_clear_toasts()
	MapPlayFleets.on_action(_play, "split:%s" % hull_id)
	_my_toasts()
	_say("  roster %d -> %d squadrons" % [before, _play.ship_layer.fleets.size()])
	var split: FleetState = _fleet_with_hull(hull_id)
	if split == null:
		_say("  the hull is on no squadron — the split lost her")
		return
	_split = split.id
	_say("  detached: fleet %d at %s — %s (%s), name kept %s, moved %s" % [
		split.id, _station(split), hull_id, hull_type,
		str(ShipNames.of(split, hull_id) == hull_name), str(split.moved),
	])
	_say("  source: fleet %d at %s — %s" % [fleet.id, _station(fleet), _named_hulls(fleet)])
	_say("  the new command's station: mission %d, beachhead %d, army %d" % [
		split.mission, split.beachhead_province, split.embarked_army,
	])
	_select(split)
	_print_dossier()
	_print_split_rows(split)
	_print_combine_rows(split)


## A combine that carries an army: the troops come aboard, and the court's own
## book has to find the squadron that now holds them.
func _army_combine_pass(player: int) -> void:
	_say("")
	_say("--- combine: the army that changes decks ---")
	var target: FleetState = _fleet_by_id(_combined)
	var split: FleetState = _fleet_by_id(_split)
	if target == null or split == null:
		_say("  the two commands are gone")
		return
	var army: ArmyState = _seat_carried(player, split)
	_say("  seated a %d-regiment army aboard fleet %d (the state boarding makes)" % [
		army.count(), split.id,
	])
	_select(split)
	_print_dossier()
	_print_combine_rows(split)
	_clear_toasts()
	MapPlayFleets.on_action(_play, "combine:%d" % target.id)
	_my_toasts()
	_say("  after the combine: fleet %d holds %d hulls, embarked_army %d" % [
		target.id, target.ship_count(), target.embarked_army,
	])
	_say("  the army's own seat: embarked_fleet %d (live squadron: %s)" % [
		army.embarked_fleet, str(_fleet_by_id(army.embarked_fleet) != null),
	])
	_select(target)
	_print_dossier()
	_print_force_army(army)
	var focused: bool = MapPlayForceLedger.focus(
		_play, _play.region_index, ForceLedger.KIND_ARMY, army.id
	)
	_say("  the muster roll's own press on the army: %s (selected fleet %d)" % [
		str(focused), _selected_fleet_id(),
	])
	var rows: Array[Dictionary] = MapPlayFleets.landing_rows(_play, target)
	if not rows.is_empty():
		_clear_toasts()
		MapPlayFleets.on_action(_play, "land:%d" % int(rows[0]["province"]))
		_my_toasts()
		_say("  landed from the combined squadron: fleet carries %d" % MapPlayFleets.carried(
			_play, target
		))
	_dump_carried("after the landing")
	_run_turn()
	_dump_carried("after the turn")
	_say("  after a turn: army %d embarked_fleet %d, fleet %d embarked_army %d" % [
		army.id, army.embarked_fleet, target.id, target.embarked_army,
	])


## The refusals the sheet prints, read from the rules' own gate.
func _refusal_pass(player: int) -> void:
	_say("")
	_say("--- refusals: what the sheet says instead of a press ---")
	var fleet: FleetState = _fleet_by_id(_combined)
	if fleet == null:
		_say("  no crown squadron left")
		return
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home != null:
		_say("  home fleet as a target: %s" % String(
			FleetCombine.can_combine(_play.model, fleet, home).get("reason", "")
		))
		_say("  home fleet split: %s" % String(
			FleetSplit.can_detach(_play.model, home, home.hulls[0]).get("reason", "")
		))
	var far: FleetState = _fleet_elsewhere(player, fleet)
	if far != null:
		_say("  another station (%s): %s" % [
			_station(far), String(
				FleetCombine.can_combine(_play.model, fleet, far).get("reason", "")
			),
		])
	var other: FleetState = _other_in_station(player, fleet)
	if other == null:
		_say("  no second command in this station for the passenger gates")
		return
	# A beachhead holds the squadron until the troops land.
	var marked: int = fleet.beachhead_province
	fleet.beachhead_province = _hostile_coast(fleet)
	fleet.beachhead_turn = _play.turn
	_say("  beachhead marked: %s" % String(
		FleetCombine.can_combine(_play.model, fleet, other).get("reason", "")
	))
	fleet.beachhead_province = marked
	# Two armies: one deck each.
	var army_a: ArmyState = _seat_carried(player, fleet)
	var army_b: ArmyState = _seat_carried(player, other)
	_say("  both decks carry an army: %s" % String(
		FleetCombine.can_combine(_play.model, fleet, other).get("reason", "")
	))
	# An army on one deck and colonists on the other.
	other.embarked_army = -1
	var unit: CivilianState = _seat_colonist(player, other)
	_say("  army and colonists: %s" % String(
		FleetCombine.can_combine(_play.model, other, fleet).get("reason", "")
	))
	# Put the fixture back.
	if unit != null:
		other.remove_civilian(unit.id)
		unit.embarked_fleet = -1
	fleet.embarked_army = -1
	other.embarked_army = -1
	army_a.embarked_fleet = -1
	army_b.embarked_fleet = -1


## The two ledgers the crown reads after the surgery: the navy hull by hull and
## the muster roll's army rows.
func _ledger_pass(player: int) -> void:
	_say("")
	_say("--- ledgers: the navy and the muster roll ---")
	var navy: Dictionary = NavalLedger.snapshot(
		_play.world, _play.ship_layer.regions, player
	)
	_say("  navy: %s" % NavalLedger.summary(navy, LedgerRows.REGION_ALL))
	for group: Dictionary in navy.get("groups", []):
		_say("    %s · %s · %d hulls · %.1f strength" % [
			String(group["heading"]), String(group["place"]),
			int(group["hulls"]), float(group["strength"]),
		])
		for row: Dictionary in group.get("rows", []):
			_say("      %s — %s · %s" % [
				String(row["name"]), String(row["class"]), String(row["state"]),
			])
	var force: Dictionary = ForceLedger.snapshot(
		_play.world, _play.army_layer.regions, _play.ship_layer.regions, player
	)
	for row: Dictionary in force.get("rows", []):
		if String(row.get("kind", "")) != ForceLedger.KIND_ARMY:
			continue
		_say("  muster: %s — %s · %s" % [
			String(row.get("title", "")), String(row.get("place", "")),
			String(row.get("state", "")),
		])


## A split command survives a save and a load with her name, her station and her
## readiness.
func _persist_pass(player: int) -> void:
	_say("")
	_say("--- persistence: the split command in a save ---")
	var fleet: FleetState = _fleet_by_id(_combined)
	if fleet == null or fleet.ship_count() < 2:
		_say("  no squadron of two hulls to split for the save")
		return
	_select(fleet)
	# A hull that has already sailed does not sail again: the new command
	# inherits the source's readiness (wiki: ships-and-naval § Ship instances).
	fleet.moved = true
	_clear_toasts()
	MapPlayFleets.on_action(_play, "split:%s" % fleet.hulls[0])
	_my_toasts()
	var split: FleetState = _other_in_station(player, fleet)
	if split == null:
		_say("  the split left no second command")
		return
	_say("  readiness: source moved %s, new command moved %s" % [
		str(fleet.moved), str(split.moved),
	])
	var hull_id: String = split.hulls[0]
	var name_before: String = ShipNames.of(split, hull_id)
	var where_before: String = _station(split)
	SaveDrive.clean_dir(SAVE_DIR)
	var status: String = SaveDrive.save_slot(_screen, 1)
	_say("  save: %s" % status)
	var loaded: MapScreen = SaveDrive.load_slot(_screen, _screen.get_parent(), 1)
	if loaded == null:
		_say("  the load browser refused the slot")
		return
	_play = loaded.play
	_screen = loaded
	var back: FleetState = _fleet_by_id(split.id)
	if back == null:
		_say("  the split command is not in the loaded roster")
		return
	_say("  loaded: fleet %d at %s (was %s) — %s, name kept %s, moved %s" % [
		back.id, _station(back), where_before, _named_hulls(back),
		str(ShipNames.of(back, hull_id) == name_before), str(back.moved),
	])


# --- fixtures ---------------------------------------------------------------


## Every squadron's carried army and every army's seat, for one line of evidence.
func _dump_carried(where: String) -> void:
	var fleets: PackedStringArray = PackedStringArray()
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.embarked_army >= 0:
			fleets.append("fleet %d -> army %d" % [fleet.id, fleet.embarked_army])
	var armies: PackedStringArray = PackedStringArray()
	for army: ArmyState in _play.army_layer.armies:
		if army != null:
			armies.append("army %d -> fleet %d at %d" % [
				army.id, army.embarked_fleet, army.province,
			])
	_say("  carried %s: [%s] / [%s]" % [
		where, ", ".join(fleets), ", ".join(armies),
	])


## An army in the state a boarding leaves it: no shore of her own, the squadron
## that carries her stored on both sides.
func _seat_carried(player: int, fleet: FleetState) -> ArmyState:
	var army: ArmyState = _muster(player, _play.capital_province, ["infantry"])
	_play.army_layer.remove_marker(army)
	army.province = MapModel.NO_ID
	army.moved = true
	army.embarked_fleet = fleet.id
	fleet.embarked_army = army.id
	return army


## A field army mustered at a province, with the layer's cursors advanced the way
## the muster path advances them.
func _muster(player: int, province: int, types: Array[String]) -> ArmyState:
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, player, province, false, types,
		_play.army_layer.next_regiment
	)
	_play.army_layer.armies.append(army)
	_play.army_layer.next_army += 1
	_play.army_layer.next_regiment += types.size()
	return army


## A colonist aboard, the state an embarkation leaves it.
func _seat_colonist(player: int, fleet: FleetState) -> CivilianState:
	for unit: CivilianState in _play.civilian_layer.units:
		if unit == null or unit.owner != player:
			continue
		if unit.embarked_fleet >= 0:
			continue
		unit.embarked_fleet = fleet.id
		fleet.add_civilian(unit.id)
		return unit
	return null


# --- presentation -----------------------------------------------------------


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % fleet.id)
		return
	_play.ship_layer.select(ship)


func _print_dossier() -> void:
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		_say("  no fleet dossier shown")
		return
	for line: String in _labels(panel):
		_say("    dossier: %s" % line)


func _print_split_rows(fleet: FleetState) -> void:
	var rows: Array[Dictionary] = FleetSplit.rows(_play.model, fleet)
	_say("  split rows (%d):" % rows.size())
	for row: Dictionary in rows:
		_say("    %s — %s%s" % [
			String(row["name"]), String(row["type_name"]),
			"" if bool(row["ok"]) else " · refused: %s" % String(row["reason"]),
		])


func _print_combine_rows(fleet: FleetState) -> void:
	var rows: Array[Dictionary] = FleetCombine.rows(
		_play.model, _play.ship_layer.fleets, fleet
	)
	_say("  combine rows (%d):" % rows.size())
	for row: Dictionary in rows:
		_say("    fleet %d %s — %d hulls%s" % [
			int(row["fleet"]), String(row["name"]), int(row["hulls"]),
			"" if bool(row["ok"]) else " · refused: %s" % String(row["reason"]),
		])


func _print_force_army(army: ArmyState) -> void:
	var force: Dictionary = ForceLedger.snapshot(
		_play.world, _play.army_layer.regions, _play.ship_layer.regions,
		_play.player_faction
	)
	for row: Dictionary in force.get("rows", []):
		if String(row.get("kind", "")) != ForceLedger.KIND_ARMY:
			continue
		if int(row.get("id", -1)) != army.id:
			continue
		_say("  muster row: %s — %s · %s" % [
			String(row.get("title", "")), String(row.get("place", "")),
			String(row.get("state", "")),
		])


func _my_toasts() -> void:
	for panel: Node in _play.hud.despatches.box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("squadron") or lower.contains("hull")
				or lower.contains("fleet") or lower.contains("army")
				or lower.contains("troops") or lower.contains("detach")
				or lower.contains("join")
			):
				_say("    toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _play.hud.despatches.box.get_children():
		child.queue_free()


## Visible label and button text, as a player reads the sheet.
func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		var button: Button = child as Button
		if button != null and not button.text.is_empty():
			out.append("[%s]%s" % [button.text, "" if not button.disabled else " (disabled)"])
		out.append_array(_labels(child))
	return out


# --- turn -------------------------------------------------------------------


func _run_turn() -> void:
	var turn: int = _play.turn
	_clear_toasts()
	MapPlayTurn.end_turn(_play)
	var guard: int = 0
	while _play.turn == turn and not _play.campaign_over() and guard < 12:
		guard += 1
		if not SaveDrive.answer_pending(_play):
			break
	_say("  calendar: turn %d -> %d" % [turn, _play.turn])
	_my_toasts()


# --- world helpers ----------------------------------------------------------


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "sea %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


func _named_hulls(fleet: FleetState) -> String:
	if fleet == null:
		return "—"
	if not fleet.is_afloat():
		return "sunk"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


func _fleet_by_id(fleet_id: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


func _fleet_with_hull(hull_id: String) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.hulls.has(hull_id):
			return fleet
	return null


## The first crown squadron with at least `hulls` hulls, in roster order.
func _first_with(player: int, hulls: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == player and fleet.is_afloat() and fleet.ship_count() >= hulls:
			return fleet
	return null


func _other_in_station(player: int, fleet: FleetState) -> FleetState:
	for other: FleetState in _play.ship_layer.fleets:
		if other == fleet or other.owner != player or not other.is_afloat():
			continue
		if FleetCombine.same_station(fleet, other):
			return other
	return null


func _fleet_elsewhere(player: int, fleet: FleetState) -> FleetState:
	for other: FleetState in _play.ship_layer.fleets:
		if other == fleet or other.owner != player or not other.is_afloat():
			continue
		if not FleetCombine.same_station(fleet, other):
			return other
	return null


func _selected_fleet_id() -> int:
	var fleet: FleetState = _play.ship_layer.fleet_of(_play.ship_layer.selected())
	return fleet.id if fleet != null else -1


## A hostile coast on the squadron's own water, for the beachhead refusal.
func _hostile_coast(fleet: FleetState) -> int:
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, fleet.sea_zone):
		var owner: int = _play.model.province_owner(province_id)
		if owner == _play.player_faction or owner == MapModel.NO_ID:
			continue
		return province_id
	return MapModel.NO_ID


func _zone_beside(province: int) -> int:
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, province)
	return zones[0] if not zones.is_empty() else -1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_fleet_split_combine: %d steps ---" % _steps.size())
	quit()
