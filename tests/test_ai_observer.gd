extends GdToolsTest
## Full-AI observer (wiki: game-setup § Human/AI slot assignment, an empty human
## slot set is the full-AI observer; turn-trace-interpretation): every crown on
## the shared AI planners, the one court reader they all ask, the merged
## per-turn record, the dashboard's snapshot contract, and the feed/card
## collaborators (merged from test_observer_parts — one Godot boot).

const Fixture = preload("res://tests/map_fixture.gd")
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")

## One mount and one resolved turn for the whole suite: under coverage a mount
## costs ~0.5 s and a turn that plans six crowns ~1.5 s, so the cases share the
## chart and re-seat from the turn-1 save (~0.2 s) instead of mounting and
## re-planning again (docs/testing.md speed rules). Cases that prove a *mode*
## changing what the turn plans ask for the top of turn 1 (`_seat(0)`).
## Pure AiTurnLog / dashboard-chrome cases never touch `_screen`, so they skip
## the re-seat (docs/testing.md § Speed rules; same lazy pattern as map_screen).
##
## Non-underscore: gd-tools clones a fresh suite instance per test and does not
## copy underscore fields out of before_all (docs/testing.md speed rules).
var world_snapshot: Array = []
var mounted: MapScreen = null
var pristine: Dictionary = {}
var turn_one: Dictionary = {}
var turn_one_ai: Dictionary = {}
var turn_one_log: Array = []
## Set when this case has paid for a re-seat; cleared in `before_each`.
var _chart_bound: bool = false


func before_all() -> void:
	world_snapshot = Fixture.snapshot(Fixture.world())
	mounted = _mount()
	pristine = Fixture.suite_capture(mounted)
	# The first turn is resolved once: every case that reads a court's ledger,
	# plan or merged record reads the state this turn actually wrote.
	MapPlayTurn.end_turn(mounted.play)
	turn_one = Fixture.suite_capture(mounted)
	if mounted.play.ai != null:
		turn_one_ai = mounted.play.ai.to_dict()
	turn_one_log = mounted.play.ai_turns.duplicate(true)


func before_each() -> void:
	_chart_bound = false


func after_all() -> void:
	MapPlayTurn.view_live = true
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}
	turn_one = {}
	turn_one_ai = {}
	turn_one_log = []


func _mount() -> MapScreen:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = Fixture.WORLD_WIDTH
	screen.map_height = Fixture.WORLD_HEIGHT
	screen.preset_world = Fixture.world()
	screen.observer_mode = true
	screen.infinite_mode = true
	add_child(screen)
	return screen


## Re-seats the shared chart at the top of turn 1 (`after_turns = 0`) or just
## after its first resolved turn (the default), then hands the case back the
## turn log that turn wrote. Live cases reach it through `_screen` / `_seat()`;
## pure cases that never ask never pay `suite_reset`.
func _seat(after_turns: int = 1) -> void:
	Fixture.restore(Fixture.world(), world_snapshot)
	Fixture.suite_reset(mounted, pristine if after_turns == 0 else turn_one)
	_chart_bound = true
	if after_turns == 0:
		MapPlayTurn.view_live = true
		return
	mounted.play.ai = AiState.from_dict(turn_one_ai.duplicate(true))
	mounted.play.ai_turns.assign(turn_one_log.duplicate(true))
	MapPlayTurn.view_live = true


## Live cases that read the observatory chart; defaults to the turn-1 capture.
var _screen: MapScreen:
	get:
		if not _chart_bound:
			_seat(1)
		return mounted


func _step(turns: int = 1) -> void:
	for _turn in turns:
		MapPlayTurn.end_turn(_screen.play)


func test_observer_gives_every_great_power_an_ai_ledger() -> void:
	var play: PlaySession = _screen.play
	assert_true(play.observer_mode, "the session is an all-AI observer")
	assert_eq(play.diplomacy.human_faction, MapModel.NO_ID, "no court holds consent")
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(
			play.ai.economies.has(faction),
			"%s keeps an AI ledger" % FactionCatalog.name_of(faction)
		)


## The map screen hands its menu to the session, so the ledgers reach the seal
## through the narrow session surface, and the observer seals it for the run
## (the door case rides this suite's observer mount; a second observer mount in
## `test_panel_parts_rules` cost ~15 s under coverage for the same asserts).
func test_the_screen_binds_the_door_and_the_observer_seals_it() -> void:
	var screen: MapScreen = _screen
	assert_true(screen.play.pause_menu == screen.game_menu, "the session names its pause menu")
	var seal: Button = screen.hud.top_row.find_child("MenuSeal", true, false) as Button
	assert_not_null(seal, "the MENU seal is mounted on the bar")
	if seal == null:
		return
	assert_false(seal.visible, "the observer owns no pause door")
	assert_true(screen.game_menu.door.is_sealed(), "the door stays sealed for the run")
	# The card is built on this screen all turn and closes on every back press:
	# that close must never hand the observer's chrome back.
	screen.improvements.close()
	assert_false(seal.visible, "a stray close leaves the observer's door sealed")


func test_observer_resolves_a_turn_for_every_crown() -> void:
	var play: PlaySession = _screen.play
	var before: int = play.turn
	_step(1)
	assert_eq(play.turn, before + 1, "the calendar advances")
	assert_eq(play.ai_turns.size(), 2, "one merged record per resolved turn")
	var factions: Dictionary = play.ai_turns[0]["factions"]
	assert_eq(factions.size(), FactionCatalog.great_power_ids().size())
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(factions.has(faction), "record names every crown")
		assert_true(factions[faction].has("actions"))
		assert_true(factions[faction].has("events"))


func test_observer_never_queues_a_human_decision() -> void:
	# The turn that resolved in `before_all` is a real observer turn: had the
	# pass queued a consent, an intervention or a proposal, it would still wait
	# on the freshly seated session.
	var play: PlaySession = _screen.play
	assert_true(play.diplomacy.pending_calls.is_empty(), "no call to arms waits")
	assert_true(play.diplomacy.pending_interventions.is_empty(), "no intervention waits")
	assert_true(play.diplomacy.pending_offers.is_empty(), "no proposal waits")
	assert_false(play.turn_suspended, "the observer never suspends the calendar")
	# The court helpers are inert in an observer session (no hidden HUD work).
	MapPlayDiplomacy.open(play)
	MapPlayDiplomacy.refresh(play)
	assert_false(_screen.hud.panels.is_diplomacy_open(), "the court never opens")


func test_headless_run_keeps_the_rules_and_drops_the_view() -> void:
	# `MapPlayTurn.view_live = false` is the batch harness (docs/ai-observer.md §
	# Performance budget): same rules, no per-turn view follow-up. Two turns are
	# enough to prove the calendar and the merged record keep growing without a
	# view; five turns used to burn ~9 s under coverage for the same asserts.
	# Seat first: a lazy `_screen` re-seat restores `view_live = true`.
	var play: PlaySession = _screen.play
	MapPlayTurn.view_live = false
	assert_false(MapPlayTurn.view_live, "the turn knows no view is followed")
	var before: int = play.turn
	_step(2)
	assert_eq(play.turn, before + 2, "the calendar still advances")
	assert_eq(play.ai_turns.size(), 3, "every turn still records")
	# Same rules as an on-screen observer: every crown still holds a ledger.
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(
			play.ai.economies.has(faction),
			"%s still plans without a view" % FactionCatalog.name_of(faction)
		)


