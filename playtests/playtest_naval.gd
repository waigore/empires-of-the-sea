extends SceneTree
## Headless free-playtest drive for the naval squadron (wiki: ships-and-naval):
## the crown's own squadron, its named hulls, the sortie out of the home port,
## a station taken on a rival coast, the sea battle the map reports, troops
## carried to another shore, and a port that changes hands. Every order goes
## through the game's own play helpers (MapPlayFleets, MapPlayCivilianVoyage,
## MapPlayFleetMissions, MapPlayNavalTurn, MapPlayPortLoss) and every line the
## court reads is printed as it is, so the drive falsifies what the wiki
## promises against what the map actually shows. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_naval.gd
##
## A squadron is seated or moved only where a scenario seat is the shortest way
## to the rare branch (a rival squadron in the same water, a captured port); the
## movement, stations, combat, loss pruning and presentation are the real ones.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _sortie_fleet_id: int = -1


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
	var war_zone: int = _war_zone(player)
	if war_zone < 0:
		_say("no rival coast on any water the crown can reach")
		_finish()
		return
	var rival: int = _rival_off(war_zone, player)
	_declare(player, rival)
	_troops_pass(player, war_zone)
	_station_pass(war_zone, rival)
	_battle_pass(war_zone, rival)
	_port_pass(player, rival)
	_finish()


## The water the crown will fight on: a zone a sortie or a sail can reach that
## borders a rival Great Power's port.
func _war_zone(player: int) -> int:
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home != null:
		var crew: Dictionary = MapPlayCivilianVoyage.crew(_play, home)
		for raw: Variant in crew.get("sortie", []):
			var zone: int = int((raw as Dictionary)["zone"])
			if _rival_off(zone, player) >= 0:
				return zone
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != player or not fleet.is_afloat():
			continue
		var zone: int = fleet.sea_zone if fleet.is_at_sea() else _zone_beside(fleet.province)
		if zone >= 0 and _rival_off(zone, player) >= 0:
			return zone
	return -1


# --- passes -----------------------------------------------------------------


## What the crown actually owns afloat, and what its dossier says about it. The
## hull names the yard minted are printed beside the dossier line that hides
## them, so the reading is evidence, not opinion.
func _roster_pass(player: int) -> void:
	_say("")
	_say("--- roster: the crown's squadrons ---")
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != player:
			continue
		_say("  fleet %d at %s — %s" % [fleet.id, _station(fleet), _named_hulls(fleet)])
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home == null:
		_say("  no home fleet at the capital")
		return
	_say("--- dossier: the home fleet at %s ---" % _play.model.province_name(home.province))
	_select(home)
	_print_dossier()


