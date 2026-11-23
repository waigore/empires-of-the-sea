extends SceneTree
## Headless free-playtest drive for a land war on the NEW WORLD chart: hosts
## that never share a chart with the seat (wiki: military-armies § Movement and
## attacks, § Combat and province loss; map-topology § two regions).
##
## The opening campaign gives a crown no land in the New World, so the drive
## reaches the area the only way a crown does — a landed field army that storms
## a Tribe's province — and then reads every surface the court meets there:
## the march the rules allow, the despatch, the toasts, the province sheet's own
## reading, the army dossier's place and hint, and the crown's army and realm
## counsels. A second pass marches deeper, now from the crown's own New World
## ground, so interior lines and the road home are read on a chart with no seat.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_new_world_war.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const ADVANCED: String = AdvancedStart.TURNS100
## The landed expedition: one guard per hull a small squadron carries.
const HOST_MEN: int = 6

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null
var _screen: MapScreen = null
var _host: ArmyState = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, ADVANCED)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s · turn %d · %s · seat %s (%s)" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(_play.player_faction),
		_play.world.region(FactionCatalog.OLD_WORLD).province_name(_play.capital_province),
		FactionCatalog.region_label(FactionCatalog.OLD_WORLD),
	])
	_play.screen.switch_region(FactionCatalog.NEW_WORLD)
	await process_frame
	_say("chart on screen: %s" % FactionCatalog.region_label(_play.region_index))
	_survey()
	if _play.model == null or _play.model.region_id != FactionCatalog.NEW_WORLD:
		_say("the New World chart did not mount — update playtests/playtest_new_world_war.gd")
		_finish()
		return
	var step: Dictionary = _war_target()
	if step.is_empty():
		_say("no Tribe province beside a staging province — the drive cannot run")
		_finish()
		return
	await _first_pass(int(step["province"]), int(step["staging"]), int(step["tribe"]))
	await _second_pass()
	await _stranded_pass()
	await _seat_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## One landed host storms a Tribe's province beside it: the march, the despatch,
## the toasts, and what every sheet says on a chart with no seat.
func _first_pass(target: int, staging: int, tribe: int) -> void:
	_say("")
	_say("--- first pass: a landed host storms %s (%s) from %s ---" % [
		_province_name(target), FactionCatalog.name_of(tribe),
		_province_name(staging),
	])
	_host = _seat(HOST_MEN, staging)
	_say("seated a %d-regiment crown host at %s (fixture); %s owns it" % [
		_host.count(), _province_name(staging), _owner_name(_province_owner(staging)),
	])
	_declare(tribe)
	MapPlayArmies.select(_play, _host)
	var order: Dictionary = _play.army_layer.order(
		_host, target, MapPlayArmies.may_invade(_play, target)
	)
	_say("order march %s → %s: %s\"%s\"" % [
		_province_name(staging), _province_name(target),
		"ok " if bool(order.get("ok", false)) else "refused ",
		String(order.get("reason", "")),
	])
	if not bool(order.get("ok", false)):
		return
	_host_readings("before the turn")
	await _run_turn()
	_after_capture(target, tribe)


## Everything the court meets once the province is the crown's own New World
## ground: the sheets, the toasts, and the road home.
func _after_capture(target: int, tribe: int) -> void:
	_say("")
	_say("--- after the turn: %s is held by %s; %s holds %d provinces here ---" % [
		_province_name(target), _owner_name(_province_owner(target)),
		FactionCatalog.name_of(_play.player_faction), CapitalLoss.owned_provinces(
			_play.model, _play.player_faction
		).size(),
	])
	if _host == null or _host.is_empty():
		_say("the host fell in the storm — nothing to read")
		return
	_host_readings("after the capture")
	_province_sheet(target)
	_counsel_lines(target)
	var data: ProvinceState = _play.model.province_data(target)
	_say("province record: capital %s · capital_tile %s · town %d" % [
		str(data.capital), str(data.capital_tile), data.town_development,
	])
	_say("seats: Old World %d · New World %d · play.capital_province %d" % [
		CapitalLoss.seat_of(_play.world.region(FactionCatalog.OLD_WORLD), _play.player_faction),
		CapitalLoss.seat_of(_play.model, _play.player_faction),
		_play.capital_province,
	])
	_collision_probe()


