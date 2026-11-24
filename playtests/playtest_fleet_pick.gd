extends SceneTree
## Headless free-playtest drive for the fleet dossier's advice line: what the
## court's own admiral would order a squadron this turn (wiki: ships-and-naval
## § Missions and Movement, ai-architecture § Naval policy; DR-20261120-04).
##
## The drive reads only what the crown is shown. It reaches the states a player
## reaches in the first turns — the home squadron in port, then at sea, then at
## war, then a rival squadron in the next water — and reads the gold line under
## the dossier's station note in each. Every word is held to the planner's own
## record: the same call the rival pass and the Auto seat make for a court, asked
## again with the crown's own chart, footing and roster. Then it checks that the
## hulls have not moved, because the line is advice and never an order.
##
## A rival squadron is seated in the water only where a scenario seat is the
## shortest way to the branch; the sortie, the war and the dossier are the game's
## own.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_fleet_pick.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _fleet: FleetState = null
var _rival: int = -1
var _checks: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	var player: int = _play.player_faction
	_fleet = _play.ship_layer.home_fleet(_play.capital_province)
	_rival = _first_rival(player)
	_say("seed %s · turn %d · player %s · home squadron %s" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(player),
		"none" if _fleet == null else _station(_fleet),
	])
	if _fleet == null or _rival < 0:
		_say("no home squadron or no rival Great Power on this chart")
		_finish()
		return
	_read_pass("in port at the seat, at peace", player)
	if not _sortie_pass(player):
		_finish()
		return
	_read_pass("at sea in the seat's water, at peace", player)
	_declare(player, _rival)
	_read_pass("at sea, at war with %s" % FactionCatalog.name_of(_rival), player)
	var foe: FleetState = _seat_rival(_next_water(), _rival)
	if foe == null:
		_say("no rival squadron could be seated in the next water")
	else:
		_say("")
		_say("  the rival: %s in the %s" % [
			FactionCatalog.name_of(_rival), _play.model.sea_zone_name(foe.sea_zone),
		])
		_read_pass("a hostile squadron in the next water", player)
		_moor_merchant(player)
		_read_pass("the holds ashore again, and a hostile in the next water", player)
	_quiet_pass(player)
	_finish()


## One read of the dossier's advice line, held to the planner's own record: the
## pick's kind, water and harbour are the order's, the words name the place, the
## sheet prints them, and no hull has moved.
func _read_pass(label: String, player: int) -> void:
	_say("")
	_say("=== %s ===" % label)
	var before: Dictionary = _state_of(player)
	var pick: Dictionary = MapPlayFleetPick.pick(_play, _fleet)
	var order: Dictionary = _planner_order(player)
	_say("  fleet %d · %s" % [_fleet.id, _station(_fleet)])
	_say("  the planner: %s" % _order_text(order))
	_check(
		"the pick is the planner's own order",
		pick.is_empty() == order.is_empty()
			and String(pick.get("kind", "")) == String(order.get("kind", ""))
			and int(pick.get("zone", MapModel.NO_ID)) == int(order.get("zone", MapModel.NO_ID))
			and bool(pick.get("dock", false)) == bool(order.get("dock", false))
			and int(pick.get("province", MapModel.NO_ID)) == int(order.get("province", MapModel.NO_ID)),
		_order_text(pick)
	)
	if pick.is_empty():
		_say("  the court gives her no order")
	else:
		var line: String = String(pick.get("line", ""))
		_say("  the sheet: %s" % line)
		_check("the words name the water or the harbour", _names_place(line, pick), line)
	_check(
		"nothing sailed: the roster is where it was",
		_state_of(player) == before,
		"%d squadron(s)" % _own_flights(player).size()
	)
	_sheet_pass(player)


## The dossier's own line: the gold row under the station note prints the pick's
## words, and hides when the court would give her none.
func _sheet_pass(player: int) -> void:
	_select()
	var section: FleetMissionSection = _screen.hud._fleet_panel._mission
	var expected: String = MapPlayFleetPick.line(_play, _fleet)
	_say("  the gold row: \"%s\"" % section._pick.text)
	_check("the dossier prints the pick", section._pick.text == expected, section._pick.text)
	_check(
		"the row follows the pick",
		section._pick.visible == not expected.is_empty(),
		"visible %s" % str(section._pick.visible)
	)
	_check(
		"the block stands behind the pick",
		section.visible if not expected.is_empty() else true,
		"block visible %s" % str(section.visible)
	)


## A squadron the crown has already ordered carries no advice, and the sheet keeps
## its block without the gold row.
func _quiet_pass(player: int) -> void:
	_say("")
	_say("=== a squadron that has sailed ===")
	_sheet_pass(player)
	_fleet.moved = true
	_check(
		"a hull that has sailed is not re-ordered",
		MapPlayFleetPick.pick(_play, _fleet).is_empty(),
		"fleet %d" % _fleet.id
	)
	_sheet_pass(player)
	_fleet.moved = false


# --- the reached state -------------------------------------------------------


