extends SceneTree
## Headless free-playtest drive for a shared station's row and stack (wiki:
## ships-and-naval § Fleets in one station; DR-20261119-08). The chart's fan only
## appears once several of the crown's squadrons hold one water, which ordinary
## play reaches only by splitting a squadron hull by hull, so the drive reaches it
## that way and reads what a player reads:
##
## 1. the reach: the home squadron sorties on a turn-100 start, then detaches
##    hulls from the largest command until four of the crown's stand in the water;
## 2. the plan: who takes a row step, who is covered, where each hull is drawn;
## 3. the tap: every fanned squadron is hit at the point she is drawn, and a
##    covered one takes no tap;
## 4. the words: what the court is told when it picks a squadron of a crowded
##    station — her place, the station's count and the flagship;
## 5. the stack: a rival seated in the same water rides the stack, never a nation
##    row of her own, and a second tap cycles the head;
## 6. the fog: a rival the chart does not draw never takes the head, is skipped by
##    the cycle and is not counted in the words.
##
## The rival and the fourth command are seated where a launch or a sail would have
## put them (no order on the chart floats a rival, and a fourth command needs a
## hull the opening does not carry); every row, stack, tap and line under test is
## the game's own.
##
## Not a CI gate — run it by hand:
##   tools/run.sh --headless --script res://playtests/playtest_station_fan.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## The crown's squadrons the row holds before the rest ride the stack.
const ROW: int = FleetLanes.FAN_LIMIT

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null
var _zone: int = -1
var _checks: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen: MapScreen = await Launch.open_map(
		self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100
	)
	if screen == null:
		_finish()
		return
	_play = screen.play
	var player: int = _play.player_faction
	_say("seed %s — %s, turn %d, chart %d" % [
		SEED_TEXT, FactionCatalog.name_of(player), _play.turn, _play.model.region_id,
	])
	_roster_pass(player)
	_lone_pass(player)
	if not _reach_pass(player):
		_finish()
		return
	_plan_pass(player)
	_tap_pass(player)
	_rival_pass(player)
	_stack_pass(player)
	_words_pass(player)
	_fog_pass(player)
	_port_pass(player)
	_finish()


# --- reach ------------------------------------------------------------------


func _roster_pass(player: int) -> void:
	_say("")
	_say("--- roster: the crown's squadrons ---")
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != player:
			continue
		_say("  fleet %d at %s — %d hulls (%s)" % [
			fleet.id, _station(fleet), fleet.ship_count(), _named_hulls(fleet),
		])


## Sails the richest squadron out and detaches hulls until the row and a stack
## beyond it both exist: the one state the fan is about.
func _reach_pass(player: int) -> bool:
	_say("")
	_say("--- reach: four of the crown's commands in one water ---")
	var source: FleetState = _richest(player)
	if source == null:
		_say("  the crown floats no squadron")
		return false
	if source.is_in_port():
		var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, source.province)
		if zones.is_empty():
			_say("  the seat has no water beside it")
			return false
		_zone = zones[0]
		_select(source)
		_clear_toasts()
		MapPlayFleets.on_action(_play, "sortie:%d" % _zone)
		_my_toasts()
	else:
		_zone = source.sea_zone
	_say("  the station: %s" % _zone_name(_zone))
	if not _fleet_by_id(source.id).is_at_sea() or source.sea_zone != _zone:
		_say("  the sortie did not take: %s" % _station(source))
		return false
	# Detach the largest command's hulls until the crown has a row and a stack
	# beyond it, exactly as the dossier's Detach presses would.
	var guard: int = 0
	while _mine_in_station(player).size() < ROW + 1 and guard < 8:
		guard += 1
		var lead: FleetState = _largest(player, _zone)
		if lead == null or lead.ship_count() < 2:
			break
		_select(lead)
		_clear_toasts()
		MapPlayFleets.on_action(_play, "split:%s" % lead.hulls[lead.hulls.size() - 1])
		_my_toasts()
	var mine: Array[FleetState] = _mine_in_station(player)
	_say("  after the detaches: %d of the crown's commands in the station" % mine.size())
	for fleet: FleetState in mine:
		_say("    fleet %d — %s" % [fleet.id, _named_hulls(fleet)])
	if mine.size() < ROW:
		_say("  the opening carries too few hulls to fill the row — seated a command")
		_seat(player, _zone, "playtest_hull_row")
	return true


