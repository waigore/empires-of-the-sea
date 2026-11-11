extends GdToolsTest
## The court's voice (wiki: dialogue-and-mood, dialogue-management,
## dialogue-content-and-yarn): authored points, a deterministic pick, the mood
## machine's bands, and the rule that words never leave a mark on state
## (REQ-P2-01, REQ-P2-03, REQ-P2-04).
## Consolidated rulebook: test_dialogue_agenda, test_dialogue_beats
## (one Godot boot per domain).

var state: DiplomacyState

## One recorded act per voiced kind, so a new beat cannot ship without words.
const VOICED: Dictionary = {
	"warDeclared": {},
	"peaceMade": {},
	"allianceFormed": {},
	"allianceBroken": {},
	"callToArmsAccepted": {"aggressor": 2},
	"callToArmsRefused": {"aggressor": 2},
	"interventionIntervened": {"aggressor": 2},
	"interventionDoNothing": {"aggressor": 2},
	"interventionProtest": {"target": 6},
	"proposalAccepted": {"kind": "alliance", "stage": ""},
	"proposalRefused": {"kind": "peace", "stage": ""},
	"overtureEstablished": {"stage": "consulate"},
	"overtureRejected": {"stage": "consulate"},
	"firstContact": {},
	"colonyFormed": {"stage": "join_empire"},
	"techStudied": {"tech": "printing_press"},
	"capitalThreatened": {"province": 1},
}

## Acts that are bookkeeping, not a court speaking.
const SILENT: Array[String] = [
	"overturesCleared",
	"joinEmpire",
	"colonyReleased",
	"subsidySet",
	"subsidyCancelled",
	"grantAid",
	"proposalMade",
]


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_every_point_is_authored_with_a_category_and_two_ways_to_say_it() -> void:
	assert_true(DialogueCatalog.points().size() >= 20, "the catalogue covers the beats")
	for point: String in DialogueCatalog.points():
		assert_true(
			[DialogueCatalog.CAT_DIPLOMATIC, DialogueCatalog.CAT_EVENT,
			DialogueCatalog.CAT_NEGOTIATION, DialogueCatalog.CAT_REACTIVE,
			DialogueCatalog.CAT_AGENDA].has(DialogueCatalog.category_for(point)),
			"%s has a documented category" % point
		)
		assert_true(DialogueCatalog.lines_for(point).size() >= 2, "%s repeats less" % point)
		assert_false(DialogueCatalog.moods_for(point).is_empty(), "%s wears a face" % point)
		for mood: Variant in DialogueCatalog.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)


func test_every_face_is_a_documented_portrait_mood() -> void:
	assert_eq(DialogueMood.MOODS.size(), 8, "the eight documented moods")
	for mood: String in DialogueMood.MOODS:
		assert_eq(DialogueMood.MOODS.count(mood), 1, "%s appears once" % mood)


func test_no_line_carries_a_number_or_a_raw_placeholder() -> void:
	var digits := RegEx.new()
	digits.compile("\\d")
	for point: String in DialogueCatalog.points():
		for template: Variant in DialogueCatalog.lines_for(point):
			var text: String = DialogueCatalog.render(String(template), "Spain", "Genoa")
			assert_null(digits.search(text), "%s keeps numbers out" % point)
			assert_false(text.contains("{"), "%s fills every placeholder" % point)


func test_a_line_and_a_face_are_chosen_deterministically() -> void:
	for point: String in DialogueCatalog.points():
		assert_eq(
			DialogueCatalog.line_for(point, 11), DialogueCatalog.line_for(point, 11),
			"%s repeats on a reload" % point
		)
		var seen: Dictionary = {}
		for salt in DialogueCatalog.lines_for(point).size():
			seen[DialogueCatalog.line_for(point, salt)] = true
		assert_eq(
			seen.size(), DialogueCatalog.lines_for(point).size(),
			"%s reaches every variant" % point
		)


