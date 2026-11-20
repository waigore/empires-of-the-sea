extends GdToolsTest
## Auto mode (wiki: auto-mode; issue #725): the crown's own seat handed to the
## shared planners, paced by the driver, read-only for the court, never stalled
## on a consent decision, and off again after a load.
##
## One mount, one seat and one drained paced turn for the whole suite: under
## coverage a mount + arm + end-turn is ~1.2 s and a drained Auto turn ~1 s more,
## so cases that only need the AI holding the seat (or the log that turn wrote)
## re-seat from those captures (~0.2 s) instead of re-planning (docs/testing.md
## speed rules; `test_ai_observer` is the reference). Mode / arming cases still
## start with the court in hand. Auto fields are live-seat state a save never
## carries, so each re-seat re-applies them beside the SaveCodec snapshot.
## Live cases reach the chart through `screen` / `_seat*()`; a case that asks
## for the AI or drained capture pays one re-seat, not a pristine seat first
## (docs/testing.md § Speed rules).

const Fixture = preload("res://tests/map_fixture.gd")

## Non-underscore: gd-tools clones a fresh suite instance per test and does not
## copy underscore fields out of before_all (docs/testing.md speed rules).
var mounted: MapScreen = null
var world_snapshot: Array = []
var pristine: Dictionary = {}
var seated: Dictionary = {}
var seated_auto: Dictionary = {}
var seated_ai: Dictionary = {}
var drained: Dictionary = {}
var drained_auto: Dictionary = {}
var drained_ai: Dictionary = {}
## Set when this case has paid for a re-seat; cleared in `before_each`.
var _chart_bound: bool = false


func before_all() -> void:
	world_snapshot = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)
	# Arm once and close the turn the seat change waits for: every case that
	# only needs the AI holding the seat re-seats from this capture.
	MapPlayAuto.arm(mounted.play)
	_play_turn(mounted.play)
	seated = Fixture.suite_capture(mounted)
	seated_auto = _capture_auto(mounted.play)
	if mounted.play.ai != null:
		seated_ai = mounted.play.ai.to_dict()
	# Drain one paced Auto turn once: log / orders cases re-seat from here.
	_drain(mounted.play)
	drained = Fixture.suite_capture(mounted)
	drained_auto = _capture_auto(mounted.play)
	if mounted.play.ai != null:
		drained_ai = mounted.play.ai.to_dict()


func before_each() -> void:
	_chart_bound = false


func after_all() -> void:
	MapPlayTurn.view_live = true
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}
	seated = {}
	seated_auto = {}
	seated_ai = {}
	drained = {}
	drained_auto = {}
	drained_ai = {}


## Re-seats the shared chart: court in hand (`0`), AI seated after the arming
## turn (`1`), or after that seat's first drained paced turn (`2`).
func _seat(after: int = 0) -> PlaySession:
	Fixture.restore(Fixture.world(), world_snapshot)
	match after:
		1:
			Fixture.suite_reset(mounted, seated)
			_apply_auto(mounted.play, seated_auto)
			if not seated_ai.is_empty():
				mounted.play.ai = AiState.from_dict(seated_ai.duplicate(true))
		2:
			Fixture.suite_reset(mounted, drained)
			_apply_auto(mounted.play, drained_auto)
			if not drained_ai.is_empty():
				mounted.play.ai = AiState.from_dict(drained_ai.duplicate(true))
		_:
			Fixture.suite_reset(mounted, pristine)
			_clear_auto(mounted.play)
	_chart_bound = true
	MapPlayTurn.view_live = true
	return mounted.play


## Live cases that read the campaign chart; defaults to the court in hand.
var screen: MapScreen:
	get:
		if not _chart_bound:
			_seat(0)
		return mounted


## Hands the seat to the AI the way the player does — from the suite's one
## arming-turn capture, not a fresh end-turn.
func _seat_the_ai() -> PlaySession:
	return _seat(1)


## The AI holds the seat after one drained paced turn (log filled, calendar
## advanced): for cases that used to `_seat_the_ai(); _drain()`.
func _seat_drained() -> PlaySession:
	return _seat(2)


func _capture_auto(play: PlaySession) -> Dictionary:
	return {
		"armed": play.auto_armed,
		"active": play.auto_active,
		"speed": play.auto_speed,
		"steps": play.auto_steps.duplicate(),
		"log": play.auto_log.duplicate(),
		"stage": play.ai_stage_faction,
	}