func _plan_pass(player: int) -> void:
	_say("")
	_say("--- the plan: who stands in the row, who is covered ---")
	var plan: Dictionary = FleetLanes.plan(_play.ship_layer.fleets, player)
	var lanes: Dictionary = plan["lanes"]
	var stacks: Dictionary = plan["stacks"]
	var fronts: Dictionary = plan["fronts"]
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		var lane: Variant = lanes.get(fleet.id)
		_say("  fleet %d (%d hulls): %s · drawn at %s · covered %s · pips %s" % [
			fleet.id, fleet.ship_count(),
			"a row step" if lane is Vector2 and not _in_stack(stacks, fleet.id) else "the stack",
			"(none)" if not (lane is Vector2) else str((lane as Vector2) / FleetLanes.LANE_SPAN),
			str(ship.covered) if ship != null else "no marker",
			str(ship.pips) if ship != null else "-",
		])
	var seen: Array[Vector2] = []
	var overlap: int = 0
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null or not ship.shows_hull():
			continue
		var at: Vector2 = ship.drawn_position()
		if seen.has(at):
			overlap += 1
		seen.append(at)
	_check("no two drawn hulls of the crown share a point", overlap == 0, "%d overlaps" % overlap)
	_check(
		"the station's drawn hulls stand one lane step apart",
		_spacing_ok(player),
		"steps %s" % str(_steps_apart(player))
	)
	if not _mine_in_station(player).is_empty():
		var key: String = FleetLanes.station_of(_mine_in_station(player)[0])
		_check(
			"the station names the squadron whose hull it draws",
			fronts.has(key),
			"fronts %s" % str(fronts)
		)


func _tap_pass(player: int) -> void:
	_say("")
	_say("--- the tap: the drawn point is the picked point ---")
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null:
			continue
		var hit: Ship = _play.ship_layer.ship_at(ship.drawn_position(), _radius())
		var label: String = "  tap on fleet %d at her drawn point" % fleet.id
		if ship.covered:
			_say("%s — covered, no tap of her own (nearest: %s)" % [
				label, "none" if hit == null else str(hit.fleet_id),
			])
			continue
		_say("%s — hit %s" % [label, "none" if hit == null else str(hit.fleet_id)])
		_check(
			"a tap lands on the hull it looks like it hits",
			hit != null and hit.fleet_id == fleet.id,
			"fleet %d drew at %s, the tap found %s" % [
				fleet.id, str(ship.drawn_position()),
				"none" if hit == null else str(hit.fleet_id),
			]
		)
		# The real entry the mouse and the finger both use.
		_clear_toasts()
		MapPlayInput.on_tapped(_play, ship.drawn_position())
		var picked: FleetState = _play.ship_layer.fleet_of(_play.ship_layer.selected())
		_check(
			"the tap selects the squadron it hit",
			picked != null and picked.id == fleet.id,
			"picked %s" % ("none" if picked == null else str(picked.id))
		)
		_my_toasts()


func _words_pass(player: int) -> void:
	_say("")
	_say("--- the words: a selection in a crowded station ---")
	var here: Array[FleetState] = _drawn_in_station(player)
	for fleet: FleetState in here:
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null:
			continue
		_play.ship_layer.select(ship)
		var line: String = MapPlayFleets.selection_line(_play, ship, fleet)
		_say("  fleet %d (%s): %s" % [
			fleet.id, FactionCatalog.name_of(fleet.owner),
			"(silent)" if line.is_empty() else line,
		])
		_check(
			"a crowded station names her place and the station's count",
			line.contains("of %d squadrons here" % here.size()),
			"fleet %d said \"%s\" of %d drawn in the station" % [
				fleet.id, line, here.size(),
			]
		)


func _stack_pass(player: int) -> void:
	_say("")
	_say("--- the stack: a second tap cycles ---")
	# The rival is in the crown's hand from the last pass, and she draws the head:
	# let go of the water first so the station's own first squadron holds it.
	_play.ship_layer.deselect()
	var head: FleetState = _stack_front(player)
	if head == null:
		_say("  no stack stands in the station")
		return
	var ship: Ship = _play.ship_layer.ship_for(head)
	_say("  the head draws fleet %d; her cycle %s" % [head.id, str(ship.stack)])
	var walked: Array[int] = []
	for _step in ship.stack.size() + 1:
		_clear_toasts()
		MapPlayInput.on_tapped(_play, ship.drawn_position())
		var picked: FleetState = _play.ship_layer.fleet_of(_play.ship_layer.selected())
		if picked == null:
			_say("  tap: nothing")
			break
		walked.append(picked.id)
		_say("  tap %d: fleet %d — %s" % [
			walked.size(), picked.id, MapPlayFleets.selection_line(
				_play, _play.ship_layer.selected(), picked
			),
		])
		_my_toasts()
		ship = _play.ship_layer.ship_for(picked)
		if ship == null:
			break
	_check(
		"tapping the head walks the station's cycle",
		walked.size() >= 2 and walked[0] != walked[1],
		"walked %s" % str(walked)
	)
	_play.ship_layer.deselect()