## The crown's own New World ground beside the captured province: one more war
## province taken, so interior lines are read from ground the crown holds here.
func _second_pass() -> void:
	_say("")
	if _host == null or _host.is_empty():
		_say("no host surviving to march again")
		return
	_host.moved = false
	var next: int = _next_target(_host.province)
	if next < 0:
		_say("no hostile province beside %s — the second pass cannot run" % _province_name(
			_host.province
		))
		return
	var tribe: int = _province_owner(next)
	_say("--- second pass: from own ground in the New World, storm %s (%s) ---" % [
		_province_name(next), FactionCatalog.name_of(tribe),
	])
	_say("before the war: army counsel \"%s\"" % MapPlayArmyPick.line(_play, _host))
	_declare(tribe)
	_host.moved = false
	_say("with war on: army counsel \"%s\"" % MapPlayArmyPick.line(_play, _host))
	_counsel_lines(next)
	MapPlayArmies.select(_play, _host)
	var from: String = _province_name(_host.province)
	var order: Dictionary = _play.army_layer.order(
		_host, next, MapPlayArmies.may_invade(_play, next)
	)
	_say("order march %s → %s: %s\"%s\"" % [
		from, _province_name(next),
		"ok " if bool(order.get("ok", false)) else "refused ",
		String(order.get("reason", "")),
	])
	if not bool(order.get("ok", false)):
		return
	_host_readings("before the second turn")
	await _run_turn()
	_after_capture(next, tribe)


## A crown host cut off on the New World chart: no own land touches it and no
## land march from this shore reaches the seat, which lies across the sea. The
## drive reads the dossier's hint, the march's refusal and the court's pick — the
## one place a free playtest cannot reach by playing forward — so the rule's
## words for an army that never shares a chart with its seat are proven on the
## chart, not only in a unit fixture (wiki: military-armies § Movement and
## attacks; ships-and-naval § Naval transport (armies); DR-20261122-07).
func _stranded_pass() -> void:
	_say("")
	var spot: int = _cut_off_ground()
	if spot < 0:
		_say("no ground here is cut off from the crown — the stranded pass cannot run")
		return
	# A standard of its own, minted with the layer's next ids: `army_by_id`
	# answers the first standard that carries an id, so the drive never reuses the
	# first pass's.
	var host: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, _play.player_faction, spot, false,
		["guards"] as Array[String], _play.army_layer.next_regiment
	)
	_play.army_layer.next_army += 1
	_play.army_layer.next_regiment += 1
	_play.army_layer.armies.append(host)
	_play.army_layer.add_marker(host)
	MapPlayArmies.select(_play, host)
	var panel: ArmyPanel = _play.hud.panels.army_panel
	_say("--- fourth pass: a host cut off at %s (%s) ---" % [
		_province_name(spot), _owner_name(_province_owner(spot)),
	])
	_say("seat on this chart: %d · seat lies elsewhere: %s · stranded: %s" % [
		ArmyMovement.capital_province_on(_play.model, _play.player_faction),
		str(ArmyMovement.seat_elsewhere(_play.model, host)),
		str(ArmyMovement.stranded(_play.model, host)),
	])
	_say("dossier place:  \"%s\"" % panel._location.text)
	_say("dossier status: \"%s\"" % panel._status.text)
	_say("dossier hint:   \"%s\"" % panel._hint.text)
	_say("dossier pick:   \"%s\"" % panel._pick.text)
	_say("army counsel:   \"%s\"" % MapPlayArmyPick.line(_play, host))
	_say("army sheet:     \"%s\"" % MapPlayArmyOrdersPick.line(_play))
	var own_far: int = _farthest_own(spot)
	if own_far >= 0:
		var check: Dictionary = ArmyMovement.can_move(_play.model, host, own_far, false)
		_say("march home to %s: %s\"%s\"" % [
			_province_name(own_far), "ok " if bool(check.get("ok", false)) else "refused ",
			String(check.get("reason", "")),
		])
	_play.army_layer.armies.erase(host)
	_play.army_layer.remove_marker(host)
	_play.army_layer.deselect()


