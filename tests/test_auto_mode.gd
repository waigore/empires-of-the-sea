extends GdToolsTest
## Auto mode (wiki: auto-mode; issue #725): the crown's own seat handed to the
## shared planners, paced by the driver, read-only for the court, never stalled
## on a consent decision, and off again after a load.
##
## One mount for the whole suite: the cases share the fixture chart and re-seat
## it from the pristine save (docs/testing.md speed rules). Cases that need the
## AI to hold the seat arm it and close one turn, which is the boundary the seat
## changes at.

const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null
var world_snapshot: Array = []
var pristine: Dictionary = {}


func before_all() -> void:
	world_snapshot = Fixture.snapshot(Fixture.world())
	screen = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(screen)


func before_each() -> void:
	Fixture.restore(Fixture.world(), world_snapshot)
	Fixture.suite_reset(screen, pristine)
	# Auto is a live-seat state a save never carries (wiki: auto-mode): a re-seat
	# starts with the court in hand, exactly as a load does.
	var play: PlaySession = screen.play
	play.auto_armed = false
	play.auto_active = false
	play.auto_speed = 1
	play.auto_steps.clear()
	play.auto_book = null
	play.auto_log.clear()
	play.ai_stage_faction = MapModel.NO_ID
	MapPlayTurn.view_live = true


func after_all() -> void:
	MapPlayTurn.view_live = true
	if is_instance_valid(screen):
		screen.free()
	screen = null
	pristine = {}


## Hands the seat to the AI the way the player does: arm, then play the turn the
## seat change waits for.
func _seat_the_ai() -> PlaySession:
	var play: PlaySession = screen.play
	MapPlayAuto.arm(play)
	_play_turn(play)
	return play


## Closes one turn the way the player does, answering whatever the court left
## waiting so the fixture's seed never strands a case on a consent prompt.
func _play_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn_suspended and guard < 4:
		guard += 1
		Fixture.settle(play)
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_offer(play, false)
		else:
			return


## Drains the paced turn (the driver's ticks without the clock), so a case can
## read a fully resolved Auto turn.
func _drain(play: PlaySession) -> int:
	var guard: int = 0
	# The first tick presses the turn; the rest spend its staged passes.
	MapPlayAuto.tick(play)
	while play.auto_book != null and guard < 40:
		MapPlayAuto.tick(play)
		guard += 1
	return guard


# --- lifecycle ---------------------------------------------------------------


func test_arming_waits_for_the_turn_to_close() -> void:
	var play: PlaySession = screen.play
	assert_false(play.auto_active, "a campaign starts with the court in hand")
	MapPlayAuto.arm(play)
	assert_true(play.auto_armed, "the seal asks for the seat")
	assert_false(MapPlayAuto.active(play), "arming does not seize the turn in flight")
	_play_turn(play)
	assert_true(play.auto_active, "the AI takes the seat at the turn's close")
	assert_true(MapPlayAuto.blocks_orders(play), "and the court is read-only from then on")


func test_disarming_returns_the_court_at_the_turn_boundary() -> void:
	var play: PlaySession = _seat_the_ai()
	MapPlayAuto.disarm(play)
	assert_true(play.auto_active, "a discharge still serves out the turn in flight")
	assert_false(play.auto_armed, "the seat is already marked for release")
	MapPlayAuto.tick(play)
	_drain(play)
	assert_false(play.auto_active, "the court answers the turn after the discharge")
	assert_true(play.auto_log.has("The court returns to your hand."), "the release is told")


func test_a_load_leaves_auto_off() -> void:
	var play: PlaySession = screen.play
	play.auto_armed = true
	play.auto_active = true
	play.auto_speed = 3
	var data: Dictionary = SaveCodec.capture(play)
	var reopened: MapScreen = Fixture.open_save(self, data)
	assert_false(reopened.play.auto_active, "a load never seats the AI")
	assert_false(reopened.play.auto_armed, "nor arms it")
	assert_eq(reopened.play.auto_speed, 1, "nor carries the pace")
	reopened.free()


