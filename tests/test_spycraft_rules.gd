extends GdToolsTest
## One boot for espionage: spy networks, the evidence an agent gathers and the
## dossier the court reads (wiki: civilian-units § Spy).

## Merged from test_spy_networks, test_intel_evidence, test_intel_dossier.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const Fixture = preload("res://tests/civilian_fixture.gd")
const intel_dossier_Fixture = preload("res://tests/map_fixture.gd")

const PLAYER: int = 0
const RIVAL: int = 1
const MINOR: int = 6
const intel_evidence_VIEWER: int = 0
const intel_evidence_ENGLAND: int = 1
const intel_evidence_GENOA: int = 6
const intel_evidence_PORTUGAL: int = 3
const intel_dossier_VIEWER: int = 0
const intel_dossier_ENGLAND: int = 1
const intel_dossier_GENOA: int = 6
const intel_dossier_PORTUGAL: int = 3

var _model: MapModel = null
var intel_evidence_state: DiplomacyState
var intel_dossier_state: DiplomacyState

var _suite_setup: String = ""

func _setup_spy_networks() -> void:
	_suite_setup = "spy_networks"
	_model = Fixture.build()

func _setup_intel_evidence() -> void:
	_suite_setup = "intel_evidence"
	intel_evidence_state = DiplomacyState.new()
	intel_evidence_state.initialize(1)

func _setup_intel_dossier() -> void:
	_suite_setup = "intel_dossier"
	intel_dossier_state = DiplomacyState.new()
	intel_dossier_state.initialize(1)

# --- test_spy_networks ---

func _spy(tile: Vector2i, owner: int = PLAYER) -> CivilianState:
	return CivilianState.create(1, owner, "spy", tile)

func test_a_spy_on_a_rival_great_powers_land_shadows_that_court() -> void:
	_setup_spy_networks()
	# (3, 1) sits in province 1, owned by Great Power 1.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])

func test_a_spy_on_the_crowns_own_land_shadows_nobody() -> void:
	_setup_spy_networks()
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(1, 1))], PLAYER
	)
	assert_eq(rivals, [], "own soil is no rival court")

func test_minor_nations_and_tribes_are_not_research_rivals() -> void:
	_setup_spy_networks()
	var model: MapModel = Fixture.build_minor()
	# build_minor() province 1 belongs to Minor Nation 6.
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(2, 1))], PLAYER
	)
	assert_eq(rivals, [], "the wiki names rival Great Powers only")
	assert_eq(model.province_owner(1), MINOR, "fixture sanity")

func test_two_spies_in_one_court_shadow_it_once() -> void:
	_setup_spy_networks()
	var units: Array[CivilianState] = [
		_spy(Vector2i(3, 0)), _spy(Vector2i(3, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(_model, units, PLAYER)
	assert_eq(rivals, [RIVAL], "one court, one share")

func test_each_shadowed_court_counts_its_own_land() -> void:
	_setup_spy_networks()
	var model: MapModel = _three_courts_map()
	var units: Array[CivilianState] = [
		_spy(Vector2i(2, 1)), _spy(Vector2i(4, 1)),
	]
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(model, units, PLAYER)
	assert_eq(rivals, [RIVAL, 2], "ascending, one entry per court")
	assert_eq(SpyNetworks.rival_names(rivals), "England, France")

func test_a_deed_putting_land_in_a_crowns_hands_counts_as_its_land() -> void:
	_setup_spy_networks()
	# An England-owned deed inside Genoa's province makes England the host.
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(Vector2i(3, 1), RIVAL))
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		model, [_spy(Vector2i(3, 1))], PLAYER
	)
	assert_eq(rivals, [RIVAL])

func test_an_offscreen_spy_reads_nothing() -> void:
	_setup_spy_networks()
	var rivals: Array[int] = SpyNetworks.qualifying_rivals(
		_model, [_spy(Vector2i(99, 99))], PLAYER
	)
	assert_eq(rivals, [])

func test_a_boost_lands_only_on_techs_the_shadowed_court_already_knows() -> void:
	_setup_spy_networks()
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"navigation": true, "land_enclosure": false}}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 15)
	assert_eq(SpyNetworks.boost_for(boost, "land_enclosure"), 0, "locked tech")
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 0, "unknown tech")