func test_an_unknown_point_speaks_nothing() -> void:
	assert_false(DialogueCatalog.has_point("diplomatic/never_written"))
	assert_eq(DialogueCatalog.line_for("diplomatic/never_written", 3), "")
	assert_eq(DialogueCatalog.category_for("diplomatic/never_written"), "")
	assert_eq(
		DialogueCatalog.mood_for("diplomatic/never_written", 3), DialogueMood.OPEN_MOOD,
		"a missing point falls back to the open face"
	)


func test_the_mood_machine_walks_the_documented_bands() -> void:
	assert_eq(
		DialogueMood.for_offer(0, 0.0, 0), DialogueMood.OPEN_MOOD, "a fresh offer considers"
	)
	assert_eq(DialogueMood.for_offer(3, 1.0, 0), DialogueMood.IMPATIENT, "a long wait tires")
	assert_eq(DialogueMood.for_offer(3, 1.0, 1), DialogueMood.SKEPTICAL, "the seed breaks it")
	assert_eq(DialogueMood.for_offer(0, 1.0, 0), DialogueMood.PLEASED, "generosity pleases")
	assert_eq(DialogueMood.for_offer(0, 1.0, 1), DialogueMood.GRACIOUS, "or graces")
	assert_eq(DialogueMood.for_offer(0, -1.0, 0), DialogueMood.IRRITATED, "a poor offer stings")
	assert_eq(DialogueMood.for_offer(0, -1.0, 1), DialogueMood.DISMISSIVE, "or is dismissed")
	assert_eq(DialogueMood.for_offer(1, 0.2, 0), DialogueMood.CALCULATING, "the middling count")
	assert_eq(DialogueMood.for_offer(1, 0.2, 1), DialogueMood.CONSIDERING, "chews it over")
	assert_eq(DialogueMood.label(DialogueMood.IMPATIENT), "Impatient")


func test_quality_is_the_surplus_over_what_the_offer_requires() -> void:
	assert_eq(DialogueMood.quality(DiplomacyCatalog.ALLIANCE_MIN_SCORE, 51.0), 0.0)
	assert_eq(DialogueMood.quality(92.0, 51.0), 1.0, "well above the floor is a full band")
	assert_eq(DialogueMood.quality(11.0, 51.0), -1.0, "well below it is the other")
	assert_true(DialogueMood.quality(61.0, 51.0) > 0.0)


func test_stall_counts_the_turns_an_offer_has_waited() -> void:
	assert_eq(DialogueMood.stall(4, 4), 0, "a fresh offer waits none")
	assert_eq(DialogueMood.stall(2, 6), 4)
	assert_eq(DialogueMood.stall(9, 6), 0, "a clock that went backwards waits none")


func test_a_declaration_is_spoken_by_the_court_that_makes_it() -> void:
	var event: Dictionary = _event("warDeclared", 6, 0)
	var spoken: Dictionary = DialogueEvents.for_event(state, event, 0)
	assert_eq(int(spoken["speaker"]), 6, "the declaring court answers")
	assert_eq(String(spoken["point"]), "diplomatic/war_declared_by_them")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_DIPLOMATIC)
	assert_true(String(spoken["text"]).length() > 10)


func test_the_declared_upon_court_answers_in_its_own_voice() -> void:
	var event: Dictionary = _event("warDeclared", 0, 6)
	assert_eq(
		String(DialogueEvents.for_event(state, event, 0)["point"]),
		"diplomatic/war_declared_by_you"
	)
	assert_eq(
		int(DialogueEvents.for_event(state, event, 0)["speaker"]), 6,
		"the reader never speaks its own line"
	)


func test_every_voiced_act_has_words_from_the_other_court() -> void:
	for kind: String in VOICED.keys():
		var event: Dictionary = _event(kind, 0, 6)
		var spoken: Dictionary = DialogueEvents.for_event(state, event, 0)
		assert_false(spoken.is_empty(), "%s is voiced" % kind)
		assert_eq(int(spoken["speaker"]), 6, "%s is spoken by the rival" % kind)
		assert_true(String(spoken["text"]).length() > 10, "%s has words" % kind)
		assert_false(String(spoken["text"]).contains("{"), "%s fills its names" % kind)