## Ground of another court with no crown province beside it: the shore a beaten
## host can be left on, where no own land touches.
func _cut_off_ground() -> int:
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction or province.owner == MapModel.NO_ID:
			continue
		var cut: bool = true
		for id: int in MapGeo.province_neighbors(_play.model, province.id):
			if _province_owner(id) == _play.player_faction:
				cut = false
				break
		if cut:
			return province.id
	return -1


## The crown's own province here that stands farthest from the host, so the march
## it cannot walk is the one the refusal words.
func _farthest_own(from: int) -> int:
	var model: MapModel = _play.model
	var distances: Dictionary = {}
	var queue: Array[int] = [from]
	distances[from] = 0
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for id: int in MapGeo.province_neighbors(model, current):
			if distances.has(id):
				continue
			distances[id] = int(distances[current]) + 1
			queue.append(id)
	var best: int = -1
	var best_distance: int = -1
	for province: ProvinceState in model.provinces:
		if province.owner != _play.player_faction:
			continue
		if not distances.has(province.id):
			continue
		if int(distances[province.id]) > best_distance:
			best = province.id
			best_distance = int(distances[province.id])
	return best


## The seat's own orders queued on its chart, then the chart flipped before the
## turn closes: a hire, a muster and a launch are the seat's, not the chart's,
## and must land at the capital wherever the crown is looking (wiki:
## workers-and-population § Phase placement; military-armies § Home Army).
func _seat_pass() -> void:
	_play.screen.switch_region(FactionCatalog.OLD_WORLD)
	await process_frame
	var seat: int = _play.capital_province
	_say("")
	_say("--- third pass: a hire, a muster and a launch at %s, then the chart flips ---" % (
		_province_name(seat)
	))
	var before: Dictionary = _counts()
	MapPlayInput.select_province(_play, seat, Vector2.ZERO)
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "train_explorer")
	_say("ordered a hire: %s" % _toasts_line())
	_clear_toasts()
	MapPlayArmyMuster.recruit(_play, _regiment_type())
	_say("ordered a regiment: %s" % _toasts_line())
	_clear_toasts()
	var hull: String = _hull_type()
	MapPlayFleetYard.launch(_play, hull)
	_say("ordered a %s: %s" % [hull, _toasts_line()])
	_play.screen.switch_region(FactionCatalog.NEW_WORLD)
	await process_frame
	_say("chart flipped to %s at turn %d — closing the turn here" % [
		FactionCatalog.region_label(_play.region_index), _play.turn,
	])
	await _run_turn()
	var after: Dictionary = _counts()
	_say("before the turn: %s" % _count_text(before))
	_say("after the turn:  %s" % _count_text(after))
	for raw: Variant in _play.civilian_layer.regions.value(FactionCatalog.NEW_WORLD, []):
		var unit: CivilianState = raw
		if unit == null or unit.owner != _play.player_faction:
			continue
		var province: int = _play.world.region(FactionCatalog.NEW_WORLD).province_at(
			unit.tile.x, unit.tile.y
		)
		var model: MapModel = _play.world.region(FactionCatalog.NEW_WORLD)
		_say("  New World crew %d %s at tile %s — %s (%s)" % [
			unit.id, unit.type_id, str(unit.tile), model.province_name(province),
			_owner_name(model.province_owner(province)),
		])