func test_two_shadowed_courts_stack_on_a_shared_advance() -> void:
	_setup_spy_networks()
	var boost: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{
			RIVAL: {"navigation": true},
			2: {"navigation": true, "saw_mill": true},
		}
	)
	assert_eq(SpyNetworks.boost_for(boost, "navigation"), 30)
	assert_eq(SpyNetworks.boost_for(boost, "saw_mill"), 15)

func test_no_rivals_means_no_boost() -> void:
	_setup_spy_networks()
	assert_true(SpyNetworks.research_boost([], {}).is_empty())
	assert_eq(SpyNetworks.boost_for({}, "navigation"), 0)

## Six tiles wide: the crown's province, England's, then France's.
func _three_courts_map() -> MapModel:
	var model := MapModel.new()
	model.setup(6, 3)
	var mine: Array[Vector2i] = []
	var england: Array[Vector2i] = []
	var france: Array[Vector2i] = []
	for y in 3:
		for x in 6:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 2:
				model.province[model.index_of(x, y)] = 0
				mine.append(tile)
			elif x < 4:
				model.province[model.index_of(x, y)] = 1
				england.append(tile)
			else:
				model.province[model.index_of(x, y)] = 2
				france.append(tile)
	var provinces: Array[ProvinceState] = [
		ProvinceState.create(0, "Cádiz", mine, Vector2(0.5, 1.0), mine.size(), PLAYER, true),
		ProvinceState.create(1, "Plymouth", england, Vector2(2.5, 1.0), england.size(), 1, false),
		ProvinceState.create(2, "Brest", france, Vector2(4.5, 1.0), france.size(), 2, false),
	]
	model.provinces = provinces
	return model

# --- test_intel_evidence ---

func test_evidence_is_capped_and_newest_first_intel_evidence() -> void:
	_setup_intel_evidence()
	for index in 60:
		intel_evidence_state.turn = 1 + index
		intel_evidence_state.record_event("warDeclared", intel_evidence_ENGLAND, intel_evidence_GENOA)
	var entries: Array[Dictionary] = IntelEvidence.collect(intel_evidence_state, null, intel_evidence_VIEWER, intel_evidence_ENGLAND)
	assert_eq(entries.size(), IntelEvidence.EVIDENCE_CAP, "the read is capped at 50")
	assert_eq(int(entries[0]["turn"]), 60, "the newest observation leads")
	assert_eq(int(entries[entries.size() - 1]["turn"]), 11, "the oldest drop first")