func test_bookkeeping_acts_stay_out_of_the_courts_mouth() -> void:
	for kind: String in SILENT:
		assert_true(
			DialogueEvents.for_event(state, _event(kind, 0, 6), 0).is_empty(),
			"%s is bookkeeping, not speech" % kind
		)
	assert_true(
		DialogueEvents.for_event(state, _event("notARealKind", 0, 6), 0).is_empty()
	)


func test_a_third_partys_act_is_not_this_pairs_word() -> void:
	assert_true(DialogueEvents.for_event(state, _event("peaceMade", 2, 3), 0).is_empty())


func test_the_newest_voiced_act_leads_the_pair() -> void:
	_declare_war_on_me()
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 6)
	assert_eq(String(spoken["point"]), "diplomatic/war_declared_by_them")
	state.turn = 4
	DiplomacyRules.make_peace(state, 0, 6)
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "diplomatic/peace_made",
		"the newest word is the one on show"
	)


func test_a_quiet_court_still_has_a_word() -> void:
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 6)
	assert_eq(String(spoken["point"]), "reactive/standing_neutral")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_REACTIVE)
	state.relation(0, 6).score = 92.0
	assert_eq(String(DialogueEvents.standing(state, 0, 6)["point"]), "reactive/standing_friendly")
	state.relation(0, 6).score = 2.0
	assert_eq(String(DialogueEvents.standing(state, 0, 6)["point"]), "reactive/standing_cold")
	state.relation(0, 6).score = 60.0
	state.relation(0, 6).formal_alliance = true
	assert_eq(String(DialogueEvents.standing(state, 0, 6)["point"]), "reactive/standing_alliance")
	state.relation(0, 6).formal_alliance = false
	state.relation(0, 6).at_war = true
	assert_eq(String(DialogueEvents.standing(state, 0, 6)["point"]), "reactive/standing_war")


func test_the_sealed_relation_number_never_reaches_the_words() -> void:
	var digits := RegEx.new()
	digits.compile("\\d")
	for score: float in [-60.0, 2.0, 40.0, 92.0]:
		state.relation(0, 6).score = score
		_declare_war_on_me()
		for text: Variant in [
			DialogueEvents.for_pair(state, 0, 6)["text"],
			DialogueEvents.standing(state, 0, 6)["text"],
		]:
			assert_null(digits.search(String(text)), "a line carries no score")
		DiplomacyRules.make_peace(state, 0, 6)


func test_a_stranger_is_masked_in_the_word_of_a_court() -> void:
	var event: Dictionary = {"kind": "firstContact", "a": 0, "b": 9, "turn": 1, "data": {}}
	var spoken: Dictionary = DialogueEvents.for_event(state, event, 0)
	assert_false(spoken.is_empty())
	assert_true(
		String(spoken["text"]).contains(DiplomacyHistory.UNKNOWN_NAME)
		or not String(spoken["text"]).contains(FactionCatalog.name_of(9)),
		"an unmet court is never named"
	)
	assert_false(String(spoken["text"]).contains(FactionCatalog.name_of(9)))


func test_a_negotiation_beat_says_what_is_on_the_table() -> void:
	var alliance: Dictionary = {"from": 2, "kind": "alliance", "stage": "", "turn": 1}
	var spoken: Dictionary = DialogueEvents.for_offer(state, 0, alliance)
	assert_eq(String(spoken["point"]), "negotiation/proposal_alliance")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_NEGOTIATION)
	assert_eq(int(spoken["speaker"]), 2)
	assert_true(String(spoken["text"]).length() > 10)
	assert_eq(
		String(DialogueEvents.for_offer(state, 0, {"from": 2, "kind": "peace", "turn": 1})["point"]),
		"negotiation/proposal_peace"
	)
	assert_eq(
		String(
			DialogueEvents.for_offer(
				state, 0, {"from": 6, "kind": "overture", "stage": "consulate", "turn": 1}
			)["point"]
		),
		"negotiation/proposal_overture"
	)


