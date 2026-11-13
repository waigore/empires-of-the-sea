extends SceneTree
## Headless free-playtest drive for a rival's sighted strength (wiki:
## ships-and-naval § Sighted strength; DR-20261113-20): the first sighting, the
## marker's `*`, the dossier's `???`, the zone that takes no verdict, the watch
## that closes across a real turn, the chart switch, the save, and the read
## dropped when the squadron leaves the crown's water.
##
## Every read is a line the court can actually see (the marker's own state, the
## fleet dossier's labels, the zone's odds line, the toasts of the turn), and
## every state change the drive can make through a player's path goes through one
## — `MapPlayTurn` closes the turn, the seal switches the chart, the pause menu
## saves and loads. A rival squadron is seated only where a scenario seat is the
## shortest way to the rare branch (a hostile squadron under the crown's chart on
## turn 0). Not a CI gate, run it by hand:
##   godot --headless --path . --script res://playtests/playtest_naval_intel.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SaveDrive = preload("res://playtests/playtest_save_drive.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const SLOT: int = 1
const DIR: String = "user://playtest_naval_intel"

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _main: Node = null
var _play: PlaySession = null
var _rival: int = -1
var _foe_id: int = -1
var _zone: int = -1
var _watch_zone: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	SaveDrive.clean_dir(DIR)
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX)
	if _screen == null:
		_finish()
		return
	_main = _screen.get_parent()
	_play = _screen.play
	if not _war_pass():
		_finish()
		return
	_sight_pass()
	_watch_pass()
	_chart_pass()
	_save_pass()
	_drop_pass()
	_finish()


# --- passes -----------------------------------------------------------------


## War on a court whose coast borders water the crown's chart already covers,
## so the rival's arrival can be read this turn. Her squadron is then seated in
## that water (fixture: the rare branch is a hostile rival under the crown's eye
## on turn 0, and no AI pass would sail her there on demand).
func _war_pass() -> bool:
	var player: int = _play.player_faction
	_say("seed %s · turn %d · player %s · capital %s" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(player),
		_play.model.province_name(_play.capital_province),
	])
	_zone = _visible_zone_with_rival_coast(player)
	if _zone < 0:
		_say("no fully charted water borders a rival Great Power — nothing to sight")
		return false
	_rival = _rival_off(_zone, player)
	_watch_zone = _quiet_zone(player, _zone)
	_say("")
	_say("--- war on %s (coast of the %s) ---" % [
		FactionCatalog.name_of(_rival), _play.model.sea_zone_name(_zone),
	])
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, player, _rival)
	_say("  declaration: %s" % (
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused"))
	))
	if not bool(war.get("ok", false)):
		return false
	var foe: FleetState = _seat_rival(_zone, _rival)
	if foe == null:
		_say("  no %s squadron to seat in the water" % FactionCatalog.name_of(_rival))
		return false
	_foe_id = foe.id
	MapPlayFleets.refresh_visibility(_play)
	_say("  seated her in the %s (fixture): %s" % [
		_play.model.sea_zone_name(_zone), _named_hulls(foe),
	])
	return true


## The first sighting: what the marker and the dossier hand over before the
## watch has closed, and the zone's odds while one rival is unread.
func _sight_pass() -> void:
	_say("")
	_say("--- first sighting: her marker and dossier ---")
	_print_marker()
	_select(_foe_id)
	_my_toasts()
	_print_dossier()
	_say("  watch: watched %s, revealed %s" % [
		str(_play.naval_intel.watched(_play.region_index)),
		str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)),
	])
	_say("")
	_say("--- the crown's own dossier in the same water ---")
	_select(_own_fleet_id_in(_zone))
	_print_dossier()


## She sails on under the same chart. One real turn closes the watch.
func _watch_pass() -> void:
	_say("")
	_say("--- she sails on, still under the crown's chart ---")
	var foe: FleetState = _fleet_anywhere(_foe_id)
	if foe == null:
		_say("  she is gone from both charts")
		return
	if _watch_zone >= 0:
		foe.location = FleetState.Location.AT_SEA
		foe.sea_zone = _watch_zone
		foe.province = MapModel.NO_ID
		foe.moved = true
		_play.ship_layer.rebuild_markers()
		MapPlayFleets.refresh_visibility(_play)
		_say("  she is in the %s (fixture); watch watched %s, revealed %s" % [
			_play.model.sea_zone_name(_watch_zone),
			str(_play.naval_intel.watched(_play.region_index)),
			str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)),
		])
	else:
		_say("  no second charted water to sail her into — closing the turn where she lies")
	_say("")
	_say("--- the watch closes: one turn ---")
	_select(_foe_id)
	_clear_toasts()
	_run_turn()
	foe = _fleet_anywhere(_foe_id)
	if foe == null:
		_say("  she is gone from the chart — no watch to close")
		return
	_print_marker()
	_say("  watch: revealed %s" % str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)))
	_say("  dossier open on her through the turn:")
	_print_dossier()
	var said: bool = false
	for text: String in _toast_texts():
		var lower: String = text.to_lower()
		if lower.contains("read") or lower.contains("weight") or lower.contains("strength"):
			said = true
			_say("    toast names the read: %s" % text)
	if not said:
		_say("    no toast, despatch or ledger line names the read")
	_say("")
	_say("--- the crown's own dossier after the watch ---")
	_select(_own_fleet_id_in(_zone))
	_print_dossier()