func _apply_auto(play: PlaySession, data: Dictionary) -> void:
	play.auto_armed = bool(data.get("armed", false))
	play.auto_active = bool(data.get("active", false))
	play.auto_speed = int(data.get("speed", 1))
	play.auto_steps.assign(data.get("steps", []))
	play.auto_book = null
	play.auto_log.assign(data.get("log", []))
	play.ai_stage_faction = int(data.get("stage", MapModel.NO_ID))
	_refresh_auto_chrome()


func _clear_auto(play: PlaySession) -> void:
	play.auto_armed = false
	play.auto_active = false
	play.auto_speed = 1
	play.auto_steps.clear()
	play.auto_book = null
	play.auto_log.clear()
	play.ai_stage_faction = MapModel.NO_ID
	_refresh_auto_chrome()


## The plaque mirrors from a signature of the seat; clear it so a re-seat shows
## the restored armed/active/log state instead of the previous case's chrome.
func _refresh_auto_chrome() -> void:
	if mounted == null or mounted.hud == null or mounted.hud.auto_bar == null:
		return
	mounted.hud.auto_bar._signature = ""
	mounted.hud.auto_bar._mirror()


## Closes one turn the way the player does, answering whatever the court left
## waiting so the fixture's seed never strands a case on a consent prompt.
func _play_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn_suspended and guard < 4:
		guard += 1
		Fixture.settle(play)
		match ConsentLadder.pending_kind(play.diplomacy, play.player_faction):
			ConsentLadder.CALL:
				MapPlayTurn.answer_call(play, false)
			ConsentLadder.INTERVENTION:
				MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
			ConsentLadder.OFFER:
				MapPlayTurn.answer_offer(play, false)
			_:
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
	# The suite already drained one paced turn in before_all; re-seat that
	# capture instead of paying another rival walk under coverage
	# (docs/testing.md § Speed rules).
	play = _seat_drained()
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
	var play: PlaySession = _seat_drained()
	assert_eq(play.ai_stage_faction, MapModel.NO_ID, "the staged pass clears its court")
	assert_true(
		play.auto_log.has("Crews work the crown's orders."),
		"the seat's own passes report into the log"
	)
	assert_true(
		play.auto_log.size() > MapPlayAuto.STEPS.size(),
		"the log carries the seat's despatches, not only the turn's opening line"
	)


# --- the action log ----------------------------------------------------------


## The plate prints the newest lines only; the rest of a busy turn is what the
## LOG seal opens (REQ-P5-05).
func test_the_plate_prints_the_newest_lines_and_holds_the_rest_back() -> void:
	var play: PlaySession = _seat_drained()
	var plate: AutoLogPlate = screen.hud.auto_bar._log
	assert_not_null(plate, "the log plate mounts with the seat's chrome")
	# A busy turn raises more orders than the plate has room for.
	while play.auto_log.size() <= plate.visible_lines():
		MapPlayAuto.note(play, "Sorties — Mar Tirreno")
	var bar: AutoBar = screen.hud.auto_bar
	bar._signature = ""
	bar._mirror()
	assert_eq(
		_printed(plate), plate.visible_lines(), "the plate prints its own count and no more"
	)
	assert_eq(
		plate.held_back(),
		play.auto_log.size() - plate.visible_lines(),
		"the seal's count is exactly what the plate held back"
	)
	var foot: Label = plate._box.get_child(plate._box.get_child_count() - 1) as Label
	assert_eq(foot.text, String(play.auto_log.back()), "the plate's foot is the newest line")


## The sheet is the whole kept log, oldest first, so the turn's first orders are
## read after the plate has moved on.
func test_the_log_sheet_prints_every_kept_line_oldest_first() -> void:
	var play: PlaySession = _seat_drained()
	var plate: AutoLogPlate = screen.hud.auto_bar._log
	plate.open_sheet()
	var sheet: AutoLogSheet = plate.sheet
	assert_true(sheet.is_open(), "the plate's seal opens the whole log")
	var rows: Array[String] = _sheet_rows(sheet)
	assert_eq(rows.size(), play.auto_log.size(), "every kept line is on the sheet")
	assert_true(
		rows[0].ends_with(String(play.auto_log[0])), "the oldest line leads the sheet"
	)
	assert_true(
		rows[rows.size() - 1].ends_with(String(play.auto_log[play.auto_log.size() - 1])),
		"the newest line is at the foot"
	)


## A log that grew under the reader would move the lines they opened it to read,
## so the sheet holds the clock the way a confirmation does (wiki: auto-mode
## § Pacing).
func test_the_log_sheet_holds_the_clock_while_it_is_open() -> void:
	var play: PlaySession = _seat_the_ai()
	var bar: AutoBar = screen.hud.auto_bar
	play.auto_speed = 3
	bar._on_log_pressed()
	assert_true(bar._log.sheet_open(), "the LOG seal opens the whole log")
	bar._drive(10.0)
	assert_null(play.auto_book, "a held clock spends no tick")
	bar._log.sheet.close()
	bar._drive(10.0)
	assert_not_null(play.auto_book, "the seat resumes its turn when the sheet closes")


