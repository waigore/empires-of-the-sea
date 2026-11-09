extends GdToolsTest
## The court dossier (wiki: ai-dossier, hidden-agendas): evidence from observable
## acts, the band table, the best guess, the cap, and the seal on the truth
## (REQ-P2-01, REQ-P2-04).

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const VENICE: int = 3

const Fixture = preload("res://tests/map_fixture.gd")

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_the_bands_follow_the_dossier_table() -> void:
	var cases: Dictionary = {
		0: ["Unknown", 0], 2: ["Unknown", 0],
		3: ["Possible", 25], 5: ["Possible", 25],
		6: ["Likely", 60], 8: ["Likely", 60],
		9: ["Almost certain", 85], 10: ["Almost certain", 85],
		11: ["Confirmed", 100], 20: ["Confirmed", 100],
	}
	for score: int in cases.keys():
		var band: Dictionary = IntelDossier.band_for(score)
		assert_eq(String(band["label"]), String(cases[score][0]), "band at %d" % score)
		assert_eq(int(band["confidence"]), int(cases[score][1]), "confidence at %d" % score)
	assert_eq(String(IntelDossier.band_for(-4)["label"]), "Unknown", "a negative never reads")


func test_a_declaration_of_war_reads_as_a_warmonger() -> void:
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(int(scores.get(AiAgenda.WARMONGER, 0)), IntelDossier.W_WAR, "the act is evidence")
	assert_true(
		(IntelDossier.report(state, null, VIEWER, ENGLAND)["guess"] as Dictionary).is_empty(),
		"one act alone stays below Possible"
	)


func test_breaking_an_alliance_reads_as_a_backstabber() -> void:
	state.relation(ENGLAND, VIEWER).score = 80.0
	DiplomacyRules.form_alliance(state, ENGLAND, VIEWER, DiplomacyRules.DECISION_ACCEPT)
	DiplomacyRules.break_alliance(state, ENGLAND, VIEWER)
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(int(scores.get(AiAgenda.BACKSTABBER, 0)), IntelDossier.W_BREAK_ALLY)
	assert_eq(int(scores.get(AiAgenda.ISOLATIONIST, 0)), IntelDossier.W_BREAK_ISOLATION)


func test_a_war_on_a_former_ally_reads_as_a_backstabber() -> void:
	state.relation(ENGLAND, VIEWER).score = 80.0
	DiplomacyRules.form_alliance(state, ENGLAND, VIEWER, DiplomacyRules.DECISION_ACCEPT)
	DiplomacyRules.declare_war(state, ENGLAND, VIEWER)
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(
		int(scores.get(AiAgenda.BACKSTABBER, 0)),
		IntelDossier.W_WAR_ON_ALLY,
		"the treaty it held is what the reading weighs"
	)


func test_a_refused_call_to_arms_reads_as_isolationist() -> void:
	state.record_event("callToArmsRefused", ENGLAND, VENICE, {"aggressor": VIEWER})
	assert_eq(int(_scores(ENGLAND).get(AiAgenda.ISOLATIONIST, 0)), IntelDossier.W_CTA_REFUSED)


func test_a_peace_and_an_intervention_read_as_a_peacemaker() -> void:
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	DiplomacyRules.make_peace(state, ENGLAND, GENOA)
	state.record_event("interventionIntervened", ENGLAND, GENOA, {"aggressor": VENICE})
	assert_eq(
		int(_scores(ENGLAND).get(AiAgenda.PEACEMAKER, 0)),
		IntelDossier.W_PEACE + IntelDossier.W_INTERVENED,
		"treaties and interventions add up"
	)


func test_a_weaker_neighbour_weighs_heavier() -> void:
	var world: WorldMap = Fixture.world()
	var pair: Array[int] = _asym_pair()
	var big: int = pair[0]
	var small: int = pair[1]
	state.record_event("warDeclared", big, small)
	var scores: Dictionary = _scores(big, world)
	assert_eq(
		int(scores.get(AiAgenda.WARMONGER, 0)),
		IntelDossier.W_WAR + IntelDossier.W_WEAKER,
		"striking downward is the warmonger's signature"
	)
	assert_eq(int(scores.get(AiAgenda.ENVY, 0)), 0, "no envy in striking a smaller court")


func test_a_stronger_court_is_evidence_of_envy() -> void:
	var world: WorldMap = Fixture.world()
	var pair: Array[int] = _asym_pair()
	var big: int = pair[0]
	var small: int = pair[1]
	state.record_event("warDeclared", small, big)
	assert_eq(
		int(_scores(small, world).get(AiAgenda.ENVY, 0)),
		IntelDossier.W_STRONGER,
		"a smaller crown striking the one ahead reads as envy"
	)