func test_snapshot_ranks_every_crown_and_exposes_the_metrics() -> void:
	var play: PlaySession = _screen.play
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	var rows: Array = snapshot["rows"]
	assert_eq(rows.size(), FactionCatalog.great_power_ids().size())
	var keys: Array[String] = [
		"faction", "name", "leader", "agenda", "phase", "posture",
		"goal", "intent", "reserve", "plans",
		"provinces_old", "provinces_new",
		"power", "regiments", "ships", "civilians", "treasury", "stock",
		"workers", "wars", "progress", "rank", "alive", "headline",
		"pressure", "pressure_stage", "pressure_need", "pressure_regiments",
	]
	for index in rows.size():
		var row: Dictionary = rows[index]
		assert_eq(int(row["rank"]), index + 1, "rows arrive already ranked")
		for key: String in keys:
			assert_true(row.has(key), "row exposes %s" % key)
		assert_true(
			[AiIncome.GOAL_EARN, AiIncome.GOAL_SPEND].has(String(row["goal"])),
			"the row prints the court's money goal (DR-20261113-19)"
		)
		assert_eq(String(row["intent"]), AiIncome.label(String(row["goal"])))
		if index > 0:
			assert_true(
				int(rows[index - 1]["provinces_old"]) >= int(row["provinces_old"]),
				"the standing sorts by Old World provinces"
			)
	var record: Dictionary = rows[0]
	assert_almost_eq(
		float(record["progress"]),
		float(int(record["provinces_old"])) / float(VictoryRules.MILITARY_THRESHOLD),
		0.0001
	)
	assert_ne(JSON.stringify(snapshot), "", "the snapshot is JSON-safe")


func test_market_reading_names_the_book_food_against_every_courts_ration() -> void:
	# Issue #766 clause 3: the book's food supply against the courts' demand is a
	# reading on the turn trace, so the acceptance never needs a throwaway probe.
	var play: PlaySession = _screen.play
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	var market: Dictionary = snapshot["market"] as Dictionary
	var offered: int = 0
	for offer: Dictionary in play.economy.market.minor_offers:
		if CommodityCatalog.is_food(String(offer["commodity"])):
			offered += int(offer["quantity"])
	var demand: int = 0
	for raw: Dictionary in (snapshot["rows"] as Array):
		demand += int((raw["larder"] as Dictionary)["wanted"])
	assert_gt(demand, 0, "a resolved turn's courts all eat")
	assert_eq(
		int(market["minor_food"]), offered,
		"minor_food is the food tonnage the book offers, not every offer row"
	)
	assert_eq(
		int(market["ration_demand"]), demand,
		"ration_demand sums every court's larder"
	)
	assert_eq(
		int(market["food_gap"]), maxi(demand - offered, 0),
		"food_gap is the book's food against the courts' demand"
	)
	assert_true(market.has("minor_offers"), "the offer-row count still prints")


## The deed gate's own readings ride the trace: the purchased tiles each court
## holds and the deals the last clearing settled through first right of refusal,
## so a run that never signs a deed or never fills one through the privilege
## says so on the turn line instead of needing a throwaway probe (issue #841).
func test_the_trace_reads_deeds_and_first_right_fills() -> void:
	var play: PlaySession = _screen.play
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	var market: Dictionary = snapshot["market"] as Dictionary
	assert_true(market.has("frr_fills"), "the clearing's first-right fills print")
	var frr: int = 0
	for deal: Dictionary in play.economy.market.book.last_deals:
		if bool(deal.get("is_frr", false)):
			frr += 1
	assert_eq(int(market["frr_fills"]), frr, "frr_fills counts the Deal Book's own rows")
	for raw: Dictionary in (snapshot["rows"] as Array):
		assert_true(raw.has("deeds"), "every court row prints its deeds")
		assert_eq(
			int(raw["deeds"]),
			MapPlayObserver.deeds_held(play, int(raw["faction"])),
			"the row's deed count is the court's purchased land"
		)
	# A deed signed on the chart is the count the row reads.
	var model: MapModel = play.world.region(WorldMap.OLD_WORLD)
	var province: ProvinceState = model.provinces[0]
	var buyer: int = int(snapshot["rows"][0]["faction"])
	var before: int = MapPlayObserver.deeds_held(play, buyer)
	model.purchase_tile(province.tiles[0], buyer)
	assert_eq(
		MapPlayObserver.deeds_held(play, buyer), before + 1,
		"a signed deed is one more purchased tile"
	)


func test_observer_former_crown_plays_through_the_planners() -> void:
	var play: PlaySession = _screen.play
	var economy: PlayerEconomy = play.ai.economy_for(play.player_faction)
	assert_true(
		economy.production.assignments().size() > 0,
		"the former human crown sets production like a rival"
	)
	var record: Dictionary = play.ai_turns[0]["factions"][play.player_faction]
	assert_true(
		int(record["actions"].get("production", 0)) > 0,
		"the merged trace records that order"
	)


func test_noop_mode_issues_no_planner_orders() -> void:
	# Noop is proved from the top of turn 1: a court that never planned keeps an
	# empty roster and an empty workshop.
	_seat(0)
	var play: PlaySession = _screen.play
	play.ai_mode = AiControl.NOOP
	assert_false(AiControl.plans(play, play.player_faction), "noop crowns do not plan")
	_step(1)
	var economy: PlayerEconomy = play.ai.economy_for(play.player_faction)
	assert_eq(
		economy.production.assignments().size(), 0,
		"a noop crown never opens a workshop run"
	)
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	assert_eq(String(snapshot["ai_mode"]), AiControl.NOOP)
	for row: Dictionary in snapshot["rows"]:
		assert_false(bool(row["plans"]), "every crown is inert under noop")


func test_bench_mode_assigns_subject_baseline_and_random() -> void:
	_seat(0)
	var play: PlaySession = _screen.play
	var live: int = play.player_faction
	play.ai_mode = AiControl.BENCH
	play.ai_live_faction = live
	assert_true(AiControl.plans(play, live), "the subject plans")
	assert_eq(AiControl.court_kind(play, live), AiControl.KIND_SUBJECT)
	var baselines: Array[int] = AiControl.baseline_factions(play)
	assert_eq(baselines.size(), 2, "two baseline rivals")
	for faction: int in baselines:
		assert_eq(AiControl.court_kind(play, faction), AiControl.KIND_BASELINE)
		assert_true(AiControl.plans(play, faction), "baselines plan")
	var randoms: int = 0
	for faction: int in FactionCatalog.great_power_ids():
		if AiControl.court_kind(play, faction) == AiControl.KIND_RANDOM:
			randoms += 1
			assert_true(AiControl.plans(play, faction), "random courts act")
	assert_eq(randoms, 3, "three random fillers")
	_step(1)
	var live_economy: PlayerEconomy = play.ai.economy_for(live)
	assert_true(
		live_economy.production.assignments().size() > 0,
		"the subject still sets production"
	)
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	assert_eq(String(snapshot["ai_mode"]), AiControl.BENCH)
	assert_eq(int(snapshot["ai_live"]), live)
	for row: Dictionary in snapshot["rows"]:
		assert_false(String(row.get("court_kind", "")).is_empty(), "row names court_kind")