func test_the_face_of_an_offer_reads_its_wait_and_its_generosity() -> void:
	state.relation(0, 2).score = 92.0
	var fresh: Dictionary = DialogueEvents.for_offer(
		state, 0, {"from": 2, "kind": "alliance", "turn": 1}
	)
	assert_true(
		[DialogueMood.PLEASED, DialogueMood.GRACIOUS].has(String(fresh["mood"])),
		"a rich alliance offer is welcome"
	)
	state.turn = 6
	var stale: Dictionary = DialogueEvents.for_offer(
		state, 0, {"from": 2, "kind": "alliance", "turn": 1}
	)
	assert_true(
		[DialogueMood.IMPATIENT, DialogueMood.SKEPTICAL].has(String(stale["mood"])),
		"five turns of silence tires the envoy"
	)
	state.relation(0, 2).score = 0.0
	var poor: Dictionary = DialogueEvents.for_offer(
		state, 0, {"from": 2, "kind": "peace", "stage": "", "turn": 6}
	)
	assert_true(
		[DialogueMood.IRRITATED, DialogueMood.DISMISSIVE].has(String(poor["mood"])),
		"a poor offer at a cold court stings"
	)
	var late: Dictionary = DialogueEvents.for_offer(
		state, 0, {"from": 2, "kind": "peace", "stage": "", "turn": 1}
	)
	assert_true(
		[DialogueMood.IMPATIENT, DialogueMood.SKEPTICAL].has(String(late["mood"])),
		"the wait speaks louder than the terms"
	)


func test_an_unknown_proposal_kind_has_no_beat() -> void:
	assert_true(
		DialogueEvents.for_offer(state, 0, {"from": 2, "kind": "trade", "turn": 1}).is_empty()
	)
	assert_true(DialogueEvents.for_offer(state, 0, {}).is_empty())
	assert_true(DialogueEvents.for_offer(null, 0, {"from": 2}).is_empty())


func test_the_court_speaks_the_same_words_after_a_save() -> void:
	_declare_war_on_me()
	var before: Dictionary = DialogueEvents.for_pair(state, 0, 6)
	var captured: Dictionary = SaveCourt.capture_diplomacy(state)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(captured)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 6)
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")
	assert_eq(String(after["mood"]), String(before["mood"]))


func test_names_are_masked_before_they_reach_a_line() -> void:
	assert_eq(
		DialogueCatalog.render("{speaker} sends word to {other}.", "Spain", "Genoa"),
		"Spain sends word to Genoa."
	)
	assert_eq(
		DialogueCatalog.render("{other} is named.", DiplomacyHistory.UNKNOWN_NAME, "Spain"),
		"Spain is named."
	)
	var masked: String = DialogueCatalog.render(
		"{other}, is it?", "Genoa", DiplomacyHistory.name_for(state, 0, 9)
	)
	assert_true(masked.contains(DiplomacyHistory.UNKNOWN_NAME), "strangers stay masked")


func test_speaking_never_alters_the_court() -> void:
	_declare_war_on_me()
	var events: int = state.events.size()
	var score: float = state.relation(0, 6).score
	for _turn in 3:
		DialogueEvents.for_pair(state, 0, 6)
		DialogueEvents.standing(state, 0, 6)
		DialogueEvents.for_offer(state, 0, {"from": 6, "kind": "peace", "turn": state.turn})
	assert_eq(state.events.size(), events, "words are never written into the log")
	assert_eq(state.relation(0, 6).score, score, "and never move a relation")


func test_no_court_talks_to_itself() -> void:
	assert_true(DialogueEvents.for_pair(state, 0, 0).is_empty())
	assert_true(DialogueEvents.standing(state, 0, 0).is_empty())
	assert_true(DialogueEvents.for_pair(null, 0, 6).is_empty())


