extends GdToolsTest
## Full-AI observer (wiki: game-setup § Human/AI slot assignment, an empty human
## slot set is the full-AI observer; turn-trace-interpretation): every crown on
## the shared AI planners, the one court reader they all ask, the merged
## per-turn record, and the dashboard's snapshot contract.

const Fixture = preload("res://tests/map_fixture.gd")
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")

## Non-underscore: gd-tools clones a fresh suite instance per test and does not
## copy underscore fields out of before_all (docs/testing.md speed rules).
var world_snapshot: Array = []
var _screen: MapScreen = null


func before_all() -> void:
	world_snapshot = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	Fixture.restore(Fixture.world(), world_snapshot)
	_screen = SCENE.instantiate()
	_screen.map_width = Fixture.WORLD_WIDTH
	_screen.map_height = Fixture.WORLD_HEIGHT
	_screen.preset_world = Fixture.world()
	_screen.observer_mode = true
	_screen.infinite_mode = true
	add_child(_screen)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func _step(turns: int = 1) -> void:
	for _turn in turns:
		MapPlayTurn.end_turn(_screen.play)


func test_observer_gives_every_great_power_an_ai_ledger() -> void:
	var play: PlaySession = _screen.play
	assert_true(play.observer_mode, "the session is an all-AI observer")
	assert_eq(play.diplomacy.human_faction, MapModel.NO_ID, "no court holds consent")
	_step(1)
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(
			play.ai.economies.has(faction),
			"%s keeps an AI ledger" % FactionCatalog.name_of(faction)
		)


func test_observer_resolves_a_turn_for_every_crown() -> void:
	var play: PlaySession = _screen.play
	var before: int = play.turn
	_step(2)
	assert_eq(play.turn, before + 2, "the calendar advances")
	assert_eq(play.ai_turns.size(), 2, "one merged record per resolved turn")
	var factions: Dictionary = play.ai_turns[0]["factions"]
	assert_eq(factions.size(), FactionCatalog.great_power_ids().size())
	for faction: int in FactionCatalog.great_power_ids():
		assert_true(factions.has(faction), "record names every crown")
		assert_true(factions[faction].has("actions"))
		assert_true(factions[faction].has("events"))


func test_observer_never_queues_a_human_decision() -> void:
	var play: PlaySession = _screen.play
	_step(2)
	assert_true(play.diplomacy.pending_calls.is_empty(), "no call to arms waits")
	assert_true(play.diplomacy.pending_interventions.is_empty(), "no intervention waits")
	assert_true(play.diplomacy.pending_offers.is_empty(), "no proposal waits")
	assert_false(play.turn_suspended, "the observer never suspends the calendar")
	# The court helpers are inert in an observer session (no hidden HUD work).
	MapPlayDiplomacy.open(play)
	MapPlayDiplomacy.refresh(play)
	assert_false(_screen.hud.panels.is_diplomacy_open(), "the court never opens")


func test_snapshot_ranks_every_crown_and_exposes_the_metrics() -> void:
	var play: PlaySession = _screen.play
	_step(1)
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


func test_observer_former_crown_plays_through_the_planners() -> void:
	var play: PlaySession = _screen.play
	_step(1)
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


func test_dashboard_renders_the_live_snapshot() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	_step(1)
	panel.refresh()
	assert_true(panel._turn_label.text.begins_with("TURN"), "the panel names the turn")
	assert_eq(panel._cards.size(), FactionCatalog.great_power_ids().size())
	assert_ne(panel._result.text, "", "the panel reports the standing")


## A court that can see the bar is marked on its card (DR-20261114-04): the
## standing reads `pressing` beside the province count, and drops it when the
## court is far from the bar.
func test_the_card_marks_a_court_that_presses_for_the_bar() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	_step(1)
	panel.refresh()
	var row: Dictionary = MapPlayObserver.snapshot(_screen.play)["rows"][0].duplicate(true)
	var progress: Label = panel._cards[int(row["faction"])]["progress"]
	row["pressure_stage"] = AiVictoryPressure.STAGE_NEAR
	panel._refresh_card(row)
	assert_true(progress.text.ends_with("pressing"), "the endgame court is marked")
	assert_true(
		progress.text.begins_with("%d/%d" % [
			int(row["provinces_old"]), VictoryRules.MILITARY_THRESHOLD,
		]),
		"the standing still leads the line"
	)
	row["pressure_stage"] = AiVictoryPressure.STAGE_FAR
	panel._refresh_card(row)
	assert_false(progress.text.ends_with("pressing"), "a court far from the bar is not")


func test_dashboard_controls_step_pause_and_collapse() -> void:
	var panel := _screen.get_node_or_null("AiObserver") as AiObserverPanel
	assert_not_null(panel, "the observatory panel mounts")
	if panel == null:
		return
	var play: PlaySession = _screen.play
	panel.running = false
	var before: int = play.turn
	panel._step_once()
	assert_eq(play.turn, before + 1, "Step resolves exactly one turn")
	panel._toggle_running()
	assert_true(panel.running, "Resume restarts the loop")
	panel._toggle_running()
	assert_false(panel.running, "Pause stops the loop")
	panel._cycle_speed()
	assert_eq(panel._speed_index, 1, "speed cycles")
	panel._toggle_panel()
	assert_false(panel._frame.visible, "the panel collapses")
	assert_true(panel._tab.visible, "a tab keeps it reachable")
	panel._toggle_panel()
	assert_true(panel._frame.visible, "the panel returns")


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


func test_court_reader_counts_only_fighting_hulls() -> void:
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