# --- pacing ------------------------------------------------------------------


func test_the_speed_seal_cycles_pause_one_two_three() -> void:
	var play: PlaySession = screen.play
	assert_eq(MapPlayAuto.seconds(play), 1.0, "play is one second an action")
	MapPlayAuto.cycle_speed(play)
	assert_eq(MapPlayAuto.seconds(play), 0.5, "2x is half a second")
	MapPlayAuto.cycle_speed(play)
	assert_eq(MapPlayAuto.seconds(play), 0.25, "3x is a quarter")
	MapPlayAuto.cycle_speed(play)
	assert_eq(MapPlayAuto.speed_label(play), "PAUSE", "the cycle ends paused")
	play.auto_active = true
	assert_false(MapPlayAuto.running(play), "a paused seat spends no tick")
	MapPlayAuto.cycle_speed(play)
	assert_true(MapPlayAuto.running(play), "and resumes from the seal")


func test_the_turn_waits_on_the_crowns_own_passes() -> void:
	var play: PlaySession = _seat_the_ai()
	var before: int = play.turn
	MapPlayAuto.tick(play)
	assert_eq(play.turn, before, "one tick stages the seat; it does not resolve the turn")
	assert_not_null(play.auto_book, "the turn book is held open for the driver")
	assert_eq(play.auto_steps.size(), MapPlayAuto.STEPS.size(), "every seat pass is owed")
	_drain(play)
	assert_eq(play.turn, before + 1, "the turn resolves once the queue drains")
	assert_null(play.auto_book, "and nothing is left open")


func test_the_seat_runs_the_rivals_planner_surface() -> void:
	var play: PlaySession = screen.play
	play.auto_active = true
	play.ai_stage_faction = play.player_faction
	assert_eq(
		MapPlayCourt.planning_factions(play), [play.player_faction],
		"a staged pass plans the crown alone"
	)
	play.ai_stage_faction = MapModel.NO_ID
	assert_false(
		MapPlayCourt.planning_factions(play).has(play.player_faction),
		"the rival passes never plan the crown's seat twice"
	)
	# The seat spends the crown's own purse: the planners read one ledger per
	# court, and for the crown that ledger is its real one (REQ-P2-03).
	MapPlayAuto.ensure_seat_ledger(play)
	assert_eq(
		play.ai.economies.get(play.player_faction), play.economy.economy,
		"the seat reads the crown's own ledger, not a shadow copy"
	)


func test_the_crowns_orders_land_and_are_logged() -> void:
	var play: PlaySession = _seat_the_ai()
	_drain(play)
	assert_eq(play.ai_stage_faction, MapModel.NO_ID, "the staged pass clears its court")
	assert_true(
		play.auto_log.has("Crews work the crown's orders."),
		"the seat's own passes report into the log"
	)
	assert_true(
		play.auto_log.size() > MapPlayAuto.STEPS.size(),
		"the log carries the seat's despatches, not only the turn's opening line"
	)


# --- the plaque and its prompt -----------------------------------------------


func test_the_plaque_asks_before_it_hands_the_seat_over() -> void:
	var bar: AutoBar = screen.hud.auto_bar
	var play: PlaySession = screen.play
	assert_not_null(bar, "the plaque mounts with the HUD")
	bar._on_toggle_pressed()
	assert_true(bar._prompt.is_open(), "the plaque asks before it hands the seat over")
	assert_eq(bar._prompt._confirm.text, "ENABLE", "arming says ENABLE")
	bar._prompt._on_cancel()
	assert_false(bar._prompt.is_open(), "cancel closes the plate")
	assert_false(play.auto_armed, "and arms nothing")
	bar._on_toggle_pressed()
	bar._prompt._on_confirm()
	assert_true(play.auto_armed, "the confirm arms the seat")
	bar._on_speed_pressed()
	assert_eq(play.auto_speed, 2, "the pace seal cycles from the plaque")


