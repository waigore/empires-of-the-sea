extends GdToolsTest
## A rival court's veiled word about its own hidden motive (wiki:
## dialogue-and-mood § Seeding / cadence; hidden-agendas § Playable slice;
## DR-20261111-19). The cadence is one word in seven turns, the crown hears
## nothing before its own dossier already suspects the motive, and the beat
## speaks the same words after a save (REQ-P2-01, REQ-P2-03, REQ-P2-04).

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


# --- content ----------------------------------------------------------------


func test_every_agenda_has_a_veiled_point() -> void:
	for agenda_id: String in AiAgenda.IDS:
		var point: String = DialogueAgenda.point_for(agenda_id)
		assert_true(DialogueCatalog.has_point(point), "%s is authored" % point)
		assert_eq(DialogueCatalog.category_for(point), DialogueCatalog.CAT_AGENDA)
		assert_true(DialogueCatalog.lines_for(point).size() >= 2, "%s repeats less" % point)
		for mood: Variant in DialogueCatalog.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)


func test_no_veiled_line_names_its_own_motive() -> void:
	# The player overhears a hint; the agenda id may never reach the words.
	for agenda_id: String in AiAgenda.IDS:
		for raw: Variant in DialogueCatalog.lines_for(DialogueAgenda.point_for(agenda_id)):
			var line: String = String(raw).to_lower()
			assert_false(
				line.contains(agenda_id.replace("_", " ")) or line.contains(agenda_id),
				"%s does not confess its name" % agenda_id
			)


# --- cadence ----------------------------------------------------------------


func test_a_court_speaks_once_in_seven_turns() -> void:
	for faction: int in FactionCatalog.great_power_ids():
		var due: Array[int] = _due_turns(1500, faction, 70)
		assert_eq(due.size(), 10, "court %d speaks ten times in seventy turns" % faction)
		for index: int in range(1, due.size()):
			assert_eq(due[index] - due[index - 1], DialogueAgenda.CADENCE, "one word in seven")


func test_each_court_keeps_its_own_cadence() -> void:
	var seen: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var first: int = _next_due(1500, faction)
		assert_true(first >= 1 and first <= DialogueAgenda.CADENCE)
		seen[first] = true
	assert_true(seen.size() > 1, "six courts do not all speak on the same turn")


func test_the_cadence_is_the_same_after_a_reload() -> void:
	var seed_value: int = DialogueAgenda.seed_for(1500, 3)
	assert_eq(seed_value, DialogueAgenda.seed_for(1500, 3), "the seed is stable")
	var turn: int = _next_due(1500, 3)
	assert_true(DialogueAgenda.due(1500, 3, turn))
	assert_true(DialogueAgenda.due(1500, 3, turn + DialogueAgenda.CADENCE), "and comes round again")
	assert_false(DialogueAgenda.due(1500, 3, turn + 1))


func test_no_turn_before_the_first_speaks() -> void:
	assert_false(DialogueAgenda.due(1500, 1, 0))
	assert_false(DialogueAgenda.due(1500, 1, -7))


# --- the evidence gate ------------------------------------------------------


func test_the_beat_waits_for_the_dossiers_evidence() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	assert_false(
		DialogueAgenda.record(state, WorldMap.new(), 0, 1, seed_value, turn),
		"no evidence, no word about the motive"
	)
	assert_eq(_kind_count(DialogueAgenda.SPOKE), 0)


func test_a_suspected_motive_is_voiced_by_the_court() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	assert_true(DialogueAgenda.record(state, WorldMap.new(), 0, 1, seed_value, turn))
	var event: Dictionary = state.events[state.events.size() - 1]
	assert_eq(String(event["kind"]), DialogueAgenda.SPOKE)
	assert_eq(int(event["a"]), 0, "the crown records the word it hears")
	assert_eq(int(event["b"]), 1, "the rival speaks")
	assert_eq(String(event["data"]["agenda"]), AiAgenda.WARMONGER)
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 1)
	assert_eq(String(spoken["point"]), "agenda/warmonger")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_AGENDA)
	assert_eq(int(spoken["speaker"]), 1, "the reader never speaks its own agenda")
	assert_true(String(spoken["text"]).length() > 10)