func test_ai_control_parse_accepts_known_modes() -> void:
	assert_eq(AiControl.parse("FULL"), AiControl.FULL)
	assert_eq(AiControl.parse("noop"), AiControl.NOOP)
	assert_eq(AiControl.parse("bench"), AiControl.BENCH)
	assert_eq(AiControl.parse("mystery"), AiControl.FULL)


func test_observer_keeps_the_calendar_open_past_the_cap() -> void:
	var play: PlaySession = _screen.play
	play.turn = TurnTime.cap_turn()
	MapPlayTurn.end_turn(play)
	assert_false(play.campaign_halted, "only a whole-game observer runs past the cap")
	assert_eq(play.turn, TurnTime.cap_turn() + 1)


func test_decided_observer_campaign_refuses_another_turn() -> void:
	var play: PlaySession = _screen.play
	play.victory = VictoryState.military(FactionCatalog.PLAYER_FACTION, play.turn)
	var before: int = play.turn
	MapPlayTurn.end_turn(play)
	assert_eq(play.turn, before, "a decided campaign takes no further turn")
	assert_eq(play.victory.winner_player_id, FactionCatalog.PLAYER_FACTION)
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	assert_eq(int(snapshot["winner"]), FactionCatalog.PLAYER_FACTION)
	assert_true(String(snapshot["result"]).contains("military victory"))


func test_snapshot_reports_the_calendar_standing() -> void:
	var play: PlaySession = _screen.play
	play.campaign_halted = true
	var snapshot: Dictionary = MapPlayObserver.snapshot(play)
	assert_true(snapshot["campaign_over"], "a halted campaign reads as over")
	assert_true(String(snapshot["result"]).contains("age"), "the standing names the age")


func test_headline_handles_an_empty_record() -> void:
	assert_eq(AiTurnLog.headline({}), "no resolved turn yet")
	assert_eq(AiTurnLog.headline({"actions": {}}), "held station, no orders")


# --- the turn trace's recorders (REQ-P3-01) ---
## Each pass that hands a report in owns its rows: the diplomacy recorder reads
## the pass's own trace, the economy recorder the economy report, and AiTurnLog
## keeps the merged record, its one event cap and the headline.


## A bare session: the recorders need only the turn, the domestic trace and the
## merged list, so these cases skip a mounted chart.
func _trace_session() -> PlaySession:
	var play := PlaySession.new()
	play.turn = 12
	return play


func _diplomacy_row(faction: int, kind: String, target: int) -> Dictionary:
	return {"faction": faction, "action": {"kind": kind, "target": target}}


func test_the_trace_counts_every_diplomacy_kind_under_its_key() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	play.ai_trace = [
		_diplomacy_row(crown, AiDiplomacyPlanner.KIND_DECLARE_WAR, rival),
		_diplomacy_row(crown, AiDiplomacyPlanner.KIND_OFFER_PEACE, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_ALLIANCE, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_OVERTURE, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_BREAK, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_FTP, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_REVOKE_FTP, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_BOYCOTT, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_REVOKE_BOYCOTT, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_AID, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_SUBSIDY, rival),
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_CANCEL_SUBSIDY, rival),
	]
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	var actions: Dictionary = merged["factions"][crown]["actions"]
	assert_eq(int(actions.get("war", 0)), 1, "a declaration keeps the war row")
	assert_eq(int(actions.get("peace", 0)), 1, "a peace offer keeps its own row")
	assert_eq(int(actions.get("treaty", 0)), 3, "alliance, overture and a broken alliance read as treaty")
	assert_eq(int(actions.get("trade", 0)), 7, "the pact, boycott, aid and subsidy family read as trade")
	var events: Array = merged["factions"][crown]["events"]
	assert_eq(events.size(), 12, "every accepted order prints one sentence")
	assert_eq(
		String(events[0]),
		"%s declares war on %s." % [
			FactionCatalog.name_of(crown), FactionCatalog.name_of(rival),
		],
		"the declaration prints its own line"
	)


func test_the_trace_prints_the_pass_message_or_its_own_diplomacy_line() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	play.ai_trace = [
		{
			"faction": crown,
			"action": {"kind": AiDiplomacyOffers.KIND_AID, "target": rival},
			"message": "Aid reaches the court.",
		},
		_diplomacy_row(crown, AiDiplomacyOffers.KIND_SUBSIDY, MapModel.NO_ID),
		_diplomacy_row(crown, "mystery", rival),
	]
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	var events: Array = merged["factions"][crown]["events"]
	assert_eq(String(events[0]), "Aid reaches the court.", "the pass's own sentence wins")
	assert_eq(
		String(events[1]),
		"%s adjusts its court." % FactionCatalog.name_of(crown),
		"an order with no target names no court"
	)
	assert_eq(
		String(events[2]),
		"%s proposes a treaty to %s." % [
			FactionCatalog.name_of(crown), FactionCatalog.name_of(rival),
		],
		"an unfamiliar kind still reads as a treaty"
	)


func test_the_trace_drops_a_refused_order_and_a_foreign_court() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	var minor: int = FactionCatalog.minor_ids()[0]
	play.ai_trace = [
		{
			"faction": crown,
			"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": rival},
			"result": {"ok": false},
		},
		_diplomacy_row(minor, AiDiplomacyOffers.KIND_AID, crown),
		{"faction": crown, "action": {}},
		{
			"faction": crown,
			"action": {"kind": AiDiplomacyOffers.KIND_FTP, "target": rival},
			"result": {"ok": true},
		},
	]
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	var actions: Dictionary = merged["factions"][crown]["actions"]
	assert_eq(int(actions.get("war", 0)), 0, "a refused declaration never happened")
	assert_eq(int(actions.get("trade", 0)), 1, "the accepted pact still counts")
	assert_eq((merged["factions"][crown]["events"] as Array).size(), 1, "only the accepted order prints")
	assert_false(merged["factions"].has(minor), "a minor nation has no trace bucket")


func test_the_trace_reads_every_economy_row_the_pass_handed() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var report: Dictionary = {"factions": {crown: {
		"production": {"assignments": [{"workshop": 1}]},
		"recruits": [{"trade": "peasant"}],
		"civilians": {
			"orders": [{"workshop": 1}, {"workshop": 2}],
			"training": [{"trade": "peasant"}],
		},
		"cargo": {
			"routes": [{"colony": 1}],
			"launch": {"type_id": "fluyte"},
			"warship": {"type_id": "frigate", "price": 120, "chest": 300},
		},
		"claims": ["rations 4/6"],
	}}}
	var merged: Dictionary = AiTurnLog.record(play, [], [], report)
	var bucket: Dictionary = merged["factions"][crown]
	var actions: Dictionary = bucket["actions"]
	assert_eq(int(actions.get("production", 0)), 1, "the runs are one production row")
	assert_eq(int(actions.get("recruit", 0)), 1, "one muster is one recruit row")
	assert_eq(int(actions.get("work", 0)), 2, "two work orders count twice")
	assert_eq(int(actions.get("train", 0)), 1, "a mustered civilian is its own row")
	assert_eq(int(actions.get("cargo", 0)), 2, "a route and a merchant launch both count as cargo")
	assert_eq(int(actions.get("build", 0)), 1, "the warship is the yard's build row")
	var who: String = FactionCatalog.name_of(crown)
	var events: Array = bucket["events"]
	assert_eq(events.size(), 7, "every economy row prints one sentence")
	assert_eq(String(events[4]), "%s routes 1 merchant squadron home." % who)
	assert_eq(
		String(events[6]),
		"%s lays down a Frigate for the fleet: 120 ducats against a 300 chest." % who,
		"the yard row names its price and the chest that allowed it"
	)
	assert_eq(bucket["claims"], ["rations 4/6"], "the reservations travel with the record")