## The seal is offered exactly when there is something behind it, and its caption
## names how many lines the plate does not print.
func test_the_log_seal_names_what_the_plate_holds_back() -> void:
	var play: PlaySession = _seat_drained()
	var bar: AutoBar = screen.hud.auto_bar
	while play.auto_log.size() <= bar._log.visible_lines():
		MapPlayAuto.note(play, "Sorties — Mar Tirreno")
	bar._signature = ""
	bar._mirror()
	assert_true(bar._log_seal.visible, "the seat's chrome offers the log door")
	assert_eq(
		bar._log_caption.text,
		"LOG +%d" % bar._log.held_back(),
		"the caption counts the lines the plate holds back"
	)


func test_a_quiet_seat_offers_no_log_door() -> void:
	var bar: AutoBar = screen.hud.auto_bar
	bar._signature = ""
	bar._mirror()
	assert_false(bar._log_seal.visible, "no news, no log door")
	assert_false(bar._log.sheet_open(), "and nothing opens")


## Labels the plate actually prints (the box holds nothing else).
func _printed(plate: AutoLogPlate) -> int:
	var shown: int = 0
	for child: Node in plate._box.get_children():
		if child is Label:
			shown += 1
	return shown


## The sheet's rows in print order, without the empty notice it keeps.
func _sheet_rows(sheet: AutoLogSheet) -> Array[String]:
	var rows: Array[String] = []
	for child: Node in sheet._rows.get_children():
		if child is Label and child != sheet._empty:
			rows.append((child as Label).text)
	return rows


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
	# A drained Auto seat already answered whatever the fixture left waiting;
	# re-seat that capture instead of draining again under coverage
	# (docs/testing.md § Speed rules).
	var play: PlaySession = _seat_drained()
	assert_false(play.turn_suspended, "Auto never leaves the calendar suspended")
	assert_false(
		DiplomacyProposals.has_pending(play.diplomacy, play.player_faction),
		"and no proposal waits behind it"
	)


func test_battles_never_open_a_plate() -> void:
	var play: PlaySession = _seat_the_ai()
	# Seat a real clash on land and at sea so the Auto gate is walked, not only
	# asserted against an empty battle pass (wiki: auto-mode § No interruptions).
	var rival: int = 2
	var province: int = Fixture.foreign_province(play.model)
	assert_true(province >= 0, "the fixture seats a foreign province")
	play.model.province_data(province).owner = rival
	play.model.province_data(province).fort_level = 0
	DiplomacyRules.declare_war(play.diplomacy, play.player_faction, rival)
	play.army_layer.armies.clear()
	var holding: ArmyState = ArmyState.muster(
		1, rival, province, false, ["guards", "guards"], 1
	)
	var field: ArmyState = ArmyState.muster(
		2, play.player_faction, province, false,
		["guards", "guards", "guards", "guards", "guards", "guards", "guards", "guards"],
		100
	)
	field.moved = true
	play.army_layer.armies.append(holding)
	play.army_layer.armies.append(field)
	play.army_layer._rebuild_markers()
	var land: Array[Dictionary] = MapPlayLandTurn.resolve(play)
	assert_false(land.is_empty(), "the crown fights on land under Auto")
	assert_false(play.hud.is_quick_battle_shown(), "Auto fights Quick Battles silently")
	assert_true(play.hud.plates.land_queue.is_empty(), "no land plate is queued")

	var zone: int = int(play.model.sea_zones[0].id)
	# Dock every standing squadron so only the minted pair shares the water.
	for fleet: FleetState in play.ship_layer.fleets:
		fleet.location = FleetState.Location.IN_PORT
		fleet.province = int(play.model.provinces[0].id)
	var player_fleet: FleetState = FleetState.at_sea(
		901, play.player_faction, zone, ["hull_player"], {"hull_player": "carrack"}
	)
	player_fleet.moved = true
	var enemy_fleet: FleetState = FleetState.at_sea(
		902, rival, zone, ["hull_enemy"], {"hull_enemy": "fluyte"}
	)
	play.ship_layer.fleets.append(player_fleet)
	play.ship_layer.fleets.append(enemy_fleet)
	play.ship_layer.regions.set_region(play.model.region_id, play.ship_layer.fleets)
	play.ship_layer.rebuild_markers()
	var sea: Array[Dictionary] = MapPlayNavalTurn.resolve(play)
	assert_false(sea.is_empty(), "the crown fights at sea under Auto")
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
