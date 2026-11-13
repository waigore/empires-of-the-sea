extends SceneTree
## Headless free-playtest drive for the overseas invasion chain (wiki:
## ships-and-naval § Missions and Movement, § Naval transport): a squadron marks
## a beachhead on a hostile coast, the landing waits a turn, the troops storm
## ashore, the land battle resolves, and the marker's three deaths — sailed
## away, peace made, one turn unused — are read as the court reads them.
##
## Every order goes through the game's own play helpers (MapPlayFleets,
## MapPlayBeachhead, MapPlayArmies, MapPlayTurn) and every line the court reads
## is printed as it is, so the drive falsifies what the wiki promises against
## what the map actually shows. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_beachhead.gd
##
## A field army is mustered at the seat (fixture) because the opening campaign
## has no spare field army; the boarding, sortie, marking, landing, battle and
## expiry are the real ones.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _fleet_id: int = -1
var _army_id: int = -1
var _seated: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_screen.battle_resolved.connect(_on_battle)
	var player: int = _play.player_faction
	_say("seed %s · turn %d · player %s · capital %s (%d)" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(player),
		_play.model.province_name(_play.capital_province), _play.capital_province,
	])
	var zone: int = _war_zone(player)
	if zone < 0:
		_say("no rival coast on any water the crown can reach")
		_finish()
		return
	var rival: int = _rival_off(zone, player)
	_declare(player, rival)
	_board_pass(player, zone)
	_mark_pass(zone, rival)
	_land_pass(zone, rival)
	_expire_pass(zone)
	_sail_away_pass(zone, rival)
	_peace_pass(zone, rival)
	_finish()


# --- passes -----------------------------------------------------------------


## Every battle the turn resolves, as the rules recorded it.
func _on_battle(battles: Array[Dictionary]) -> void:
	for battle: Dictionary in battles:
		if battle.has("zone"):
			_say("  battle (sea): %s" % BattleReport.describe(
				battle, _play.model.sea_zone_name(int(battle["zone"])), FactionCatalog.names()
			))
			continue
		var region: int = int(battle.get("region", _play.region_index))
		var model: MapModel = _play.model if region == _play.region_index \
			else _play.world.region(region)
		_say("  battle (land): %s" % BattleReport.describe_land(
			battle, model.province_name(int(battle["province"])) if model != null else "—",
			FactionCatalog.names()
		))


## The army boards the home squadron at the seat and the squadron puts to sea
## into the rival's water (wiki: § Naval transport, § Home Fleet).
func _board_pass(player: int, zone: int) -> void:
	_say("")
	_say("--- board: troops to the rival's water ---")
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home == null:
		_say("no home squadron in port to take troops aboard")
		return
	var province: int = home.province
	var types: Array[String] = []
	for _index in maxi(home.ship_count(), 1):
		types.append("infantry")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, player, province, false, types,
		_play.army_layer.next_regiment
	)
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)
	_play.army_layer.selected_army = army
	_army_id = army.id
	_say("  seated a %d-regiment field army at %s (fixture)" % [
		army.count(), _play.model.province_name(province),
	])
	_select(home)
	_clear_toasts()
	MapPlayArmies.embark(_play, army)
	_my_toasts()
	_say("  aboard: army %d embarked on fleet %d; holds %d" % [
		army.id, army.embarked_fleet, army.count(),
	])
	if army.embarked_fleet < 0:
		return
	_clear_toasts()
	MapPlayCivilianVoyage.sortie(_play, home, zone)
	_fleet_id = home.id
	_my_toasts()
	_say("  sortie: %s, moved %s, carried %d" % [
		_station(home), str(home.moved), MapPlayFleets.carried(_play, home),
	])
	_run_turn()