func test_an_unmet_court_is_named_not_leaked_intel_evidence() -> void:
	_setup_intel_evidence()
	intel_evidence_state.record_event("callToArmsRefused", intel_evidence_ENGLAND, 9, {"aggressor": intel_evidence_PORTUGAL})
	var text: String = String((IntelEvidence.collect(intel_evidence_state, null, intel_evidence_VIEWER, intel_evidence_ENGLAND)[0])["text"])
	assert_true(text.contains(IntelEvidence.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")

## The despatch narrates the turn that resolved, though the spy reports after the
## calendar has advanced: the observation keeps its own turn.
func test_a_despatch_keeps_the_turn_it_resolved_intel_evidence() -> void:
	_setup_intel_evidence()
	intel_evidence_state.turn = 9
	intel_evidence_state.record_event(
		IntelEvidence.SPY_TECH, intel_evidence_ENGLAND, intel_evidence_VIEWER,
		{"tech": "crop_rotation", IntelEvidence.OBSERVED_TURN: 8}
	)
	var entries: Array[Dictionary] = IntelEvidence.collect(intel_evidence_state, null, intel_evidence_VIEWER, intel_evidence_ENGLAND)
	assert_eq(int(entries[0]["turn"]), 8, "the act belongs to the turn it resolved")
	intel_evidence_state.record_event("warDeclared", intel_evidence_ENGLAND, intel_evidence_GENOA)
	assert_eq(IntelEvidence.turn_of(intel_evidence_state.events[1]), 9, "a plain act keeps the chronicle stamp")

func test_a_viewer_reads_nothing_about_itself() -> void:
	_setup_intel_evidence()
	intel_evidence_state.record_event("warDeclared", intel_evidence_VIEWER, intel_evidence_GENOA)
	assert_true(IntelEvidence.collect(intel_evidence_state, null, intel_evidence_VIEWER, intel_evidence_VIEWER).is_empty())

func test_a_missing_world_counts_no_provinces() -> void:
	_setup_intel_evidence()
	assert_eq(IntelEvidence.provinces(null, intel_evidence_ENGLAND), 0)

# --- test_intel_dossier ---

func test_the_bands_follow_the_dossier_table() -> void:
	_setup_intel_dossier()
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
	_setup_intel_dossier()
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_GENOA)
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(int(scores.get(AiAgenda.WARMONGER, 0)), IntelEvidence.W_WAR, "the act is evidence")
	assert_true(
		(IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["guess"] as Dictionary).is_empty(),
		"one act alone stays below Possible"
	)

func test_breaking_an_alliance_reads_as_a_backstabber() -> void:
	_setup_intel_dossier()
	intel_dossier_state.relation(intel_dossier_ENGLAND, intel_dossier_VIEWER).score = 80.0
	DiplomacyRules.form_alliance(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_VIEWER, DiplomacyRules.DECISION_ACCEPT)
	DiplomacyRules.break_alliance(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_VIEWER)
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(int(scores.get(AiAgenda.BACKSTABBER, 0)), IntelEvidence.W_BREAK_ALLY)
	assert_eq(int(scores.get(AiAgenda.ISOLATIONIST, 0)), IntelEvidence.W_BREAK_ISOLATION)

func test_a_war_on_a_former_ally_reads_as_a_backstabber() -> void:
	_setup_intel_dossier()
	intel_dossier_state.relation(intel_dossier_ENGLAND, intel_dossier_VIEWER).score = 80.0
	DiplomacyRules.form_alliance(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_VIEWER, DiplomacyRules.DECISION_ACCEPT)
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_VIEWER)
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(
		int(scores.get(AiAgenda.BACKSTABBER, 0)),
		IntelEvidence.W_WAR_ON_ALLY,
		"the treaty it held is what the reading weighs"
	)

func test_a_refused_call_to_arms_reads_as_isolationist() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event("callToArmsRefused", intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"aggressor": intel_dossier_VIEWER})
	assert_eq(int(_scores(intel_dossier_ENGLAND).get(AiAgenda.ISOLATIONIST, 0)), IntelEvidence.W_CTA_REFUSED)

func test_a_peace_and_an_intervention_read_as_a_peacemaker() -> void:
	_setup_intel_dossier()
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_GENOA)
	DiplomacyRules.make_peace(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_GENOA)
	intel_dossier_state.record_event("interventionIntervened", intel_dossier_ENGLAND, intel_dossier_GENOA, {"aggressor": intel_dossier_PORTUGAL})
	assert_eq(
		int(_scores(intel_dossier_ENGLAND).get(AiAgenda.PEACEMAKER, 0)),
		IntelEvidence.W_PEACE + IntelEvidence.W_INTERVENED,
		"treaties and interventions add up"
	)

## A court that does not join the war but protests it still reads as a
## peace-seeker, one point, and the dossier names the war it objected to
## (DR-20261110-16).
func test_a_protest_reads_as_a_quieter_peacemaker() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(
		"interventionProtest", intel_dossier_ENGLAND, intel_dossier_PORTUGAL,
		{"target": intel_dossier_GENOA, "penalty": 10.0}
	)
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(int(scores.get(AiAgenda.PEACEMAKER, 0)), IntelEvidence.W_PROTESTED)
	assert_eq(
		String((IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)[0])["text"]),
		"Protested Portugal's war on Genoa."
	)

