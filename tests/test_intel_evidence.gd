extends GdToolsTest
## The chronicle read behind the court dossier (wiki: ai-dossier): which acts
## count, how the cap and the turn stamp behave, and how a stranger stays masked
## (REQ-P2-01, REQ-P3-01). IntelDossier's own suite covers the reading built on
## top of these observations.

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const PORTUGAL: int = 3

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_evidence_is_capped_and_newest_first() -> void:
	for index in 60:
		state.turn = 1 + index
		state.record_event("warDeclared", ENGLAND, GENOA)
	var entries: Array[Dictionary] = IntelEvidence.collect(state, null, VIEWER, ENGLAND)
	assert_eq(entries.size(), IntelEvidence.EVIDENCE_CAP, "the read is capped at 50")
	assert_eq(int(entries[0]["turn"]), 60, "the newest observation leads")
	assert_eq(int(entries[entries.size() - 1]["turn"]), 11, "the oldest drop first")


func test_an_unmet_court_is_named_not_leaked() -> void:
	state.record_event("callToArmsRefused", ENGLAND, 9, {"aggressor": PORTUGAL})
	var text: String = String((IntelEvidence.collect(state, null, VIEWER, ENGLAND)[0])["text"])
	assert_true(text.contains(IntelEvidence.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")


## The despatch narrates the turn that resolved, though the spy reports after the
## calendar has advanced: the observation keeps its own turn.
func test_a_despatch_keeps_the_turn_it_resolved() -> void:
	state.turn = 9
	state.record_event(
		IntelEvidence.SPY_TECH, ENGLAND, VIEWER,
		{"tech": "crop_rotation", IntelEvidence.OBSERVED_TURN: 8}
	)
	var entries: Array[Dictionary] = IntelEvidence.collect(state, null, VIEWER, ENGLAND)
	assert_eq(int(entries[0]["turn"]), 8, "the act belongs to the turn it resolved")
	state.record_event("warDeclared", ENGLAND, GENOA)
	assert_eq(IntelEvidence.turn_of(state.events[1]), 9, "a plain act keeps the chronicle stamp")


func test_a_viewer_reads_nothing_about_itself() -> void:
	state.record_event("warDeclared", VIEWER, GENOA)
	assert_true(IntelEvidence.collect(state, null, VIEWER, VIEWER).is_empty())


func test_a_missing_world_counts_no_provinces() -> void:
	assert_eq(IntelEvidence.provinces(null, ENGLAND), 0)
