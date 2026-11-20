extends SceneTree
## Headless free-playtest drive for the opening home fleet (wiki: ships-and-naval
## § Home Fleet; issue #1043): every Great Power's hulls ride one command, moored
## in port at its own capital, and every sheet the crown opens reads that one
## command — the chart's dossier, the navy's hull-by-hull ledger, the cargo holds
## the market spends, the food the navy eats, and the marker the chart draws.
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_home_fleet.gd
##
## Nothing here is seated: the drive opens a real campaign at the game's own seed
## and reads what the game built.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const MAX_TURN_ATTEMPTS: int = 4

## The setup's advanced-start preset, read from `PT_ADVANCED` (empty = turn 0),
## so the same drive reads both openings without a second copy of the passes.
var _advanced: String = OS.get_environment("PT_ADVANCED")

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, _advanced)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s · turn %d · start %s · player %s · capital %s (%d)" % [
		SEED_TEXT, _play.turn,
		"turn 0" if _advanced.is_empty() else _advanced,
		FactionCatalog.name_of(_play.player_faction),
		_play.model.province_name(_play.capital_province), _play.capital_province,
	])
	_muster_pass()
	_marker_pass()
	_dossier_pass()
	_ledger_pass()
	_cargo_pass()
	await _upkeep_pass()
	await _chart_pass()
	await _sortie_pass()
	await _yard_pass()
	await _away_yard_pass()
	_finish()


# --- passes -----------------------------------------------------------------


## What the opening mustered on the chart now shown: one command per power, in
## port at that power's own capital, carrying every hull it starts with.
func _muster_pass() -> void:
	_say("")
	_say("--- the opening muster: %s ---" % FactionCatalog.region_label(_play.region_index))
	var player: int = _play.player_faction
	var seen: Dictionary = {}
	var by_owner: Dictionary = {}
	for fleet: FleetState in _play.ship_layer.fleets:
		_say("  fleet %d %s — %s — %s" % [
			fleet.id, FactionCatalog.name_of(fleet.owner), _place(fleet),
			_named_hulls(fleet),
		])
		_say("    home fleet? %s · mission %d · moved %s · afloat %s · %d hulls" % [
			str(NavalMovement.is_home_fleet(_play.model, fleet)), fleet.mission,
			str(fleet.moved), str(fleet.is_afloat()), fleet.ship_count(),
		])
		by_owner[fleet.owner] = int(by_owner.get(fleet.owner, 0)) + 1
		for hull_id: String in fleet.hulls:
			if seen.has(hull_id):
				_say("    !! hull id %s rides two fleets: %s and %d" % [
					hull_id, String(seen[hull_id]), fleet.id,
				])
			seen[hull_id] = fleet.id
	for power: int in FactionCatalog.great_power_ids():
		var capital: int = WorldBootstrap.capital_province(_play.model, power)
		var count: int = int(by_owner.get(power, 0))
		var home: FleetState = FleetHomeMerge.home_fleet(_play.model, _play.ship_layer.fleets, power)
		_say("  %s: %d command(s), capital %s, home fleet %s, holds %d" % [
			FactionCatalog.name_of(power),
			count,
			"none" if capital < 0 else _play.model.province_name(capital),
			"none" if home == null else "fleet %d" % home.id,
			TradeCargo.fleet_holds(home),
		])
	_say("  the crown's hulls afloat in every region: %d" % _play.ship_layer.hull_count_all(player))