func test_the_plaque_names_the_seat_state() -> void:
	var bar: AutoBar = screen.hud.auto_bar
	var play: PlaySession = screen.play
	assert_eq(bar._state_text(), "hand the seat to the AI", "the idle plaque offers the seat")
	MapPlayAuto.arm(play)
	assert_eq(bar._state_text(), "arms after this turn", "an armed seat says when")
	play.auto_active = true
	assert_eq(bar._state_text(), "the AI holds your seat", "a held seat says who plays")
	MapPlayAuto.disarm(play)
	assert_eq(bar._state_text(), "ends with this turn", "a discharged seat says when it ends")
	assert_true(bar.is_showing(), "the chrome stays up while the seat changes")


func test_the_driver_holds_the_clock_for_a_prompt_and_a_pause() -> void:
	var bar: AutoBar = screen.hud.auto_bar
	var play: PlaySession = screen.play
	play.auto_active = true
	play.auto_speed = 0
	bar._drive(10.0)
	assert_null(play.auto_book, "a paused seat spends no tick")
	bar._on_toggle_pressed()
	play.auto_speed = 3
	bar._drive(10.0)
	assert_null(play.auto_book, "an open prompt holds the clock")
	bar._prompt._on_cancel()
	bar._drive(10.0)
	assert_not_null(play.auto_book, "and the next tick presses the seat's turn")


# --- read-only while it runs -------------------------------------------------


func test_the_chart_stays_readable_but_raises_no_order() -> void:
	var play: PlaySession = _seat_the_ai()
	var army: ArmyState = _ensure_army(play)
	var marker: ArmyMarker = play.army_layer.marker_for(army)
	assert_not_null(marker, "the fixture seats a marker the chart can open")
	MapPlayInput.on_tapped(play, marker.position)
	assert_eq(play.army_layer.selected_army, army, "a marker still opens its dossier")
	# Far from the marker so the tap is an order attempt, not a re-select.
	var away: Vector2 = marker.position + Vector2(PlaySession.TILE_SIZE * 3, 0)
	MapPlayInput.on_tapped(play, away)
	assert_false(army.moved, "a tap on the chart raises no march")
	play.army_layer.selected_army = null
	var ship: Ship = _ensure_ship(play)
	assert_not_null(ship, "the capital still has a hull")
	play.ship_layer.select(ship)
	MapPlayInput.on_tapped(play, away)
	assert_false(army.moved, "and a sailing tap raises no march either")
	MapPlayInput.on_panel_action(play, "recruit")
	assert_true(MapPlayAuto.blocks_orders(play), "the province sheet is gated too")


func test_the_ledger_and_college_raise_no_order() -> void:
	var play: PlaySession = _seat_the_ai()
	var orders: LedgerOrders = play.economy.orders
	var book: MarketBook = play.economy.market.book
	var before: int = book.orders_for(play.player_faction).size()
	var treasury: int = play.economy.economy.treasury
	assert_true(orders.seat_held_elsewhere(), "Auto holds the ledger")
	assert_eq(orders.trade("grain", 1, true), {}, "a bid is ignored")
	orders.offer("no-court-sells-this", 1)
	orders.withdraw("no-such-order")
	orders.set_production("lumber", 2)
	orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	orders.assign_research("land_enclosure")
	orders.cancel_research(0)
	orders.cycle_research_funding(0)
	assert_eq(book.orders_for(play.player_faction).size(), before, "the book is untouched")
	assert_eq(play.economy.economy.treasury, treasury, "the purse is untouched")
	assert_eq(
		play.economy.economy.production.assignment_units("lumber"), 0, "no run is assigned"
	)