func test_a_weaker_neighbour_weighs_heavier() -> void:
	_setup_intel_dossier()
	var world: WorldMap = intel_dossier_Fixture.world()
	var pair: Array[int] = _asym_pair()
	var big: int = pair[0]
	var small: int = pair[1]
	intel_dossier_state.record_event("warDeclared", big, small)
	var scores: Dictionary = _scores(big, world)
	assert_eq(
		int(scores.get(AiAgenda.WARMONGER, 0)),
		IntelEvidence.W_WAR + IntelEvidence.W_WEAKER,
		"striking downward is the warmonger's signature"
	)
	assert_eq(int(scores.get(AiAgenda.ENVY, 0)), 0, "no envy in striking a smaller court")

func test_a_stronger_court_is_evidence_of_envy() -> void:
	_setup_intel_dossier()
	var world: WorldMap = intel_dossier_Fixture.world()
	var pair: Array[int] = _asym_pair()
	var big: int = pair[0]
	var small: int = pair[1]
	intel_dossier_state.record_event("warDeclared", small, big)
	assert_eq(
		int(_scores(small, world).get(AiAgenda.ENVY, 0)),
		IntelEvidence.W_STRONGER,
		"a smaller crown striking the one ahead reads as envy"
	)

func test_the_guess_needs_a_possible_band() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event("grantAid", intel_dossier_ENGLAND, intel_dossier_GENOA, {"amount": 1000})
	assert_true((IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["guess"] as Dictionary).is_empty())
	intel_dossier_state.record_event("grantAid", intel_dossier_ENGLAND, intel_dossier_VIEWER, {"amount": 1000})
	intel_dossier_state.record_event("allianceFormed", intel_dossier_ENGLAND, intel_dossier_PORTUGAL)
	intel_dossier_state.record_event("grantAid", intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"amount": 1000})
	var report: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)
	var guess: Dictionary = report["guess"] as Dictionary
	assert_eq(String(guess["id"]), AiAgenda.PEACEMAKER, "three amiable acts reach Possible")
	assert_eq(String(guess["band"]), "Possible")
	assert_eq(int(guess["confidence"]), 25)

func test_evidence_is_capped_and_newest_first_intel_dossier() -> void:
	_setup_intel_dossier()
	for index in 60:
		intel_dossier_state.turn = 1 + index
		intel_dossier_state.record_event("warDeclared", intel_dossier_ENGLAND, intel_dossier_GENOA)
	var entries: Array[Dictionary] = IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)
	assert_eq(entries.size(), IntelEvidence.EVIDENCE_CAP, "the dossier is capped at 50")
	assert_eq(int(entries[0]["turn"]), 60, "the newest observation leads")
	assert_eq(int(entries[entries.size() - 1]["turn"]), 11, "the oldest drop first")

func test_only_the_subjects_own_acts_count() -> void:
	_setup_intel_dossier()
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_PORTUGAL, intel_dossier_GENOA)
	assert_true(_scores(intel_dossier_GENOA).is_empty(), "the target of an act is not its author")
	intel_dossier_state.record_event("warDeclared", intel_dossier_VIEWER, intel_dossier_GENOA)
	assert_true(_scores(intel_dossier_ENGLAND).is_empty(), "another crown's war stays out")

func test_the_reading_never_holds_the_true_agenda() -> void:
	_setup_intel_dossier()
	var report: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)
	for key: String in ["subject", "evidence", "agendas", "guess", "notes"]:
		assert_true(report.has(key), "the report carries %s" % key)
	assert_false(report.has("agenda"), "no true agenda can leak through the report")
	for row: Dictionary in report["agendas"] as Array:
		assert_true(
			["Unknown", "Possible", "Likely", "Almost certain", "Confirmed"].has(String(row["band"])),
			"every row is a band, never a verdict"
		)
	assert_eq((report["agendas"] as Array).size(), AiAgenda.IDS.size(), "all six are weighed")

func test_an_unmet_court_is_named_not_leaked_intel_dossier() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event("callToArmsRefused", intel_dossier_ENGLAND, 9, {"aggressor": intel_dossier_PORTUGAL})
	var text: String = String((IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)[0])["text"])
	assert_true(text.contains(IntelEvidence.UNKNOWN_COURT), "the stranger stays masked")
	assert_false(text.contains("Aztec"), "its name never reaches the page")