## The marker the chart draws for the home fleet: one hull, her badge count, and
## the stack she rides.
func _marker_pass() -> void:
	_say("")
	_say("--- the chart's markers ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	for ship: Ship in _play.ship_layer.ships:
		_say("  marker fleet %d %s — hulls %d · strength %.1f · known %s · stack %s" % [
			ship.fleet_id, FactionCatalog.name_of(ship.faction), ship.hull_count,
			ship.strength, str(ship.strength_known), str(ship.stack),
		])
	if home == null:
		_say("  no home fleet to mark")
		return
	var marker: Ship = _play.ship_layer.ship_for(home)
	_say("  home marker: %s" % ("none" if marker == null else "hulls %d" % marker.hull_count))


## The dossier exactly as the panel builds it, opened on the home fleet.
func _dossier_pass() -> void:
	_say("")
	_say("--- the dossier: the home fleet ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	if home == null:
		_say("  no home fleet on this chart")
		return
	_select(home)
	for line: String in _labels(_play.hud.panels.fleet_panel):
		_say("    dossier: %s" % line)


## The navy sheet's own projection: every hull the crown floats, per chart.
func _ledger_pass() -> void:
	_say("")
	_say("--- the crown's navy: every hull, hull by hull ---")
	var data: Dictionary = NavalLedger.snapshot(
		_play.world, _play.ship_layer.regions, _play.player_faction
	)
	_say("  hulls %d · squadrons %s · strength %.1f · holds %d" % [
		int(data.get("total", 0)), str(data.get("squadrons", {})),
		float(data.get("strength", 0.0)), int(data.get("holds", 0)),
	])
	for region_key: String in LedgerRows.REGION_FILTERS:
		_say("  the count line (%s): %s · %s" % [
			region_key, NavalLedger.summary(data, region_key),
			str(NavalLedger.filter_counts(data, region_key)),
		])
	for group: Dictionary in data.get("groups", []) as Array:
		_say("  squadron: %s/%s · %s · %d holds · %.1f strength" % [
			String(group.get("region_label", "?")), String(group.get("title", "?")),
			String(group.get("station", "?")), int(group.get("holds", 0)),
			float(group.get("strength", 0.0)),
		])
		for row: Dictionary in group.get("rows", []) as Array:
			_say("    row: %s — %s — %s — %s" % [
				String(row.get("name", "?")), String(row.get("class", "?")),
				String(row.get("state", "?")), String(row.get("place", "?")),
			])
	_say("  note: %s" % NavalLedger.note())


## The holds the market may spend this turn, against the hulls that carry them.
func _cargo_pass() -> void:
	_say("")
	_say("--- cargo: the holds the market may spend ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	_say("  home fleet holds (TradeCargo.fleet_holds): %d" % TradeCargo.fleet_holds(home))
	_say("  every region's capacity: %d" % TradeCargo.capacity(
		_play.world, _play.ship_layer.regions.snapshot(), _play.player_faction
	))
	_say("  the ledger's own reading: %s" % str(_play.economy.trade_cargo()))


## The food the opening navy eats, before and after one resolved turn.
func _upkeep_pass() -> void:
	_say("")
	_say("--- upkeep: what the navy eats ---")
	var economy: PlayerEconomy = _play.economy.economy
	var ships: int = _play.economy.fleet_ships()
	_say("  hulls the ledger counts: %d · %d food a turn" % [
		ships, ShipEconomy.food_upkeep_per_ship() * ships,
	])
	_say("  grain before: %d · navy feeding %.2f" % [
		int(economy.stockpile.get("grain", 0)), economy.navy_feeding,
	])
	if not await _advance():
		_say("  the turn stayed shut")
		return
	_say("  turn %d · grain after: %d · navy feeding %.2f" % [
		_play.turn, int(economy.stockpile.get("grain", 0)), economy.navy_feeding,
	])
	_muster_pass()


## The other chart: a region with no Great Power capital musters no squadron,
## and coming back to the Old World keeps the commands already mustered.
func _chart_pass() -> void:
	_say("")
	_say("--- the other chart ---")
	if _play.world == null or _play.world.region_count() < 2:
		_say("  one chart only")
		return
	MapPlayRegion.cycle(_play, _screen.sea_backdrop)
	await process_frame
	_say("  now showing %s · capital %s (%d)" % [
		FactionCatalog.region_label(_play.region_index),
		_play.model.province_name(_play.capital_province), _play.capital_province,
	])
	_muster_pass()
	MapPlayRegion.cycle(_play, _screen.sea_backdrop)
	await process_frame
	_say("  back on %s · capital %s" % [
		FactionCatalog.region_label(_play.region_index),
		_play.model.province_name(_play.capital_province),
	])
	_muster_pass()


# --- helpers ----------------------------------------------------------------


## The home squadron puts to sea and moors back at the seat: her holds leave the
## market with her, and the one command comes home to the capital.
func _sortie_pass() -> void:
	_say("")
	_say("--- the home squadron puts to sea ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	if home == null:
		_say("  no home fleet on this chart")
		return
	var zones: Array[int] = FleetSortie.zones(_play.model, home)
	_say("  the zones she may put to sea into: %s · her holds %d · the market's capacity %d" % [
		str(zones), TradeCargo.fleet_holds(home), _capacity(),
	])
	if zones.is_empty():
		return
	_select(home)
	MapPlayFleets.on_action(_play, "sortie:%d" % zones[0])
	_say("  after the sortie: %s · home fleet? %s · moved %s" % [
		_place(home), str(NavalMovement.is_home_fleet(_play.model, home)), str(home.moved),
	])
	_say("  her holds %d · the market's capacity %d" % [
		TradeCargo.fleet_holds(home), _capacity(),
	])
	_say("  the market's own reading: %s" % str(_play.economy.trade_cargo()))
	_my_toasts()
	_print_dossier()
	if not await _advance():
		return
	var result: Dictionary = _play.ship_layer.order(
		home, FleetState.Location.IN_PORT, _play.capital_province
	)
	_say("  docking back at %s: ok %s · %s" % [
		_play.model.province_name(_play.capital_province),
		str(result.get("ok", false)), _place(home),
	])
	_say("  home fleet? %s · her holds %d · the market's capacity %d · commands at the seat %d" % [
		str(NavalMovement.is_home_fleet(_play.model, home)),
		TradeCargo.fleet_holds(home), _capacity(), _commands_at_seat(),
	])
	_my_toasts()
	_print_dossier()


## A hull laid down at the seat: she joins the one home fleet, and the dossier,
## the badge and the holds all read her.
func _yard_pass() -> void:
	_say("")
	_say("--- the yard at the seat: a hull joins the one home fleet ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	if home == null:
		_say("  no home fleet on this chart")
		return
	var rows: Array[Dictionary] = MapPlayFleetYard.rows(_play, home)
	var pick: Dictionary = {}
	for row: Dictionary in rows:
		if bool(row.get("ok", false)):
			pick = row
			break
	if pick.is_empty():
		var reason: String = "no rows"
		for row: Dictionary in rows:
			reason = String(row.get("reason", "(no reason)"))
			break
		_say("  the slip offers nothing the crown may lay down: %s" % reason)
		return
	var before: int = home.ship_count()
	_say("  before: %s · holds %d" % [_named_hulls(home), TradeCargo.fleet_holds(home)])
	_say("  laying down: %s — %s" % [String(pick["name"]), String(pick["cost_text"])])
	MapPlayFleetYard.launch(_play, String(pick["type_id"]))
	_my_toasts()
	for _attempt in 2:
		if not await _advance():
			return
		if home.ship_count() > before:
			break
	_say("  after: %d hulls · holds %d · the market's capacity %d · commands at the seat %d" % [
		home.ship_count(), TradeCargo.fleet_holds(home), _capacity(), _commands_at_seat(),
	])
	_say("  her roster: %s" % _named_hulls(home))
	_select(home)
	_print_dossier()


## A hull laid down while the home squadron is at sea: the yard founds a slip at
## the seat, and the squadron that comes home must fold into it, not stand beside
## it (wiki: ships-and-naval § Home Fleet — only one command in port at the seat).
func _away_yard_pass() -> void:
	_say("")
	_say("--- the yard while the home squadron is at sea ---")
	var home: FleetState = FleetHomeMerge.home_fleet(
		_play.model, _play.ship_layer.fleets, _play.player_faction
	)
	if home == null:
		_say("  no home fleet on this chart")
		return
	if home.moved and not await _advance():
		return
	_select(home)
	var zones: Array[int] = FleetSortie.zones(_play.model, home)
	if zones.is_empty():
		_say("  no zone to put to sea into")
		return
	MapPlayFleets.on_action(_play, "sortie:%d" % zones[0])
	_say("  she sails: %s · commands at the seat %d · capacity %d" % [
		_place(home), _commands_at_seat(), _capacity(),
	])
	# The dossier's own Shipyard door: with no squadron afloat the bare slip opens.
	MapPlayFleetYard.open(_play)
	_say("  the slip the court sees:")
	for line: String in _labels(_play.hud.panels.fleet_panel):
		_say("    slip: %s" % line)
	var rows: Array[Dictionary] = FleetYard.rows(
		_play.economy.economy, true, MapPlayFleetYard.flown(_play)
	)
	var pick: Dictionary = {}
	for row: Dictionary in rows:
		if bool(row.get("ok", false)):
			pick = row
			break
	if pick.is_empty():
		_say("  the slip offers nothing the crown may lay down")
		return
	_say("  laying down: %s — %s" % [String(pick["name"]), String(pick["cost_text"])])
	MapPlayFleetYard.launch(_play, String(pick["type_id"]))
	_my_toasts()
	for _attempt in 2:
		if not await _advance():
			return
	_say("  the seat while she is away: %d command(s), %d hull(s)" % [
		_commands_at_seat(), _hulls_at_seat(),
	])
	var result: Dictionary = _play.ship_layer.order(
		home, FleetState.Location.IN_PORT, _play.capital_province
	)
	_say("  she docks back: ok %s · merged into %s · home fleet? %s" % [
		str(result.get("ok", false)), str(result.get("merged_into", "—")),
		str(NavalMovement.is_home_fleet(_play.model, home)),
	])
	_say("  commands at the seat %d · hulls at the seat %d · capacity %d" % [
		_commands_at_seat(), _hulls_at_seat(), _capacity(),
	])
	_select(_seat_fleet())
	_print_dossier()
	_my_toasts()


func _hulls_at_seat() -> int:
	var total: int = 0
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_in_port() \
				and fleet.province == _play.capital_province:
			total += fleet.ship_count()
	return total


func _seat_fleet() -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_in_port() \
				and fleet.province == _play.capital_province:
			return fleet
	return null


func _capacity() -> int:
	return TradeCargo.capacity(
		_play.world, _play.ship_layer.regions.snapshot(), _play.player_faction
	)


## The crown's commands lying in port at its capital: the wiki allows one.
func _commands_at_seat() -> int:
	var count: int = 0
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_in_port() \
				and fleet.province == _play.capital_province:
			count += 1
	return count


func _advance() -> bool:
	for _attempt in MAX_TURN_ATTEMPTS:
		var before: int = _play.turn
		MapPlayTurn.end_turn(_play)
		await process_frame
		if _play.turn > before:
			return true
		if not _answer_pending():
			_say("  the turn stayed shut at %d (suspended %s)" % [
				_play.turn, str(_play.turn_suspended),
			])
			return false
		# An answered consent resumes the same turn's remaining phases.
		await process_frame
		if _play.turn > before:
			return true
	return false


func _answer_pending() -> bool:
	if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
		MapPlayTurn.answer_call(_play, false)
		return true
	if Intervention.has_pending(_play.diplomacy, _play.player_faction):
		MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		return true
	if DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
		MapPlayTurn.answer_offer(_play, false)
		return true
	return false


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % fleet.id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


func _place(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "at sea, %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "in port, %s" % _play.model.province_name(fleet.province)


## "ship_1 Carrack 'Trinidad'" — the ids the muster minted and the names she flies.
func _named_hulls(fleet: FleetState) -> String:
	if fleet == null:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s '%s'" % [
			hull_id, fleet.type_of(hull_id), ShipNames.of(fleet, hull_id),
		])
	return "none" if parts.is_empty() else ", ".join(parts)


## The fleet dossier exactly as the panel builds it: every label and button.
func _print_dossier() -> void:
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		_say("  no fleet dossier shown")
		return
	for line: String in _labels(panel):
		_say("    dossier: %s" % line)


## Toasts about this area, so a turn's general noise does not bury them.
func _my_toasts() -> void:
	for panel: Node in _play.hud.despatches.box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("fleet") or lower.contains("squadron")
				or lower.contains("hull") or lower.contains("ship")
				or lower.contains("cargo") or lower.contains("hold")
				or lower.contains("port") or lower.contains("yard")
			):
				_say("    toast: %s" % text)


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node == null:
		return out
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var canvas: CanvasItem = child as CanvasItem
		if canvas != null and not canvas.is_visible_in_tree():
			continue
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		var button: Button = child as Button
		if button != null and not button.text.is_empty():
			out.append("[%s]%s" % [button.text, " (disabled)" if button.disabled else ""])
		out.append_array(_labels(child))
	return out


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_home_fleet: %d steps ---" % _steps.size())
	quit()
