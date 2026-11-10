extends GdToolsTest
## The court dossier (wiki: ai-dossier, hidden-agendas): evidence from observable
## acts, the band table, the best guess, the cap, and the seal on the truth
## (REQ-P2-01, REQ-P2-04).

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const PORTUGAL: int = 3

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
	state.record_event("callToArmsRefused", ENGLAND, PORTUGAL, {"aggressor": VIEWER})
	assert_eq(int(_scores(ENGLAND).get(AiAgenda.ISOLATIONIST, 0)), IntelDossier.W_CTA_REFUSED)


func test_a_peace_and_an_intervention_read_as_a_peacemaker() -> void:
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	DiplomacyRules.make_peace(state, ENGLAND, GENOA)
	state.record_event("interventionIntervened", ENGLAND, GENOA, {"aggressor": PORTUGAL})
	assert_eq(
		int(_scores(ENGLAND).get(AiAgenda.PEACEMAKER, 0)),
		IntelDossier.W_PEACE + IntelDossier.W_INTERVENED,
		"treaties and interventions add up"
	)


## A court that does not join the war but protests it still reads as a
## peace-seeker, one point, and the dossier names the war it objected to
## (DR-20261110-16).
func test_a_protest_reads_as_a_quieter_peacemaker() -> void:
	state.record_event(
		"interventionProtest", ENGLAND, PORTUGAL,
		{"target": GENOA, "penalty": 10.0}
	)
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(int(scores.get(AiAgenda.PEACEMAKER, 0)), IntelDossier.W_PROTESTED)
	assert_eq(
		String((IntelDossier.evidence(state, null, VIEWER, ENGLAND)[0])["text"]),
		"Protested Portugal's war on Genoa."
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
	state.record_event("allianceFormed", ENGLAND, PORTUGAL)
	state.record_event("grantAid", ENGLAND, PORTUGAL, {"amount": 1000})
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
	DiplomacyRules.declare_war(state, PORTUGAL, GENOA)
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
	state.record_event("callToArmsRefused", ENGLAND, 9, {"aggressor": PORTUGAL})
	var text: String = String((IntelDossier.evidence(state, null, VIEWER, ENGLAND)[0])["text"])
	assert_true(text.contains(IntelDossier.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")


func test_the_notes_count_public_behaviour() -> void:
	var world: WorldMap = Fixture.world()
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	state.record_event("callToArmsRefused", ENGLAND, PORTUGAL, {"aggressor": VIEWER})
	var notes: Dictionary = IntelDossier.report(state, world, VIEWER, ENGLAND)["notes"] as Dictionary
	assert_eq(int(notes["war"]), 1)
	assert_eq(int(notes["refused"]), 1)
	assert_eq(
		int(notes["province"]),
		DiplomacyRules.provinces_owned(world, ENGLAND),
		"the holding count is the shared public score, not a private tally"
	)


func test_offers_aid_and_absorption_are_read_and_spoken() -> void:
	state.record_event("proposalAccepted", PORTUGAL, ENGLAND, {"kind": "alliance", "stage": ""})
	state.record_event("grantAid", ENGLAND, GENOA, {"amount": 1000})
	state.record_event("joinEmpire", ENGLAND, GENOA, {})
	state.record_event("interventionDoNothing", ENGLAND, GENOA, {"aggressor": PORTUGAL})
	var text: String = _joined(IntelDossier.evidence(state, null, VIEWER, ENGLAND))
	assert_true(text.contains("Accepted Portugal's offer of a formal alliance."), text)
	assert_true(text.contains("Stood aside while Portugal made war on Genoa."), text)
	assert_true(text.contains("Sent aid to Genoa."), text)
	assert_true(text.contains("Absorbed Genoa into its empire."), text)
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(
		int(scores.get(AiAgenda.PEACEMAKER, 0)),
		IntelDossier.W_ACCEPTED_OFFER + IntelDossier.W_AID,
		"an answered offer and aid both read as peacemaking"
	)
	assert_eq(int(scores.get(AiAgenda.WARMONGER, 0)), IntelDossier.W_ABSORB)
	assert_eq(int(scores.get(AiAgenda.ISOLATIONIST, 0)), IntelDossier.W_STOOD_ASIDE)


func test_a_quiet_court_has_an_empty_dossier() -> void:
	var report: Dictionary = IntelDossier.report(state, null, VIEWER, GENOA)
	assert_true((report["evidence"] as Array).is_empty())
	assert_true((report["guess"] as Dictionary).is_empty())
	assert_true(_scores(GENOA).is_empty())


## A study is invisible to every crown but the one that posted the spy, so the
## court report is its only path into the dossier and it reads as tech-catching
## (DR-20261110-25).
func test_a_study_seen_by_a_spy_reads_as_a_tech_thief() -> void:
	state.record_event(IntelDossier.SPY_TECH, ENGLAND, VIEWER, {"tech": "crop_rotation"})
	var scores: Dictionary = _scores(ENGLAND)
	assert_eq(int(scores.get(AiAgenda.TECH_THIEF, 0)), IntelDossier.W_SPY_TECH)
	assert_eq(
		String(IntelDossier.evidence(state, null, VIEWER, ENGLAND)[0]["text"]),
		"Finished Crop Rotation while our spy watched."
	)


func test_only_the_crown_that_posted_the_spy_hears_of_a_study() -> void:
	state.record_event(IntelDossier.SPY_TECH, ENGLAND, PORTUGAL, {"tech": "crop_rotation"})
	assert_true(_scores(ENGLAND).is_empty(), "the despatch belongs to the court that paid for it")


func test_two_studies_under_the_spy_eye_reach_possible() -> void:
	state.record_event(IntelDossier.SPY_TECH, ENGLAND, VIEWER, {"tech": "crop_rotation"})
	state.record_event(IntelDossier.SPY_TECH, ENGLAND, VIEWER, {"tech": "cartography"})
	var guess: Dictionary = IntelDossier.report(state, null, VIEWER, ENGLAND)["guess"]
	assert_eq(String(guess["band"]), "Possible")
	assert_eq(String(guess["id"]), AiAgenda.TECH_THIEF)
	assert_eq(
		int((IntelDossier.report(state, null, VIEWER, ENGLAND)["notes"])["spy_tech"]), 2
	)


## Each agenda carries the observations that fed it, so the full screen can show
## one timeline per reading (DR-20261110-25).
func test_every_agenda_carries_its_own_timeline() -> void:
	DiplomacyRules.declare_war(state, ENGLAND, GENOA)
	state.record_event("grantAid", ENGLAND, PORTUGAL, {"amount": 100})
	var rows: Array = IntelDossier.report(state, null, VIEWER, ENGLAND)["agendas"]
	var war: Dictionary = _row(rows, AiAgenda.WARMONGER)
	var war_line: Array = war["timeline"] as Array
	assert_eq(war_line.size(), 1, "one act feeds the warmonger reading")
	assert_eq(int((war_line[0] as Dictionary)["points"]), IntelDossier.W_WAR)
	assert_eq(String((war_line[0] as Dictionary)["text"]), "Declared war on Genoa.")
	var peace: Dictionary = _row(rows, AiAgenda.PEACEMAKER)
	assert_eq((peace["timeline"] as Array).size(), 1, "the aid feeds peacemaker")
	assert_true(_row(rows, AiAgenda.ENVY)["timeline"].is_empty())


## Build notes are behaviour, not suspicion: the spy's sightings are counted and
## weigh on no agenda.
func test_build_notes_come_from_the_spy_and_weigh_nothing() -> void:
	state.record_event(
		IntelDossier.SPY_BUILD, ENGLAND, VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	var report: Dictionary = IntelDossier.report(state, null, VIEWER, ENGLAND)
	var build: Dictionary = (report["notes"] as Dictionary)["build"]
	assert_eq(int(build["improvement"]), 2)
	assert_eq(int(build["town"]), 1)
	assert_true((report["evidence"] as Array).is_empty(), "a build is a theme, not evidence")
	assert_true(_scores(ENGLAND).is_empty())


func test_another_crowns_spy_build_notes_stay_out() -> void:
	state.record_event(IntelDossier.SPY_BUILD, ENGLAND, PORTUGAL, {"works": {"town": 3}})
	var notes: Dictionary = IntelDossier.report(state, null, VIEWER, ENGLAND)["notes"]
	assert_true((notes["build"] as Dictionary).is_empty())


func _row(rows: Array, id: String) -> Dictionary:
	for raw: Variant in rows:
		var row: Dictionary = raw as Dictionary
		if String(row["id"]) == id:
			return row
	return {}


func _scores(subject: int, world: WorldMap = null) -> Dictionary:
	return IntelDossier.suspicion(IntelDossier.evidence(state, world, VIEWER, subject))


func _joined(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append(String(entry["text"]))
	return " | ".join(parts)


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