func _rival_pass(player: int) -> void:
	_say("")
	_say("--- the stack: a rival in the crown's water ---")
	var rival: int = _rival_beside(player)
	var fleet: FleetState = _seat(rival, _zone, "playtest_hull_rival", 2)
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	_say("  a %s squadron (%d hulls) stands in the station: covered %s, pips on her %s" % [
		FactionCatalog.name_of(rival), fleet.ship_count(), str(ship.covered), str(ship.pips),
	])
	_check(
		"a rival never takes a row step of her own",
		ship.covered,
		"the rival's lane %s" % str(ship.lane / FleetLanes.LANE_SPAN)
	)
	_check(
		"the crown's fanned row keeps its steps beside her",
		_spacing_ok(player),
		"steps %s" % str(_steps_apart(player))
	)
	_play.ship_layer.select(ship)
	var line: String = MapPlayFleets.selection_line(_play, ship, fleet)
	_say("  the words: %s" % line)
	_check(
		"a rival's line says observe only",
		line.contains("observe only"),
		"said \"%s\"" % line
	)
	_check(
		"a sighted, unread rival still prints her plate",
		ship.shows_plate(),
		"read %s, plate %s" % [str(ship.strength_known), str(ship.shows_plate())]
	)
	# The pips over the head name the courts behind her, one per squadron.
	var front: FleetState = _stack_front(player)
	if front != null:
		var head: Ship = _play.ship_layer.ship_for(front)
		_say("  the head fleet %d now wears pips %s" % [front.id, str(head.pips)])
		_check(
			"the head wears the rival's pennant",
			head.pips.has(rival),
			"pips %s" % str(head.pips)
		)


func _fog_pass(player: int) -> void:
	_say("")
	_say("--- the fog: a rival the chart does not draw ---")
	var hidden: Ship = null
	for ship: Ship in _play.ship_layer.ships:
		var fleet: FleetState = _play.ship_layer.fleet_of(ship)
		if fleet == null or fleet.owner == player:
			continue
		if fleet.sea_zone == _zone:
			hidden = ship
			break
	if hidden == null:
		_say("  no rival in the station to hide")
		return
	_play.ship_layer.deselect()
	var head_before: Ship = _play.ship_layer.ship_for(_stack_front(player))
	var pips_before: int = _pips_of(head_before, hidden.faction)
	var count_before: int = _words_count(player)
	_say("  before the fog: the head's pips %s, the station's count %d" % [
		str(head_before.pips) if head_before != null else "-", count_before,
	])
	hidden.visible = false
	_play.ship_layer.relayout()
	var head: Ship = _play.ship_layer.ship_for(_stack_front(player))
	_say("  hidden fleet %d: covered %s; the head's pips %s; the count %d" % [
		hidden.fleet_id, str(hidden.covered), str(head.pips) if head != null else "-",
		_words_count(player),
	])
	_check(
		"an unseen rival never draws the hull",
		hidden.covered,
		"covered %s" % str(hidden.covered)
	)
	_check(
		"an unseen rival's colour stays off the pips",
		head == null or _pips_of(head, hidden.faction) < pips_before,
		"pips %s (was %d of her court)" % [
			str(head.pips) if head != null else "-", pips_before,
		]
	)
	_check(
		"an unseen rival is not counted in the words",
		_words_count(player) == count_before - 1,
		"count %d, was %d" % [_words_count(player), count_before]
	)
	hidden.visible = true
	_play.ship_layer.relayout()
	_check(
		"the rival is counted again once the chart draws her",
		_words_count(player) == count_before,
		"count %d, was %d" % [_words_count(player), count_before]
	)
	for fleet: FleetState in _drawn_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null:
			continue
		_play.ship_layer.select(ship)
		var line: String = MapPlayFleets.selection_line(_play, ship, fleet)
		_say("  fleet %d: %s" % [fleet.id, line])


