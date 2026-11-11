extends GdToolsTest
## The court answers the crown's own turn (wiki: dialogue-and-mood § Design
## intent — `event`: tech discovered, capital threatened, colony founded;
## DR-20261111-08). Words come from the rules, a stranger never speaks, and the
## beat survives a save (REQ-P2-01, REQ-P2-03, REQ-P2-04).

const Fixture = preload("res://tests/army_fixture.gd")

const POINTS: Array[String] = [
	"event/tech_studied",
	"event/capital_threatened",
	"event/colony_founded",
]

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_the_home_beats_are_authored_event_points() -> void:
	for point: String in POINTS:
		assert_true(DialogueCatalog.has_point(point), "%s is authored" % point)
		assert_eq(DialogueCatalog.category_for(point), DialogueCatalog.CAT_EVENT)
		assert_true(DialogueCatalog.lines_for(point).size() >= 2, "%s repeats less" % point)
		for mood: Variant in DialogueCatalog.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)


func test_one_table_serves_both_catalogues() -> void:
	assert_eq(
		DialogueCatalog.table().size(),
		DialogueCatalog.POINTS.size() + DialogueEpisodes.POINTS.size()
		+ DialogueAgendaLines.POINTS.size(),
		"the merged catalogue loses no point"
	)
	assert_true(
		DialogueCatalog.points().has("diplomatic/peace_made"),
		"the pair beats stay reachable"
	)
	assert_true(DialogueCatalog.points().has("event/field_won"), "and the episodes")


func test_a_study_is_answered_by_the_coldest_rival() -> void:
	_set_score(1, 80.0)
	_set_score(2, 20.0)
	_set_score(3, 40.0)
	assert_eq(DialogueHome.watching_court(state, 0), 2, "the coldest court watches")
	assert_true(DialogueHome.record_tech_studied(state, 0, "printing_press"))
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 2)
	assert_eq(String(spoken["point"]), "event/tech_studied")
	assert_eq(int(spoken["speaker"]), 2, "the reader never speaks its own study")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT)
	assert_true(String(spoken["text"]).length() > 10)


func test_the_study_is_the_readers_beat_not_the_rivals_line_about_it() -> void:
	DialogueHome.record_tech_studied(state, 0, "printing_press")
	var event: Dictionary = state.events[state.events.size() - 1]
	assert_true(
		DialogueEvents.for_event(state, event, 2).is_empty(),
		"the rival does not quote the crown to itself"
	)


func test_a_crown_with_no_rival_writes_no_beat() -> void:
	var lonely := DiplomacyState.new()
	assert_eq(DialogueHome.watching_court(lonely, 0), -1, "nobody to watch")
	assert_false(DialogueHome.record_tech_studied(lonely, 0, "printing_press"))


func test_the_strongest_host_at_the_seat_speaks() -> void:
	_declare_war(1)
	_declare_war(2)
	var hosts: Array = [
		{"owner": 1, "strength": 12.0},
		{"owner": 2, "strength": 30.0},
	]
	assert_true(DialogueHome.record_capital_threat(state, 0, 4, hosts))
	var event: Dictionary = state.events[state.events.size() - 1]
	assert_eq(String(event["kind"]), DialogueHome.CAPITAL_THREATENED)
	assert_eq(int(event["b"]), 2, "the heaviest host answers")
	assert_eq(int(event["data"]["province"]), 4, "the seat is named for the record")
	assert_eq(String(DialogueEvents.for_pair(state, 0, 2)["point"]), "event/capital_threatened")


func test_a_host_at_power_says_nothing_about_the_seat() -> void:
	var hosts: Array = [{"owner": 1, "strength": 30.0}]
	assert_false(
		DialogueHome.record_capital_threat(state, 0, 4, hosts),
		"a court at peace threatens nothing"
	)
	assert_false(DialogueHome.record_capital_threat(state, 0, -1, hosts), "no seat, no beat")