## A battle is an event beat: the court that reads the verdict speaks it
## (wiki: dialogue-and-mood § Design intent — event: battle results; DR-20261111-01).
func test_the_beaten_court_answers_the_field() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	var spoken: Dictionary = DialogueEvents.for_pair(state, 0, 6)
	assert_eq(String(spoken["point"]), "event/field_lost", "the loser owns the loss")
	assert_eq(int(spoken["speaker"]), 6, "the reader never speaks its own line")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT)
	state.events.clear()
	state.record_event("battleFought", 6, 0, {"kind": "field", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/field_won",
		"a beaten reader hears the winner's line"
	)
	state.events.clear()
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/field_won",
		"the court that won the field says so"
	)


func test_a_siege_names_the_part_each_court_played() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/siege_taken",
		"the reader carried the walls and the defender answers"
	)
	state.events.clear()
	state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/siege_held",
		"the walls held against the reader"
	)
	state.events.clear()
	state.record_event("battleFought", 6, 0, {"kind": "siege", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/siege_won",
		"the court that took the town boasts of it"
	)
	state.events.clear()
	state.record_event("battleFought", 6, 0, {"kind": "siege", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/siege_lost",
		"a siege raised is not a wall held"
	)


func test_the_water_answers_to_its_holder() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "sea", "winner": 0})
	assert_eq(String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/sea_lost")
	state.events.clear()
	state.record_event("battleFought", 0, 6, {"kind": "sea", "winner": 6})
	assert_eq(String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/sea_won")


func test_a_battle_without_a_verdict_says_nothing() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": -1})
	assert_true(
		DialogueEvents.for_event(state, state.events[0], 0).is_empty(),
		"a standoff has no winner to speak for"
	)
	assert_true(
		DialogueEvents.for_event(
			state, {"kind": "battleFought", "a": 0, "b": 6, "turn": 1, "data": {}}, 0
		).is_empty(),
		"a beat without a verdict is silent"
	)
	assert_true(
		DialogueEvents.for_event(
			state,
			{"kind": "battleFought", "a": 0, "b": 6, "turn": 1,
			"data": {"kind": "field", "winner": 2}},
			0
		).is_empty(),
		"a third court's verdict is not this pair's word"
	)


func test_a_battle_is_kept_out_of_the_chronicle() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	assert_true(
		DiplomacyHistory.entries(state, 0, 6).is_empty(),
		"the field is the court's word, not a diplomatic act"
	)
	assert_false(DialogueEvents.for_pair(state, 0, 6).is_empty(), "but it is still spoken")


func test_a_battle_leads_the_pair_over_an_older_word() -> void:
	_declare_war_on_me()
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]),
		"diplomatic/war_declared_by_them"
	)
	state.turn = 3
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/field_lost",
		"the newest word is the one on show"
	)


func test_a_battle_is_recorded_only_for_the_reader() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	var count: int = state.events.size()
	assert_true(
		DialogueEvents.record_land_battle(
			state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
		)
	)
	assert_eq(state.events.size(), count + 1, "the reader's own fight is kept")
	assert_false(
		DialogueEvents.record_land_battle(
			state, _land_battle(2, 3, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
		),
		"a fight the reader was not in is nobody's word"
	)
	assert_false(
		DialogueEvents.record_land_battle(
			state, _land_battle(0, 6, ArmyCombat.Outcome.STALEMATE), 0
		),
		"a standoff writes nothing"
	)
	assert_false(
		DialogueEvents.record_land_battle(
			state, _land_battle(0, 6, ArmyCombat.Outcome.MUTUAL_ANNIHILATION), 0
		),
		"mutual ruin writes nothing"
	)
	assert_eq(state.events.size(), count + 1, "only the verdict was written")


func test_a_siege_is_told_from_a_field_battle_by_the_report() -> void:
	DialogueEvents.record_land_battle(
		state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY, "siege"), 0
	)
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/siege_taken"
	)
	state.events.clear()
	DialogueEvents.record_land_battle(
		state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
	)
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/field_lost"
	)