## The home squadron puts to sea in the water beside the seat: the sortie spends
## her move, so the drive clears that one field the way a turn boundary does.
func _sortie_pass(player: int) -> bool:
	_say("")
	_say("=== sortie: the home squadron to sea ===")
	var zones: Array[int] = FleetSortie.zones(_play.model, _fleet)
	if zones.is_empty():
		_say("the seat has no water to sortie into")
		return false
	MapPlayCivilianVoyage.sortie(_play, _fleet, zones[0])
	var fleet: FleetState = _fleet_by_id(_fleet.id)
	if fleet == null or not fleet.is_at_sea():
		_say("the home squadron did not reach the water")
		return false
	_fleet = fleet
	_fleet.moved = false
	_say("  %s" % _station(_fleet))
	return true


## Water the crown's squadron could enter next, other than the one she holds.
func _next_water() -> int:
	var zones: Array[int] = NavalMovement.destination_zones(_play.model, _fleet)
	for zone: int in zones:
		if zone != _fleet.sea_zone:
			return zone
	return -1


## A merchant hull moored in port at the seat, so the crown keeps holds ashore:
## the policy's holds-first release stands aside and the hunt is what the court
## would order. One hull of the crown's own, seated where a player's capture or
## a surviving second command would put her.
func _moor_merchant(player: int) -> void:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == player and fleet.is_in_port():
			return
	var seat: int = NavalMovement.seat_harbour(_play.model, player)
	if seat < 0:
		return
	var moored: FleetState = FleetState.in_port(
		_play.ship_layer.next_hull + 80, player, seat, ["playtest_hold_1"], {"playtest_hold_1": "galleon"}
	)
	_play.ship_layer.fleets.append(moored)
	_play.ship_layer.rebuild_markers()
	_say("")
	_say("  a merchant moored at %s: %d holds ashore" % [
		_play.model.province_name(seat), TradeCargo.fleet_holds(moored),
	])


func _seat_rival(zone: int, rival: int) -> FleetState:
	if zone < 0:
		return null
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == rival and fleet.is_afloat():
			fleet.location = FleetState.Location.AT_SEA
			fleet.sea_zone = zone
			fleet.province = MapModel.NO_ID
			fleet.clear_beachhead()
			fleet.moved = true
			fleet.mission = FleetState.Mission.MOVE
			_play.ship_layer.rebuild_markers()
			return fleet
	return null


func _declare(player: int, rival: int) -> void:
	_say("")
	_say("--- war on %s ---" % FactionCatalog.name_of(rival))
	if DiplomacyRules.at_war_with(_play.diplomacy, player, rival):
		_say("  already at war")
		return
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, player, rival)
	_say("  %s" % (
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused"))
	))


# --- the planner's own record ------------------------------------------------


## The order the published naval policy gives the crown's squadron, asked exactly
## as the rival pass asks it.
func _planner_order(player: int) -> Dictionary:
	var kind: String = AiControl.court_kind(_play, player)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(kind, player, _play.map_seed)
	var plan: Dictionary = AiBindCampaign.naval_orders(
		kind, config, _play.diplomacy, _play.model,
		MapPlayCourt.region_fleets(_play, _play.model.region_id), _play.court_charts
	)
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		if int(order.get("fleet_id", -1)) == _fleet.id:
			return order
	return {}


func _order_text(order: Dictionary) -> String:
	if order.is_empty():
		return "no order"
	var parts: PackedStringArray = PackedStringArray()
	parts.append("kind %s" % String(order.get("kind", "")))
	if int(order.get("zone", MapModel.NO_ID)) != MapModel.NO_ID:
		parts.append("water %s" % _play.model.sea_zone_name(int(order["zone"])))
	if bool(order.get("dock", false)):
		parts.append("dock %s" % _play.model.province_name(int(order.get("province", -1))))
	if int(order.get("threat", 0)) > 0:
		parts.append("threat %d" % int(order["threat"]))
	if not String(order.get("reason", "")).is_empty():
		parts.append("reason %s" % String(order["reason"]))
	return " · ".join(parts)


## True when the printed line carries the place the order names.
func _names_place(line: String, order: Dictionary) -> bool:
	var zone: int = int(order.get("zone", MapModel.NO_ID))
	if zone != MapModel.NO_ID:
		return line.contains(_play.model.sea_zone_name(zone))
	var port: int = int(order.get("province", MapModel.NO_ID))
	if port == MapModel.NO_ID:
		return false
	return line.contains(_play.model.province_name(port))


# --- world helpers -----------------------------------------------------------


func _own_flights(player: int) -> Array[FleetState]:
	var out: Array[FleetState] = []
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet != null and fleet.owner == player and fleet.is_afloat():
			out.append(fleet)
	out.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return out


func _first_rival(player: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		var owner: int = _play.model.province_owner(province.id)
		if owner == player or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
			return owner
	return -1


func _fleet_by_id(fleet_id: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


## What every own squadron is, so a read can prove it moved nothing.
func _state_of(player: int) -> Dictionary:
	var out: Dictionary = {}
	for fleet: FleetState in _own_flights(player):
		out[fleet.id] = "%d|%d|%d|%s|%d" % [
			fleet.location, fleet.sea_zone, fleet.province, str(fleet.moved), fleet.mission,
		]
	return out


func _select() -> void:
	var ship: Ship = _play.ship_layer.ship_for(_fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % _fleet.id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "at sea · %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "in port · %s" % _play.model.province_name(fleet.province)


func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	_say("  %s %s — %s" % ["ok  " if ok else "FAIL", label, detail])


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_fleet_pick: %d steps, %d checks, %d failed ---" % [
		_steps.size(), _checks, _failed,
	])
	quit()