## The Beachhead mission from the dossier: the coasts offered, the order, the
## note the court reads, and the landing the same turn must refuse.
func _mark_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- mark: a landing site on %s's coast ---" % FactionCatalog.name_of(rival))
	var fleet: FleetState = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("the squadron did not survive to mark a beachhead")
		return
	_select(fleet)
	if _selected_fleet() == null:
		_say("the dossier cannot reach the squadron — the order path is closed")
		return
	var rows: Array[Dictionary] = MapPlayBeachhead.rows(_play, fleet)
	_say("  coasts offered by the dossier: %s" % str(rows))
	if rows.is_empty():
		_say("  no hostile coast borders this water")
		return
	var coast: int = int(rows[0]["province"])
	_say("  note before the order: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_clear_toasts()
	MapPlayBeachhead.establish(_play, fleet, coast)
	_my_toasts()
	_say("  after the order: mission %d, beachhead %d, marked turn %d, moved %s" % [
		fleet.mission, fleet.beachhead_province, fleet.beachhead_turn, str(fleet.moved),
	])
	_say("  note: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_say("  landing rows now: %s" % str(MapPlayFleets.landing_rows(_play, fleet)))
	_clear_toasts()
	MapPlayFleets.on_action(_play, "land:%d" % coast)
	_my_toasts()
	_say("  same-turn landing: army province %d, fleet carried %d" % [
		_army().province if _army() != null else -1, MapPlayFleets.carried(_play, fleet),
	])
	_print_dossier()
	_run_turn()


## The ready turn: the marker survived the calendar, the coast is offered, the
## troops land, the marker is spent, and the land battle resolves.
func _land_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- land: the ready turn ---")
	var fleet: FleetState = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("the squadron did not survive to the ready turn")
		return
	_select(fleet)
	_say("  marker: %d (marked turn %d), turn %d, ready %s" % [
		fleet.beachhead_province, fleet.beachhead_turn, _play.turn,
		str(NavalTransport.beachhead_ready(fleet, _play.turn)),
	])
	_say("  note: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	var rows: Array[Dictionary] = MapPlayFleets.landing_rows(_play, fleet)
	_say("  landing rows: %s" % str(rows))
	var coast: int = _invasion_row(rows)
	if coast < 0:
		_say("  the marked coast is not offered for a landing")
		return
	var owner_before: int = _play.model.province_owner(coast)
	_clear_toasts()
	MapPlayFleets.on_action(_play, "land:%d" % coast)
	_my_toasts()
	var army: ArmyState = _army()
	_say("  after the landing: army province %d (%s), fleet carried %d, marker %d" % [
		army.province if army != null else -1,
		_play.model.province_name(army.province) if army != null else "—",
		MapPlayFleets.carried(_play, fleet), fleet.beachhead_province,
	])
	_say("  note after the landing: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_say("  coast owner before the battle: %s" % FactionCatalog.name_of(owner_before))
	if army != null:
		_say("  army: province %d, owner %s, moved %s, regiments %d" % [
			army.province, FactionCatalog.name_of(army.owner), str(army.moved), army.count(),
		])
	_say("  contested provinces now: %s" % str(
		ArmyCombat.contested_provinces(_play.model, _play.army_layer.armies)
	))
	_say("  attackers of %d now: %s" % [coast, str(ArmyCombat.ordered_attackers(
		_play.army_layer.armies, coast, _play.model.province_owner(coast),
		MapPlayLandTurn.battle_context(_play),
	))])
	_clear_toasts()
	_run_turn()
	_all_toasts()
	_say("  coast owner after the battle: %s" % FactionCatalog.name_of(
		_play.model.province_owner(coast)
	))
	_say("  army after the battle: %s" % (
		"gone" if _army() == null else "province %d (%s), regiments %d, moved %s" % [
			_army().province, _play.model.province_name(_army().province),
			_army().count(), str(_army().moved),
		]
	))
	var roster: PackedStringArray = PackedStringArray()
	for a: ArmyState in _play.army_layer.armies:
		roster.append("%d:%s@%d" % [a.id, FactionCatalog.name_of(a.owner), a.province])
	_say("  armies on this chart: %s" % ", ".join(roster))


## A site left unused lapses at the end of its ready turn: the wiki promises one
## full turn and no more (wiki: ships-and-naval § Missions and Movement).
func _expire_pass(zone: int) -> void:
	_say("")
	_say("--- leave it: the site nobody used ---")
	var fleet: FleetState = _seat_squadron(zone)
	if fleet == null:
		_say("no squadron to seat in the rival's water")
		return
	_select(fleet)
	var rows: Array[Dictionary] = MapPlayBeachhead.rows(_play, fleet)
	if rows.is_empty():
		_say("  no hostile coast to mark")
		return
	var coast: int = int(rows[0]["province"])
	MapPlayBeachhead.establish(_play, fleet, coast)
	_say("  marked %s at turn %d; note \"%s\"" % [
		_play.model.province_name(coast), fleet.beachhead_turn,
		MapPlayFleetMissions.note(_play, fleet),
	])
	_run_turn()
	fleet = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("  the squadron did not survive the ready turn")
		return
	_select(fleet)
	_say("  ready turn %d: marker %d, note \"%s\"" % [
		_play.turn, fleet.beachhead_province, MapPlayFleetMissions.note(_play, fleet),
	])
	_run_turn()
	fleet = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("  the squadron did not survive the unused turn")
		return
	_select(fleet)
	_say("  turn %d: marker %d, note \"%s\"" % [
		_play.turn, fleet.beachhead_province, MapPlayFleetMissions.note(_play, fleet),
	])


## A marker dies when the squadron sails: the dossier must stop promising it.
func _sail_away_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- sail away: the marker the squadron leaves behind ---")
	var fleet: FleetState = _seat_squadron(zone)
	if fleet == null:
		_say("no squadron to seat in the rival's water")
		return
	_select(fleet)
	var rows: Array[Dictionary] = MapPlayBeachhead.rows(_play, fleet)
	if rows.is_empty():
		_say("  no hostile coast to mark before sailing")
		return
	var coast: int = int(rows[0]["province"])
	_clear_toasts()
	MapPlayBeachhead.establish(_play, fleet, coast)
	_my_toasts()
	_say("  marked %s; note: \"%s\"" % [
		_play.model.province_name(coast), MapPlayFleetMissions.note(_play, fleet),
	])
	_run_turn()
	fleet = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("  the squadron did not survive to sail")
		return
	_select(fleet)
	_say("  ready turn: marker %d, note \"%s\"" % [
		fleet.beachhead_province, MapPlayFleetMissions.note(_play, fleet),
	])
	var destinations: Array[int] = NavalMovement.destination_zones(_play.model, fleet)
	_say("  water the squadron can sail to: %s" % str(destinations))
	var destination: int = -1
	for zone_id: int in destinations:
		if zone_id != fleet.sea_zone:
			destination = zone_id
			break
	if destination < 0:
		_say("  no other water to sail to")
		return
	_clear_toasts()
	MapPlayFleets.try_sea_order(_play, fleet, destination)
	_my_toasts()
	_say("  after sailing: %s, marker %d, note \"%s\"" % [
		_station(fleet), fleet.beachhead_province, MapPlayFleetMissions.note(_play, fleet),
	])
	_run_turn()


## A marker dies when the war does: peace lapses the landing site.
func _peace_pass(zone: int, rival: int) -> void:
	_say("")
	_say("--- peace: the shore that stops being hostile ---")
	var fleet: FleetState = _seat_squadron(zone)
	if fleet == null:
		_say("no squadron to seat in the rival's water")
		return
	_select(fleet)
	var rows: Array[Dictionary] = MapPlayBeachhead.rows(_play, fleet)
	if rows.is_empty():
		_say("  no hostile coast to mark before peace")
		return
	var coast: int = int(rows[0]["province"])
	var coast_owner: int = _play.model.province_owner(coast)
	_clear_toasts()
	MapPlayBeachhead.establish(_play, fleet, coast)
	_my_toasts()
	_say("  marked %s; note: \"%s\"" % [
		_play.model.province_name(coast), MapPlayFleetMissions.note(_play, fleet),
	])
	_run_turn()
	fleet = _fleet()
	if fleet == null or not fleet.is_afloat():
		_say("  the squadron did not survive to the ready turn")
		return
	_select(fleet)
	_say("  ready turn: marker %d, note \"%s\"" % [
		fleet.beachhead_province, MapPlayFleetMissions.note(_play, fleet),
	])
	var peace: Dictionary = DiplomacyRules.make_peace(
		_play.diplomacy, _play.player_faction, coast_owner
	)
	_say("  peace with %s: %s" % [
		FactionCatalog.name_of(coast_owner),
		"made" if bool(peace.get("ok", false)) else String(peace.get("reason", "refused")),
	])
	_say("  note after peace: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	_say("  landing rows after peace: %s" % str(MapPlayFleets.landing_rows(_play, fleet)))
	_print_dossier()


# --- turn -------------------------------------------------------------------


func _run_turn() -> void:
	var turn: int = _play.turn
	MapPlayTurn.end_turn(_play)
	_say("  toasts right after the turn: %d, plate %s, queued %d" % [
		_play.hud._toast_box.get_child_count(), str(_play.hud.is_quick_battle_shown()),
		_play.hud._toast_queue.size(),
	])
	for child: Node in _play.hud._toast_box.get_children():
		var texts: Array[String] = _labels(child)
		if not texts.is_empty():
			_say("    raw toast: %s" % " | ".join(texts))
		else:
			_say("    unlabeled toast child: %s (%d kids)" % [
				child.get_class(), child.get_child_count(),
			])
	_skip_plates()
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
		# The answer resumes the turn, and the resumed turn may raise a plate.
		_skip_plates()
	_skip_plates()
	_say("  calendar: turn %d -> %d" % [turn, _play.turn])
	if _play.turn == turn:
		_say("  the calendar stayed shut: suspended %s, plate %s, over %s" % [
			str(_play.turn_suspended), str(_play.hud.is_quick_battle_shown()),
			str(_play.campaign_over()),
		])
	_my_toasts()


## The battle plate owns input while it plays; a headless drive skips it so the
## calendar can close (REQ-P5-06). `skip` only ends the animation, so the
## Continue press is the drive's own.
func _skip_plates() -> void:
	var plates: int = 0
	while _play.hud != null and _play.hud.is_quick_battle_shown() and plates < 8:
		plates += 1
		_play.hud.quick_battle_overlay.skip()
		_play.hud.quick_battle_overlay._on_continue()


# --- presentation -----------------------------------------------------------


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % fleet.id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


func _print_dossier() -> void:
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		_say("  no fleet dossier shown")
		return
	for line: String in _labels(panel):
		_say("    dossier: %s" % line)


func _my_toasts() -> void:
	for panel: Node in _play.hud._toast_box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("beachhead") or lower.contains("ashore")
				or lower.contains("land") or lower.contains("troops")
				or lower.contains("army") or lower.contains("fleet")
				or lower.contains("squadron") or lower.contains("peace")
			):
				_say("    toast: %s" % text)


## Every toast of the turn, unfiltered: the battle line is the evidence.
func _all_toasts() -> void:
	for panel: Node in _play.hud._toast_box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
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


# --- world helpers ----------------------------------------------------------


## A crown squadron seated in the rival's water (fixture): the landing chain
## above may have cost the crown its only hulls, and the marker's two deaths
## still need a squadron to die on.
func _seat_squadron(zone: int) -> FleetState:
	_seated += 1
	var fleet: FleetState = FleetState.at_sea(
		_play.ship_layer.next_hull + 80 + _seated, _play.player_faction, zone
	)
	if not fleet.is_afloat():
		return null
	_play.ship_layer.fleets.append(fleet)
	_play.ship_layer.rebuild_markers()
	_fleet_id = fleet.id
	_say("  seated a crown squadron in %s (fixture): %s" % [
		_play.model.sea_zone_name(zone), _named_hulls(fleet),
	])
	return fleet


func _named_hulls(fleet: FleetState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


func _fleet() -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.id == _fleet_id:
			return fleet
	return null


func _army() -> ArmyState:
	for army: ArmyState in _play.army_layer.armies:
		if army.id == _army_id:
			return army
	return null


## The row the beachhead opened: the only landing row that is an invasion.
func _invasion_row(rows: Array[Dictionary]) -> int:
	for row: Dictionary in rows:
		if bool(row.get("invade", false)):
			return int(row["province"])
	return -1


func _selected_fleet() -> FleetState:
	return _play.ship_layer.fleet_of(_play.ship_layer.selected())


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "sea %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


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


func _zone_beside(province_id: int) -> int:
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, province_id)
	return zones[0] if not zones.is_empty() else -1


func _rival_off(zone: int, player: int) -> int:
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, zone):
		var owner: int = _play.model.province_owner(province_id)
		if owner == player or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.great_power_ids().has(owner):
			return owner
	return -1


# --- output -----------------------------------------------------------------


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: %s" % line)


func _finish() -> void:
	print("")
	print("--- playtest_beachhead: %d steps ---" % _steps.size())
	quit()