## The chart switch: a read squadron does not leave the crown's view because the
## crown looked at the other hemisphere. The seal is the player's own button.
func _chart_pass() -> void:
	_say("")
	_say("--- chart switch: the seal ---")
	var foe: FleetState = _fleet_anywhere(_foe_id)
	if foe == null:
		_say("  she is gone from the chart")
		return
	_say("  before: region %d, revealed %s" % [
		_play.region_index, str(_play.naval_intel.is_revealed(_foe_id, FactionCatalog.OLD_WORLD)),
	])
	_screen.hud.region_toggle_pressed.emit()
	_say("  on the other chart: region %d, revealed %s" % [
		_play.region_index, str(_play.naval_intel.is_revealed(_foe_id, FactionCatalog.OLD_WORLD)),
	])
	# Fleet ids are minted per roster, so the squadron wearing her id on this
	# chart is another court's: her plate must still fly `*`.
	_print_marker()
	_screen.hud.region_toggle_pressed.emit()
	_say("  back on her chart: region %d, revealed %s" % [
		_play.region_index, str(_play.naval_intel.is_revealed(_foe_id, FactionCatalog.OLD_WORLD)),
	])
	_print_marker()
	_select(_foe_id)
	_print_dossier()


## The watch rides the save (wiki: § Sighted strength; campaign-persistence
## § Snapshot contract).
func _save_pass() -> void:
	_say("")
	_say("--- save: the watch rides the campaign ---")
	var foe: FleetState = _fleet_anywhere(_foe_id)
	if foe == null:
		_say("  she is gone from the chart")
		return
	if not _play.naval_intel.is_revealed(_foe_id, _play.region_index):
		_say("  nothing read to save — the watch is already lost")
	_say("  save: \"%s\"" % SaveDrive.save_slot(_screen, SLOT))
	_screen = SaveDrive.load_slot(_screen, _main, SLOT)
	if _screen == null:
		_say("  the load browser did not build a campaign")
		return
	_play = _screen.play
	_say("  after the load: turn %d, region %d, revealed %s" % [
		_play.turn, _play.region_index,
		str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)),
	])
	_print_marker()
	_select(_foe_id)
	_print_dossier()


## The read dropped: she leaves the crown's water, and a return must be watched
## afresh (wiki: § Sighted strength — "dropping out of view clears the read").
func _drop_pass() -> void:
	_say("")
	_say("--- out of sight: the read dropped ---")
	var foe: FleetState = _fleet_anywhere(_foe_id)
	if foe == null:
		_say("  she is gone from the chart")
		return
	var away: int = _unwatched_zone()
	if away < 0:
		_say("  no water outside the crown's chart to sail her into")
		return
	var home_zone: int = foe.sea_zone
	foe.sea_zone = away
	foe.province = MapModel.NO_ID
	foe.moved = true
	_play.ship_layer.rebuild_markers()
	MapPlayFleets.refresh_visibility(_play)
	_say("  she sails into the %s (unwatched water): revealed %s, watched %s, fog %d" % [
		_play.model.sea_zone_name(away),
		str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)),
		str(_play.naval_intel.watched(_play.region_index)), _fog_at(away),
	])
	_print_marker()
	foe.sea_zone = home_zone
	_play.ship_layer.rebuild_markers()
	MapPlayFleets.refresh_visibility(_play)
	_say("  she returns the same turn: revealed %s (the clock restarts)" % [
		str(_play.naval_intel.is_revealed(_foe_id, _play.region_index)),
	])
	_print_marker()


# --- presentation -----------------------------------------------------------


func _print_marker() -> void:
	var ship: Ship = _ship_for(_foe_id)
	if ship == null:
		_say("  no marker for her on this chart")
		return
	_say("  marker: visible %s, strength_known %s, hull badge %s, strength %.1f" % [
		str(ship.visible), str(ship.strength_known),
		("yes" if ship.hull_count > 1 and ship.strength_known else "no"),
		ship.strength,
	])