func test_the_beat_is_the_weakest_word_of_the_turn() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	assert_true(DialogueAgenda.record(state, WorldMap.new(), 0, 1, seed_value, turn))
	# A study of the crown's own turn is recorded after the beat and wins.
	assert_true(DialogueHome.record_tech_studied(state, 0, "printing_press"))
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 1)["point"]),
		"event/tech_studied",
		"the court's newest word is not the veiled one"
	)


func test_a_court_the_crown_has_never_met_says_nothing() -> void:
	var seed_value: int = _seed_for(9, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 9)
	assert_false(
		DialogueAgenda.record(state, WorldMap.new(), 0, 9, seed_value, turn),
		"a stranger is not on the court's list"
	)


func test_the_rival_does_not_quote_its_own_agenda() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	DialogueAgenda.record(state, WorldMap.new(), 0, 1, seed_value, turn)
	var event: Dictionary = state.events[state.events.size() - 1]
	assert_true(
		DialogueEvents.for_event(state, event, 1).is_empty(),
		"only the crown that overheard it reads the word"
	)


func test_an_unknown_agenda_speaks_nothing() -> void:
	var event: Dictionary = {
		"kind": DialogueAgenda.SPOKE,
		"a": 0,
		"b": 1,
		"turn": 3,
		"data": {"agenda": "warlord"},
	}
	assert_true(DialogueEvents.for_event(state, event, 0).is_empty(), "no such motive, no words")
	assert_true(DialogueEvents.for_event(state, {"kind": DialogueAgenda.SPOKE, "a": 0, "b": 1}, 0).is_empty())


func test_the_beat_survives_a_save() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	DialogueAgenda.record(state, WorldMap.new(), 0, 1, seed_value, turn)
	var before: Dictionary = DialogueEvents.for_pair(state, 0, 1)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 1)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")


# --- the map's own turn -----------------------------------------------------


func test_the_map_records_the_agenda_beat_on_its_cadence_turn() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var play: PlaySession = _play(seed_value, _next_due(seed_value, 1))
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 1, "one rival speaks")
	assert_eq(
		String(DialogueEvents.for_pair(play.diplomacy, 0, 1)["point"]),
		"agenda/warmonger"
	)


func test_a_turn_off_the_cadence_says_nothing() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1) + 1
	var play: PlaySession = _play(seed_value, turn)
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 0, "off the cadence, silence")


func test_an_observer_turn_raises_no_agenda_beat() -> void:
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var play: PlaySession = _play(seed_value, _next_due(seed_value, 1))
	play.observer_mode = true
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 0, "the observatory speaks to nobody")


# --- fixtures ---------------------------------------------------------------


## The first game seed that rolls `agenda_id` for `faction`. Assignment is
## deterministic, so the search is stable from run to run.
func _seed_for(faction: int, agenda_id: String) -> int:
	for candidate: int in range(1, 500):
		if AiAgenda.assign(candidate, faction) == agenda_id:
			return candidate
	assert_true(false, "no seed rolls %s for court %d" % [agenda_id, faction])
	return -1


func _next_due(seed_value: int, faction: int) -> int:
	for turn: int in range(1, DialogueAgenda.CADENCE + 1):
		if DialogueAgenda.due(seed_value, faction, turn):
			return turn
	return 0


func _due_turns(seed_value: int, faction: int, through: int) -> Array[int]:
	var found: Array[int] = []
	for turn: int in range(1, through + 1):
		if DialogueAgenda.due(seed_value, faction, turn):
			found.append(turn)
	return found


## The subject's own wars, the evidence a dossier reads first.
func _wars_by(subject: int, against: int, share: DiplomacyState = null) -> void:
	var log: DiplomacyState = share if share != null else state
	for _i in range(3):
		log.record_event("warDeclared", subject, against)


func _kind_count(kind: String, share: DiplomacyState = null) -> int:
	var log: DiplomacyState = share if share != null else state
	var total: int = 0
	for event: Dictionary in log.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total


## The smallest session that reaches the court-voice pass: a crown, its log and
## a campaign clock. No army layer, so the seat stays silent.
func _play(seed_value: int, turn: int) -> PlaySession:
	var play := PlaySession.new()
	play.player_faction = 0
	play.map_seed = seed_value
	play.turn = turn
	play.world = WorldMap.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	return play