## The crown's crews, hulls and Home Army regiments, chart by chart.
func _counts() -> Dictionary:
	var out: Dictionary = {}
	for region: int in _play.world.region_count():
		var crews: int = 0
		for raw: Variant in _play.civilian_layer.regions.value(region, []):
			var unit: CivilianState = raw
			if unit != null and unit.owner == _play.player_faction:
				crews += 1
		var hulls: int = 0
		for raw: Variant in _play.ship_layer.regions.value(region, []):
			var fleet: FleetState = raw
			if fleet != null and fleet.owner == _play.player_faction:
				hulls += fleet.ship_count()
		var home: int = 0
		for raw: Variant in _play.army_layer.regions.value(region, []):
			var army: ArmyState = raw
			if army != null and army.owner == _play.player_faction and army.is_home_army():
				home = army.count()
		out[region] = {"crews": crews, "hulls": hulls, "home": home}
	return out


func _count_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for region: int in counts.keys():
		var row: Dictionary = counts[region]
		parts.append("%s crews %d, hulls %d, Home Army %d" % [
			FactionCatalog.region_label(region), int(row["crews"]), int(row["hulls"]),
			int(row["home"]),
		])
	return " · ".join(parts)


## The first standard the drill yard's own rows would raise.
func _regiment_type() -> String:
	for row: Dictionary in ArmyTraining.rows(_play.economy.economy):
		if bool(row.get("ok", false)):
			return String(row.get("type_id", ""))
	return RegimentCatalog.ids()[0]


## The first hull the yard's own rows would lay down.
func _hull_type() -> String:
	var rows: Array[Dictionary] = FleetYard.rows(
		_play.economy.economy, true, MapPlayFleetYard.flown(_play)
	)
	for row: Dictionary in rows:
		if bool(row.get("ok", false)):
			return String(row.get("type_id", ""))
	return "sloop"


# --- readings --------------------------------------------------------------


func _survey() -> void:
	var model: MapModel = _play.model
	if model == null:
		return
	var crown: Array[String] = []
	var tribes: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if province.owner == _play.player_faction:
			crown.append(province.name)
		elif FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			tribes[province.owner] = int(tribes.get(province.owner, 0)) + 1
	_say("crown provinces here: %d%s" % [
		crown.size(), "" if crown.is_empty() else " (%s)" % ", ".join(crown),
	])
	var named: PackedStringArray = []
	for tribe: int in tribes:
		named.append("%s %d" % [FactionCatalog.name_of(tribe), int(tribes[tribe])])
	_say("Tribes on this chart: %s" % (", ".join(named) if not named.is_empty() else "none"))
	var armies: int = 0
	for raw: Variant in MapPlayCourtRoster.region_armies(_play, FactionCatalog.NEW_WORLD):
		var army: ArmyState = raw
		if army != null and army.owner == _play.player_faction:
			armies += 1
	_say("crown armies stored on this chart: %d" % armies)
	var crews: int = 0
	for raw: Variant in _play.civilian_layer.regions.value(FactionCatalog.NEW_WORLD, []):
		var unit: CivilianState = raw
		if unit != null and unit.owner == _play.player_faction:
			crews += 1
	_say("crown crews stored on this chart: %d" % crews)


## The host as the court reads it: place, status, hint, and the counsels.
func _host_readings(where: String) -> void:
	if _host == null:
		return
	MapPlayArmies.select(_play, _host)
	var panel: ArmyPanel = _play.hud.panels.army_panel
	_say("host (%s): %d regiments at %s (%s)" % [
		where, _host.count(), _province_name(_host.province),
		_owner_name(_province_owner(_host.province)),
	])
	_say("dossier place:  \"%s\"" % panel._location.text)
	_say("dossier status: \"%s\"" % panel._status.text)
	_say("dossier hint:   \"%s\"" % panel._hint.text)
	_say("dossier pick:   \"%s\"" % panel._pick.text)
	_say("army counsel:   \"%s\"" % MapPlayArmyPick.line(_play, _host))
	var destinations: Array[int] = ArmyMovement.destinations(_play.model, _host)
	var own: int = 0
	var list: PackedStringArray = []
	for id: int in destinations:
		if _province_owner(id) == _host.owner:
			own += 1
		list.append("%s (%s)" % [
			_province_name(id), _owner_name(_province_owner(id)),
		])
	_say("tap list: %d provinces, %d ours — %s" % [
		destinations.size(), own, ", ".join(list) if not list.is_empty() else "none",
	])
	_say("on own ground: %s · stranded: %s" % [
		str(ArmyMovement.on_own_ground(_play.model, _host)),
		str(ArmyMovement.stranded(_play.model, _host)),
	])