## Court in hand: the ordering gates open so a march tap is attempted (covers
## the `if ordering:` true branch the Auto-on cases leave cold).
func test_the_ordering_gates_open_when_the_court_holds_the_seat() -> void:
	var play: PlaySession = screen.play
	assert_false(MapPlayAuto.blocks_orders(play), "the court still holds the seat")
	var army: ArmyState = _ensure_army(play)
	play.army_layer.select(army)
	var away: Vector2 = play.army_layer.marker_for(army).position + Vector2(
		PlaySession.TILE_SIZE * 3, 0
	)
	MapPlayInput.on_tapped(play, away)
	play.army_layer.selected_army = null
	var ship: Ship = _ensure_ship(play)
	play.ship_layer.select(ship)
	MapPlayInput.on_tapped(play, ship.position)
	assert_eq(play.ship_layer.selected(), ship, "a hull marker still opens its dossier")
	# Off the chart, a held turn, and a decided campaign: the early returns the
	# seat-gate insert shifts into the patch.
	MapPlayInput.on_tapped(play, Vector2(-10000, -10000))
	play.turn_suspended = true
	MapPlayInput.on_panel_action(play, "recruit")
	play.turn_suspended = false
	play.campaign_halted = true
	MapPlayInput.on_panel_action(play, "recruit")
	play.campaign_halted = false
	# Null-host short-circuit on the ledger gates the insert also shifts.
	var bare := LedgerOrders.new(null)
	bare.offer("x", 1)
	bare.assign_research("land_enclosure")


func test_the_court_plays_normally_when_it_holds_the_seat() -> void:
	var play: PlaySession = screen.play
	play.selected_province = play.capital_province
	MapPlayInput.on_panel_action(play, "upgrade_town")
	_tap_crew_then_ground(play)
	var book: Dictionary = play.economy.market.to_dict()
	play.economy.orders.offer("", 1)
	play.economy.orders.withdraw("no-such-order")
	play.economy.orders.set_production("", 0)
	play.economy.orders.worker_action(0, "recruit")
	play.economy.orders.assign_research("")
	play.economy.orders.cancel_research(0)
	play.economy.orders.cycle_research_funding(0)
	play.economy.orders.trade("grain", 1, true)
	assert_ne(play.economy.market.to_dict(), book, "the book takes the court's own order")


func test_every_door_shuts_while_the_ai_holds_the_seat() -> void:
	var play: PlaySession = _seat_the_ai()
	# The province sheet's own orders.
	play.selected_province = play.capital_province
	MapPlayInput.on_panel_action(play, "upgrade_town")
	# The chart's orders, with a crew and an army selected in turn.
	_tap_crew_then_ground(play)
	# The ledger's and the college's intents, one of each.
	var book: Dictionary = play.economy.market.to_dict()
	var research: String = _research_signature(play)
	assert_eq(play.economy.orders.trade("grain", 5, true), {}, "no bid reaches the book")
	play.economy.orders.offer("", 1)
	play.economy.orders.withdraw("no-such-order")
	play.economy.orders.set_production("", 0)
	play.economy.orders.worker_action(0, "recruit")
	play.economy.orders.assign_research("")
	play.economy.orders.cancel_research(0)
	play.economy.orders.cycle_research_funding(0)
	assert_eq(play.economy.market.to_dict(), book, "the book is untouched")
	assert_eq(_research_signature(play), research, "the college is untouched")


# --- no interruptions --------------------------------------------------------


