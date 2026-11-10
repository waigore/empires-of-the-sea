extends GdToolsTest
## The court chronicle (wiki: diplomacy § Diplomatic History): pair scope,
## newest-first order, sealed relation numbers, masked strangers, full
## retention and save round-trip (REQ-P2-01, REQ-P2-04).

var state: DiplomacyState

## One synthetic event body per narrated kind, so a new rule event cannot reach
## the panel without a sentence.
const SAMPLES: Dictionary = {
	"warDeclared": {},
	"overturesCleared": {},
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
	"overtureEstablished": {"stage": "embassy"},
	"overtureRejected": {"stage": "consulate"},
	"joinEmpire": {},
	"colonyFormed": {},
	"colonyReleased": {},
	"subsidySet": {"percent": 10},
	"subsidyCancelled": {"percent": 10},
	"ftpSigned": {},
	"ftpRefused": {},
	"ftpRevoked": {},
	"boycottSet": {},
	"boycottRevoked": {},
	"grantAid": {"amount": 1000},
	"firstContact": {},
}


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_the_chronicle_is_pair_scoped_and_newest_first() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	DiplomacyRules.declare_war(state, 2, 7)
	state.turn = 5
	DiplomacyRules.make_peace(state, 0, 6)
	var entries: Array[Dictionary] = DiplomacyHistory.entries(state, 0, 6)
	assert_eq(entries.size(), 2, "only the pair's own two acts")
	assert_eq(int(entries[0]["turn"]), 5, "the newest act leads")
	assert_true(String(entries[0]["text"]).contains("peace"))
	assert_false(_joined(entries).contains("Venice"), "another court's war stays out")


func test_the_chronicle_is_symmetric_for_either_court() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	assert_eq(
		DiplomacyHistory.entries(state, 0, 6).size(),
		DiplomacyHistory.entries(state, 6, 0).size(),
		"the same page is read from either side"
	)


func test_the_calendar_stamp_names_the_year_and_turn() -> void:
	assert_eq(DiplomacyHistory.stamp_for_turn(1), "Year 1500 (Turn 1)")
	assert_eq(
		DiplomacyHistory.stamp_for_turn(12),
		"Year %d (Turn 12)" % TurnTime.year_for_turn(12)
	)


func test_a_stranger_is_masked_in_the_viewing_courts_chronicle() -> void:
	state.record_event("callToArmsAccepted", 0, 6, {"aggressor": 9})
	var line: String = _joined(DiplomacyHistory.entries(state, 0, 6))
	assert_true(line.contains("Spain"), "the viewing crown reads its own name")
	assert_true(line.contains("Genoa"), "a known court is named")
	assert_true(line.contains(DiplomacyHistory.UNKNOWN_NAME), "an unmet court is masked")
	assert_false(line.contains(FactionCatalog.name_of(9)), "its name never leaks")


func test_the_sealed_relation_number_never_reaches_the_page() -> void:
	state.record_event("interventionProtest", 0, 2, {"target": 6})
	var line: String = _joined(DiplomacyHistory.entries(state, 0, 2))
	assert_false(line.contains("relation"))
	var digits := RegEx.new()
	digits.compile("\\d")
	assert_null(digits.search(line), "a chronicle line carries no score")


func test_a_war_records_the_overtures_it_ends() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	DiplomacyRules.declare_war(state, 0, 6)
	assert_true(_has_event("overturesCleared"), "the lost NAP is written down")
	assert_true(
		_joined(DiplomacyHistory.entries(state, 0, 6)).contains("ended the overtures")
	)


func test_a_war_that_ends_no_overture_writes_no_note() -> void:
	# Great Powers hold the auto-embassy, which war keeps: nothing is cleared.
	DiplomacyRules.declare_war(state, 0, 1)
	assert_false(_has_event("overturesCleared"), "no empty note for an untouched treaty")


func test_history_is_never_truncated() -> void:
	for _index in 300:
		state.record_event("firstContact", 0, 6)
	assert_eq(state.events.size(), 300, "a campaign keeps every entry")


func test_the_chronicle_survives_a_save_and_load() -> void:
	DiplomacyRules.declare_war(state, 0, 6)
	var captured: Dictionary = SaveCourt.capture_diplomacy(state)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(captured)
	assert_eq(restored.events.size(), state.events.size())
	assert_eq(
		DiplomacyHistory.entries(restored, 0, 6).size(),
		DiplomacyHistory.entries(state, 0, 6).size(),
		"the page loads back whole"
	)


func test_every_narrated_kind_has_a_sentence() -> void:
	assert_eq(
		SAMPLES.size(), DiplomacyHistory.NARRATED.size(), "the sample table is complete"
	)
	for kind: String in DiplomacyHistory.NARRATED:
		assert_true(SAMPLES.has(kind), "%s has a sample" % kind)
		var text: String = DiplomacyHistory.describe(
			state, _event(kind), FactionCatalog.PLAYER_FACTION
		)
		assert_false(text.is_empty(), "%s is narrated" % kind)
		assert_false(text.contains("%s"), "%s fills every name" % kind)


func test_a_prompt_or_unknown_kind_stays_out_of_the_page() -> void:
	assert_eq(DiplomacyHistory.describe(state, _event("proposalMade"), 0), "")
	assert_eq(DiplomacyHistory.describe(state, _event("callToArmsOffered"), 0), "")
	assert_eq(DiplomacyHistory.describe(state, _event("notARealKind"), 0), "")


func test_no_history_between_equal_courts() -> void:
	assert_true(DiplomacyHistory.entries(state, 0, 0).is_empty())


func _event(kind: String) -> Dictionary:
	var data: Dictionary = SAMPLES.get(kind, {})
	return {"kind": kind, "a": 0, "b": 6, "turn": 1, "data": data}


func _joined(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append(String(entry["text"]))
	return " | ".join(parts)


func _has_event(kind: String) -> bool:
	for event: Dictionary in state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false