func test_the_trace_skips_an_empty_cargo_and_a_foreign_ledger() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var minor: int = FactionCatalog.minor_ids()[0]
	var report: Dictionary = {"factions": {
		crown: {"production": {}, "cargo": {}, "claims": "not a list"},
		minor: {"production": {"assignments": [{"workshop": 1}]}, "recruits": [{}]},
	}}
	var merged: Dictionary = AiTurnLog.record(play, [], [], report)
	var bucket: Dictionary = merged["factions"][crown]
	assert_true((bucket["actions"] as Dictionary).is_empty(), "a quiet ledger counts nothing")
	assert_true((bucket["events"] as Array).is_empty(), "and prints nothing")
	assert_false(bucket.has("claims"), "a claims field that is not a list is dropped")


func test_the_trace_caps_one_crown_events_and_ignores_an_empty_key() -> void:
	var play: PlaySession = _trace_session()
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	var trace: Array[Dictionary] = []
	for step in 70:
		trace.append({
			"faction": crown,
			"action": {"kind": AiDiplomacyOffers.KIND_AID, "target": rival},
			"message": "Aid %d." % step,
		})
	play.ai_trace = trace
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	var bucket: Dictionary = merged["factions"][crown]
	assert_eq((bucket["events"] as Array).size(), 60, "the panel's event cap holds")
	assert_eq((merged["events"] as Array).size(), 60, "the merged list is capped with it")
	var before: int = (bucket["events"] as Array).size()
	AiTurnLog.event(merged, bucket, crown, "")
	assert_eq((bucket["events"] as Array).size(), before, "an empty sentence adds no row")
	var actions: Dictionary = {"aid": 1}
	AiTurnLog.bump(actions, "")
	AiTurnLog.bump(actions, "aid", 2)
	assert_eq(int(actions["aid"]), 3)
	assert_false(actions.has(""), "an empty key adds no row")


func test_the_trace_files_a_siege_after_the_economy_rows() -> void:
	var play: PlaySession = _screen.play
	play.ai_trace = []
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	var province: int = 0
	var battle: Dictionary = {
		"attacker": crown, "defender": rival, "province": province,
		"region": play.region_index, "outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_mauled": 5,
		"siege": {
			"guns_lost": 2, "guns_start": 2, "fort_downgraded": true,
			"fort_before": 2, "fort_after": 1,
		},
	}
	var report: Dictionary = {"factions": {crown: {
		"production": {"assignments": [{"workshop": 1}]},
	}}}
	var merged: Dictionary = AiTurnLog.record(play, [], [], report)
	BattleTrace.record(merged, play, [battle], [])
	var events: Array = merged["factions"][crown]["events"]
	assert_eq(events.size(), 2, "the economy row and the fight both print")
	assert_eq(
		String(events[1]),
		BattleReport.describe_land(
			battle, play.model.province_name(province), FactionCatalog.names()
		),
		"the observer reads the same sentence the live despatch prints"
	)
	assert_true(
		String(events[1]).contains("emplaced guns silenced"),
		"the siege's battery and the fort level it left are named"
	)
	assert_eq(
		String(merged["events"][1]["text"]), String(events[1]),
		"the fight is the newest row, so the panel's feed leads with it"
	)


func test_the_trace_files_a_sea_battle() -> void:
	var play: PlaySession = _screen.play
	play.ai_trace = []
	var crown: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	var battle: Dictionary = {
		"attacker": crown, "defender": rival, "zone": 0,
		"region": play.region_index, "outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"defender_lost": [1], "attacker_lost": [],
	}
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	BattleTrace.record(merged, play, [], [battle])
	var events: Array = merged["factions"][crown]["events"]
	assert_eq(
		String(events[0]),
		BattleReport.describe(
			battle, play.model.sea_zone_name(0), FactionCatalog.names()
		),
		"the sea despatch is the one the court would read"
	)


func test_the_trace_skips_a_battle_whose_attacker_is_no_great_power() -> void:
	var play: PlaySession = _screen.play
	play.ai_trace = []
	var crown: int = FactionCatalog.great_power_ids()[0]
	var minor: int = FactionCatalog.minor_ids()[0]
	var battle: Dictionary = {
		"attacker": minor, "defender": crown, "province": 0,
		"region": play.region_index, "outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
	}
	var merged: Dictionary = AiTurnLog.record(play, [], [], {})
	BattleTrace.record(merged, play, [battle], [])
	assert_true(
		(merged["factions"][crown]["events"] as Array).is_empty(),
		"a minor's fight files no row under the crown it beat"
	)


func test_dashboard_renders_the_live_snapshot() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	panel.refresh()
	assert_true(
		panel.board.turn_label.text.begins_with("TURN"), "the panel names the turn"
	)
	assert_eq(
		panel.board.crowns_by_id.size(), FactionCatalog.great_power_ids().size()
	)
	assert_ne(panel.board.result.text, "", "the panel reports the standing")


## A court that can see the bar is marked on its card (DR-20261114-04): the
## standing reads `pressing` beside the province count, and drops it when the
## court is far from the bar.
func test_the_card_marks_a_court_that_presses_for_the_bar() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	panel.refresh()
	var row: Dictionary = MapPlayObserver.snapshot(_screen.play)["rows"][0].duplicate(true)
	var card: ObserverCrownCard = panel.board.crowns_by_id[int(row["faction"])]
	var progress: Label = card.progress
	row["pressure_stage"] = AiVictoryPressure.STAGE_NEAR
	panel.board.fill_crown(row)
	assert_true(progress.text.ends_with("pressing"), "the endgame court is marked")
	assert_true(
		progress.text.begins_with("%d/%d" % [
			int(row["provinces_old"]), VictoryRules.MILITARY_THRESHOLD,
		]),
		"the standing still leads the line"
	)
	row["pressure_stage"] = AiVictoryPressure.STAGE_FAR
	panel.board.fill_crown(row)
	assert_false(progress.text.ends_with("pressing"), "a court far from the bar is not")