func test_a_beaten_squadron_that_withdraws_still_lost_the_water() -> void:
	DialogueEvents.record_naval_battle(
		state,
		{
			"attacker": 0, "defender": 6, "outcome": NavalCombat.Outcome.NONE,
			"retreat": {"success": true, "beaten": 6},
		},
		0
	)
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/sea_lost",
		"the court that quit the zone owns the loss"
	)
	state.events.clear()
	DialogueEvents.record_naval_battle(
		state,
		{
			"attacker": 0, "defender": 6,
			"outcome": NavalCombat.Outcome.SIDE2_VICTORY, "retreat": {},
		},
		0
	)
	assert_eq(
		String(DialogueEvents.for_pair(state, 0, 6)["point"]), "event/sea_won"
	)


func test_a_battle_speaks_the_same_words_after_a_save() -> void:
	state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 0})
	var before: Dictionary = DialogueEvents.for_pair(state, 0, 6)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 6)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")


## A war the reader did not start: the rival is the declarer.
func _declare_war_on_me() -> void:
	DiplomacyRules.declare_war(state, 6, 0)


func _event(kind: String, a: int, b: int) -> Dictionary:
	return {"kind": kind, "a": a, "b": b, "turn": 1, "data": VOICED.get(kind, {})}


## The shape ArmyCombat writes, trimmed to the fields the beat reads.
func _land_battle(
	attacker: int, defender: int, outcome: int, mode: String = "field"
) -> Dictionary:
	return {
		"province": 1,
		"attacker": attacker,
		"defender": defender,
		"outcome": outcome,
		"battle_mode": mode,
	}

# --- from test_dialogue_agenda.gd ---
## A rival court's veiled word about its own hidden motive (wiki:
## dialogue-and-mood § Seeding / cadence; hidden-agendas § Playable slice;
## DR-20261111-19). The cadence is one word in seven turns, the crown hears
## nothing before its own dossier already suspects the motive, and the beat
## speaks the same words after a save (REQ-P2-01, REQ-P2-03, REQ-P2-04).


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

# --- from test_dialogue_beats.gd ---
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


func test_the_home_beat_survives_a_save() -> void:
	DialogueHome.record_tech_studied(state, 0, "printing_press")
	var before: Dictionary = DialogueEvents.for_pair(state, 0, 1)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 1)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")


func test_the_map_speaks_the_turn_it_resolved() -> void:
	var play: PlaySession = _battle_play()
	MapPlayCourtVoice.record_turn(
		play, {"research": {"researched": ["saw_mill", "printing_press"]}}
	)
	assert_eq(_play_kind_count(play, DialogueHome.TECH_STUDIED), 1, "one study, one beat")
	assert_eq(
		_play_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"the host at the seat answers"
	)
	assert_eq(
		String(DialogueEvents.for_pair(play.diplomacy, 0, 1)["point"]),
		"event/capital_threatened",
		"the seat speaks last"
	)
	play.army_layer.free()


func test_an_observer_turn_raises_no_beat() -> void:
	var play: PlaySession = _battle_play()
	play.observer_mode = true
	var before: int = play.diplomacy.events.size()
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": ["printing_press"]}})
	assert_eq(play.diplomacy.events.size(), before, "the observer courts speak to nobody")
	play.army_layer.free()


func test_a_seat_off_screen_reads_its_stored_roster() -> void:
	var play: PlaySession = _battle_play()
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
		_play_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"a host off screen still answers"
	)
	assert_eq(_play_kind_count(play, DialogueHome.TECH_STUDIED), 0, "no study, no beat")
	play.army_layer.free()


func test_an_embarked_host_is_at_sea_and_says_nothing() -> void:
	var play: PlaySession = _battle_play()
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
	var play: PlaySession = _battle_play()
	MapPlayCourtVoice.record_turn(play, {"research": "not a report"})
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": "not a list"}})
	assert_eq(_play_kind_count(play, DialogueHome.TECH_STUDIED), 0, "a broken report is not a study")
	play.army_layer.free()


# --- fixtures ---------------------------------------------------------------


## A crown holding a capital in province 0, an enemy host drawn up on it, and
## one declared war — the smallest turn that has something to say.
func _battle_play() -> PlaySession:
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


func _play_kind_count(play: PlaySession, kind: String) -> int:
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