## The station order goes through the selected squadron, exactly as the dossier's
## own button does. The sortie spent the move, so the first order is refused and
## the station is taken on the next turn.
func _station_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- station: blockade off %s ---" % FactionCatalog.name_of(rival))
	var fleet: FleetState = _selected_fleet()
	if fleet == null:
		fleet = _fleet_by_id(_sortie_fleet_id)
	if fleet == null or fleet.owner != _play.player_faction:
		_say("no crown squadron selected to take a station")
		return
	if fleet.moved:
		_run_turn()
		fleet = _fleet_by_id(fleet.id)
		if fleet == null or not fleet.is_afloat():
			_say("the squadron did not survive to take a station")
			return
	# Re-tap after the turn: the marker is a fresh view handle.
	_select(fleet)
	if _selected_fleet() == null:
		_say("the dossier cannot reach the squadron — the order path is closed")
		return
	var targets: Array[int] = FleetMissions.blockade_targets(
		_play.model, fleet, _hostile()
	)
	_say("  blockade targets from %s: %s" % [
		_play.model.sea_zone_name(fleet.sea_zone), str(targets),
	])
	if targets.is_empty():
		_say("  the station is not offered: no hostile coast borders this water")
		return
	_say("  dossier before the order: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:blockade:%d" % targets[0])
	_my_toasts()
	_say("  after the order: mission %d, blockade %d, moved %s" % [
		fleet.mission, fleet.blockade_province, str(fleet.moved),
	])
	_say("  dossier note: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_print_dossier()
	_run_turn()


## The sea battle and the despatch the court reads. A rival squadron is seated in
## the zone (scenario seat) so the clash is certain; the resolver, loss pruning
## and despatch are the game's own.
func _battle_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- battle: contested %s ---" % _play.model.sea_zone_name(zone))
	var home: FleetState = _player_fleet_in(zone)
	if home == null:
		_say("no crown squadron left in the zone to fight")
		return
	var foe: FleetState = _rival_fleet_in_zone(zone, rival)
	if foe == null:
		foe = _seat_rival_fleet(zone, rival)
		_say("seated %s's squadron in the zone (fixture): %s" % [
			FactionCatalog.name_of(rival), _named_hulls(foe),
		])
	var before: Dictionary = _hull_names_by_fleet(zone)
	_say("  own before: %s" % _owned_in(zone))
	_say("  foe before: %s" % _named_hulls(foe))
	_clear_toasts()
	var battles: Array[Dictionary] = MapPlayNavalTurn.resolve(_play)
	for battle: Dictionary in battles:
		_say("  record: attacker %s, defender %s, share %.3f, outcome %d, retreat %s" % [
			FactionCatalog.name_of(int(battle["attacker"])),
			FactionCatalog.name_of(int(battle["defender"])),
			float(battle["attacker_strength"]) / maxf(
				float(battle["attacker_strength"]) + float(battle["defender_strength"]), 0.001
			),
			int(battle["outcome"]), str(battle.get("retreat", {})),
		])
		_say("  despatch: %s" % BattleReport.describe(
			battle, _play.model.sea_zone_name(int(battle["zone"])), FactionCatalog.names()
		))
		_say("  hulls lost: attacker %s, defender %s" % [
			str(battle.get("attacker_lost", [])), str(battle.get("defender_lost", [])),
		])
		_say("  names the court could have been told: %s" % _lost_names(before, zone))
	_my_toasts()
	_say("  own after: %s" % _owned_in(zone))
	var survivor: FleetState = _player_fleet_in(zone)
	if survivor != null:
		_select(survivor)
		_print_dossier()


## Troops to another shore: a field army boards the home squadron at the seat,
## the squadron puts to sea, and the army lands on a crown coast in the zone
## (wiki: § Naval transport, § Home Fleet). Every step is the dossier's own.
func _troops_pass(player: int, zone: int) -> void:
	_say("")
	_say("--- troops: board, sortie, land ---")
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home == null:
		_say("no home squadron in port to take troops aboard")
		return
	var province: int = home.province
	var capacity: int = home.ship_count()
	var types: Array[String] = []
	for _index in maxi(capacity, 1):
		types.append("infantry")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, player, province, false, types,
		_play.army_layer.next_regiment
	)
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)
	_play.army_layer.selected_army = army
	_say("  seated a %d-regiment field army at %s (fixture)" % [
		army.count(), _play.model.province_name(province),
	])
	_select(home)
	if _selected_fleet() == null:
		_say("the dossier cannot reach the squadron — the order path is closed")
		return
	_clear_toasts()
	MapPlayArmies.embark(_play, army)
	_my_toasts()
	_say("  aboard: army %d embarked on fleet %d; holds %d" % [
		army.id, army.embarked_fleet, army.count(),
	])
	if army.embarked_fleet < 0:
		return
	_print_dossier()
	_clear_toasts()
	MapPlayCivilianVoyage.sortie(_play, home, zone)
	_sortie_fleet_id = home.id
	_my_toasts()
	_say("  sortie: %s, moved %s, carried %d" % [
		_station(home), str(home.moved), MapPlayFleets.carried(_play, home),
	])
	var rows: Array[Dictionary] = MapPlayFleets.landing_rows(_play, home)
	_say("  coasts offered: %s" % str(rows))
	if rows.is_empty():
		_say("no crown coast in this zone to land the troops on")
		return
	var destination: int = int(rows[0]["province"])
	_clear_toasts()
	MapPlayFleets.on_action(_play, "land:%d" % destination)
	_my_toasts()
	_say("  landing order at %s: army province %d, fleet carried %d" % [
		_play.model.province_name(destination), army.province,
		MapPlayFleets.carried(_play, home),
	])


## A port that changes hands: the rival squadron in harbour sorts out to sea
## rather than being taken (wiki: § Ports that change hands).
func _port_pass(player: int, rival: int) -> void:
	_say("")
	_say("--- port: a harbour falls ---")
	var port: int = _rival_port(rival)
	if port < 0:
		_say("the rival holds no port on this chart")
		return
	var fleet: FleetState = FleetState.in_port(
		_play.ship_layer.next_hull + 60, rival, port
	)
	_play.ship_layer.fleets.append(fleet)
	_play.ship_layer.rebuild_markers()
	_say("  %s keeps a squadron in port at %s (fixture): %s" % [
		FactionCatalog.name_of(rival), _play.model.province_name(port),
		_named_hulls(fleet),
	])
	_play.model.province_data(port).owner = player
	_clear_toasts()
	MapPlayFleets.settle_ports(_play, [])
	_my_toasts()
	_say("  after the fall: %s, holds %s" % [
		_station(fleet), str(fleet.hulls.size()),
	])


# --- turn ------------------------------------------------------------------


## One whole turn through the real closure, answering whatever the court asks.
func _run_turn() -> void:
	var turn: int = _play.turn
	_clear_toasts()
	MapPlayTurn.end_turn(_play)
	var guard: int = 0
	while _play.turn == turn and not _play.campaign_over() and guard < 12:
		guard += 1
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: call to arms — stood aside")
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: intervention — did nothing")
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: a proposal — refused")
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
	_say("  calendar: turn %d -> %d; holds %d" % [turn, _play.turn, _holds(_play.player_faction)])
	_my_toasts()