## The province sheet for one province of this chart, as the court reads it.
func _province_sheet(province: int) -> void:
	_play.hud.panels.show_province(
		_play.model, province, MapPlayImprovements.crown_link(_play, province)
	)
	var panel: ProvincePanel = _play.hud.panels.panel
	_say("province sheet for %s (owner %s):" % [
		_province_name(province), _owner_name(_province_owner(province)),
	])
	for line: String in _labels(panel):
		_say("  sheet: %s" % line)


## The crown-wide counsels: the realm's line, the people's line, the army sheet,
## the muster roll and the province dossier's own reading.
func _counsel_lines(province: int) -> void:
	_say("realm counsel:   \"%s\"" % MapPlayRealmCounsel.line(_play))
	_say("people counsel:  \"%s\"" % MapPlayPeoplePick.line(_play))
	_say("army sheet:      \"%s\"" % MapPlayArmyOrdersPick.line(_play))
	_say("muster roll:     \"%s\"" % MapPlayForceCounsel.line(_play))
	_say("province read:   \"%s\"" % MapPlayProvinceCounsel.line(
		_play, _play.model, province
	))
	_press_orders(province)


## The province sheet's own order rows, pressed as a crown would press them: the
## muster door and the drill rows of a chart with no seat.
func _press_orders(province: int) -> void:
	MapPlayInput.select_province(_play, province, Vector2.ZERO)
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "recruit")
	_say("press [Recruit Regiment]: %s" % _toasts_line())
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "train_explorer")
	_say("press [Train Explorer]:   %s" % _toasts_line())
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "shipyard")
	_say("press [Shipyard]:         %s" % _toasts_line())


## The seat's local province id read on the chart on screen: the id a province
## holds here is not the id the same number holds at home (wiki:
## world-model-identity § prefixed ids).
func _collision_probe() -> void:
	var seat: int = _play.capital_province
	_say("seat probe: field %d · seat_province %d · capital_province(model) %d · seat_of %d" % [
		seat, _play.world.seat_province(FactionCatalog.NEW_WORLD, _play.player_faction),
		WorldBootstrap.capital_province(_play.model, _play.player_faction),
		CapitalLoss.seat_of(_play.model, _play.player_faction),
	])
	var owned: Array[String] = []
	for province: ProvinceState in _play.model.provinces:
		if province.owner == _play.player_faction:
			owned.append("%d:%s%s" % [province.id, province.name, " (capital)" if province.capital else ""])
	_say("crown provinces here: %s" % ", ".join(owned))
	var data: ProvinceState = _play.model.province_data(seat)
	if data == null:
		_say("this chart has no province %d" % seat)
		return
	_say("province %d here is %s (%s), harbour %s — the seat's own number" % [
		seat, data.name, _owner_name(data.owner),
		str(NavalMovement.has_harbour(_play.model, seat)),
	])
	if data.owner != _play.player_faction:
		return
	MapPlayInput.select_province(_play, seat, Vector2.ZERO)
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "train_explorer")
	_say("press [Train Explorer] on %s: %s" % [data.name, _toasts_line()])
	var crews: int = 0
	for raw: Variant in _play.civilian_layer.regions.value(FactionCatalog.NEW_WORLD, []):
		var unit: CivilianState = raw
		if unit != null and unit.owner == _play.player_faction:
			crews += 1
	_say("crown crews on this chart after the press: %d (the quartermaster holds the hire)" % crews)
	_clear_toasts()
	MapPlayInput.on_panel_action(_play, "shipyard")
	var fleet_open: bool = _play.hud.panels.is_fleet_panel_open()
	_say("press [Shipyard] on %s: fleet sheet open %s · %s" % [
		data.name, str(fleet_open), _toasts_line(),
	])
	if fleet_open:
		for line: String in _labels(_play.hud.panels.fleet_panel):
			_say("  yard: %s" % line)