func test_the_guess_needs_a_possible_band() -> void:
	state.record_event("grantAid", ENGLAND, GENOA, {"amount": 1000})
	assert_true((IntelDossier.report(state, null, VIEWER, ENGLAND)["guess"] as Dictionary).is_empty())
	state.record_event("grantAid", ENGLAND, VIEWER, {"amount": 1000})
	state.record_event("allianceFormed", ENGLAND, VENICE)
	state.record_event("grantAid", ENGLAND, VENICE, {"amount": 1000})
	var report: Dictionary = IntelDossier.report(state, null, VIEWER, ENGLAND)
	var guess: Dictionary = report["guess"] as Dictionary
	assert_eq(String(guess["id"]), AiAgenda.PEACEMAKER, "three amiable acts reach Possible")
	assert_eq(String(guess["band"]), "Possible")
	assert_eq(int(guess["confidence"]), 25)


func test_evidence_is_capped_and_newest_first() -> void:
	for index in 60:
		state.turn = 1 + index
		state.record_event("warDeclared", ENGLAND, GENOA)
	var entries: Array[Dictionary] = IntelDossier.evidence(state, null, VIEWER, ENGLAND)
	assert_eq(entries.size(), IntelDossier.EVIDENCE_CAP, "the dossier is capped at 50")
	assert_eq(int(entries[0]["turn"]), 60, "the newest observation leads")
	assert_eq(int(entries[entries.size() - 1]["turn"]), 11, "the oldest drop first")


func test_only_the_subjects_own_acts_count() -> void:
	DiplomacyRules.declare_war(state, VENICE, GENOA)
	assert_true(_scores(GENOA).is_empty(), "the target of an act is not its author")
	state.record_event("warDeclared", VIEWER, GENOA)
	assert_true(_scores(ENGLAND).is_empty(), "another crown's war stays out")


func test_the_reading_never_holds_the_true_agenda() -> void:
	var report: Dictionary = IntelDossier.report(state, null, VIEWER, ENGLAND)
	for key: String in ["subject", "evidence", "agendas", "guess", "notes"]:
		assert_true(report.has(key), "the report carries %s" % key)
	assert_false(report.has("agenda"), "no true agenda can leak through the report")
	for row: Dictionary in report["agendas"] as Array:
		assert_true(
			["Unknown", "Possible", "Likely", "Almost certain", "Confirmed"].has(String(row["band"])),
			"every row is a band, never a verdict"
		)
	assert_eq((report["agendas"] as Array).size(), AiAgenda.IDS.size(), "all six are weighed")


func test_an_unmet_court_is_named_not_leaked() -> void:
	state.record_event("callToArmsRefused", ENGLAND, 9, {"aggressor": VENICE})
	var text: String = String((IntelDossier.evidence(state, null, VIEWER, ENGLAND)[0])["text"])
	assert_true(text.contains(IntelDossier.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")


func test_the_notes_count_public_behaviour() -> void:
	var world: WorldMap = Fixture.world()
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	state.record_event("callToArmsRefused", ENGLAND, VENICE, {"aggressor": VIEWER})
	var notes: Dictionary = IntelDossier.report(state, world, VIEWER, ENGLAND)["notes"] as Dictionary
	assert_eq(int(notes["war"]), 1)
	assert_eq(int(notes["refused"]), 1)
	assert_eq(
		int(notes["province"]),
		DiplomacyRules.provinces_owned(world, ENGLAND),
		"the holding count is the shared public score, not a private tally"
	)


func test_a_quiet_court_has_an_empty_dossier() -> void:
	var report: Dictionary = IntelDossier.report(state, null, VIEWER, GENOA)
	assert_true((report["evidence"] as Array).is_empty())
	assert_true((report["guess"] as Dictionary).is_empty())
	assert_true(_scores(GENOA).is_empty())


func _scores(subject: int, world: WorldMap = null) -> Dictionary:
	return IntelDossier.suspicion(IntelDossier.evidence(state, world, VIEWER, subject))


## The widest gap in holdings between two courts other than the viewer, read
## from the shared generated world (never mutated).
func _asym_pair() -> Array[int]:
	var world: WorldMap = Fixture.world()
	var ids: Array[int] = []
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		if id != VIEWER:
			ids.append(id)
	ids.sort()
	var big: int = ids[0]
	var small: int = ids[ids.size() - 1]
	var best: int = -1
	for a: int in ids:
		for b: int in ids:
			if a == b:
				continue
			var gap: int = (
				DiplomacyRules.provinces_owned(world, a) - DiplomacyRules.provinces_owned(world, b)
			)
			if gap > best:
				best = gap
				big = a
				small = b
	return [big, small]