# --- presentation ----------------------------------------------------------


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % fleet.id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


## The fleet dossier exactly as the panel builds it: every label and button.
func _print_dossier() -> void:
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		_say("  no fleet dossier shown")
		return
	for line: String in _labels(panel):
		_say("    dossier: %s" % line)


## Toasts this area emits, so a turn's general noise does not bury them.
func _my_toasts() -> void:
	for panel: Node in _play.hud._toast_box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("fleet") or lower.contains("squadron")
				or lower.contains("hull") or lower.contains("ship")
				or lower.contains("army") or lower.contains("troops")
				or lower.contains("prize") or lower.contains("port")
				or lower.contains("sea") or lower.contains("cargo")
			):
				_say("    toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _play.hud._toast_box.get_children():
		child.queue_free()


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		var button: Button = child as Button
		if button != null and not button.text.is_empty():
			out.append("[%s]%s" % [button.text, "" if not button.disabled else " (disabled)"])
		out.append_array(_labels(child))
	return out


# --- world helpers ---------------------------------------------------------


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "sea %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


## "ship_3 Trinidad, ship_7 Neptune" — the names the yard minted.
func _named_hulls(fleet: FleetState, live: bool = true) -> String:
	if fleet == null:
		return "—"
	if live and not fleet.is_afloat():
		return "sunk"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


func _holds(player: int) -> int:
	return _play.ship_layer.hull_count_all(player)


func _hostile() -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(_play.diplomacy, a, b)


func _declare(player: int, rival: int) -> void:
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, player, rival)
	_say("")
	_say("--- war on %s: %s ---" % [
		FactionCatalog.name_of(rival),
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused")),
	])


func _player_fleet_in(zone: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_at_sea() \
				and fleet.sea_zone == zone and fleet.is_afloat():
			return fleet
	return null


## The squadron the dossier is open on — the same one the order buttons act on.
func _selected_fleet() -> FleetState:
	return _play.ship_layer.fleet_of(_play.ship_layer.selected())


func _fleet_by_id(fleet_id: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


## Every crown squadron in the zone, with the names it flies.
func _owned_in(zone: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != _play.player_faction or not fleet.is_at_sea() \
				or fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		parts.append("fleet %d [%s]" % [fleet.id, _named_hulls(fleet)])
	return "none" if parts.is_empty() else "; ".join(parts)


func _rival_fleet_in_zone(zone: int, rival: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == rival and fleet.is_at_sea() and fleet.sea_zone == zone:
			return fleet
	return null


## Moves an existing rival squadron into the zone rather than minting one, so
## hull ids and names stay the campaign's own.
func _seat_rival_fleet(zone: int, rival: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == rival and fleet.is_afloat():
			fleet.location = FleetState.Location.AT_SEA
			fleet.sea_zone = zone
			fleet.province = MapModel.NO_ID
			fleet.clear_beachhead()
			fleet.moved = true
			_play.ship_layer.rebuild_markers()
			return fleet
	var seated: FleetState = FleetState.at_sea(
		_play.ship_layer.next_hull + 20, rival, zone
	)
	_play.ship_layer.fleets.append(seated)
	_play.ship_layer.rebuild_markers()
	return seated


## Every hull in the zone with the name it flies, for a before/after diff.
func _hull_names_by_fleet(zone: int) -> Dictionary:
	var out: Dictionary = {}
	for fleet: FleetState in _play.ship_layer.fleets:
		if not fleet.is_at_sea() or fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		var names: Dictionary = {}
		for hull_id: String in fleet.hulls:
			names[hull_id] = ShipNames.of(fleet, hull_id)
		out[fleet.id] = names
	return out


## The names that left the zone, read from the before-snapshot.
func _lost_names(before: Dictionary, zone: int) -> String:
	var still: Dictionary = {}
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.is_at_sea() and fleet.sea_zone == zone and fleet.is_afloat():
			for hull_id: String in fleet.hulls:
				still[hull_id] = true
	var parts: PackedStringArray = PackedStringArray()
	for raw_id: Variant in before.keys():
		var names: Dictionary = before[raw_id] as Dictionary
		for hull_id: String in names.keys():
			if still.has(hull_id):
				continue
			parts.append("%s %s" % [hull_id, String(names[hull_id])])
	return "none" if parts.is_empty() else ", ".join(parts)


## A rival that holds a port on this sea zone.
func _rival_off(zone: int, player: int) -> int:
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, zone):
		var owner: int = _play.model.province_owner(province_id)
		if owner == player or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.great_power_ids().has(owner):
			return owner
	return -1


func _rival_port(rival: int) -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == rival and province.port_tile.x >= 0:
			return province.id
	return -1


func _zone_beside(province: int) -> int:
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, province)
	return zones[0] if not zones.is_empty() else -1


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_naval: %d steps ---" % _steps.size())
	quit()