## A busy turn raises more rows than the plate has room for. The feed scrolls
## through the turns it keeps whole instead of printing the newest dozen and
## dropping the rest — the war declared and the first march are the rows a
## watcher most needs (REQ-P5-05).
func test_the_feed_prints_a_busy_turn_whole() -> void:
	var play: PlaySession = _screen.play
	var crown: int = FactionCatalog.great_power_ids()[0]
	var merged: Dictionary = AiTurnLog.record(play, [], [], {"factions": {crown: {}}})
	var bucket: Dictionary = merged["factions"][crown]
	for index in 30:
		AiTurnLog.event(merged, bucket, crown, "Order %d." % index)
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	panel.refresh()
	var rows: int = (merged["events"] as Array).size()
	assert_true(rows > 12, "the turn is busier than the plate's old dozen")
	var lines: PackedStringArray = panel.board.feed.text.split("\n")
	var prefix: String = "T%d  " % int(merged["turn"])
	var printed: int = 0
	for line: String in lines:
		if line.begins_with(prefix):
			printed += 1
	assert_eq(printed, rows, "every row of the turn reaches the feed")
	assert_eq(
		lines[0], "%sOrder 29." % prefix,
		"the newest order still leads the feed"
	)
	assert_true(
		lines.has("%sOrder 0." % prefix),
		"the turn's first order is kept, not cut"
	)
	var kept: int = 0
	for index in range(ObserverTurnFeed.first_kept(play.ai_turns), play.ai_turns.size()):
		kept += (play.ai_turns[index]["events"] as Array).size()
	assert_true(
		panel.board.feed_caption.text.contains("%d rows over" % kept),
		"the caption counts every row the feed holds"
	)


## The dashboard on a landscape handset (360 points tall): its stack is taller
## than the screen, so the plate scrolls and the crown cards keep their room
## instead of being squeezed to nothing (REQ-P1-07, RUB-P1-07).
func test_the_plate_fits_a_landscape_handset() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = Fixture.WORLD_WIDTH
	screen.map_height = Fixture.WORLD_HEIGHT
	screen.preset_world = Fixture.world()
	screen.observer_mode = true
	screen.infinite_mode = true
	viewport.add_child(screen)
	for _frame in 4:
		await get_tree().process_frame
	var panel := screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts on a handset")
	if panel == null:
		screen.free()
		viewport.free()
		return
	panel._fit()
	for _frame in 2:
		await get_tree().process_frame
	assert_true(
		panel.board.crowns_scroll.size.y >= AiObserverPanel.CARD_MIN_HEIGHT - 1.0,
		"the crown cards keep their window on a 360-point-tall screen"
	)
	assert_true(
		panel.board.plate.get_v_scroll_bar().max_value > panel.board.plate.size.y,
		"the plate scrolls when its stack is taller than the screen"
	)
	assert_true(
		panel.board.frame.size.x > 200.0 and panel.board.frame.size.x < 720.0,
		"the plate keeps a readable width"
	)
	screen.free()
	viewport.free()


func test_dashboard_controls_step_pause_and_collapse() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	var play: PlaySession = _screen.play
	panel.running = false
	var before: int = play.turn
	panel.board.step_button.pressed.emit()
	assert_eq(play.turn, before + 1, "Step resolves exactly one turn")
	panel.board.pause_button.pressed.emit()
	assert_true(panel.running, "Resume restarts the loop")
	assert_eq(panel.board.status.text.split("  ·  ")[0], "RUNNING", "the caption follows")
	panel.board.pause_button.pressed.emit()
	assert_false(panel.running, "Pause stops the loop")
	assert_eq(panel.board.status.text.split("  ·  ")[0], "PAUSED", "the caption follows")
	panel.board.speed_button.pressed.emit()
	assert_eq(panel._speed_index, 1, "speed cycles")
	assert_eq(panel.board.speed_button.text, AiObserverPanel.SPEED_LABELS[1], "the seal names it")
	panel.board.tab.pressed.emit()
	assert_false(panel.board.frame.visible, "the panel collapses")
	assert_true(panel.board.tab.visible, "a tab keeps it reachable")
	panel.board.tab.pressed.emit()
	assert_true(panel.board.frame.visible, "the panel returns")
	# The MENU seal pauses the calendar and hands the screen's pause door on.
	panel.board.menu_button.pressed.emit()
	assert_false(panel.running, "the pause menu pauses the run")
	_screen.game_menu.close()


## The plate answers its own handles: an unmounted one guards, a mounted one
## fits a phone width and trades the frame for its tab.
func test_the_dashboard_chrome_answers_its_handles() -> void:
	var dashboard := ObserverDashboard.new()
	assert_null(dashboard.get_parent(), "a new plate stands alone until mounted")
	dashboard.frame = null
	dashboard.fit(Vector2(1280.0, 800.0))
	dashboard._tab_view()
	dashboard = ObserverDashboard.new()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(dashboard)
	assert_not_null(dashboard.frame, "the plate builds its frame")
	dashboard.fit(Vector2(720.0, 360.0))
	assert_true(
		dashboard.frame.custom_minimum_size.x >= 280.0
		and dashboard.frame.custom_minimum_size.x <= 470.0,
		"a phone width keeps the plate readable"
	)
	# The plate owns its column, not the screen: the chart beside it must stay
	# clickable, or the observatory could never read a province it taps
	# (DR-20261117-11).
	assert_true(
		dashboard.plate.size.x < 720.0,
		"the plate leaves the chart its own width"
	)
	assert_true(
		dashboard.plate.get_global_rect().end.x <= dashboard.frame.custom_minimum_size.x + 24.0,
		"the plate stops at its own column"
	)
	var shown: bool = dashboard.frame.visible
	dashboard._toggle_frame()
	assert_ne(dashboard.frame.visible, shown, "HIDE and the tab trade places")
	var kept: Button = dashboard.tab
	dashboard.tab = null
	dashboard._tab_view()
	dashboard.tab = kept
	dashboard.free()
	canvas.free()


## The feed's window follows the screen: a handset keeps its 128-point window, a
## desktop gives the rows more of the plate, and a very tall screen stops at the
## cap so the crown cards keep their room (REQ-P1-07, REQ-P5-05).
func test_the_feed_window_follows_the_screen() -> void:
	var dashboard := ObserverDashboard.new()
	add_child(dashboard)
	dashboard.fit(Vector2(720.0, 360.0))
	assert_eq(
		dashboard.feed_scroll.custom_minimum_size.y, ObserverDashboard.FEED_MIN_HEIGHT,
		"a landscape handset keeps the feed's smallest window"
	)
	dashboard.fit(Vector2(1280.0, 800.0))
	assert_eq(
		dashboard.feed_scroll.custom_minimum_size.y, 240.0,
		"a desktop gives the feed a share of its height"
	)
	dashboard.fit(Vector2(1280.0, 2000.0))
	assert_eq(
		dashboard.feed_scroll.custom_minimum_size.y, ObserverDashboard.FEED_MAX_HEIGHT,
		"a very tall screen stops at the cap"
	)
	dashboard.free()