func test_a_waiting_call_to_arms_is_answered_not_held() -> void:
	var play: PlaySession = _seat_the_ai()
	var state: DiplomacyState = play.diplomacy
	var pact: DiplomacyRelation = state.relation(play.player_faction, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_true(CallToArms.has_pending(state, play.player_faction), "the ally calls")
	assert_true(MapPlayAuto.answer_pending(play), "Auto answers it at once")
	assert_false(
		CallToArms.has_pending(state, play.player_faction), "and the ladder is clear"
	)
	assert_true(
		state.relation(play.player_faction, 3).at_war,
		"the alliance is honoured against the aggressor"
	)


func test_a_rival_proposal_is_declined_without_stopping_the_turn() -> void:
	var play: PlaySession = _seat_the_ai()
	play.turn_suspended = true
	_drain(play)
	assert_false(play.turn_suspended, "Auto never leaves the calendar suspended")
	assert_false(
		DiplomacyProposals.has_pending(play.diplomacy, play.player_faction),
		"and no proposal waits behind it"
	)


func test_battles_never_open_a_plate() -> void:
	var play: PlaySession = _seat_the_ai()
	_drain(play)
	assert_false(play.hud.is_quick_battle_shown(), "Auto fights Quick Battles silently")
	assert_true(play.hud.plates.land_queue.is_empty(), "no land plate is queued")
	assert_true(play.hud.plates.sea_queue.is_empty(), "no sea plate is queued")


# --- fixtures ----------------------------------------------------------------


func _own_army(play: PlaySession) -> ArmyState:
	for region: int in play.army_layer.regions.region_ids():
		for raw: Variant in play.army_layer.regions.value(region, []):
			var army: ArmyState = raw
			if army != null and army.owner == play.player_faction:
				return army
	return null


## Seats a crown army on the capital when the fixture chart has none yet.
func _ensure_army(play: PlaySession) -> ArmyState:
	var army: ArmyState = _own_army(play)
	if army != null:
		return army
	var capital: int = play.capital_province
	army = ArmyState.muster(99, play.player_faction, capital, false, ["pikemen"], 990)
	play.army_layer.armies.append(army)
	play.army_layer.add_marker(army)
	return army


## Seats a crown hull when the fixture chart has none yet, so a sailing tap can
## hit the Auto gate rather than the empty-selection path.
func _ensure_ship(play: PlaySession) -> Ship:
	var capital: int = play.capital_province
	var fleet: FleetState = play.ship_layer.home_fleet(capital)
	if fleet == null:
		fleet = FleetState.in_port(90, play.player_faction, capital, ["ship_90"], {})
		play.ship_layer.fleets.append(fleet)
		play.ship_layer.rebuild_markers()
	return play.ship_layer.ship_for(fleet)


## Selects an own crew, then taps bare ground: both the crew's work order and
## the army's march order are asked for and refused by the gate.
func _tap_crew_then_ground(play: PlaySession) -> void:
	var unit: CivilianState = _own_civilian(play)
	if unit == null:
		return
	var marker: CivilianMarker = play.civilian_layer.marker_for(unit)
	if marker != null:
		MapPlayInput.on_tapped(play, marker.position)
	var army: ArmyState = _own_army(play)
	var province: ProvinceState = (
		play.model.province_data(army.province) if army != null
		else play.model.province_data(play.capital_province)
	)
	if province == null or province.tiles.is_empty():
		return
	var tile: Vector2i = province.tiles[0]
	MapPlayInput.on_tapped(play, MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE))


## One crew of the crown's, standing in the region on screen.
func _own_civilian(play: PlaySession) -> CivilianState:
	for raw: Variant in play.civilian_layer.units:
		var unit: CivilianState = raw
		if unit != null and unit.owner == play.player_faction:
			return unit
	return null


## What the college would say it is studying, so a refused intent can be told
## from one that landed.
func _research_signature(play: PlaySession) -> String:
	if play.economy == null or play.economy.economy == null:
		return ""
	var research: ResearchState = play.economy.economy.research
	var parts := PackedStringArray()
	for slot: int in research.slot_count():
		parts.append("%s/%s" % [research.tech_at(slot), research.funding_at(slot)])
	return "|".join(parts)


## A land tile of the army's own province, so a refused order is refused by the
## gate and not by the map.
func _land_tile(model: MapModel, army: ArmyState) -> Vector2i:
	var province: ProvinceState = model.province_data(army.province)
	if province != null and not province.tiles.is_empty():
		return province.tiles[0]
	return Vector2i(1, 1)