func test_the_notes_count_public_behaviour() -> void:
	_setup_intel_dossier()
	var world: WorldMap = intel_dossier_Fixture.world()
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_GENOA)
	intel_dossier_state.record_event("callToArmsRefused", intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"aggressor": intel_dossier_VIEWER})
	var notes: Dictionary = IntelDossier.report(intel_dossier_state, world, intel_dossier_VIEWER, intel_dossier_ENGLAND)["notes"] as Dictionary
	assert_eq(int(notes["war"]), 1)
	assert_eq(int(notes["refused"]), 1)
	assert_eq(
		int(notes["province"]),
		DiplomacyRules.provinces_owned(world, intel_dossier_ENGLAND),
		"the holding count is the shared public score, not a private tally"
	)

func test_offers_aid_and_absorption_are_read_and_spoken() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event("proposalAccepted", intel_dossier_PORTUGAL, intel_dossier_ENGLAND, {"kind": "alliance", "stage": ""})
	intel_dossier_state.record_event("grantAid", intel_dossier_ENGLAND, intel_dossier_GENOA, {"amount": 1000})
	intel_dossier_state.record_event("joinEmpire", intel_dossier_ENGLAND, intel_dossier_GENOA, {})
	intel_dossier_state.record_event("interventionDoNothing", intel_dossier_ENGLAND, intel_dossier_GENOA, {"aggressor": intel_dossier_PORTUGAL})
	var text: String = _joined(IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND))
	assert_true(text.contains("Accepted Portugal's offer of a formal alliance."), text)
	assert_true(text.contains("Stood aside while Portugal made war on Genoa."), text)
	assert_true(text.contains("Sent aid to Genoa."), text)
	assert_true(text.contains("Absorbed Genoa into its empire."), text)
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(
		int(scores.get(AiAgenda.PEACEMAKER, 0)),
		IntelEvidence.W_ACCEPTED_OFFER + IntelEvidence.W_AID,
		"an answered offer and aid both read as peacemaking"
	)
	assert_eq(int(scores.get(AiAgenda.WARMONGER, 0)), IntelEvidence.W_ABSORB)
	assert_eq(int(scores.get(AiAgenda.ISOLATIONIST, 0)), IntelEvidence.W_STOOD_ASIDE)

func test_a_quiet_court_has_an_empty_dossier() -> void:
	_setup_intel_dossier()
	var report: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_GENOA)
	assert_true((report["evidence"] as Array).is_empty())
	assert_true((report["guess"] as Dictionary).is_empty())
	assert_true(_scores(intel_dossier_GENOA).is_empty())

## A study is invisible to every crown but the one that posted the spy, so the
## court report is its only path into the dossier and it reads as tech-catching
## (DR-20261110-25).
func test_a_study_seen_by_a_spy_reads_as_a_tech_thief() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(IntelEvidence.SPY_TECH, intel_dossier_ENGLAND, intel_dossier_VIEWER, {"tech": "crop_rotation"})
	var scores: Dictionary = _scores(intel_dossier_ENGLAND)
	assert_eq(int(scores.get(AiAgenda.TECH_THIEF, 0)), IntelEvidence.W_SPY_TECH)
	assert_eq(
		String(IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)[0]["text"]),
		"Finished Crop Rotation while our spy watched."
	)

## The despatch narrates the turn that resolved, though the spy reports after the
## calendar has advanced: the observation keeps its own turn.
func test_a_despatch_keeps_the_turn_it_resolved_intel_dossier() -> void:
	_setup_intel_dossier()
	intel_dossier_state.turn = 9
	intel_dossier_state.record_event(
		IntelEvidence.SPY_TECH, intel_dossier_ENGLAND, intel_dossier_VIEWER,
		{"tech": "crop_rotation", IntelEvidence.OBSERVED_TURN: 8}
	)
	var entries: Array[Dictionary] = IntelDossier.evidence(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)
	assert_eq(int(entries[0]["turn"]), 8, "the act belongs to the turn it resolved")
	intel_dossier_state.record_event("warDeclared", intel_dossier_ENGLAND, intel_dossier_GENOA)
	assert_eq(IntelEvidence.turn_of(intel_dossier_state.events[1]), 9, "a plain act keeps the chronicle stamp")