func test_a_tribe_under_the_flag_speaks_in_its_own_voice() -> void:
	state.touch(0, 7, "colonyFormed", {"stage": "join_empire"})
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 7)
	assert_eq(String(spoken["point"]), "event/colony_founded")
	assert_eq(int(spoken["speaker"]), 7, "the Tribe speaks for its lost land")


func test_the_beat_survives_a_save() -> void:
	DialogueHome.record_tech_studied(state, 0, "printing_press")
	var before: Dictionary = DialogueEvents.for_pair(state, 0, 1)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 1)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")


func test_the_map_speaks_the_turn_it_resolved() -> void:
	var play: PlaySession = _play()
	MapPlayCourtVoice.record_turn(
		play, {"research": {"researched": ["saw_mill", "printing_press"]}}
	)
	assert_eq(_kind_count(play, DialogueHome.TECH_STUDIED), 1, "one study, one beat")
	assert_eq(
		_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"the host at the seat answers"
	)
	assert_eq(
		String(DialogueEvents.for_pair(play.diplomacy, 0, 1)["point"]),
		"event/capital_threatened",
		"the seat speaks last"
	)
	play.army_layer.free()


func test_an_observer_turn_raises_no_beat() -> void:
	var play: PlaySession = _play()
	play.observer_mode = true
	var before: int = play.diplomacy.events.size()
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": ["printing_press"]}})
	assert_eq(play.diplomacy.events.size(), before, "the observer courts speak to nobody")
	play.army_layer.free()


func test_a_seat_off_screen_reads_its_stored_roster() -> void:
	var play: PlaySession = _play()
	# The crown is looking at the other region: the seat's armies live in the
	# layer's stored table, not in the live roster.
	play.world.add_region(Fixture.build())
	play.model = play.world.region(1)
	play.model.region_id = 1
	var stored: Array[ArmyState] = [ArmyState.muster(2, 1, 0, false, ["pikemen"], 10)]
	play.army_layer.regions.set_region(0, stored)
	play.army_layer.armies.clear()
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(
		_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"a host off screen still answers"
	)
	assert_eq(_kind_count(play, DialogueHome.TECH_STUDIED), 0, "no study, no beat")
	play.army_layer.free()


func test_an_embarked_host_is_at_sea_and_says_nothing() -> void:
	var play: PlaySession = _play()
	var host: ArmyState = play.army_layer.armies[0]
	host.embarked_fleet = 1
	var before: int = play.diplomacy.events.size()
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(play.diplomacy.events.size(), before, "a host afloat is not at the gate")
	play.army_layer.free()


func test_a_session_without_a_seat_or_a_report_is_silent() -> void:
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = WorldMap.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(play.diplomacy.events.size(), 0, "nothing happened, nothing is said")


func test_a_malformed_report_writes_nothing() -> void:
	var play: PlaySession = _play()
	MapPlayCourtVoice.record_turn(play, {"research": "not a report"})
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": "not a list"}})
	assert_eq(_kind_count(play, DialogueHome.TECH_STUDIED), 0, "a broken report is not a study")
	play.army_layer.free()


# --- fixtures ---------------------------------------------------------------


## A crown holding a capital in province 0, an enemy host drawn up on it, and
## one declared war — the smallest turn that has something to say.
func _play() -> PlaySession:
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = WorldMap.new()
	play.world.add_region(Fixture.build())
	play.model = play.world.region(0)
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 0)
	play.army_layer = ArmyLayer.new()
	play.army_layer.armies.append(ArmyState.muster(1, 1, 0, false, ["pikemen"], 1))
	return play


func _kind_count(play: PlaySession, kind: String) -> int:
	var total: int = 0
	for event: Dictionary in play.diplomacy.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total


func _declare_war(against: int) -> void:
	DiplomacyRules.declare_war(state, against, 0)


func _set_score(other: int, score: float) -> void:
	var record: DiplomacyRelation = state.relation(0, other)
	assert_true(record != null, "a Great Power pair holds a relation")
	record.score = score