func _toasts_line() -> String:
	var out: Array[String] = []
	for text: String in _toasts():
		out.append(text)
	return " | ".join(out) if not out.is_empty() else "nothing on the lane"


func _clear_toasts() -> void:
	if _play.hud == null:
		return
	for child: Node in _play.hud.despatches.box.get_children():
		child.queue_free()


# --- orders ----------------------------------------------------------------


func _declare(tribe: int) -> void:
	var war: Dictionary = DiplomacyRules.declare_war(
		_play.diplomacy, _play.player_faction, tribe
	)
	_say("war on %s: %s" % [
		FactionCatalog.name_of(tribe),
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused")),
	])


func _run_turn() -> void:
	var turn: int = _play.turn
	MapPlayTurn.end_turn(_play)
	await process_frame
	_skip_plates()
	var guard: int = 0
	while _play.turn == turn and not _play.campaign_over() and guard < 8:
		guard += 1
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
		_skip_plates()
	_skip_plates()
	_say("calendar: turn %d -> %d" % [turn, _play.turn])
	for text: String in _toasts():
		_say("  toast: %s" % text)


func _skip_plates() -> void:
	var plates: int = 0
	while _play.hud != null and _play.hud.is_quick_battle_shown() and plates < 8:
		plates += 1
		_play.hud.quick_battle_overlay.skip()
		_play.hud.quick_battle_overlay._on_continue()


# --- seating ---------------------------------------------------------------


func _seat(count: int, province: int) -> ArmyState:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, _play.player_faction, province, false, types,
		_play.army_layer.next_regiment
	)
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)
	return army


## A Tribe province beside one of the crown's own New World provinces — the
## ground a landed expedition really starts from — else any Tribe province with a
## neighbour of another owner: `{province, staging, tribe}`.
func _war_target() -> Dictionary:
	var model: MapModel = _play.model
	var fallback: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.TRIBE:
			continue
		for id: int in MapGeo.province_neighbors(model, province.id):
			var holder: int = model.province_owner(id)
			if holder == province.owner or holder == MapModel.NO_ID:
				continue
			if holder == _play.player_faction:
				return {"province": province.id, "staging": id, "tribe": province.owner}
			if fallback.is_empty():
				fallback = {"province": province.id, "staging": id, "tribe": province.owner}
	return fallback


## The province beside the host the crown would have to fight for, or -1 when no
## other court holds ground next to it.
func _next_target(province: int) -> int:
	for id: int in MapGeo.province_neighbors(_play.model, province):
		var holder: int = _province_owner(id)
		if holder == _play.player_faction or holder == MapModel.NO_ID:
			continue
		return id
	return -1


# --- places ----------------------------------------------------------------


func _province_name(province: int) -> String:
	return _play.model.province_name(province)


func _province_owner(province: int) -> int:
	return _play.model.province_owner(province)


func _owner_name(faction: int) -> String:
	if faction == MapModel.NO_ID:
		return "unowned"
	return FactionCatalog.name_of(faction)


# --- output ----------------------------------------------------------------


func _toasts() -> Array[String]:
	var out: Array[String] = []
	if _play.hud == null:
		return out
	for panel: Node in _play.hud.despatches.box.get_children():
		if panel.is_queued_for_deletion():
			continue
		out.append_array(_labels(panel))
	return out


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var label: Label = child as Label
		if label != null and not label.text.is_empty() and label.is_visible_in_tree():
			out.append(label.text)
		var button: Button = child as Button
		if button != null and not button.text.is_empty() and button.is_visible_in_tree():
			out.append("[%s]%s" % [button.text, "" if not button.disabled else " (disabled)"])
		out.append_array(_labels(child))
	return out


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: %s" % line)


func _finish() -> void:
	print("")
	print("--- playtest_new_world_war: %d steps ---" % _steps.size())
	quit()