func test_only_the_crown_that_posted_the_spy_hears_of_a_study() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(IntelEvidence.SPY_TECH, intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"tech": "crop_rotation"})
	assert_true(_scores(intel_dossier_ENGLAND).is_empty(), "the despatch belongs to the court that paid for it")

func test_two_studies_under_the_spy_eye_reach_possible() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(IntelEvidence.SPY_TECH, intel_dossier_ENGLAND, intel_dossier_VIEWER, {"tech": "crop_rotation"})
	intel_dossier_state.record_event(IntelEvidence.SPY_TECH, intel_dossier_ENGLAND, intel_dossier_VIEWER, {"tech": "cartography"})
	var guess: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["guess"]
	assert_eq(String(guess["band"]), "Possible")
	assert_eq(String(guess["id"]), AiAgenda.TECH_THIEF)
	assert_eq(
		int((IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["notes"])["spy_tech"]), 2
	)

## Each agenda carries the observations that fed it, so the full screen can show
## one timeline per reading (DR-20261110-25).
func test_every_agenda_carries_its_own_timeline() -> void:
	_setup_intel_dossier()
	DiplomacyRules.declare_war(intel_dossier_state, intel_dossier_ENGLAND, intel_dossier_GENOA)
	intel_dossier_state.record_event("grantAid", intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"amount": 100})
	var rows: Array = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["agendas"]
	var war: Dictionary = _row(rows, AiAgenda.WARMONGER)
	var war_line: Array = war["timeline"] as Array
	assert_eq(war_line.size(), 1, "one act feeds the warmonger reading")
	assert_eq(int((war_line[0] as Dictionary)["points"]), IntelEvidence.W_WAR)
	assert_eq(String((war_line[0] as Dictionary)["text"]), "Declared war on Genoa.")
	var peace: Dictionary = _row(rows, AiAgenda.PEACEMAKER)
	assert_eq((peace["timeline"] as Array).size(), 1, "the aid feeds peacemaker")
	assert_true(_row(rows, AiAgenda.ENVY)["timeline"].is_empty())

## Build notes are behaviour, not suspicion: the spy's sightings are counted and
## weigh on no agenda.
func test_build_notes_come_from_the_spy_and_weigh_nothing() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(
		IntelEvidence.SPY_BUILD, intel_dossier_ENGLAND, intel_dossier_VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	var report: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)
	var build: Dictionary = (report["notes"] as Dictionary)["build"]
	assert_eq(int(build["improvement"]), 2)
	assert_eq(int(build["town"]), 1)
	assert_true((report["evidence"] as Array).is_empty(), "a build is a theme, not evidence")
	assert_true(_scores(intel_dossier_ENGLAND).is_empty())

func test_another_crowns_spy_build_notes_stay_out() -> void:
	_setup_intel_dossier()
	intel_dossier_state.record_event(IntelEvidence.SPY_BUILD, intel_dossier_ENGLAND, intel_dossier_PORTUGAL, {"works": {"town": 3}})
	var notes: Dictionary = IntelDossier.report(intel_dossier_state, null, intel_dossier_VIEWER, intel_dossier_ENGLAND)["notes"]
	assert_true((notes["build"] as Dictionary).is_empty())

func _row(rows: Array, id: String) -> Dictionary:
	for raw: Variant in rows:
		var row: Dictionary = raw as Dictionary
		if String(row["id"]) == id:
			return row
	return {}

func _scores(subject: int, world: WorldMap = null) -> Dictionary:
	return IntelDossier.suspicion(IntelDossier.evidence(intel_dossier_state, world, intel_dossier_VIEWER, subject))

func _joined(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append(String(entry["text"]))
	return " | ".join(parts)

## The widest gap in holdings between two courts other than the viewer, read
## from the shared generated world (never mutated).
func _asym_pair() -> Array[int]:
	var world: WorldMap = intel_dossier_Fixture.world()
	var ids: Array[int] = []
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		if id != intel_dossier_VIEWER:
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