func _lone_pass(player: int) -> void:
	_say("")
	_say("--- a station of one ---")
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or fleet.owner != player or not fleet.is_afloat():
			continue
		if _station_count(fleet) > 1:
			continue
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null:
			continue
		_play.ship_layer.select(ship)
		_say("  fleet %d at %s: lane %s, covered %s, station %s, words \"%s\"" % [
			fleet.id, _station(fleet), str(ship.lane), str(ship.covered),
			str(ship.station), MapPlayFleets.selection_line(_play, ship, fleet),
		])
		_check(
			"a squadron alone lays out on her own water",
			ship.lane == Vector2.ZERO and not ship.covered,
			"lane %s" % str(ship.lane)
		)
		_check(
			"a squadron alone says nothing new",
			MapPlayFleets.selection_line(_play, ship, fleet).is_empty(),
			"said something"
		)
		return
	_say("  the crown floats no squadron alone")


func _port_pass(player: int) -> void:
	_say("")
	_say("--- a port is not the water beside it ---")
	var berth: int = _play.capital_province
	var ported: Array[FleetState] = [
		FleetState.in_port(9001, player, berth, ["playtest_hull_port_a"], {}),
		FleetState.in_port(9002, player, berth, ["playtest_hull_port_b"], {}),
	]
	var at_sea: FleetState = FleetState.at_sea(9003, player, 0, ["playtest_hull_port_c"], {})
	var plan: Dictionary = FleetLanes.plan(
		[ported[0], ported[1], at_sea, _play.ship_layer.fleets[0]], player
	)
	var lanes: Dictionary = plan["lanes"] as Dictionary
	var stations: Dictionary = plan["stations"] as Dictionary
	_say("  two squadrons moored at %s: keys %s and %s" % [
		_play.model.province_name(berth),
		FleetLanes.station_of(ported[0]), FleetLanes.station_of(ported[1]),
	])
	_check(
		"a port station is one station, named apart from the water",
		FleetLanes.station_of(ported[0]) == FleetLanes.station_of(ported[1])
			and FleetLanes.station_of(ported[0]) != FleetLanes.station_of(at_sea),
		"port %s, water %s" % [
			FleetLanes.station_of(ported[0]), FleetLanes.station_of(at_sea),
		]
	)
	_check(
		"the crown's moored pair fans out in the harbour",
		fanned(lanes, ported),
		"lanes %s" % str(lanes)
	)
	_check(
		"a port's reading hears both hulls in the harbour",
		(stations.get(ported[0].id, [] as Array) as Array).size() == 2
			and (stations.get(ported[1].id, [] as Array) as Array).size() == 2,
		"station %s" % str(stations.get(ported[0].id, []))
	)


func fanned(lanes: Dictionary, fleets: Array[FleetState]) -> bool:
	var steps: Array[Vector2] = []
	for fleet: FleetState in fleets:
		var seat: Variant = lanes.get(fleet.id)
		if not (seat is Vector2):
			return false
		steps.append(seat)
	return steps.size() == 2 and not steps[0].is_equal_approx(steps[1])


# --- seating ----------------------------------------------------------------


## Seats a squadron the way a launch or a sail would leave it: on the live
## roster, with a marker under the chart's watch, and the row re-laid.
func _seat(owner: int, zone: int, hull_id: String, hulls: int = 1) -> FleetState:
	var ids: Array[String] = []
	var types: Dictionary = {}
	for index in maxi(hulls, 1):
		var id: String = "%s_%d" % [hull_id, index]
		ids.append(id)
		types[id] = "carrack" if index % 2 == 0 else "sloop"
	var fleet: FleetState = FleetState.at_sea(
		FleetRosters.next_id(_play.ship_layer.fleets), owner, zone, ids, types
	)
	_play.ship_layer.fleets.append(fleet)
	_play.ship_layer.regions.set_region(_play.model.region_id, _play.ship_layer.fleets)
	_play.ship_layer.attach_marker(fleet)
	_play.ship_layer.relayout()
	return fleet


