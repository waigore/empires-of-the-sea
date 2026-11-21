extends GdToolsTest
## The counsel picks' one seat bind: the planner kind a crown plans on, the
## config bound to that kind and the footing the config reads (REQ-P2-03,
## REQ-P3-02). A pick reads this seat once instead of carrying its own
## kind/config pair, so no sheet can plan on a different bind than the pass.

const AiFixture = preload("res://tests/ai_fixture.gd")


func test_a_session_with_no_planner_has_no_seat() -> void:
	assert_null(MapPlayCourt.seat(null, FactionCatalog.PLAYER_FACTION), "no session")
	var play := PlaySession.new()
	play.ai_mode = AiControl.NOOP
	assert_null(
		MapPlayCourt.seat(play, FactionCatalog.PLAYER_FACTION),
		"a noop court plans nothing"
	)


func test_a_planning_seat_binds_the_kind_and_its_config() -> void:
	var play := PlaySession.new()
	var faction: int = FactionCatalog.PLAYER_FACTION
	var seat: MapPlayCourt.Seat = MapPlayCourt.seat(play, faction)
	assert_not_null(seat, "the crown plans in a full game")
	assert_eq(seat.faction, faction, "the seat names the crown it plans for")
	assert_eq(seat.kind, AiControl.KIND_SUBJECT, "the full game seats the subject")
	assert_true(seat.config is AiConfig, "the bind is the planner's own config")


func test_a_random_court_still_binds_a_seat() -> void:
	var play := PlaySession.new()
	play.ai_mode = AiControl.BENCH
	play.ai_live_faction = FactionCatalog.PLAYER_FACTION
	# The two smallest Great Powers other than the subject are baselines; the
	# rest take random legal actions, which still need a bound config.
	var random_id: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if AiControl.court_kind(play, faction) == AiControl.KIND_RANDOM:
			random_id = faction
			break
	assert_true(random_id >= 0, "the bench seats at least one random court")
	var seat: MapPlayCourt.Seat = MapPlayCourt.seat(play, random_id)
	assert_not_null(seat, "a random court still plans with a config")
	assert_eq(seat.kind, AiControl.KIND_RANDOM, "the seat keeps the court's kind")
	assert_not_null(seat.config, "and binds a config for it")


func test_the_seat_reads_the_one_footing_the_pass_reads() -> void:
	var play := PlaySession.new()
	var seat: MapPlayCourt.Seat = MapPlayCourt.seat(
		play, FactionCatalog.PLAYER_FACTION
	)
	play.diplomacy = DiplomacyState.new()
	assert_eq(seat.phase(play), AiPhasePlanner.PHASE_PEACE, "no war on the books")
	play.diplomacy = null
	assert_eq(
		seat.phase(play), AiPhasePlanner.PHASE_UNKNOWN, "no relations, no footing"
	)


func test_the_passes_walk_only_the_planning_seats() -> void:
	var play := PlaySession.new()
	play.world = AiFixture.world([0, 1, 2, 3, 4, 5])
	play.ai_mode = AiControl.BENCH
	play.ai_live_faction = FactionCatalog.PLAYER_FACTION
	# The observer seats the former human crown like any rival, so it walks the
	# subject and its two baselines; the random courts are left to the rules'
	# own fallback, so a pass never walks them.
	play.observer_mode = true
	var ids: Array[int] = []
	for seat: MapPlayCourt.Seat in MapPlayCourt.planning_seats(play):
		ids.append(seat.faction)
	assert_eq(ids, [0, 1, 2] as Array[int], "the subject and its two baselines")