## The dashboard takes its whole reading from one snapshot, so a decided
## campaign, a fallen court and an idle run all paint through the same door.
func test_the_dashboard_paints_one_snapshot() -> void:
	var dashboard := ObserverDashboard.new()
	add_child(dashboard)
	var rows: Array = [
		{
			"faction": 1, "rank": 1, "name": "Britain", "alive": true,
			"leader": "Anne", "agenda": "trade", "profile": "merchant",
			"posture": "bold", "intent": "press", "headline": "Took Cadiz.",
			"provinces_old": 9, "provinces_new": 1, "power": 30, "regiments": 5,
			"ships": 3, "civilians": 2, "treasury": 700, "stock": 8, "workers": 4,
			"wars": [], "pressure_stage": AiVictoryPressure.STAGE_FAR,
		},
		{
			"faction": 2, "rank": 2, "name": "United Provinces", "alive": false,
			"leader": "Willem", "agenda": "flood", "profile": "banker",
			"posture": "wary", "intent": "hold", "headline": "Fell at Amsterdam.",
			"provinces_old": 2, "provinces_new": 0, "power": 4, "regiments": 1,
			"ships": 0, "civilians": 0, "treasury": 60, "stock": 0, "workers": 0,
			"wars": ["Britain"], "pressure_stage": AiVictoryPressure.STAGE_FAR,
		},
	]
	var snap: Dictionary = {
		"turn": 12, "year": 1705, "seed": 4242, "rows": rows,
		"result": "Britain leads with 9 of 20", "campaign_over": false,
	}
	dashboard.paint(snap, [])
	assert_eq(dashboard.turn_label.text, "TURN 12  ·  1705  ·  SEED 4242")
	assert_true(dashboard.standing.text.begins_with("STANDING"), "the line leads")
	assert_true(
		dashboard.standing.text.contains("2 U. Provinces 2"),
		"a long crown reads its short name"
	)
	assert_eq(dashboard.feed.text, ObserverTurnFeed.EMPTY_TEXT, "no orders yet")
	assert_eq(dashboard.result.text, "Britain leads with 9 of 20")
	dashboard.fill_crown({"faction": 99, "rank": 1})
	dashboard.sync_controls(false, false, "2×")
	assert_eq(dashboard.pause_button.text, "RESUME", "a paused run offers Resume")
	assert_false(dashboard.step_button.disabled, "Step stays open while playing")
	dashboard.sync_controls(true, true, "1×")
	assert_eq(dashboard.status.text, "DECIDED  ·  the calendar has stopped")
	assert_true(dashboard.step_button.disabled, "a decided campaign seals Step")
	dashboard.free()


# --- one court reader --------------------------------------------------------


func test_court_reader_names_the_planning_courts() -> void:
	var play: PlaySession = _screen.play
	var planning: Array[int] = MapPlayCourt.planning_factions(play)
	assert_true(planning.has(play.player_faction), "the observer's former player court plans")
	assert_eq(planning.size(), FactionCatalog.great_power_ids().size(), "every crown plans")
	# The human's own court is never handed to a rival pass.
	play.observer_mode = false
	assert_false(
		MapPlayCourt.planning_factions(play).has(play.player_faction),
		"a human court keeps its own orders"
	)
	play.observer_mode = true
	play.ai_mode = AiControl.NOOP
	assert_true(MapPlayCourt.planning_factions(play).is_empty(), "a noop session plans nowhere")


func test_court_reader_counts_the_order_of_battle() -> void:
	var play: PlaySession = _screen.play
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			MapPlayCourt.regiments(play, faction),
			play.army_layer.regiment_count_all(faction),
			"regiments read the whole order of battle"
		)
		assert_eq(
			MapPlayCourt.ships(play, faction),
			play.ship_layer.hull_count_all(faction),
			"hulls read the whole navy"
		)


## One published pass: the panel, the calendar's declared winner and the
## observer all read the strength and hulls `public_orders` builds, so a new
## regiment moves every published score together (wiki: diplomacy § Great Power
## power score; REQ-P2-03, REQ-P3-02).
func test_court_reader_publishes_one_order_of_battle() -> void:
	_seat(0)
	var play: PlaySession = _screen.play
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var owner: int = crowns[0]
	var before: float = float(
		MapPlayCourt.public_strength(play).get(owner, 0.0)
	)
	var region: int = play.region_index
	var armies: Array[ArmyState] = MapPlayCourt.region_armies(play, region)
	var province: int = int(play.world.region(region).provinces[0].id)
	armies.append(
		ArmyState.muster(9201, owner, province, false, ["knights"])
	)
	play.army_layer.regions.set_region(region, armies)
	var orders: Dictionary = MapPlayCourt.public_orders(play)
	var strength: Dictionary = orders["strength"]
	var ships: Dictionary = orders["ships"]
	assert_almost_eq(
		float(strength.get(owner, 0.0)), before + 6.0, 0.001,
		"a knight adds its FPN + FPM to the published strength"
	)
	for faction: int in crowns:
		assert_eq(
			int(ships.get(faction, 0)), MapPlayCourt.ships(play, faction),
			"the published hulls read the same navy"
		)
	assert_eq(
		int(MapPlayObserver.row(play, owner)["power"]),
		AiPower.score(
			play.world,
			owner,
			int(roundf(float(strength.get(owner, 0.0)))),
			int(ships.get(owner, 0))
		),
		"the observer prints the published score, not its own arithmetic"
	)


## The observer row names the larder the next Consumption phase will eat — the
## store, every mouth the phase feeds and the shortfall that strikes — so the
## destitute-court signature is measured from a turn trace instead of a
## throwaway probe (issues #676 clause 4, #766).
func test_court_reader_names_the_larder_the_next_consumption_eats() -> void:
	_seat(1)
	var play: PlaySession = _screen.play
	var owner: int = FactionCatalog.great_power_ids()[0]
	var economy: PlayerEconomy = play.ledger_for(owner)
	assert_true(economy != null, "the court keeps a ledger to read")
	var larder: Dictionary = MapPlayObserver.row(play, owner)["larder"]
	for key: String in ["store", "wanted", "army", "navy", "pool", "wards", "strikers", "short"]:
		assert_true(larder.has(key), "the row names the larder's %s" % key)
	assert_eq(
		int(larder["wanted"]),
		int(larder["army"]) + int(larder["navy"]) + int(larder["pool"]) + int(larder["wards"]),
		"every mouth the phase feeds is counted once"
	)
	# A full larder covers every mouth and strikes no one.
	economy.add("grain", int(larder["wanted"]) + 10)
	var fed: Dictionary = MapPlayObserver.larder_reading(economy)
	assert_true(int(fed["store"]) >= int(fed["wanted"]), "the store covers the mouths")
	assert_eq(int(fed["strikers"]), 0, "a fed court strikes no one")
	# The same mouths from an empty larder are the strike the signature measures.
	economy.take("grain", economy.quantity("grain"))
	economy.take("meat", economy.quantity("meat"))
	var starved: Dictionary = MapPlayObserver.larder_reading(economy)
	assert_true(int(starved["short"]) > 0, "the shortfall the store cannot cover is named")
	assert_true(int(starved["strikers"]) > 0, "and the workforce strikes")