func _select(fleet_id: int) -> void:
	if fleet_id < 0:
		_say("  nothing to select")
		return
	var ship: Ship = _ship_for(fleet_id)
	if ship == null:
		_say("  no marker on this chart for fleet %d" % fleet_id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


## Every label and button the fleet dossier shows — the reading a player makes.
func _print_dossier() -> void:
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		_say("  no fleet dossier shown")
		return
	for line: String in _labels(panel):
		_say("    dossier: %s" % line)


## Toasts this area emits, so a turn's general noise does not bury them.
func _my_toasts() -> void:
	for text: String in _toast_texts():
		var lower: String = text.to_lower()
		if (
			lower.contains("fleet") or lower.contains("squadron")
			or lower.contains("strength") or lower.contains("watch")
		):
			_say("    toast: %s" % text)


func _toast_texts() -> Array[String]:
	var out: Array[String] = []
	for child: Node in _play.hud._toast_box.get_children():
		if child.is_queued_for_deletion():
			continue
		out.append_array(_labels(child))
	return out


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


# --- turn -------------------------------------------------------------------


## One whole turn through the real closure, answering whatever the court asks.
func _run_turn() -> void:
	var turn: int = _play.turn
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
	_say("  calendar: turn %d -> %d" % [turn, _play.turn])


# --- world helpers ----------------------------------------------------------


## Every tile of the water is on the crown's chart, so a squadron seated there is
## under the crown's eye the moment she arrives.
func _visible_zone_with_rival_coast(player: int) -> int:
	for zone_id in _play.model.sea_zone_count():
		if not _fully_charted(zone_id):
			continue
		if _rival_off(zone_id, player) >= 0:
			return zone_id
	return -1


## A charted zone the crown keeps no squadron in, so the turn's combat pass has
## nothing to fight and the watch is the only thing that changes.
func _quiet_zone(player: int, not_zone: int) -> int:
	for zone_id in _play.model.sea_zone_count():
		if zone_id == not_zone or not _fully_charted(zone_id):
			continue
		if _own_fleet_id_in(zone_id) < 0 and _rival_fleet_in(zone_id) < 0:
			return zone_id
	return -1


func _fully_charted(zone_id: int) -> bool:
	var zone: SeaZoneState = _play.model.sea_zone_data(zone_id)
	if zone == null or zone.tiles.is_empty():
		return false
	for tile: Vector2i in zone.tiles:
		if _play.visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.FULLY_VISIBLE:
			return false
	return true


## The fog level the crown's chart holds on the water's first tile — the point a
## squadron at sea is drawn at (and read from).
func _fog_at(zone_id: int) -> int:
	var zone: SeaZoneState = _play.model.sea_zone_data(zone_id)
	if zone == null or zone.tiles.is_empty():
		return VisibilityModel.Level.UNKNOWN
	var tile: Vector2i = zone.tiles[0]
	return _play.visibility.level_at(tile.x, tile.y)


## Water the crown's chart does not cover: she is invisible there.
func _unwatched_zone() -> int:
	for zone_id in _play.model.sea_zone_count():
		if not _fully_charted(zone_id):
			return zone_id
	return -1


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "sea %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


func _named_hulls(fleet: FleetState) -> String:
	if fleet == null:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


## The rival's own squadron, sailed into the crown's water. Hull ids come from
## the layer's counter outside its live range, so a later launch cannot collide.
func _seat_rival(zone: int, rival: int) -> FleetState:
	for fleet: FleetState in _fleets_all():
		if fleet.owner == rival and fleet.is_afloat():
			fleet.location = FleetState.Location.AT_SEA
			fleet.sea_zone = zone
			fleet.province = MapModel.NO_ID
			fleet.clear_beachhead()
			fleet.moved = true
			_play.ship_layer.rebuild_markers()
			return fleet
	var base: int = _play.ship_layer.next_hull + 400
	var seated: FleetState = FleetState.at_sea(
		base, rival, zone, ["ship_%d" % base, "ship_%d" % (base + 1)],
		{"ship_%d" % base: "frigate", "ship_%d" % (base + 1): "carrack"}
	)
	_play.ship_layer.fleets.append(seated)
	_play.ship_layer.rebuild_markers()
	return seated


func _fleets_all() -> Array[FleetState]:
	var out: Array[FleetState] = []
	for roster: Array in FleetRosters.all(_play.ship_layer.regions):
		for raw: Variant in roster:
			var fleet: FleetState = raw as FleetState
			if fleet != null:
				out.append(fleet)
	return out


func _ship_for(fleet_id: int) -> Ship:
	for ship: Ship in _play.ship_layer.ships:
		var fleet: FleetState = _play.ship_layer.fleet_of(ship)
		if fleet != null and fleet.id == fleet_id:
			return ship
	return null


func _own_fleet_id_in(zone: int) -> int:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_at_sea() \
				and fleet.sea_zone == zone and fleet.is_afloat():
			return fleet.id
	return -1


func _rival_fleet_in(zone: int) -> int:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != _play.player_faction and fleet.is_at_sea() \
				and fleet.sea_zone == zone and fleet.is_afloat():
			return fleet.id
	return -1


## A fleet on either chart: the seal's switch swaps the layer's live roster.
func _fleet_anywhere(fleet_id: int) -> FleetState:
	for roster: Array in FleetRosters.all(_play.ship_layer.regions):
		var found: FleetState = FleetRosters.find(roster, fleet_id)
		if found != null:
			return found
	return null


func _rival_off(zone: int, player: int) -> int:
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, zone):
		var owner: int = _play.model.province_owner(province_id)
		if owner == player or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.great_power_ids().has(owner):
			return owner
	return -1



func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	SaveDrive.clean_dir(DIR)
	print("\n--- playtest_naval_intel: %d steps ---" % _steps.size())
	quit()