func _rival_beside(player: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != player:
			return faction
	return 1


# --- station reads ----------------------------------------------------------


func _mine_in_station(player: int) -> Array[FleetState]:
	var out: Array[FleetState] = []
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or fleet.owner != player or not fleet.is_afloat():
			continue
		if fleet.sea_zone == _zone and fleet.is_at_sea():
			out.append(fleet)
	out.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return out


## Every squadron holding the station under test whose marker the chart draws —
## the crown's and any rival's the fog gives up — which is the count a selection
## in that water is read against.
func _drawn_in_station(player: int) -> Array[FleetState]:
	var out: Array[FleetState] = []
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or not fleet.is_afloat() or not fleet.is_at_sea():
			continue
		if fleet.sea_zone != _zone:
			continue
		if fleet.owner != player and not _drawn(fleet):
			continue
		out.append(fleet)
	out.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return out


func _drawn(fleet: FleetState) -> bool:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	return ship != null and ship.visible


## How many squadrons of every court hold one squadron's station.
func _station_count(fleet: FleetState) -> int:
	var key: String = FleetLanes.station_of(fleet)
	var count: int = 0
	for other: FleetState in _play.ship_layer.fleets:
		if other == null or not other.is_afloat():
			continue
		if FleetLanes.station_of(other) == key:
			count += 1
	return count


func _largest(player: int, zone: int) -> FleetState:
	var best: FleetState = null
	for fleet: FleetState in _mine_in_station(player):
		if fleet.sea_zone != zone:
			continue
		if best == null or fleet.ship_count() > best.ship_count():
			best = fleet
	return best


func _richest(player: int) -> FleetState:
	var best: FleetState = null
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet == null or fleet.owner != player or not fleet.is_afloat():
			continue
		if fleet.is_in_port() and fleet.province != _play.capital_province:
			continue
		if best == null or fleet.ship_count() > best.ship_count():
			best = fleet
	return best


func _stack_front(player: int) -> FleetState:
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship != null and not ship.stack.is_empty() and not ship.covered:
			return fleet
	return null


func _fleet_by_id(fleet_id: int) -> FleetState:
	return FleetRosters.find(_play.ship_layer.fleets, fleet_id)


func _in_stack(stacks: Dictionary, fleet_id: int) -> bool:
	return stacks.has(fleet_id)


func _steps_apart(player: int) -> Array[float]:
	var steps: Array[float] = []
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null or not ship.shows_hull():
			continue
		steps.append(snappedf(ship.lane.x / FleetLanes.LANE_SPAN, 0.01))
	return steps


func _spacing_ok(player: int) -> bool:
	var steps: Array[float] = _steps_apart(player)
	for index in range(1, steps.size()):
		if not is_equal_approx(steps[index] - steps[index - 1], 1.0):
			return false
	return true


## How many pennants of one court a stack head wears.
func _pips_of(ship: Ship, faction: int) -> int:
	var count: int = 0
	if ship == null:
		return count
	for pip: int in ship.pips:
		if pip == faction:
			count += 1
	return count


## The count a selection in the station's water prints ("N of M squadrons
## here"), read off the line itself rather than off the state it was built from.
func _words_count(player: int) -> int:
	for fleet: FleetState in _mine_in_station(player):
		var ship: Ship = _play.ship_layer.ship_for(fleet)
		if ship == null:
			continue
		var line: String = MapPlayFleets.selection_line(_play, ship, fleet)
		var at: int = line.find(" of ")
		if at < 0:
			continue
		var rest: String = line.substr(at + 4)
		var end: int = rest.find(" squadrons here")
		if end < 0:
			continue
		return int(rest.substr(0, end))
	return 0


func _radius() -> float:
	return 30.0 / maxf(_play.camera.zoom.x, 0.001)


# --- bookkeeping ------------------------------------------------------------


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if ok:
		_say("  ok — %s" % what)
		return
	_failed += 1
	_say("  FAIL — %s (%s)" % [what, detail])


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship != null:
		_play.ship_layer.select(ship)


func _my_toasts() -> void:
	for panel: Node in _play.hud.despatches.box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if (
				lower.contains("squadron") or lower.contains("hull")
				or lower.contains("fleet") or lower.contains("here")
			):
				_say("    toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _play.hud.despatches.box.get_children():
		child.queue_free()


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
			out.append("[%s]" % button.text)
		out.append_array(_labels(child))
	return out


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return _zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


func _zone_name(zone: int) -> String:
	return "sea %s" % _play.model.sea_zone_name(zone)


func _named_hulls(fleet: FleetState) -> String:
	if fleet == null:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("")
	print("--- playtest_station_fan: %d steps, %d checks, %d failed ---" % [
		_steps.size(), _checks, _failed,
	])
	quit()