func test_court_reader_counts_only_fighting_hulls() -> void:
	# From the top of turn 1: the cached turn's AI pass may already hold wars,
	# and this case names its own.
	_seat(0)
	var play: PlaySession = _screen.play
	var owner: int = FactionCatalog.great_power_ids()[0]
	var rival: int = FactionCatalog.great_power_ids()[1]
	var region: int = play.region_index
	var fleets: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
	var before_ships: int = MapPlayCourt.ships(play, owner)
	var before_warships: int = MapPlayCourt.warships(play, owner)
	fleets.append(
		FleetState.at_sea(
			900, owner, 0, ["court_a", "court_b", "court_c"],
			{"court_a": "sloop", "court_b": "carrack", "court_c": "sloop"}
		)
	)
	play.ship_layer.regions.set_region(region, fleets)
	assert_eq(MapPlayCourt.ships(play, owner), before_ships + 3, "every hull counts")
	assert_eq(
		MapPlayCourt.warships(play, owner), before_warships + 2,
		"merchant hulls are not fighting hulls"
	)
	# The enemy's navy is the threat only once a war is declared.
	var war: DiplomacyRelation = play.diplomacy.ensure_relation(owner, rival, play.turn)
	war.at_war = true
	assert_true(MapPlayCourt.at_war(play, owner), "the declaring court reads at war")
	var enemies: Array[int] = [rival]
	assert_eq(MapPlayCourt.at_war_with(play, owner), enemies, "the enemy is named")
	assert_eq(
		MapPlayCourt.hostile_ships(play, owner), MapPlayCourt.ships(play, rival),
		"the threat counts the enemy's hulls"
	)
	assert_eq(
		MapPlayCourt.hostile_warships(play, owner), MapPlayCourt.warships(play, rival),
		"the threat counts the enemy's fighting hulls"
	)


func test_court_reader_looks_up_forces_by_owner() -> void:
	var fleet: FleetState = FleetState.at_sea(7, 3, 0, ["hull_a"], {"hull_a": "sloop"})
	var other: FleetState = FleetState.at_sea(7, 4, 0, ["hull_b"], {"hull_b": "sloop"})
	var roster: Array[FleetState] = [fleet, other]
	assert_eq(MapPlayCourt.fleet_by_id(roster, 7), fleet, "the first match wins")
	assert_eq(MapPlayCourt.fleet_by_id(roster, 7, 4), other, "the owner narrows the id")
	assert_null(MapPlayCourt.fleet_by_id(roster, 7, 5), "a stranger holds no such squadron")
	assert_null(MapPlayCourt.fleet_by_id(roster, 8), "an unknown id reads nothing")
	var army: ArmyState = ArmyState.new()
	army.id = 11
	army.owner = 3
	var armies: Array[ArmyState] = [army]
	assert_eq(MapPlayCourt.army_by_id(armies, 11), army, "the standard answers by id")
	assert_null(MapPlayCourt.army_by_id(armies, 11, 4), "another court holds no such army")


func test_court_reader_reads_region_rosters() -> void:
	var play: PlaySession = _screen.play
	var region: int = play.region_index
	var fleets: Array[FleetState] = MapPlayCourt.region_fleets(play, region)
	assert_eq(fleets.size(), play.ship_layer.regions.value(region, []).size(), "one roster")
	var armies: Array[ArmyState] = MapPlayCourt.region_armies(play, region)
	assert_eq(armies.size(), play.army_layer.armies.size(), "the live region answers")
	MapPlayCourt.refresh_hulls(play)
	assert_eq(
		play.army_layer.armies.size(), armies.size(),
		"a hull refresh leaves the field armies alone"
	)


## The former human slot is a planning crown in the observer, so it must chart
## like one: its New World grid is its own, never the screen's region table,
## which no pass grows (issue #603).
func test_the_observed_court_charts_like_any_rival() -> void:
	var play: PlaySession = _screen.play
	assert_true(play.observer_mode, "the session is an all-AI observer")
	var charts: CourtCharts = play.court_charts
	assert_eq(
		charts.human_faction, MapModel.NO_ID,
		"no planning crown reads the screen's own region table"
	)
	for faction: int in FactionCatalog.great_power_ids():
		for region in play.world.region_count():
			assert_true(
				charts.model_for(faction, region) != null,
				"%s charts region %d" % [FactionCatalog.name_of(faction), region]
			)


## The observatory's province sheet reads one province for the court that holds
## it: every word is another module's own — the fact grid's wall and ward, the
## survey's estates, the defence lens's band — so the sheet can name no number
## the rules would not (docs/ai-observer.md; REQ-P2-03, REQ-P3-03).
func test_the_observer_reads_one_province_in_its_owners_terms() -> void:
	var play: PlaySession = _screen.play
	var province_id: int = _owned_province(play)
	assert_true(province_id >= 0, "the chart holds an owned province")
	var reading: Dictionary = ObserverProvince.reading(play, province_id)
	var data: ProvinceState = play.model.province_data(province_id)
	assert_eq(String(reading["name"]), data.name, "the province's own name")
	assert_eq(int(reading["owner"]), data.owner, "the court that holds it")
	assert_eq(
		String(reading["owner_caption"]), ProvinceSheetHead.owner_caption(data.owner),
		"the honorific the dossier prints"
	)
	assert_eq(bool(reading["capital"]), data.capital, "the CAPITAL badge reads the record")
	assert_eq(String(reading["fort"]), FortRules.describe(data.fort_level), "the wall")
	assert_eq(
		String(reading["hospital"]),
		HospitalRules.describe(data.hospital_level, data.hospital_staffed),
		"the ward"
	)
	assert_false(String(reading["terrain"]).is_empty(), "the ground the battle would fight on")
	assert_eq(
		String(reading["band"]),
		DefenceSurvey.band_for(data.fort_level, int(reading["strength"])),
		"the band is the defence lens's own"
	)
	for row: Dictionary in reading["estates"]:
		assert_true(bool(row["ours"]), "an estate on the owner's ground is the owner's")
		assert_true(row.has("tile") and row.has("level"), "an estate row is a survey row")
	assert_eq(
		String(reading["defence"]).is_empty(), false,
		"the defence line always says something"
	)


## A province id the chart does not hold reads nothing, so the sheet closes
## instead of printing a void (REQ-P5-05).
func test_the_observer_reads_no_province_it_cannot_name() -> void:
	var play: PlaySession = _screen.play
	assert_true(ObserverProvince.reading(play, -1).is_empty(), "no id, no reading")
	assert_true(ObserverProvince.reading(play, 99999).is_empty(), "no province, no reading")
	assert_true(ObserverProvince.reading(null, 0).is_empty(), "no session, no reading")


## The chart's own selection opens the reading: the observatory mounts the sheet
## and the map's selection signal fills it, then a cleared selection closes it.
func test_a_chart_selection_opens_and_closes_the_observers_sheet() -> void:
	var screen: MapScreen = _screen
	var panel: AiObserverPanel = screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory is mounted on the observer screen")
	if panel == null:
		return
	var play: PlaySession = screen.play
	var province_id: int = _owned_province(play)
	var data: ProvinceState = play.model.province_data(province_id)
	var tile: Vector2i = data.tiles[0]
	MapPlayInput.select_province(
		play, province_id, MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE)
	)
	assert_true(panel.sheet.visible, "the reading opens on the selection")
	assert_eq(panel.sheet.head.name_label.text, data.name, "the province on the sheet")
	assert_eq(panel.sheet.province_id, province_id, "the sheet keeps the province it read")
	assert_eq(panel.sheet.estates.lines().size(), (ObserverProvince.reading(play, province_id)["estates"] as Array).size())
	MapPlayInput.deselect(play)
	assert_false(panel.sheet.visible, "a cleared selection closes the sheet")
	assert_eq(panel.sheet.province_id, -1, "and forgets the province")


