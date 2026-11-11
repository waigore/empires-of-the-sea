extends GdToolsTest
## The court's voice (wiki: dialogue-and-mood, dialogue-management,
## dialogue-content-and-yarn): authored points, a deterministic pick, the mood
## machine's bands, and the rule that words never leave a mark on state
## (REQ-P2-01, REQ-P2-03, REQ-P2-04).

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
			DialogueCatalog.CAT_NEGOTIATION,
			DialogueCatalog.CAT_REACTIVE].has(DialogueCatalog.category_for(point)),
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