## The observatory has no seat to give orders from, so a tap on the chart with a
## regiment selected moves nothing: the chart is a reading there (REQ-P2-03).
func test_the_observatory_orders_nothing_from_the_chart() -> void:
	var play: PlaySession = _screen.play
	var roster: Array = play.army_layer.regions.value(play.region_index, [])
	var army: ArmyState = null
	for raw: Variant in roster:
		var candidate: ArmyState = raw
		if (
			candidate.embarked_fleet < 0
			and candidate.province != MapModel.NO_ID
			and not candidate.regiments.is_empty()
		):
			army = candidate
			break
	assert_not_null(army, "the chart on screen musters a regiment")
	if army == null:
		return
	play.army_layer.select(army)
	var before: int = army.province
	var target: int = -1
	for province: ProvinceState in play.model.provinces:
		if province.id != before and province.owner == army.owner:
			target = province.id
			break
	assert_true(target >= 0, "the crown holds a second province to march on")
	if target < 0:
		return
	var tile: Vector2i = play.model.province_data(target).tiles[0]
	MapPlayInput.on_tapped(play, MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE))
	assert_eq(army.province, before, "the observer's tap orders no march")


## The court that owns the province the reading names, or the first one the
## chart holds — a fixture province is enough for the reading's own contract.
func _owned_province(play: PlaySession) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != MapModel.NO_ID:
			return province.id
	return -1

# --- observer feed / crown card (from test_observer_parts) ----------------------
## The observatory's read-only halves: [ObserverTurnFeed] and [ObserverCrownCard]
## (REQ-P3-01, REQ-P3-03). Pure cases ride this suite's boot so they do not pay
## a second coverage process (docs/testing.md § Speed rules).

func _feed_turn(number: int, rows: int) -> Dictionary:
	var events: Array = []
	for index in rows:
		events.append({"text": "T%d order %d." % [number, index]})
	return {"turn": number, "events": events}


## The feed prints every row of the turns it keeps, newest row first, and counts
## what it holds (REQ-P5-05).
func test_the_feed_prints_every_row_of_the_turns_it_keeps() -> void:
	assert_eq(ObserverTurnFeed.text([]), ObserverTurnFeed.EMPTY_TEXT)
	assert_eq(ObserverTurnFeed.caption([]), "Recent orders", "an empty feed counts none")
	assert_eq(
		ObserverTurnFeed.caption([{"turn": 1, "events": [{"text": "Marched."}]}]),
		"Recent orders  ·  T1  ·  1 row over 1 turn, newest first",
		"one turn's one row prints as written"
	)
	assert_eq(
		ObserverTurnFeed.text([{"turn": 7, "events": []}]),
		ObserverTurnFeed.EMPTY_TEXT,
		"a turn that filed nothing prints no line"
	)


## The window is a row budget, not a turn count: a crowded campaign keeps the
## newest turns whole up to the budget and never cuts a busy turn's first row
## (REQ-P5-05, REQ-P4-01).
func test_the_window_stops_at_its_row_budget() -> void:
	var ai_turns: Array = []
	for turn in range(1, 21):
		ai_turns.append(_feed_turn(turn, 10))
	var text: String = ObserverTurnFeed.text(ai_turns)
	var lines: PackedStringArray = text.split("\n")
	var turns_kept: int = ObserverTurnFeed.ROW_BUDGET / 10
	assert_eq(lines.size(), ObserverTurnFeed.ROW_BUDGET, "the budget is the row count held")
	assert_eq(
		ObserverTurnFeed.first_kept(ai_turns), 20 - turns_kept,
		"the window reaches back exactly the turns the budget buys"
	)
	assert_eq(
		String(lines[0]), "T20  T20 order 9.", "the newest order leads the feed"
	)
	assert_eq(
		String(lines[lines.size() - 1]), "T%d  T%d order 0." % [
			21 - turns_kept, 21 - turns_kept,
		],
		"the oldest kept turn keeps its first order, not a cut one"
	)
	assert_false(text.contains("T%d  " % (20 - turns_kept)), "the turn before the window drops")
	assert_eq(
		ObserverTurnFeed.caption(ai_turns),
		"Recent orders  ·  T%d–T20  ·  %d rows over %d turns, newest first" % [
			21 - turns_kept, ObserverTurnFeed.ROW_BUDGET, turns_kept,
		],
		"the caption names the turns the window reaches back to"
	)


## A quiet campaign buys more history than a crowded one: the same budget holds
## every turn of a lean run, so a late watcher reads the whole story (REQ-P5-05).
func test_a_quiet_run_keeps_more_turns_than_a_busy_one() -> void:
	var quiet: Array = []
	for turn in range(1, 41):
		quiet.append(_feed_turn(turn, 2))
	assert_eq(ObserverTurnFeed.first_kept(quiet), 0, "every lean turn fits the budget")
	assert_eq(
		ObserverTurnFeed.caption(quiet),
		"Recent orders  ·  T1–T40  ·  80 rows over 40 turns, newest first"
	)


## The floor: however busy the newest turns are, the feed keeps a pair of them,
## so the order that caused the latest one is never the row that drops
## (REQ-P5-05).
func test_a_turn_busier_than_the_budget_still_prints_whole() -> void:
	var busy: Array = [_feed_turn(1, ObserverTurnFeed.ROW_BUDGET * 2), _feed_turn(2, 3)]
	assert_eq(ObserverTurnFeed.first_kept(busy), 0, "the floor keeps both turns")
	var lines: PackedStringArray = ObserverTurnFeed.text(busy).split("\n")
	assert_eq(
		lines.size(), ObserverTurnFeed.ROW_BUDGET * 2 + 3,
		"every row of both turns reaches the feed"
	)


## One crown's card reads rank, standing toward the bar, profile, ledger and last
## order from a single snapshot row (DR-20261114-04).
func test_a_crowns_card_reads_one_snapshot_row() -> void:
	var card := ObserverCrownCard.new()
	add_child(card)
	var row: Dictionary = {
		"faction": 3, "rank": 2, "name": "Spain", "alive": true,
		"leader": "Felipe", "agenda": "Bourbon", "profile": "trader",
		"posture": "patient", "intent": "hold", "headline": "Marched on Lisbon.",
		"provinces_old": 11, "provinces_new": 2, "power": 40, "regiments": 6,
		"ships": 4, "civilians": 3, "treasury": 900, "stock": 12, "workers": 5,
		"wars": ["Portugal"], "pressure_stage": AiVictoryPressure.STAGE_NEAR,
	}
	card.fill(row)
	assert_eq(card.rank.text, "#2")
	assert_eq(card.name_label.text, "Spain")
	assert_true(card.progress.text.ends_with("pressing"), "the endgame court is marked")
	assert_true(
		card.progress.text.begins_with(
			"%d/%d" % [11, VictoryRules.MILITARY_THRESHOLD]
		),
		"the standing leads the line"
	)
	assert_true(card.meta.text.contains("Felipe"), "the profile line names the court")
	assert_true(card.stats.text.contains("wars: Portugal"), "the ledger names the war")
	assert_eq(card.last.text, "Last turn: Marched on Lisbon.")
	row["alive"] = false
	row["pressure_stage"] = AiVictoryPressure.STAGE_FAR
	card.fill(row)
	assert_true(card.name_label.text.ends_with("(fallen)"), "a fallen crown says so")
	assert_false(card.progress.text.ends_with("pressing"), "a far court is not")
	card.free()
