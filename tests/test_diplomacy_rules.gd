extends GdToolsTest
## One boot for the court: relations, history, power, proposals, trade, orders and
## the survey, plus alliances and dialogue (wiki: diplomacy).

## Merged from test_diplomacy_state, test_diplomacy_history, test_diplomacy_power,
## test_diplomacy_proposals, test_diplomacy_trade, test_diplomacy_orders,
## test_diplomacy_survey, test_call_to_arms, test_intervention, test_dialogue_beats,
## test_dialogue_agenda, test_dialogue_rules.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const diplomacy_power_AiFixture = preload("res://tests/ai_fixture.gd")
const diplomacy_proposals_AiFixture = preload("res://tests/ai_fixture.gd")
const diplomacy_survey_Fixture = preload("res://tests/map_fixture.gd")
const _Fixture = preload("res://tests/civilian_fixture.gd")
const dialogue_beats_Fixture = preload("res://tests/army_fixture.gd")

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
	"spyTaken": {"province": "Coro"},
}
const POINTS: Array[String] = [
	"event/tech_studied",
	"event/capital_threatened",
	"event/colony_founded",
]
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
const SILENT: Array[String] = [
	"overturesCleared",
	"joinEmpire",
	"colonyReleased",
	"subsidySet",
	"subsidyCancelled",
	"grantAid",
	"proposalMade",
]

var state: DiplomacyState
var diplomacy_history_state: DiplomacyState
var diplomacy_power_state: DiplomacyState
var panel: DiplomacyPanel
var power: Dictionary = {0: 100, 1: 140, 2: 60, 6: 90}
var diplomacy_proposals_state: DiplomacyState
var diplomacy_trade_state: DiplomacyState
var diplomacy_trade_economy: PlayerEconomy
var diplomacy_orders_state: DiplomacyState
var diplomacy_orders_economy: PlayerEconomy
var _model: MapModel = null
var _state: DiplomacyState = null
var _player: int = FactionCatalog.PLAYER_FACTION
var call_to_arms_state: DiplomacyState
var intervention_state: DiplomacyState
var dialogue_beats_state: DiplomacyState
var dialogue_agenda_state: DiplomacyState
var dialogue_rules_state: DiplomacyState

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"diplomacy_power":
			_teardown_diplomacy_power()
	_suite_setup = ""

func _setup_diplomacy_state() -> void:
	_suite_setup = "diplomacy_state"
	state = DiplomacyState.new()
	state.initialize(3)

func _setup_diplomacy_history() -> void:
	_suite_setup = "diplomacy_history"
	diplomacy_history_state = DiplomacyState.new()
	diplomacy_history_state.initialize(1)

func _setup_diplomacy_power() -> void:
	_suite_setup = "diplomacy_power"
	diplomacy_power_state = DiplomacyState.new()
	diplomacy_power_state.initialize(1)
	panel = DiplomacyPanel.new()
	add_child(panel)

func _setup_diplomacy_proposals() -> void:
	_suite_setup = "diplomacy_proposals"
	diplomacy_proposals_state = DiplomacyState.new()
	diplomacy_proposals_state.initialize(1)

func _setup_diplomacy_trade() -> void:
	_suite_setup = "diplomacy_trade"
	diplomacy_trade_state = DiplomacyState.new()
	diplomacy_trade_state.initialize(1)
	diplomacy_trade_economy = PlayerEconomy.starting()

func _setup_diplomacy_orders() -> void:
	_suite_setup = "diplomacy_orders"
	diplomacy_orders_state = DiplomacyState.new()
	diplomacy_orders_state.initialize(1)
	diplomacy_orders_economy = PlayerEconomy.starting()
	diplomacy_orders_economy.tech_unlocked = {"diplomatic_expertise": true, "empire_building": true}

func _setup_diplomacy_survey() -> void:
	_suite_setup = "diplomacy_survey"
	_model = diplomacy_survey_Fixture.region()
	_state = DiplomacyState.new()
	_state.initialize(1)

func _setup_call_to_arms() -> void:
	_suite_setup = "call_to_arms"
	call_to_arms_state = DiplomacyState.new()
	call_to_arms_state.initialize(1)

func _setup_intervention() -> void:
	_suite_setup = "intervention"
	intervention_state = DiplomacyState.new()
	intervention_state.initialize(1)

func _setup_dialogue_beats() -> void:
	_suite_setup = "dialogue_beats"
	dialogue_beats_state = DiplomacyState.new()
	dialogue_beats_state.initialize(1)

func _setup_dialogue_agenda() -> void:
	_suite_setup = "dialogue_agenda"
	dialogue_agenda_state = DiplomacyState.new()
	dialogue_agenda_state.initialize(1)

func _setup_dialogue_rules() -> void:
	_suite_setup = "dialogue_rules"
	dialogue_rules_state = DiplomacyState.new()
	dialogue_rules_state.initialize(1)

func _teardown_diplomacy_power() -> void:
	if is_instance_valid(panel):
		panel.free()
	panel = null

# --- test_diplomacy_state ---

func test_initializes_same_region_pairs_only() -> void:
	_setup_diplomacy_state()
	# Old World: 6 GPs + 6 Minors = 12 factions -> 66 pairs.
	# New World: 10 Tribes -> 45 pairs. Cross-region pairs stay unknown.
	assert_eq(state.relations.size(), 111)
	assert_true(state.has_relation(0, 5))
	assert_true(state.has_relation(6, 21))
	assert_true(state.has_relation(9, 18))
	assert_false(state.has_relation(0, 9))
	assert_false(state.has_relation(6, 18))
	var record: DiplomacyRelation = state.relation(0, 1)
	assert_false(record.at_war)
	assert_eq(record.score, 50.0)
	assert_eq(record.since_turn, 3)
	assert_eq(record.last_interaction_turn, 3)

func test_great_power_pairs_start_with_a_bilateral_auto_embassy() -> void:
	_setup_diplomacy_state()
	for gp_a: int in FactionCatalog.great_power_ids():
		for gp_b: int in FactionCatalog.great_power_ids():
			if gp_a == gp_b:
				continue
			assert_eq(state.overture(gp_a, gp_b), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)

func test_relation_bands_follow_the_wiki_thresholds() -> void:
	_setup_diplomacy_state()
	assert_eq(DiplomacyCatalog.relation_level(0.0), "Hostile")
	assert_eq(DiplomacyCatalog.relation_level(25.0), "Hostile")
	assert_eq(DiplomacyCatalog.relation_level(25.1), "Neutral")
	assert_eq(DiplomacyCatalog.relation_level(50.0), "Neutral")
	assert_eq(DiplomacyCatalog.relation_level(50.1), "Friendly")
	assert_eq(DiplomacyCatalog.relation_level(75.0), "Friendly")
	assert_eq(DiplomacyCatalog.relation_level(75.1), "Allied")
	assert_eq(DiplomacyCatalog.relation_level(100.0), "Allied")

func test_war_invariant_drops_the_alliance_flag_and_clamps_the_score() -> void:
	_setup_diplomacy_state()
	var record: DiplomacyRelation = DiplomacyRelation.create(1, 0)
	record.formal_alliance = true
	record.at_war = true
	record.score = 140.0
	record.normalize()
	assert_false(record.formal_alliance)
	assert_eq(record.score, 100.0)

func test_ten_step_meter_uses_half_open_bands() -> void:
	_setup_diplomacy_state()
	assert_eq(DiplomacyCatalog.meter_step(0.0), 1)
	assert_eq(DiplomacyCatalog.meter_step(9.9), 1)
	assert_eq(DiplomacyCatalog.meter_step(10.0), 2)
	assert_eq(DiplomacyCatalog.meter_step(50.0), 6)
	assert_eq(DiplomacyCatalog.meter_step(89.9), 9)
	assert_eq(DiplomacyCatalog.meter_step(90.0), 10)
	assert_eq(DiplomacyCatalog.meter_step(100.0), 10)
	assert_eq(DiplomacyCatalog.meter_label(50.0), "Neutral")
	assert_eq(DiplomacyCatalog.meter_label(95.0), "Devoted")

func test_decay_drifts_toward_fifty_and_clamps() -> void:
	_setup_diplomacy_state()
	state.relation(0, 1).score = 40.0
	state.relation(0, 2).score = 80.0
	state.relation(0, 3).score = 48.0
	state.relation(0, 4).score = 52.0
	state.relation(0, 5).score = 50.0
	state.relation(1, 2).score = 30.0
	state.relation(1, 2).at_war = true
	var report: Dictionary = state.end_turn()
	assert_eq(state.relation(0, 1).score, 44.0)
	assert_eq(state.relation(0, 2).score, 76.0)
	assert_eq(state.relation(0, 3).score, 50.0)
	assert_eq(state.relation(0, 4).score, 50.0)
	assert_eq(state.relation(0, 5).score, 50.0)
	assert_eq(state.relation(1, 2).score, 30.0, "war freezes the score")
	assert_eq(int(report["decayed"]), 4)
	assert_eq(state.turn, 4)

func test_event_delta_skips_that_pair_for_the_turn() -> void:
	_setup_diplomacy_state()
	state.relation(0, 1).score = 40.0
	state.relation(0, 2).score = 40.0
	state.apply_delta(0, 1, 5.0, "grantAid")
	state.end_turn()
	assert_eq(state.relation(0, 1).score, 45.0, "no decay after an event delta")
	assert_eq(state.relation(0, 2).score, 44.0, "untouched pairs still drift")

func test_newly_created_relation_skips_its_creation_turn() -> void:
	_setup_diplomacy_state()
	var tribe: int = 9
	state.ensure_relation(0, tribe, state.turn)
	state.relation(0, tribe).score = 40.0
	state.touch(0, tribe, "firstContact")
	state.end_turn()
	assert_eq(state.relation(0, tribe).score, 40.0)

func test_subsidies_survive_while_the_embassy_stands() -> void:
	_setup_diplomacy_state()
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	state.end_turn()
	assert_eq(state.subsidy(0, 6), 10)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NONE)
	var report: Dictionary = state.end_turn()
	assert_eq(state.subsidy(0, 6), 0)
	assert_eq(int(report["subsidies_cancelled"]), 1)

func test_a_subsidy_is_not_a_score_event_for_decay() -> void:
	_setup_diplomacy_state()
	# wiki: diplomacy § Relation Model — only relation-score delta events skip the
	# pair's drift; setting or cancelling a subsidy is score-neutral.
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(0, 7, DiplomacyCatalog.STAGE_EMBASSY)
	state.relation(0, 6).score = 40.0
	state.relation(0, 7).score = 40.0
	state.set_subsidy(0, 6, 10)
	state.set_subsidy(0, 7, 5)
	assert_true(state.cancel_subsidy(0, 7))
	state.end_turn()
	assert_eq(state.subsidy(0, 6), 10, "the embassy keeps the standing subsidy")
	assert_eq(state.relation(0, 6).score, 44.0, "setting a subsidy does not freeze the pair")
	assert_eq(state.relation(0, 7).score, 44.0, "cancelling a subsidy does not freeze the pair")

func test_war_cancels_subsidy_at_phase_close() -> void:
	_setup_diplomacy_state()
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 15)
	state.relation(0, 6).at_war = true
	state.end_turn()
	assert_eq(state.subsidy(0, 6), 0)

func test_absorbed_faction_leaves_no_relations_or_colonies() -> void:
	_setup_diplomacy_state()
	state.set_colony(9, 6)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_subsidy(0, 6, 5)
	state.clear_relations_of(6)
	assert_false(state.has_relation(0, 6))
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.subsidy(0, 6), 0)
	assert_eq(state.colony_of(9), -1)

func test_consulate_gate_reads_the_overture_chain() -> void:
	_setup_diplomacy_state()
	# Wiki: civilian-units § Work Order Summary — explore/prospect in a Minor or
	# Tribe province needs a Consulate (or higher).
	assert_false(DiplomacyRules.has_consulate(null, 0, 6))
	assert_false(DiplomacyRules.has_consulate(state, 0, 6))
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(DiplomacyRules.has_consulate(state, 0, 6))
	assert_true(DiplomacyRules.has_consulate(state, 6, 0), "stage reads both ways")
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NONE)
	state.set_overture(6, 0, DiplomacyCatalog.STAGE_NAP)
	assert_true(DiplomacyRules.has_consulate(state, 0, 6))

# --- test_diplomacy_history ---

func test_the_chronicle_is_pair_scoped_and_newest_first() -> void:
	_setup_diplomacy_history()
	DiplomacyRules.declare_war(diplomacy_history_state, 0, 6)
	DiplomacyRules.declare_war(diplomacy_history_state, 2, 7)
	diplomacy_history_state.turn = 5
	DiplomacyRules.make_peace(diplomacy_history_state, 0, 6)
	var entries: Array[Dictionary] = DiplomacyHistory.entries(diplomacy_history_state, 0, 6)
	assert_eq(entries.size(), 2, "only the pair's own two acts")
	assert_eq(int(entries[0]["turn"]), 5, "the newest act leads")
	assert_true(String(entries[0]["text"]).contains("peace"))
	assert_false(_diplomacy_history_joined(entries).contains("Venice"), "another court's war stays out")

func test_the_chronicle_is_symmetric_for_either_court() -> void:
	_setup_diplomacy_history()
	DiplomacyRules.declare_war(diplomacy_history_state, 0, 6)
	assert_eq(
		DiplomacyHistory.entries(diplomacy_history_state, 0, 6).size(),
		DiplomacyHistory.entries(diplomacy_history_state, 6, 0).size(),
		"the same page is read from either side"
	)

func test_the_calendar_stamp_names_the_year_and_turn() -> void:
	_setup_diplomacy_history()
	assert_eq(DiplomacyHistory.stamp_for_turn(1), "Year 1500 (Turn 1)")
	assert_eq(
		DiplomacyHistory.stamp_for_turn(12),
		"Year %d (Turn 12)" % TurnTime.year_for_turn(12)
	)

func test_a_stranger_is_masked_in_the_viewing_courts_chronicle() -> void:
	_setup_diplomacy_history()
	diplomacy_history_state.record_event("callToArmsAccepted", 0, 6, {"aggressor": 9})
	var line: String = _diplomacy_history_joined(DiplomacyHistory.entries(diplomacy_history_state, 0, 6))
	assert_true(line.contains("Spain"), "the viewing crown reads its own name")
	assert_true(line.contains("Genoa"), "a known court is named")
	assert_true(line.contains(DiplomacyHistory.UNKNOWN_NAME), "an unmet court is masked")
	assert_false(line.contains(FactionCatalog.name_of(9)), "its name never leaks")

func test_the_sealed_relation_number_never_reaches_the_page() -> void:
	_setup_diplomacy_history()
	diplomacy_history_state.record_event("interventionProtest", 0, 2, {"target": 6})
	var line: String = _diplomacy_history_joined(DiplomacyHistory.entries(diplomacy_history_state, 0, 2))
	assert_false(line.contains("relation"))
	var digits := RegEx.new()
	digits.compile("\\d")
	assert_null(digits.search(line), "a chronicle line carries no score")

func test_a_war_records_the_overtures_it_ends() -> void:
	_setup_diplomacy_history()
	diplomacy_history_state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	DiplomacyRules.declare_war(diplomacy_history_state, 0, 6)
	assert_true(_has_event("overturesCleared"), "the lost NAP is written down")
	assert_true(
		_diplomacy_history_joined(DiplomacyHistory.entries(diplomacy_history_state, 0, 6)).contains("ended the overtures")
	)

func test_a_war_that_ends_no_overture_writes_no_note() -> void:
	_setup_diplomacy_history()
	# Great Powers hold the auto-embassy, which war keeps: nothing is cleared.
	DiplomacyRules.declare_war(diplomacy_history_state, 0, 1)
	assert_false(_has_event("overturesCleared"), "no empty note for an untouched treaty")

func test_history_is_never_truncated() -> void:
	_setup_diplomacy_history()
	for _index in 300:
		diplomacy_history_state.record_event("firstContact", 0, 6)
	assert_eq(diplomacy_history_state.events.size(), 300, "a campaign keeps every entry")

func test_the_chronicle_survives_a_save_and_load() -> void:
	_setup_diplomacy_history()
	DiplomacyRules.declare_war(diplomacy_history_state, 0, 6)
	var captured: Dictionary = SaveCourt.capture_diplomacy(diplomacy_history_state)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(captured)
	assert_eq(restored.events.size(), diplomacy_history_state.events.size())
	assert_eq(
		DiplomacyHistory.entries(restored, 0, 6).size(),
		DiplomacyHistory.entries(diplomacy_history_state, 0, 6).size(),
		"the page loads back whole"
	)

func test_every_narrated_kind_has_a_sentence() -> void:
	_setup_diplomacy_history()
	assert_eq(
		SAMPLES.size(), DiplomacyHistory.NARRATED.size(), "the sample table is complete"
	)
	for kind: String in DiplomacyHistory.NARRATED:
		assert_true(SAMPLES.has(kind), "%s has a sample" % kind)
		var text: String = DiplomacyHistory.describe(
			diplomacy_history_state, _diplomacy_history_event(kind), FactionCatalog.PLAYER_FACTION
		)
		assert_false(text.is_empty(), "%s is narrated" % kind)
		assert_false(text.contains("%s"), "%s fills every name" % kind)

func test_a_prompt_or_unknown_kind_stays_out_of_the_page() -> void:
	_setup_diplomacy_history()
	assert_eq(DiplomacyHistory.describe(diplomacy_history_state, _diplomacy_history_event("proposalMade"), 0), "")
	assert_eq(DiplomacyHistory.describe(diplomacy_history_state, _diplomacy_history_event("callToArmsOffered"), 0), "")
	assert_eq(DiplomacyHistory.describe(diplomacy_history_state, _diplomacy_history_event("notARealKind"), 0), "")

func test_no_history_between_equal_courts() -> void:
	_setup_diplomacy_history()
	assert_true(DiplomacyHistory.entries(diplomacy_history_state, 0, 0).is_empty())

func _diplomacy_history_event(kind: String) -> Dictionary:
	var data: Dictionary = SAMPLES.get(kind, {})
	return {"kind": kind, "a": 0, "b": 6, "turn": 1, "data": data}

func _diplomacy_history_joined(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append(String(entry["text"]))
	return " | ".join(parts)

func _has_event(kind: String) -> bool:
	for event: Dictionary in diplomacy_history_state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false

# --- test_diplomacy_power ---

func test_the_power_score_reads_provinces_strength_and_hulls() -> void:
	_setup_diplomacy_power()
	var world: WorldMap = diplomacy_power_AiFixture.world([3, 3, 1])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 3.0}, {3: 2})
	assert_eq(int(scores[3]), 33, "2 provinces × 10 + 3 strength + 2 hulls × 5")
	assert_eq(int(scores[1]), 10, "a crown with no field forces scores on land alone")
	assert_eq(int(scores[4]), 0, "a crown holding nothing scores nothing")

func test_the_score_rounds_a_fractional_order_of_battle() -> void:
	_setup_diplomacy_power()
	var world: WorldMap = diplomacy_power_AiFixture.world([3, 3])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 2.6}, {})
	assert_eq(int(scores[3]), 23, "20 land + round(2.6) strength")

func test_no_world_answers_no_scores() -> void:
	_setup_diplomacy_power()
	assert_true(DiplomacyPower.public_power(null, {0: 3.0}, {0: 1}).is_empty())

func test_the_ratio_and_its_signed_share() -> void:
	_setup_diplomacy_power()
	assert_almost_eq(DiplomacyPower.power_ratio(100, 140), 1.4, 0.0001)
	assert_eq(DiplomacyPower.power_percent(100, 140), 40)
	assert_eq(DiplomacyPower.power_percent(100, 80), -20)
	assert_eq(DiplomacyPower.power_percent(100, 100), 0, "an even court carries no sign")
	assert_almost_eq(DiplomacyPower.power_ratio(0, 50), 50.0, 0.0001)
	assert_eq(DiplomacyPower.power_percent(0, 50), 4900, "a crown with nothing is measured against 1")

func test_a_stronger_crown_reads_red_with_its_share() -> void:
	_setup_diplomacy_power()
	_refresh()
	var mark: Label = _find_label(panel._list, "STRONGER")
	assert_not_null(mark, "the band is named on the row")
	assert_true(String(mark.text).contains("+40%"), "and carries its signed share")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_WAR, "a stronger crown reads red")

func test_a_weaker_crown_reads_green_with_its_share() -> void:
	_setup_diplomacy_power()
	_refresh()
	var mark: Label = _find_label(panel._list, "FRAIL")
	assert_not_null(mark, "a crown at 0.6 of the reader is frail")
	assert_true(String(mark.text).contains("−40%"), "the share is signed down")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)

func test_an_even_crown_reads_green() -> void:
	_setup_diplomacy_power()
	power = {0: 100, 1: 100}
	_refresh()
	var mark: Label = _find_label(panel._list, "EVEN")
	assert_not_null(mark)
	assert_true(String(mark.text).contains("0%"), "an even court carries no sign")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)

func test_a_far_stronger_crown_is_overwhelming() -> void:
	_setup_diplomacy_power()
	power = {0: 100, 1: 160}
	_refresh()
	var mark: Label = _find_label(panel._list, "OVERWHELMING")
	assert_not_null(mark, "a crown half again the reader's size is named so")
	assert_true(String(mark.text).contains("+60%"))

func test_a_minor_nation_carries_no_power_line() -> void:
	_setup_diplomacy_power()
	_refresh()
	var row: VBoxContainer = _row_for("Genoa")
	assert_not_null(row, "the minor's row is in the list")
	assert_eq(row.get_child_count(), 1, "name and stand only: no score for a minor")

func test_a_court_without_scores_shows_no_line() -> void:
	_setup_diplomacy_power()
	power = {}
	_refresh()
	var row: VBoxContainer = _row_for("England")
	assert_not_null(row)
	assert_eq(row.get_child_count(), 1, "a fixture without orders draws nothing")

func test_the_detail_names_the_figures_behind_the_band() -> void:
	_setup_diplomacy_power()
	_refresh()
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Power 140"), "the rival's own score")
	assert_true(_has_text(panel._detail, "yours 100"), "beside the reader's")
	assert_true(_has_text(panel._detail, "Stronger"), "and the band in words")

func _refresh() -> void:
	panel.refresh(diplomacy_power_state, null, 0, 2500, {}, {}, power)

func _row_for(name: String) -> VBoxContainer:
	for child: Node in panel._list.get_children():
		if not child is VBoxContainer:
			continue
		var row := child as VBoxContainer
		if row.get_child_count() > 0 and _has_text(row.get_child(0), name):
			return row
	return null

func _find_label(node: Node, needle: String) -> Label:
	if node is Label and String((node as Label).text).contains(needle):
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, needle)
		if found != null:
			return found
	return null

func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false

# --- test_diplomacy_proposals ---

func test_accepting_an_alliance_proposal_signs_the_treaty() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).score = 80.0
	var queued: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(DiplomacyProposals.has_pending(diplomacy_proposals_state, 0))
	assert_false(diplomacy_proposals_state.relation(0, 2).formal_alliance, "nothing is signed before the answer")
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_true(diplomacy_proposals_state.relation(0, 2).formal_alliance, "the human answer forms the treaty")
	assert_false(DiplomacyProposals.has_pending(diplomacy_proposals_state, 0))
	assert_true(_diplomacy_proposals_event("allianceFormed"))
	assert_true(_diplomacy_proposals_event("proposalAccepted"))

func test_refusing_an_alliance_proposal_leaves_the_courts_at_peace() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(bool(answer["accepted"]))
	assert_false(diplomacy_proposals_state.relation(0, 2).formal_alliance)
	assert_eq(diplomacy_proposals_state.relation(0, 2).score, 80.0, "a refusal costs no relation")
	assert_true(_diplomacy_proposals_event("proposalRefused"))

func test_accepting_an_overture_advances_both_directions_for_free() -> void:
	_setup_diplomacy_proposals()
	var queued: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_eq(diplomacy_proposals_state.overture(2, 0), DiplomacyCatalog.STAGE_NAP)
	assert_eq(diplomacy_proposals_state.overture(0, 2), DiplomacyCatalog.STAGE_NAP)
	assert_true(_diplomacy_proposals_event("overtureEstablished"))
	assert_true(_diplomacy_proposals_event("proposalAccepted"))

func test_refusing_an_overture_keeps_the_previous_stage() -> void:
	_setup_diplomacy_proposals()
	DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_eq(diplomacy_proposals_state.overture(2, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_diplomacy_proposals_event("overtureRejected"))
	assert_true(_diplomacy_proposals_event("proposalRefused"))

func test_only_one_proposal_waits_on_the_court() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).score = 80.0
	diplomacy_proposals_state.relation(0, 3).score = 80.0
	assert_true(DiplomacyProposals.queue(diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_ALLIANCE)["ok"])
	var second: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 3, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(second["ok"], "the court answers one proposal at a time")
	assert_eq(diplomacy_proposals_state.pending_offers.size(), 1)

func test_no_proposal_is_offered_at_war_or_without_a_treaty_band() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).at_war = true
	var war: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(war["ok"])
	diplomacy_proposals_state.relation(0, 2).at_war = false
	diplomacy_proposals_state.relation(0, 2).score = 50.0
	var cool: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(cool["ok"], "the Allied band gates a formal alliance")

func test_accepting_a_peace_proposal_ends_the_war() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).at_war = true
	var queued: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(diplomacy_proposals_state.relation(0, 2).at_war, "the war holds until the court answers")
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_false(diplomacy_proposals_state.relation(0, 2).at_war, "the human answer ends the war")
	assert_false(DiplomacyProposals.has_pending(diplomacy_proposals_state, 0))
	assert_true(_diplomacy_proposals_event("peaceMade"))
	assert_true(_diplomacy_proposals_event("proposalAccepted"))

func test_refusing_a_peace_proposal_keeps_the_war() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 2).at_war = true
	DiplomacyProposals.queue(diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_PEACE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(diplomacy_proposals_state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_true(diplomacy_proposals_state.relation(0, 2).at_war, "a refusal does not end the war")
	assert_eq(diplomacy_proposals_state.relation(0, 2).score, 50.0, "a refusal costs no relation")
	assert_true(_diplomacy_proposals_event("proposalRefused"))
	assert_false(_diplomacy_proposals_event("peaceMade"))

func test_a_peace_proposal_needs_a_war() -> void:
	_setup_diplomacy_proposals()
	var refused: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_false(refused["ok"], "white peace is offered only to a court at war")

func test_only_a_great_power_may_propose() -> void:
	_setup_diplomacy_proposals()
	diplomacy_proposals_state.relation(0, 6).at_war = true
	var minor: Dictionary = DiplomacyProposals.queue(
		diplomacy_proposals_state, null, 6, DiplomacyProposals.KIND_PEACE
	)
	assert_false(minor["ok"], "a Minor keeps no court to treat with")

func test_an_ai_court_proposes_peace_and_waits() -> void:
	_setup_diplomacy_proposals()
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).at_war = true
	var result: Dictionary = AiTurn.run(
		fresh,
		diplomacy_proposals_AiFixture.world([0, 0, 0, 0, 2]),
		AiState.new(),
		2,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(fresh.relation(0, 2).at_war, "nothing is signed during the AI pass")
	assert_eq(fresh.pending_offers.size(), 1, "the offer waits for the human court")
	assert_eq(String(fresh.pending_offers[0]["kind"]), DiplomacyProposals.KIND_PEACE)
	assert_true(String(record["message"]).contains("white peace"))

func test_describe_names_the_offer() -> void:
	_setup_diplomacy_proposals()
	assert_eq(
		DiplomacyProposals.describe(DiplomacyProposals.KIND_ALLIANCE, ""),
		"a formal alliance"
	)
	assert_eq(
		DiplomacyProposals.describe(
			DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
		),
		"the Non-Aggression Pact"
	)
	assert_eq(
		DiplomacyProposals.describe(DiplomacyProposals.KIND_PEACE, ""),
		"a white peace"
	)

func test_a_recent_declaration_does_not_stop_a_fellow_court_making_peace() -> void:
	_setup_diplomacy_proposals()
	# The war cooldown is a Declare War clock only: a court that declared last
	# turn still signs peace once the war stops being worth waging (wiki:
	# diplomacy § Cooldowns, § Configurable Values).
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(1, 2, 1)
	fresh.relation(1, 2).score = 35.0
	DiplomacyRules.declare_war(fresh, 2, 1)
	var ai := AiState.new()
	ai.note_war(2, 1, 1)
	var result: Dictionary = AiTurn.run(
		fresh,
		diplomacy_proposals_AiFixture.world([1, 1, 1, 1, 2]),
		ai,
		2,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	assert_false(fresh.relation(1, 2).at_war, "the fellow court's peace is signed at once")
	assert_eq(fresh.pending_offers.size(), 0, "no human answer is involved")
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(String(record["message"]).contains("Peace is concluded"))

func test_an_ai_court_offers_a_non_aggression_pact_and_waits() -> void:
	_setup_diplomacy_proposals()
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var result: Dictionary = AiTurn.run(
		fresh,
		diplomacy_proposals_AiFixture.world([0, 0, 0, 0, 2]),
		AiState.new(),
		1,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	var action: Dictionary = record["action"]
	assert_eq(String(action["kind"]), AiDiplomacyPlanner.KIND_OVERTURE)
	assert_eq(String(action["stage"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(fresh.pending_offers.size(), 1, "the offer waits for the human court")
	assert_eq(
		fresh.overture(2, 0), DiplomacyCatalog.STAGE_EMBASSY,
		"nothing is signed during the AI pass"
	)
	assert_true(String(record["message"]).contains("proposes"))

func test_an_allied_court_proposes_a_formal_alliance() -> void:
	_setup_diplomacy_proposals()
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).score = 80.0
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var config: AiConfig = AiConfig.build(2, 1500)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL
	var context: Dictionary = diplomacy_proposals_AiFixture.context({0: 10, 2: 10}, {}, {})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, fresh, AiState.new(), diplomacy_proposals_AiFixture.world([2, 2, 2, 2, 1]), 1, context
	)
	assert_eq(
		String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_ALLIANCE,
		"the Allied band and a neutral agenda prefer the treaty"
	)

func test_the_improve_relations_cooldown_blocks_a_second_offer() -> void:
	_setup_diplomacy_proposals()
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var ai := AiState.new()
	ai.note_overture(2, 0, 1)
	var result: Dictionary = AiTurn.run(
		fresh,
		diplomacy_proposals_AiFixture.world([0, 0, 0, 0, 2]),
		ai,
		2,
		0,
		1500,
		{"regiments": {}, "ships": {}}
	)
	var record: Dictionary = _record_for(result["trace"], 2)
	assert_eq(_offer_blocked(record, AiDiplomacyOffers.KIND_OVERTURE), "overture cooldown")
	assert_true(
		fresh.pending_offers.is_empty(),
		"the cooling pair sends no second proposal"
	)

## The refusal the offers module recorded for one order kind.
func _offer_blocked(record: Dictionary, kind: String) -> String:
	var offer: Dictionary = record["candidates"][0].get("offer", {})
	for entry: Dictionary in offer.get("candidates", []):
		if String(entry.get("kind", "")) == kind:
			return String(entry.get("blocked", ""))
	return ""

func _record_for(trace: Array, faction: int) -> Dictionary:
	for record: Dictionary in trace:
		if int(record["faction"]) == faction:
			return record
	return {}

func _diplomacy_proposals_event(kind: String) -> bool:
	for event: Dictionary in diplomacy_proposals_state.events:
		if String(event["kind"]) == kind:
			return true
	return false

# --- test_diplomacy_trade ---

func test_ftp_needs_a_great_power_and_an_embassy() -> void:
	_setup_diplomacy_trade()
	assert_true(DiplomacyTrade.can_establish_ftp(diplomacy_trade_state, 0, 1)["ok"], "GP auto-embassy")
	var minor: Dictionary = DiplomacyTrade.can_establish_ftp(diplomacy_trade_state, 0, 6)
	assert_false(minor["ok"])
	assert_true(String(minor["reason"]).contains("Great Powers"))

func test_ftp_needs_friendly_standing_and_is_bilateral() -> void:
	_setup_diplomacy_trade()
	var refused: Dictionary = DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]), "score 50 is below the pact threshold")
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1))
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 1, 0))

	diplomacy_trade_state.end_turn()
	diplomacy_trade_state.relation(0, 1).score = DiplomacyCatalog.FTP_MIN_SCORE
	var signed: Dictionary = DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed["accepted"]))
	assert_true(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1), "one record serves both directions")
	assert_true(DiplomacyTrade.is_ftp(diplomacy_trade_state, 1, 0))
	assert_true(DiplomacyTrade.ftps_of(diplomacy_trade_state, 0).has(1))

func test_ftp_improves_both_crowns_terms_and_war_ends_it() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	var mine: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 0)
	var theirs: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 1)
	assert_almost_eq(float(mine["buy"]["*"]), 0.95, 0.001, "pact shaves imports")
	assert_almost_eq(float(mine["sell"]["*"]), 1.05, 0.001, "and lifts exports")
	assert_almost_eq(float(theirs["buy"]["*"]), 0.95, 0.001, "both sides gain")

	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 1)
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1), "war severs the pact")
	var after: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 0)
	assert_almost_eq(float(after["buy"]["*"]), 1.0, 0.001, "terms return to the world price")

func test_boycott_needs_a_colony_and_cancels_the_targets_subsidies() -> void:
	_setup_diplomacy_trade()
	var refused: Dictionary = DiplomacyTrade.can_boycott(diplomacy_trade_state, 0, 2)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))

	diplomacy_trade_state.set_colony(9, 0)
	diplomacy_trade_state.ensure_relation(2, 9, diplomacy_trade_state.turn)
	diplomacy_trade_state.set_overture(2, 9, DiplomacyCatalog.STAGE_EMBASSY)
	diplomacy_trade_state.set_subsidy(2, 9, 10)
	var applied: Dictionary = DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2))
	assert_eq(diplomacy_trade_state.subsidy(2, 9), 0, "the boycotted crown loses its subsidy to our colony")
	assert_false(DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)["ok"], "one boycott order per turn")
	diplomacy_trade_state.end_turn()

	var lifted: Dictionary = DiplomacyTrade.revoke_boycott(diplomacy_trade_state, 0, 2)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2))

func test_boycott_worsens_the_targets_terms_and_war_revokes_it() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	var target: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 2)
	assert_almost_eq(float(target["buy"]["*"]), 1.10, 0.001, "boycotted imports cost more")
	assert_almost_eq(float(target["sell"]["*"]), 0.90, 0.001, "and exports earn less")
	var issuer: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 0)
	assert_almost_eq(float(issuer["buy"]["*"]), 1.0, 0.001, "the issuer keeps the world price")

	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 2)
	assert_false(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2), "war auto-revokes")

func test_a_subsidy_sets_rates_on_the_subsidised_courts_goods() -> void:
	_setup_diplomacy_trade()
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	diplomacy_trade_state.ensure_relation(0, 9, diplomacy_trade_state.turn)
	diplomacy_trade_state.set_overture(0, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyAid.set_subsidy(diplomacy_trade_state, 0, 9, 10)
	var terms: Dictionary = DiplomacyTrade.terms_for_court(diplomacy_trade_state, world, 0)
	assert_almost_eq(float(terms["buy"]["timber"]), 1.10, 0.001, "surcharge on their goods")
	assert_almost_eq(float(terms["sell"]["timber"]), 0.90, 0.001, "discount on our goods")
	assert_almost_eq(float(terms["buy"]["*"]), 1.0, 0.001, "only that court's goods move")
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, terms)
	assert_eq(
		market.buy_price("timber", 0),
		roundi(float(market.price("timber")) * 1.10)
	)
	assert_eq(market.buy_price("grain", 0), market.price("grain"))
	assert_eq(market.sell_price("timber", 1), market.price("timber"), "other crowns untouched")
	var direct: int = market.price("timber")
	assert_eq(
		MinorMarket.unit_price(market, "timber", 0),
		roundi(float(direct) * 1.10),
		"the published ask names the court's own rate"
	)

func test_the_market_charges_a_crowns_buy_and_sell_terms() -> void:
	_setup_diplomacy_trade()
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 1.1}, "sell": {"*": 0.9}})
	var base: int = market.price("timber")
	var before: int = diplomacy_trade_economy.treasury
	var bought: Dictionary = market.buy(diplomacy_trade_economy, "timber", 1, 0)
	assert_eq(int(bought["unit_price"]), roundi(float(base) * 1.1))
	assert_eq(diplomacy_trade_economy.treasury, before - int(bought["cost"]))

	diplomacy_trade_economy.stockpile["timber"] = 1
	before = diplomacy_trade_economy.treasury
	var sold: Dictionary = market.sell(diplomacy_trade_economy, "timber", 1, 0)
	assert_eq(int(sold["unit_price"]), roundi(float(base) * 0.9))
	assert_eq(diplomacy_trade_economy.treasury, before + roundi(float(base) * 0.9))
	assert_eq(market.buy_price("timber", 1), base, "a crown without terms pays the world price")

func test_terms_survive_a_save_round_trip() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	diplomacy_trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	var play := PlaySession.new()
	SaveCourt.restore_diplomacy(
		play, {"diplomacy": SaveCourt.capture_diplomacy(diplomacy_trade_state)}
	)
	assert_true(DiplomacyTrade.is_ftp(play.diplomacy, 0, 1))
	assert_true(DiplomacyTrade.is_boycotting(play.diplomacy, 0, 2))

func test_court_orders_offer_trade_actions_and_the_way_back() -> void:
	_setup_diplomacy_trade()
	var options: Array[Dictionary] = DiplomacyOrders.options(diplomacy_trade_state, null, 2500, 0, 1)
	var offer: Dictionary = _diplomacy_trade_first(options, DiplomacyOrders.KIND_FTP)
	assert_eq(String(offer["group"]), DiplomacyOrders.GROUP_TRADE)
	assert_true(String(offer["hint"]).contains("5%"))
	assert_eq(
		String(_diplomacy_trade_first(options, DiplomacyOrders.KIND_BOYCOTT)["group"]),
		DiplomacyOrders.GROUP_TRADE
	)

	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	var after: Array[Dictionary] = DiplomacyOrders.options(diplomacy_trade_state, null, 2500, 0, 1)
	assert_true(_diplomacy_trade_first(after, DiplomacyOrders.KIND_FTP).is_empty())
	assert_false(_diplomacy_trade_first(after, DiplomacyOrders.KIND_REVOKE_FTP).is_empty())

func test_court_orders_sign_and_end_the_pact() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	var signed: Dictionary = DiplomacyOrders.apply(
		diplomacy_trade_state, null, diplomacy_trade_economy, {"kind": DiplomacyOrders.KIND_FTP, "from": 0, "target": 1}
	)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed.get("accepted", false)))
	assert_true(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1))
	diplomacy_trade_state.end_turn()
	var ended: Dictionary = DiplomacyOrders.apply(
		diplomacy_trade_state, null, diplomacy_trade_economy, {"kind": DiplomacyOrders.KIND_REVOKE_FTP, "from": 0, "target": 1}
	)
	assert_true(ended["ok"], ended.get("reason", ""))
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1))

func test_court_orders_impose_and_lift_the_boycott() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.set_colony(9, 0)
	var applied: Dictionary = DiplomacyOrders.apply(
		diplomacy_trade_state, null, diplomacy_trade_economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2))
	diplomacy_trade_state.end_turn()
	var lifted: Dictionary = DiplomacyOrders.apply(
		diplomacy_trade_state,
		null,
		diplomacy_trade_economy,
		{"kind": DiplomacyOrders.KIND_REVOKE_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2))

func test_validation_mirrors_the_trade_gates() -> void:
	_setup_diplomacy_trade()
	var denied: Dictionary = DiplomacyOrders.validate(
		diplomacy_trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
	)
	assert_false(denied["ok"])
	assert_true(String(denied["reason"]).contains("colony"))
	diplomacy_trade_state.set_colony(9, 0)
	assert_true(
		DiplomacyOrders.validate(
			diplomacy_trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
		)["ok"]
	)
	assert_true(
		DiplomacyOrders.validate(
			diplomacy_trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_FTP, "target": 1}
		)["ok"]
	)
	assert_false(
		DiplomacyOrders.validate(
			diplomacy_trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_REVOKE_FTP, "target": 1}
		)["ok"]
	)

func test_a_subsidy_without_an_embassy_explains_itself() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.ensure_relation(0, 6, diplomacy_trade_state.turn)
	var options: Array[Dictionary] = DiplomacyOrders.options(diplomacy_trade_state, null, 2500, 0, 6)
	var subsidy: Dictionary = _diplomacy_trade_first(options, DiplomacyOrders.KIND_SUBSIDY)
	assert_false(bool(subsidy["ok"]))
	assert_true(String(subsidy["hint"]).contains("embassy"))

func test_terms_stay_inside_the_rails() -> void:
	_setup_diplomacy_trade()
	for other: int in [10, 11, 12, 13, 14, 15]:
		diplomacy_trade_state.ftps[diplomacy_trade_state.pair_key(0, other)] = diplomacy_trade_state.turn
	var terms: Dictionary = DiplomacyTrade.faction_terms(diplomacy_trade_state, {}, 0)
	assert_almost_eq(
		float(terms["buy"]["*"]), DiplomacyCatalog.TERMS_BUY_MIN, 0.001, "buy floor"
	)
	assert_almost_eq(
		float(terms["sell"]["*"]), DiplomacyCatalog.TERMS_SELL_MAX, 0.001, "sell cap"
	)
	diplomacy_trade_state.boycotts["2>2"] = diplomacy_trade_state.turn
	assert_true(DiplomacyTrade.boycotts_against(diplomacy_trade_state, 2).is_empty(), "self-boycott ignored")

func test_clearing_terms_returns_the_world_price() -> void:
	_setup_diplomacy_trade()
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 0.9}})
	var clone: WorldMarket = market.copy()
	assert_false(clone.terms_for(0).is_empty(), "a projection keeps the terms")
	market.clear_terms()
	assert_true(market.terms_for(0).is_empty())
	assert_eq(market.buy_price("timber", 0), market.price("timber"))

func test_absorbing_a_crown_clears_its_trade_ties() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	diplomacy_trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	diplomacy_trade_state.clear_relations_of(1)
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1), "the pact dies with the court")
	diplomacy_trade_state.clear_relations_of(2)
	assert_false(DiplomacyTrade.is_boycotting(diplomacy_trade_state, 0, 2), "so does its boycott")

func test_every_trade_gate_says_why_it_refuses() -> void:
	_setup_diplomacy_trade()
	assert_true(
		String(DiplomacyTrade.can_revoke_ftp(diplomacy_trade_state, 0, 1)["reason"]).contains("No favoured")
	)
	assert_false(DiplomacyTrade.revoke_ftp(diplomacy_trade_state, 0, 1)["ok"])
	assert_true(
		String(DiplomacyTrade.can_boycott(diplomacy_trade_state, 0, 0)["reason"]).contains("itself")
	)
	assert_true(
		String(DiplomacyTrade.can_boycott(diplomacy_trade_state, 0, 6)["reason"]).contains("Great Power")
	)
	assert_true(
		String(DiplomacyTrade.can_revoke_boycott(diplomacy_trade_state, 0, 2)["reason"]).contains("No boycott")
	)
	diplomacy_trade_state.set_colony(9, 0)
	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 2)
	assert_true(
		String(DiplomacyTrade.can_boycott(diplomacy_trade_state, 0, 2)["reason"]).contains("at war")
	)
	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 1)
	assert_true(
		String(DiplomacyTrade.can_establish_ftp(diplomacy_trade_state, 0, 1)["reason"]).contains("enemy")
	)

func test_a_court_can_refuse_the_pact() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	var refused: Dictionary = DiplomacyTrade.establish_ftp(
		diplomacy_trade_state, 0, 1, DiplomacyRules.DECISION_REFUSE
	)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]))
	assert_false(DiplomacyTrade.is_ftp(diplomacy_trade_state, 0, 1))

func test_terms_are_published_to_the_market_and_cleared_again() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	var market := WorldMarket.with_default_prices()
	DiplomacyTrade.apply_terms(diplomacy_trade_state, null, market)
	assert_almost_eq(market.term_multiplier(0, "timber", true), 0.95, 0.001)
	assert_almost_eq(market.term_multiplier(1, "timber", false), 1.05, 0.001)
	assert_eq(DiplomacyTrade.market_terms(diplomacy_trade_state, null).size(), 6, "every crown is priced")
	DiplomacyTrade.apply_terms(null, null, market)
	assert_true(market.terms_for(0).is_empty(), "no court means the world price")

func test_a_court_that_grows_nothing_keeps_the_world_price() -> void:
	_setup_diplomacy_trade()
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(diplomacy_trade_state, null, 0)["buy"]["*"]), 1.0, 0.001
	)
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(diplomacy_trade_state, world, 3)["buy"]["*"]), 1.0, 0.001,
		"no produced goods, no extra rate"
	)

func test_war_narrates_the_broken_pact_and_boycott() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(diplomacy_trade_state, 0, 1)
	diplomacy_trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 1)
	DiplomacyRules.declare_war(diplomacy_trade_state, 0, 2)
	var pact: String = _diplomacy_trade_joined(DiplomacyHistory.entries(diplomacy_trade_state, 0, 1))
	assert_true(pact.contains("war ended the favoured trading pact"), pact)
	var boycott: String = _diplomacy_trade_joined(DiplomacyHistory.entries(diplomacy_trade_state, 0, 2))
	assert_true(boycott.contains("war ended Spain's boycott"), boycott)

func test_a_court_order_that_cannot_trade_says_so() -> void:
	_setup_diplomacy_trade()
	var refused: Dictionary = DiplomacyOrders.apply(
		diplomacy_trade_state, null, diplomacy_trade_economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))

func test_a_boycott_bars_aid_and_subsidies_to_the_colony() -> void:
	_setup_diplomacy_trade()
	diplomacy_trade_state.set_colony(9, 0)
	for gp: int in [2, 3]:
		diplomacy_trade_state.ensure_relation(gp, 9, diplomacy_trade_state.turn)
		diplomacy_trade_state.set_overture(gp, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyTrade.boycott(diplomacy_trade_state, 0, 2)
	var aid: Dictionary = DiplomacyAid.can_grant_aid(diplomacy_trade_state, 2, 9, 1000, 10000)
	assert_false(aid["ok"], "the boycotted crown may not aid our colony")
	assert_true(String(aid["reason"]).contains("boycott"))
	assert_false(DiplomacyAid.can_set_subsidy(diplomacy_trade_state, 2, 9, 10)["ok"])
	assert_true(DiplomacyAid.can_grant_aid(diplomacy_trade_state, 3, 9, 1000, 10000)["ok"], "others may")

func _diplomacy_trade_joined(entries: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		lines.append(String(entry["text"]))
	return " ".join(lines)

func _diplomacy_trade_first(options: Array[Dictionary], kind: String) -> Dictionary:
	for option: Dictionary in options:
		if String(option["kind"]) == kind:
			return option
	return {}

func _resource_for(commodity: String) -> int:
	for index in 64:
		if Extraction.commodity_for_resource(index) == commodity:
			return index
	return -1

func _tribe_world(owner: int, resource_index: int) -> WorldMap:
	var model := MapModel.new()
	model.setup(4, 4)
	model.faction_ids = [owner]
	model.provinces.append(
		ProvinceState.create(
			0, "P0", [Vector2i(0, 0)], Vector2(0, 0), 1, owner, false
		)
	)
	model.resource[model.index_of(0, 0)] = resource_index
	var world := WorldMap.new()
	world.add_region(model)
	return world

# --- test_diplomacy_orders ---

func test_declare_war_sets_war_and_keeps_gp_auto_embassy() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 1).score = 60.0
	diplomacy_orders_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _apply("declare_war", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(diplomacy_orders_state.relation(0, 1).at_war)
	assert_eq(diplomacy_orders_state.relation(0, 1).score, 60.0, "war freezes the score")
	assert_eq(diplomacy_orders_state.overture(0, 1), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(diplomacy_orders_state.overture(1, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(String(result["message"]).contains("declares war"))
	var again: Dictionary = _apply("declare_war", 1)
	assert_false(again["ok"])
	assert_true(String(again["reason"]).contains("already at war"))

func test_war_on_a_minor_clears_overtures_and_subsidy() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	diplomacy_orders_state.set_overture(6, 0, DiplomacyCatalog.STAGE_EMBASSY)
	diplomacy_orders_state.set_subsidy(0, 6, 10)
	var result: Dictionary = _apply("declare_war", 6)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(diplomacy_orders_state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(diplomacy_orders_state.overture(6, 0), DiplomacyCatalog.STAGE_NONE)
	assert_eq(diplomacy_orders_state.subsidy(0, 6), 0)

func test_peace_requires_war_and_minors_never_refuse() -> void:
	_setup_diplomacy_orders()
	var early: Dictionary = _apply("offer_peace", 6)
	assert_false(early["ok"])
	_apply("declare_war", 6)
	var peace: Dictionary = _apply("offer_peace", 6)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_true(bool(peace["accepted"]))
	assert_false(diplomacy_orders_state.relation(0, 6).at_war)

func test_hostile_great_power_refuses_white_peace() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 2).score = 20.0
	_apply("declare_war", 2)
	var peace: Dictionary = _apply("offer_peace", 2)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_false(bool(peace["accepted"]))
	assert_true(diplomacy_orders_state.relation(0, 2).at_war)

func test_alliance_clamps_into_the_allied_band() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 1).score = 80.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(diplomacy_orders_state.relation(0, 1).formal_alliance)
	assert_eq(diplomacy_orders_state.relation(0, 1).score, 80.0)
	var duplicate: Dictionary = _apply("alliance", 1)
	assert_false(duplicate["ok"])

func test_alliance_offer_can_be_refused_below_allied_standing() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 1).score = 60.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(bool(result["accepted"]))
	assert_false(diplomacy_orders_state.relation(0, 1).formal_alliance)
	assert_eq(diplomacy_orders_state.relation(0, 1).score, 60.0)

func test_breaking_an_alliance_applies_the_unified_penalty() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 1).score = 76.0
	diplomacy_orders_state.relation(0, 1).formal_alliance = true
	diplomacy_orders_state.relation(0, 2).score = 80.0
	diplomacy_orders_state.relation(0, 3).score = 70.0
	diplomacy_orders_state.relation(0, 4).score = 90.0
	diplomacy_orders_state.relation(0, 5).score = 50.0
	var result: Dictionary = _apply("break_alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(diplomacy_orders_state.relation(0, 1).formal_alliance)
	assert_eq(diplomacy_orders_state.relation(0, 1).score, 26.0)
	assert_eq(diplomacy_orders_state.relation(0, 2).score, 70.0)
	assert_eq(diplomacy_orders_state.relation(0, 3).score, 60.0)
	assert_eq(diplomacy_orders_state.relation(0, 4).score, 80.0)
	assert_eq(diplomacy_orders_state.relation(0, 5).score, 40.0)
	assert_false(_apply("break_alliance", 1)["ok"])

func test_alliance_needs_friendly_standing() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.relation(0, 1).score = 50.0
	var result: Dictionary = _apply("alliance", 1)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("friendly"))

func test_overture_chain_pays_once_per_stage_and_turn() -> void:
	_setup_diplomacy_orders()
	var first: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(first["ok"], first.get("reason", ""))
	assert_eq(diplomacy_orders_economy.treasury, 2000)
	assert_eq(diplomacy_orders_state.overture(0, 6), DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(diplomacy_orders_state.overture(6, 0), DiplomacyCatalog.STAGE_CONSULATE)
	var skipped: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_false(skipped["ok"], "one overture per target per turn")
	diplomacy_orders_state.end_turn()
	var second: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(second["ok"], second.get("reason", ""))
	assert_eq(diplomacy_orders_economy.treasury, 1000)
	diplomacy_orders_state.end_turn()
	var third: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_NAP)
	assert_true(third["ok"], third.get("reason", ""))
	assert_eq(diplomacy_orders_economy.treasury, 1000)
	assert_eq(diplomacy_orders_state.overture(0, 6), DiplomacyCatalog.STAGE_NAP)

func test_embassy_to_a_minor_requires_diplomatic_expertise() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_economy.tech_unlocked = {}
	var consulate: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(consulate["ok"], consulate.get("reason", ""))
	diplomacy_orders_state.end_turn()
	var refused: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("Diplomatic Expertise"))
	diplomacy_orders_economy.tech_unlocked = {"diplomatic_expertise": true}
	var accepted: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(accepted["ok"], accepted.get("reason", ""))

func test_gp_join_empire_requires_empire_building() -> void:
	_setup_diplomacy_orders()
	var world: WorldMap = _world([0, 2, 2, 2])
	diplomacy_orders_state.relation(0, 2).score = 60.0
	diplomacy_orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_economy.treasury = 30000
	diplomacy_orders_economy.tech_unlocked = {"diplomatic_expertise": true}
	var refused: Dictionary = _apply(
		"overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world
	)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("Empire Building"))
	diplomacy_orders_economy.tech_unlocked = {"diplomatic_expertise": true, "empire_building": true}
	var accepted: Dictionary = _apply(
		"overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world
	)
	assert_true(accepted["ok"], accepted.get("reason", ""))

func test_second_overture_to_a_different_target_is_still_legal() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.claim(0, 7, "overture")
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(_apply("overture", 7, DiplomacyCatalog.STAGE_CONSULATE)["ok"])

func test_overtures_are_refused_at_war() -> void:
	_setup_diplomacy_orders()
	_apply("declare_war", 6)
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("at war"))

func test_join_empire_absorbs_a_minor_and_its_provinces() -> void:
	_setup_diplomacy_orders()
	var world: WorldMap = _world([0, 6, 6, 6])
	diplomacy_orders_state.relation(0, 6).score = 60.0
	diplomacy_orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(6, 0, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_economy.treasury = 20000
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(bool(result.get("map_changed", false)))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_eq(DiplomacyRules.provinces_owned(world, 6), 0)
	assert_eq(diplomacy_orders_economy.treasury, 9000)
	assert_false(diplomacy_orders_state.has_relation(0, 6))

func test_join_empire_makes_a_tribe_a_colony_without_transfer() -> void:
	_setup_diplomacy_orders()
	var world: WorldMap = _world([0, 9, 9])
	diplomacy_orders_state.ensure_relation(0, 9, diplomacy_orders_state.turn)
	diplomacy_orders_state.relation(0, 9).score = 60.0
	diplomacy_orders_state.set_overture(0, 9, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(9, 0, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_economy.treasury = 20000
	var result: Dictionary = _apply("overture", 9, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_eq(diplomacy_orders_state.colony_of(9), 0)
	assert_eq(DiplomacyRules.provinces_owned(world, 9), 2)
	assert_eq(diplomacy_orders_economy.treasury, 11000)

func test_join_empire_absorbs_a_nearly_defeated_great_power() -> void:
	_setup_diplomacy_orders()
	var world: WorldMap = _world([0, 2, 2, 2])
	diplomacy_orders_state.relation(0, 2).score = 60.0
	diplomacy_orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_economy.treasury = 30000
	assert_true(DiplomacyRules.nearly_defeated(world, 2))
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_false(diplomacy_orders_state.has_relation(0, 2))
	assert_eq(diplomacy_orders_economy.treasury, 19000)

func test_join_empire_refuses_a_great_power_still_holding_its_capital() -> void:
	_setup_diplomacy_orders()
	var world: WorldMap = _world([0, 2, 2, 2], [1])
	diplomacy_orders_state.relation(0, 2).score = 60.0
	diplomacy_orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	diplomacy_orders_economy.treasury = 30000
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("nearly defeated"))

func test_grant_aid_needs_embassy_step_and_fixed_relation_gain() -> void:
	_setup_diplomacy_orders()
	var refused: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(refused["ok"], "no embassy yet")
	diplomacy_orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var aid: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_true(aid["ok"], aid.get("reason", ""))
	assert_eq(diplomacy_orders_economy.treasury, 1500)
	assert_eq(diplomacy_orders_state.relation(0, 6).score, 55.0)
	var odd: Dictionary = _apply("grant_aid", 6, "", null, 1500)
	assert_false(odd["ok"])

func test_aid_is_refused_to_an_enemy() -> void:
	_setup_diplomacy_orders()
	diplomacy_orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	_apply("declare_war", 6)
	var result: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(result["ok"])

func test_subsidies_are_minor_only_and_five_point_steps() -> void:
	_setup_diplomacy_orders()
	var gp: Dictionary = _apply("set_subsidy", 1, "", null, 10)
	assert_false(gp["ok"])
	diplomacy_orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(_apply("set_subsidy", 6, "", null, 7)["ok"])
	assert_false(_apply("set_subsidy", 6, "", null, 25)["ok"])
	var set_result: Dictionary = _apply("set_subsidy", 6, "", null, 10)
	assert_true(set_result["ok"], set_result.get("reason", ""))
	assert_eq(diplomacy_orders_state.subsidy(0, 6), 10)
	var cancel: Dictionary = _apply("cancel_subsidy", 6)
	assert_true(cancel["ok"], cancel.get("reason", ""))
	assert_eq(diplomacy_orders_state.subsidy(0, 6), 0)

func test_options_offer_war_overture_and_aid_with_reasons() -> void:
	_setup_diplomacy_orders()
	var options: Array[Dictionary] = DiplomacyOrders.options(diplomacy_orders_state, null, 2500, 0, 1)
	var kinds: Array[String] = []
	for option: Dictionary in options:
		kinds.append(String(option["kind"]))
	assert_true(kinds.has("declare_war"))
	assert_true(kinds.has("alliance"))
	assert_true(kinds.has("overture"))
	assert_true(kinds.has("grant_aid"))
	var overture: Dictionary = _diplomacy_orders_first(options, "overture")
	assert_eq(String(overture["arg"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(String(overture["cost_text"]), "free")
	var minor_options: Array[Dictionary] = DiplomacyOrders.options(diplomacy_orders_state, null, 2500, 0, 6)
	var consulate: Dictionary = _diplomacy_orders_first(minor_options, "overture")
	assert_eq(String(consulate["arg"]), DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(String(consulate["cost_text"]), "£500")
	assert_false(bool(_diplomacy_orders_first(minor_options, "grant_aid")["ok"]))

func _apply(
	kind: String, target: int, arg: String = "", world: WorldMap = null, amount: int = 0
) -> Dictionary:
	var order: Dictionary = {"kind": kind, "from": 0, "target": target}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = arg
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = amount
	return DiplomacyOrders.apply(diplomacy_orders_state, world, diplomacy_orders_economy, order, diplomacy_orders_economy.tech_unlocked)

func _diplomacy_orders_first(options: Array[Dictionary], kind: String) -> Dictionary:
	for option: Dictionary in options:
		if String(option["kind"]) == kind:
			return option
	return {}

func _world(owners: Array, capitals: Array = []) -> WorldMap:
	var model := MapModel.new()
	model.setup(8, 8)
	model.faction_ids = [0, 1, 2, 6, 9]
	for index in owners.size():
		var tiles: Array[Vector2i] = [Vector2i(index, 0)]
		model.provinces.append(
			ProvinceState.create(
				index,
				"P%d" % index,
				tiles,
				Vector2(index, 0),
				1,
				int(owners[index]),
				capitals.has(index)
			)
		)
	var world := WorldMap.new()
	world.add_region(model)
	return world

# --- test_diplomacy_survey ---

func test_own_provinces_read_as_self() -> void:
	_setup_diplomacy_survey()
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	var own: Dictionary = _entry(survey, _owned_province())
	assert_eq(String(own["band"]), DiplomacySurvey.BAND_SELF)
	assert_eq(String(own["standing"]), "Your realm")
	assert_gt(int(survey["counts"]["self"]), 0)
	assert_gt(int(survey["tiles"]["self"]), 0)
	assert_false((survey["runs"]["self"] as Array).is_empty())

func test_war_reads_red() -> void:
	_setup_diplomacy_survey()
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.at_war = true
	relation.normalize()
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	var entry: Dictionary = _entry(survey, _province_of(owner))
	assert_eq(String(entry["band"]), DiplomacySurvey.BAND_WAR)
	assert_eq(String(entry["standing"]), "At war")
	assert_gt(int(survey["counts"]["war"]), 0)
	assert_gt(int(survey["tiles"]["war"]), 0)

func test_allied_and_friendly_courts_read_green() -> void:
	_setup_diplomacy_survey()
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(60.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_FRIENDLY
	)
	relation.set_score(80.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_FRIENDLY
	)
	# A formal alliance is green even while the score sits in the neutral band.
	relation.set_score(50.0)
	relation.formal_alliance = true
	assert_eq(String(_entry(
		DiplomacySurvey.snapshot(_model, _state, _player), _province_of(owner)
	)["band"]), DiplomacySurvey.BAND_FRIENDLY)

func test_neutral_covers_mid_scores_and_unmet_courts() -> void:
	_setup_diplomacy_survey()
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(50.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_NEUTRAL
	)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, MapModel.NO_ID),
		DiplomacySurvey.BAND_NEUTRAL
	)
	assert_eq(
		DiplomacySurvey.standing_text(_state, _player, MapModel.NO_ID), "Unclaimed"
	)

func test_a_colony_reads_friendly() -> void:
	_setup_diplomacy_survey()
	var tribe: int = FactionCatalog.tribe_ids()[0]
	_state.set_colony(tribe, _player)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, tribe), DiplomacySurvey.BAND_FRIENDLY
	)
	assert_eq(
		DiplomacySurvey.standing_text(_state, _player, tribe), "Your colony"
	)

func test_unknown_ground_is_never_painted() -> void:
	_setup_diplomacy_survey()
	var visibility := VisibilityModel.new()
	visibility.setup(_model, _player)
	for province: ProvinceState in _model.provinces:
		for tile: Vector2i in province.tiles:
			visibility.lower_to(
				_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
			)
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player, visibility)
	assert_true((survey["provinces"] as Array).is_empty())
	for band: String in DiplomacySurvey.BANDS:
		assert_true((survey["runs"][band] as Array).is_empty())
		assert_eq(int(survey["tiles"][band]), 0)

func test_runs_merge_rows_and_cover_the_tiles() -> void:
	_setup_diplomacy_survey()
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	for band: String in DiplomacySurvey.BANDS:
		var covered: int = 0
		for raw: Variant in survey["runs"][band]:
			var run: Rect2 = raw
			assert_almost_eq(run.size.y, 1.0, 0.001, "one run is one row")
			assert_gt(int(run.size.x), 0)
			covered += int(run.size.x)
			for x in int(run.size.x):
				assert_true(
					_model.is_land(int(run.position.x) + x, int(run.position.y)),
					"a run never paints sea"
				)
		assert_eq(int(survey["tiles"][band]), covered)

func test_standing_text_names_allied_and_neutral() -> void:
	_setup_diplomacy_survey()
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(80.0)
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Friendly")
	relation.formal_alliance = true
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Allied")
	relation.formal_alliance = false
	relation.set_score(50.0)
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Neutral")

func _owned_province() -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner == _player:
			return province.id
	return -1

func _foreign_owner() -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner != _player and province.owner != MapModel.NO_ID:
			return province.owner
	return MapModel.NO_ID

func _province_of(owner: int) -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner == owner:
			return province.id
	return -1

func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}

# --- test_call_to_arms ---

func test_formal_ally_is_called_and_joins_at_fifty_or_better() -> void:
	_setup_call_to_arms()
	_ally(1, 2, 80.0)
	var war: Dictionary = DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_true(war["ok"], war.get("reason", ""))
	assert_true(call_to_arms_state.relation(1, 3).at_war, "England joins the war on Portugal")
	assert_true(_call_to_arms_event("callToArmsAccepted"), "the answer is recorded in history")
	assert_eq(call_to_arms_state.pending_calls.size(), 0, "AI allies need no consent prompt")

func test_informal_allied_band_alone_never_calls() -> void:
	_setup_call_to_arms()
	call_to_arms_state.relation(1, 2).score = 90.0
	assert_false(call_to_arms_state.relation(1, 2).formal_alliance)
	CallToArms.freeze_alliances(call_to_arms_state)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_false(call_to_arms_state.relation(1, 3).at_war, "no treaty, no obligation")
	assert_false(_call_to_arms_event("callToArmsAccepted"))

func test_alliance_signed_this_turn_never_calls() -> void:
	_setup_call_to_arms()
	call_to_arms_state.relation(1, 2).formal_alliance = true
	call_to_arms_state.relation(1, 2).score = 80.0
	# No snapshot: the treaty was signed after the preceding turn closed.
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_false(call_to_arms_state.relation(1, 3).at_war)

func test_end_turn_freezes_alliances_for_the_next_turn() -> void:
	_setup_call_to_arms()
	call_to_arms_state.relation(1, 2).formal_alliance = true
	call_to_arms_state.relation(1, 2).score = 80.0
	call_to_arms_state.end_turn()
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_true(call_to_arms_state.relation(1, 3).at_war)

func test_ai_ally_refuses_below_fifty_and_breaks_the_treaty() -> void:
	_setup_call_to_arms()
	_ally(1, 2, 40.0)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_false(call_to_arms_state.relation(1, 3).at_war)
	assert_false(call_to_arms_state.relation(1, 2).formal_alliance)
	assert_eq(call_to_arms_state.relation(1, 2).score, 0.0, "−50 clamps at zero")
	assert_eq(call_to_arms_state.relation(1, 0).score, 40.0, "−10 cascade to another GP")
	assert_eq(call_to_arms_state.relation(1, 4).score, 40.0)
	assert_eq(call_to_arms_state.relation(1, 5).score, 40.0)
	assert_eq(call_to_arms_state.relation(1, 3).score, 50.0, "the aggressor is exempt")
	assert_true(_call_to_arms_event("allianceBroken"))
	assert_true(_call_to_arms_event("callToArmsRefused"))

func test_human_call_waits_for_consent() -> void:
	_setup_call_to_arms()
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(call_to_arms_state, 0)
	assert_false(call.is_empty(), "the human court is asked")
	assert_eq(int(call["aggressor"]), 3)
	assert_eq(int(call["defender"]), 2)
	assert_false(call_to_arms_state.relation(0, 3).at_war, "no war until the player answers")
	assert_true(CallToArms.has_pending(call_to_arms_state, 0))
	var answer: Dictionary = CallToArms.resolve_human(call_to_arms_state, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(call_to_arms_state.relation(0, 3).at_war, "joining means war on the aggressor")
	assert_true(call_to_arms_state.relation(0, 2).formal_alliance, "the alliance stands")
	assert_false(CallToArms.has_pending(call_to_arms_state, 0))
	assert_true(_call_to_arms_event("callToArmsAccepted"))

## The stakes line the court reads: the war it joins and the unified penalty a
## refusal costs (wiki: diplomacy § Alliances § Mutual defence, § Breaking an
## alliance).
func test_the_offer_names_what_each_answer_costs() -> void:
	_setup_call_to_arms()
	_ally(0, 2, 80.0)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	var call: Dictionary = CallToArms.pending_call_for(call_to_arms_state, 0)
	assert_false(call.is_empty(), "the court is asked")
	var text: String = CallToArms.offer_text(call)
	assert_true(text.contains("war against Portugal"), text)
	assert_true(text.contains("−50 with France"), text)
	assert_true(text.contains("−10 with every other Great Power"), text)

func test_human_join_cancels_subsidies_with_the_aggressor() -> void:
	_setup_call_to_arms()
	_ally(0, 2, 80.0)
	call_to_arms_state.set_subsidy(0, 3, 10)
	call_to_arms_state.set_subsidy(3, 0, 5)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	CallToArms.resolve_human(call_to_arms_state, true)
	assert_eq(call_to_arms_state.subsidy(0, 3), 0)
	assert_eq(call_to_arms_state.subsidy(3, 0), 0)

func test_human_refusal_applies_the_unified_penalty() -> void:
	_setup_call_to_arms()
	_ally(0, 2, 90.0)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	var answer: Dictionary = CallToArms.resolve_human(call_to_arms_state, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(call_to_arms_state.relation(0, 2).formal_alliance)
	assert_eq(call_to_arms_state.relation(0, 2).score, 40.0, "−50 with the abandoned ally")
	assert_eq(call_to_arms_state.relation(0, 1).score, 40.0, "−10 cascade")
	assert_eq(call_to_arms_state.relation(0, 4).score, 40.0)
	assert_eq(call_to_arms_state.relation(0, 5).score, 40.0)
	assert_eq(call_to_arms_state.relation(0, 3).score, 50.0, "the aggressor is exempt")
	assert_false(call_to_arms_state.relation(0, 3).at_war)
	assert_true(_call_to_arms_event("allianceBroken"))
	assert_true(_call_to_arms_event("callToArmsRefused"))

func test_ally_already_at_war_with_the_aggressor_is_not_called() -> void:
	_setup_call_to_arms()
	call_to_arms_state.relation(1, 3).at_war = true
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(call_to_arms_state, 3, 2)
	assert_eq(CallToArms.candidates(call_to_arms_state, 3, 2), [] as Array[int])
	assert_false(_call_to_arms_event("callToArmsAccepted"))

func test_declaring_on_a_minor_never_calls_allies() -> void:
	_setup_call_to_arms()
	_ally(1, 2, 80.0)
	DiplomacyRules.declare_war(call_to_arms_state, 0, 6)
	assert_eq(CallToArms.candidates(call_to_arms_state, 0, 6), [] as Array[int])
	assert_false(CallToArms.has_pending(call_to_arms_state, 0))

func test_one_call_per_aggressor_and_defender_pair() -> void:
	_setup_call_to_arms()
	assert_true(CallToArms.queue_human_call(call_to_arms_state, 3, 2, 0))
	assert_false(CallToArms.queue_human_call(call_to_arms_state, 3, 2, 0), "the same pair never asks twice")
	assert_eq(call_to_arms_state.pending_calls.size(), 1)

func test_answering_without_a_waiting_call_is_refused() -> void:
	_setup_call_to_arms()
	var answer: Dictionary = CallToArms.resolve_human(call_to_arms_state, true)
	assert_false(answer["ok"])
	assert_false(call_to_arms_state.relation(0, 3).at_war)

func _ally(a: int, b: int, score: float) -> void:
	var record: DiplomacyRelation = call_to_arms_state.relation(a, b)
	record.formal_alliance = true
	record.score = score
	CallToArms.freeze_alliances(call_to_arms_state)

func _call_to_arms_event(kind: String) -> bool:
	for event: Dictionary in call_to_arms_state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false

# --- test_intervention ---

func test_a_war_between_great_powers_never_invites_intervention() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 2, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(intervention_state, 3, 2), [] as Array[int])
	var war: Dictionary = DiplomacyRules.declare_war(intervention_state, 3, 2)
	assert_eq(war.get("interventions", []), [] as Array[String])

func test_an_embassy_in_the_victim_court_makes_a_candidate() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(Intervention.has_embassy(intervention_state, 1, 6))
	assert_eq(Intervention.candidates(intervention_state, 3, 6), [1] as Array[int])

func test_a_consulate_alone_does_not_qualify() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(Intervention.candidates(intervention_state, 3, 6), [] as Array[int])

func test_nap_and_join_empire_keep_the_embassy() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_NAP)
	intervention_state.set_overture(4, 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE)
	assert_eq(Intervention.candidates(intervention_state, 3, 6), [1, 4] as Array[int])

func test_the_human_court_is_asked_once_per_declaration() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var war: Dictionary = DiplomacyRules.declare_war(intervention_state, 3, 6)
	var offer: Dictionary = Intervention.pending_for(intervention_state, 0)
	assert_false(offer.is_empty(), "the embassy court is asked")
	assert_eq(int(offer["aggressor"]), 3)
	assert_eq(int(offer["target"]), 6)
	assert_true(Intervention.has_pending(intervention_state, 0))
	assert_false(Intervention.queue_human(intervention_state, 3, 6, 0), "the same pair never asks twice")
	assert_eq(intervention_state.pending_interventions.size(), 1)
	assert_false(bool(war.get("interventions", []).is_empty()), "the court is told")

func test_intervening_joins_the_war_and_keeps_the_embassy() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(intervention_state, Intervention.KIND_INTERVENE)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(intervention_state.relation(0, 3).at_war, "war on the aggressor starts immediately")
	assert_eq(intervention_state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(Intervention.has_pending(intervention_state, 0))
	assert_true(_intervention_event("interventionIntervened"))

func test_standing_aside_costs_the_embassy_and_subsidy() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.set_subsidy(0, 6, 10)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(intervention_state, Intervention.KIND_NOTHING)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_eq(intervention_state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(intervention_state.subsidy(0, 6), 0)
	assert_false(intervention_state.relation(0, 3).at_war)
	assert_eq(intervention_state.relation(0, 3).score, 50.0, "standing aside is not a diplomatic act")
	assert_true(_intervention_event("interventionDoNothing"))

## Overtures are two-way: `establish_overture` writes both directions, so
## standing aside must clear both or the reverse record keeps the embassy alive
## for aid and subsidy (wiki: diplomacy § Intervention § Do Nothing).
func test_standing_aside_clears_the_embassy_in_both_directions() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.set_overture(6, 0, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	Intervention.resolve_human(intervention_state, Intervention.KIND_NOTHING)
	assert_eq(intervention_state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(intervention_state.overture(6, 0), DiplomacyCatalog.STAGE_NONE, "the reverse record goes too")
	assert_false(DiplomacyRules.has_embassy(intervention_state, 0, 6), "no embassy survives standing aside")
	assert_false(
		bool(DiplomacyAid.can_grant_aid(intervention_state, 0, 6, 1000, 5000)["ok"]),
		"aid needs a live embassy"
	)

func test_an_ai_standing_aside_also_clears_both_directions() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.set_overture(6, 1, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 6).score = 10.0
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_false(intervention_state.relation(1, 3).at_war, "0% never intervenes")
	assert_eq(intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(intervention_state.overture(6, 1), DiplomacyCatalog.STAGE_NONE, "the reverse record goes too")

func test_protest_penalises_the_aggressor_and_keeps_the_embassy() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	var answer: Dictionary = Intervention.resolve_human(intervention_state, Intervention.KIND_PROTEST)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(intervention_state.relation(0, 3).at_war)
	assert_eq(intervention_state.relation(0, 3).score, 40.0, "−10 protest penalty")
	assert_eq(intervention_state.overture(0, 6), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_intervention_event("interventionProtest"))

func test_propaganda_softens_the_protest() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	Intervention.resolve_human(intervention_state, Intervention.KIND_PROTEST, {"propaganda": true})
	assert_eq(intervention_state.relation(0, 3).score, 45.0, "−5 against a propaganda aggressor")

func test_answering_without_an_offer_is_refused() -> void:
	_setup_intervention()
	var answer: Dictionary = Intervention.resolve_human(
		intervention_state, Intervention.KIND_INTERVENE
	)
	assert_false(answer["ok"])
	assert_false(intervention_state.relation(0, 3).at_war)

func test_ai_chance_follows_the_documented_bands() -> void:
	_setup_intervention()
	assert_eq(Intervention.chance_for(0.0), 0.0)
	assert_eq(Intervention.chance_for(25.0), 0.0)
	assert_eq(Intervention.chance_for(26.0), 0.25)
	assert_eq(Intervention.chance_for(50.0), 0.25)
	assert_eq(Intervention.chance_for(51.0), 0.5)
	assert_eq(Intervention.chance_for(75.0), 0.5)
	assert_eq(Intervention.chance_for(76.0), 0.8)
	assert_eq(Intervention.chance_for(100.0), 0.8)

func test_the_ai_roll_is_a_stable_unit_sample() -> void:
	_setup_intervention()
	var first: float = Intervention.roll(7, 3, 6, 1)
	assert_eq(first, Intervention.roll(7, 3, 6, 1), "replays decide the same way")
	assert_true(first >= 0.0 and first < 1.0)

func test_ai_intervention_follows_the_band() -> void:
	_setup_intervention()
	intervention_state.relation(1, 6).score = 90.0
	var expected: bool = Intervention.roll(intervention_state.turn, 3, 6, 1) < 0.8
	assert_eq(Intervention.ai_intervenes(intervention_state, 1, 3, 6), expected)
	intervention_state.relation(1, 6).score = 10.0
	assert_false(Intervention.ai_intervenes(intervention_state, 1, 3, 6), "0% never intervenes")

func test_a_court_already_at_war_with_the_aggressor_is_not_asked() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 3).at_war = true
	assert_eq(Intervention.candidates(intervention_state, 3, 6), [] as Array[int])

func test_a_tribe_war_can_invite_intervention() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 9, DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(Intervention.candidates(intervention_state, 3, 9), [1] as Array[int])

func test_ai_answers_are_applied_at_the_declaration() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 6).score = 90.0
	var intervenes: bool = Intervention.roll(intervention_state.turn, 3, 6, 1) < 0.8
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_eq(intervention_state.relation(1, 3).at_war, intervenes, "the roll is the documented band")
	if not intervenes:
		assert_eq(
			intervention_state.overture(1, 6),
			DiplomacyCatalog.STAGE_EMBASSY,
			"a caring court protests instead of standing aside"
		)
		assert_eq(intervention_state.relation(1, 3).score, 40.0, "and charges the aggressor for it")

func test_an_absorbed_faction_drops_its_waiting_offer() -> void:
	_setup_intervention()
	intervention_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_true(Intervention.has_pending(intervention_state, 0))
	intervention_state.clear_relations_of(6)
	assert_false(Intervention.has_pending(intervention_state, 0))

## Wiki: diplomacy § GP–Minor Rules § Intervention — the trigger is an Embassy
## with the victim **or** purchased land recorded in its provinces, so a deed
## holder is offered the choice without an embassy.
func test_purchased_land_alone_makes_a_candidate() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(1)
	assert_eq(intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "a deed is not an embassy")
	assert_false(DiplomacyRules.has_embassy(intervention_state, 1, 6))
	assert_eq(Intervention.candidates(intervention_state, 3, 6, world), [1] as Array[int])

func test_purchased_land_and_an_embassy_both_invite_the_same_court_once() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var world: WorldMap = _deed_world(1)
	assert_eq(Intervention.candidates(intervention_state, 3, 6, world), [1] as Array[int])

func test_a_deed_in_a_province_the_victim_lost_does_not_count() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(1)
	world.region(0).provinces[1].owner = 7
	assert_eq(
		Intervention.candidates(intervention_state, 3, 6, world), [] as Array[int],
		"deeds follow the province, not the old owner"
	)

## The declaration path must carry the world, or the deed holder never hears of
## a war declared from the court or by a rival planner (REQ-P2-03).
func test_a_declaration_offers_the_human_deed_holder() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(0)
	var war: Dictionary = DiplomacyRules.declare_war(intervention_state, 3, 6, true, world)
	assert_true(bool(war.get("ok", false)), war.get("reason", ""))
	assert_true(Intervention.has_pending(intervention_state, 0), "the deed holder is asked")
	assert_eq(int(Intervention.pending_for(intervention_state, 0)["aggressor"]), 3)

func test_a_declaration_without_a_world_keeps_the_embassy_trigger() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	# A court that does not care about the victim stands aside, so the cleared
	# embassy proves the declaration reached it without a world to scan.
	intervention_state.relation(1, 6).score = 10.0
	var war: Dictionary = DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_true(bool(war.get("ok", false)), war.get("reason", ""))
	assert_eq(intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "the war clears it")

## A court that cares about the victim (26+) but loses the intervention roll
## protests rather than standing aside: it keeps its embassy and puts a relation
## price on the aggression (DR-20261110-16).
func test_an_ai_that_does_not_intervene_protests_while_it_cares() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 6).score = 30.0
	assert_false(
		Intervention.roll(intervention_state.turn, 3, 6, 1) < 0.25,
		"this turn's roll leaves the court at peace"
	)
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_false(intervention_state.relation(1, 3).at_war, "the court keeps the peace")
	assert_eq(intervention_state.relation(1, 3).score, 40.0, "−10 protest penalty")
	assert_eq(
		intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_EMBASSY, "a protest keeps the embassy"
	)
	assert_true(_intervention_event("interventionProtest"), "the act is on the record")

## The first intervention band is the line: 0–25 is indifference, and the court
## stands aside as it always has (DR-20261110-16).
func test_an_ai_below_the_band_stands_aside() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 6).score = 25.0
	DiplomacyRules.declare_war(intervention_state, 3, 6)
	assert_eq(intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_NONE, "no care, no embassy")
	assert_true(_intervention_event("interventionDoNothing"))
	assert_eq(intervention_state.relation(1, 3).score, 50.0, "standing aside is not a diplomatic act")

func test_ai_protest_policy_follows_the_intervention_band() -> void:
	_setup_intervention()
	intervention_state.relation(1, 6).score = 25.0
	assert_false(Intervention.ai_protests(intervention_state, 1, 6), "0% band stands aside")
	intervention_state.relation(1, 6).score = 26.0
	assert_true(Intervention.ai_protests(intervention_state, 1, 6), "the first band protests")

func test_ai_choice_prefers_the_roll_then_the_protest() -> void:
	_setup_intervention()
	intervention_state.relation(1, 6).score = 90.0
	assert_eq(
		Intervention.ai_choice(intervention_state, 1, 3, 6),
		Intervention.KIND_INTERVENE,
		"the roll passed"
	)
	intervention_state.relation(1, 6).score = 30.0
	assert_eq(
		Intervention.ai_choice(intervention_state, 1, 3, 6),
		Intervention.KIND_PROTEST,
		"the roll failed, but the court still cares"
	)
	intervention_state.relation(1, 6).score = 10.0
	assert_eq(Intervention.ai_choice(intervention_state, 1, 3, 6), Intervention.KIND_NOTHING)

## The protest penalty is read off the declarer's own ledger (Propaganda), which
## an AI declarer now hands to the rules too (DR-20261110-16).
func test_the_protest_reads_the_declarers_propaganda() -> void:
	_setup_intervention()
	intervention_state.set_overture(1, 6, DiplomacyCatalog.STAGE_EMBASSY)
	intervention_state.relation(1, 6).score = 30.0
	DiplomacyRules.declare_war(intervention_state, 3, 6, true, null, {"propaganda": true})
	assert_eq(intervention_state.relation(1, 3).score, 45.0, "−5 against a propaganda aggressor")
	assert_eq(intervention_state.overture(1, 6), DiplomacyCatalog.STAGE_EMBASSY)

## A deed is a stake, not a courtesy: a court that has bought land inside the
## victim's provinces never shrugs the aggression off, even on cold relations
## (wiki: diplomacy § Intervention "investment protection"; DR-20261110-20).
func test_one_deed_keeps_a_cold_court_from_standing_aside() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(1)
	intervention_state.relation(1, 6).score = 10.0
	assert_false(Intervention.ai_protests(intervention_state, 1, 6), "goodwill alone stands aside")
	assert_true(Intervention.ai_protests(intervention_state, 1, 6, world), "the deed is the stake")
	assert_eq(Intervention.protection_chance(intervention_state, 1, 3, 6, world), 0.25)

func test_two_deeds_raise_the_trial_to_the_second_band() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(1)
	var model: MapModel = world.region(0)
	assert_true(model.ownership.purchase(model.index_of(4, 0), 1), "a second deed")
	intervention_state.relation(1, 6).score = 10.0
	assert_eq(DeedProtection.deed_count(world, 1, 6), 2)
	assert_eq(Intervention.protection_chance(intervention_state, 1, 3, 6, world), 0.5)

## Losing the roll still leaves the deed holder protesting against the war: it
## keeps its seat at the victim's court and puts a relation price on the
## aggression.
func test_a_deed_holder_that_loses_the_roll_protests() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(1)
	intervention_state.relation(1, 6).score = 10.0
	intervention_state.turn = _turn_above_the_first_band(3, 6, 1)
	assert_eq(
		Intervention.ai_choice(intervention_state, 1, 3, 6, world),
		Intervention.KIND_PROTEST,
		"below 26 relations a court without a deed would stand aside"
	)

## The offer records what earned the court its seat, so the prompt never claims
## an embassy the court does not hold (REQ-P2-05, REQ-P5-05).
func test_a_deed_only_offer_names_the_deed_not_the_embassy() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(0)
	DiplomacyRules.declare_war(intervention_state, 3, 6, true, world)
	var offer: Dictionary = Intervention.pending_for(intervention_state, 0)
	assert_eq(String(offer.get("basis", "")), "deed")
	assert_eq(int(offer.get("deeds", 0)), 1)
	var text: String = Intervention.offer_text(offer)
	assert_true(text.contains("deed"), text)
	assert_false(text.contains("embassy"), "no embassy is claimed: " + text)

func test_standing_aside_without_an_embassy_leaves_the_deed_alone() -> void:
	_setup_intervention()
	var world: WorldMap = _deed_world(0)
	DiplomacyRules.declare_war(intervention_state, 3, 6, true, world)
	var answer: Dictionary = Intervention.resolve_human(intervention_state, Intervention.KIND_NOTHING)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(String(answer["message"]).contains("deeds"), String(answer["message"]))
	assert_eq(DeedProtection.deed_count(world, 0, 6), 1, "the land stays bought")

## The first turn whose trial roll clears the 25% band, so a protest test reads
## the band rather than the sample.
func _turn_above_the_first_band(aggressor: int, target: int, court: int) -> int:
	for turn in range(1, 200):
		if Intervention.roll(turn, aggressor, target, court) >= 0.25:
			return turn
	return 1

## Tiny world whose second province answers to Minor Nation `victim`, with one
## land tile sold to `buyer`.
func _deed_world(buyer: int) -> WorldMap:
	var model: MapModel = _Fixture.build()
	var province: ProvinceState = model.provinces[1]
	province.owner = 6
	assert_true(model.purchase_tile(province.tiles[0], buyer), "a deed is signed")
	var world := WorldMap.new()
	world.add_region(model)
	return world

func _intervention_event(kind: String) -> bool:
	for event: Dictionary in intervention_state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false

# --- test_dialogue_beats ---

func test_the_home_beats_are_authored_event_points() -> void:
	_setup_dialogue_beats()
	for point: String in POINTS:
		assert_true(DialogueCatalog.has_point(point), "%s is authored" % point)
		assert_eq(DialogueCatalog.category_for(point), DialogueCatalog.CAT_EVENT)
		assert_true(DialogueCatalog.lines_for(point).size() >= 2, "%s repeats less" % point)
		for mood: Variant in DialogueCatalog.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)

func test_one_table_serves_both_catalogues() -> void:
	_setup_dialogue_beats()
	assert_eq(
		DialogueCatalog.table().size(),
		DialogueCatalog.POINTS.size() + DialogueEpisodes.POINTS.size()
		+ DialogueAgendaLines.POINTS.size() + DialogueYarn.points().size(),
		"the merged catalogue loses no point"
	)
	assert_true(
		DialogueCatalog.points().has("diplomatic/peace_made"),
		"the pair beats stay reachable"
	)
	assert_true(DialogueCatalog.points().has("event/field_won"), "and the episodes")

func test_a_study_is_answered_by_the_coldest_rival() -> void:
	_setup_dialogue_beats()
	_set_score(1, 80.0)
	_set_score(2, 20.0)
	_set_score(3, 40.0)
	assert_eq(DialogueHome.watching_court(dialogue_beats_state, 0), 2, "the coldest court watches")
	assert_true(DialogueHome.record_tech_studied(dialogue_beats_state, 0, "printing_press"))
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_beats_state, 0, 2)
	assert_eq(String(spoken["point"]), "event/tech_studied")
	assert_eq(int(spoken["speaker"]), 2, "the reader never speaks its own study")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT)
	assert_true(String(spoken["text"]).length() > 10)

func test_the_study_is_the_readers_beat_not_the_rivals_line_about_it() -> void:
	_setup_dialogue_beats()
	DialogueHome.record_tech_studied(dialogue_beats_state, 0, "printing_press")
	var event: Dictionary = dialogue_beats_state.events[dialogue_beats_state.events.size() - 1]
	assert_true(
		DialogueEvents.for_event(dialogue_beats_state, event, 2).is_empty(),
		"the rival does not quote the crown to itself"
	)

func test_a_crown_with_no_rival_writes_no_beat() -> void:
	_setup_dialogue_beats()
	var lonely := DiplomacyState.new()
	assert_eq(DialogueHome.watching_court(lonely, 0), -1, "nobody to watch")
	assert_false(DialogueHome.record_tech_studied(lonely, 0, "printing_press"))

func test_the_strongest_host_at_the_seat_speaks() -> void:
	_setup_dialogue_beats()
	_declare_war(1)
	_declare_war(2)
	var hosts: Array = [
		{"owner": 1, "strength": 12.0},
		{"owner": 2, "strength": 30.0},
	]
	assert_true(DialogueHome.record_capital_threat(dialogue_beats_state, 0, 4, hosts))
	var event: Dictionary = dialogue_beats_state.events[dialogue_beats_state.events.size() - 1]
	assert_eq(String(event["kind"]), DialogueHome.CAPITAL_THREATENED)
	assert_eq(int(event["b"]), 2, "the heaviest host answers")
	assert_eq(int(event["data"]["province"]), 4, "the seat is named for the record")
	assert_eq(String(DialogueEvents.for_pair(dialogue_beats_state, 0, 2)["point"]), "event/capital_threatened")

func test_a_host_at_power_says_nothing_about_the_seat() -> void:
	_setup_dialogue_beats()
	var hosts: Array = [{"owner": 1, "strength": 30.0}]
	assert_false(
		DialogueHome.record_capital_threat(dialogue_beats_state, 0, 4, hosts),
		"a court at peace threatens nothing"
	)
	assert_false(DialogueHome.record_capital_threat(dialogue_beats_state, 0, -1, hosts), "no seat, no beat")

func test_a_tribe_under_the_flag_speaks_in_its_own_voice() -> void:
	_setup_dialogue_beats()
	dialogue_beats_state.touch(0, 7, "colonyFormed", {"stage": "join_empire"})
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_beats_state, 0, 7)
	assert_eq(String(spoken["point"]), "event/colony_founded")
	assert_eq(int(spoken["speaker"]), 7, "the Tribe speaks for its lost land")

func test_the_beat_survives_a_save_dialogue_beats() -> void:
	_setup_dialogue_beats()
	DialogueHome.record_tech_studied(dialogue_beats_state, 0, "printing_press")
	var before: Dictionary = DialogueEvents.for_pair(dialogue_beats_state, 0, 1)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(dialogue_beats_state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 1)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")

func test_the_map_speaks_the_turn_it_resolved() -> void:
	_setup_dialogue_beats()
	var play: PlaySession = _dialogue_beats_play()
	MapPlayCourtVoice.record_turn(
		play, {"research": {"researched": ["saw_mill", "printing_press"]}}
	)
	assert_eq(_dialogue_beats_kind_count(play, DialogueHome.TECH_STUDIED), 1, "one study, one beat")
	assert_eq(
		_dialogue_beats_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"the host at the seat answers"
	)
	assert_eq(
		String(DialogueEvents.for_pair(play.diplomacy, 0, 1)["point"]),
		"event/capital_threatened",
		"the seat speaks last"
	)
	play.army_layer.free()

func test_an_observer_turn_raises_no_beat() -> void:
	_setup_dialogue_beats()
	var play: PlaySession = _dialogue_beats_play()
	play.observer_mode = true
	var before: int = play.diplomacy.events.size()
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": ["printing_press"]}})
	assert_eq(play.diplomacy.events.size(), before, "the observer courts speak to nobody")
	play.army_layer.free()

func test_a_seat_off_screen_reads_its_stored_roster() -> void:
	_setup_dialogue_beats()
	var play: PlaySession = _dialogue_beats_play()
	# The crown is looking at the other region: the seat's armies live in the
	# layer's stored table, not in the live roster.
	play.world.add_region(dialogue_beats_Fixture.build())
	play.model = play.world.region(1)
	play.model.region_id = 1
	var stored: Array[ArmyState] = [ArmyState.muster(2, 1, 0, false, ["pikemen"], 10)]
	play.army_layer.regions.set_region(0, stored)
	play.army_layer.armies.clear()
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(
		_dialogue_beats_kind_count(play, DialogueHome.CAPITAL_THREATENED), 1,
		"a host off screen still answers"
	)
	assert_eq(_dialogue_beats_kind_count(play, DialogueHome.TECH_STUDIED), 0, "no study, no beat")
	play.army_layer.free()

func test_an_embarked_host_is_at_sea_and_says_nothing() -> void:
	_setup_dialogue_beats()
	var play: PlaySession = _dialogue_beats_play()
	var host: ArmyState = play.army_layer.armies[0]
	host.embarked_fleet = 1
	var before: int = play.diplomacy.events.size()
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(play.diplomacy.events.size(), before, "a host afloat is not at the gate")
	play.army_layer.free()

func test_a_session_without_a_seat_or_a_report_is_silent() -> void:
	_setup_dialogue_beats()
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = WorldMap.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(play.diplomacy.events.size(), 0, "nothing happened, nothing is said")

func test_a_malformed_report_writes_nothing() -> void:
	_setup_dialogue_beats()
	var play: PlaySession = _dialogue_beats_play()
	MapPlayCourtVoice.record_turn(play, {"research": "not a report"})
	MapPlayCourtVoice.record_turn(play, {"research": {"researched": "not a list"}})
	assert_eq(_dialogue_beats_kind_count(play, DialogueHome.TECH_STUDIED), 0, "a broken report is not a study")
	play.army_layer.free()

## A crown holding a capital in province 0, an enemy host drawn up on it, and
## one declared war — the smallest turn that has something to say.
func _dialogue_beats_play() -> PlaySession:
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = WorldMap.new()
	play.world.add_region(dialogue_beats_Fixture.build())
	play.model = play.world.region(0)
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	DiplomacyRules.declare_war(play.diplomacy, 1, 0)
	play.army_layer = ArmyLayer.new()
	play.army_layer.armies.append(ArmyState.muster(1, 1, 0, false, ["pikemen"], 1))
	return play

func _dialogue_beats_kind_count(play: PlaySession, kind: String) -> int:
	var total: int = 0
	for event: Dictionary in play.diplomacy.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total

func _declare_war(against: int) -> void:
	DiplomacyRules.declare_war(dialogue_beats_state, against, 0)

func _set_score(other: int, score: float) -> void:
	var record: DiplomacyRelation = dialogue_beats_state.relation(0, other)
	assert_true(record != null, "a Great Power pair holds a relation")
	record.score = score

# --- test_dialogue_agenda ---

func test_every_agenda_has_a_veiled_point() -> void:
	_setup_dialogue_agenda()
	for agenda_id: String in AiAgenda.IDS:
		var point: String = DialogueAgenda.point_for(agenda_id)
		assert_true(DialogueCatalog.has_point(point), "%s is authored" % point)
		assert_eq(DialogueCatalog.category_for(point), DialogueCatalog.CAT_AGENDA)
		assert_true(DialogueCatalog.lines_for(point).size() >= 2, "%s repeats less" % point)
		for mood: Variant in DialogueCatalog.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)

func test_no_veiled_line_names_its_own_motive() -> void:
	_setup_dialogue_agenda()
	# The player overhears a hint; the agenda id may never reach the words.
	for agenda_id: String in AiAgenda.IDS:
		for raw: Variant in DialogueCatalog.lines_for(DialogueAgenda.point_for(agenda_id)):
			var line: String = String(raw).to_lower()
			assert_false(
				line.contains(agenda_id.replace("_", " ")) or line.contains(agenda_id),
				"%s does not confess its name" % agenda_id
			)

func test_a_court_speaks_once_in_seven_turns() -> void:
	_setup_dialogue_agenda()
	for faction: int in FactionCatalog.great_power_ids():
		var due: Array[int] = _due_turns(1500, faction, 70)
		assert_eq(due.size(), 10, "court %d speaks ten times in seventy turns" % faction)
		for index: int in range(1, due.size()):
			assert_eq(due[index] - due[index - 1], DialogueAgenda.CADENCE, "one word in seven")

func test_each_court_keeps_its_own_cadence() -> void:
	_setup_dialogue_agenda()
	var seen: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		var first: int = _next_due(1500, faction)
		assert_true(first >= 1 and first <= DialogueAgenda.CADENCE)
		seen[first] = true
	assert_true(seen.size() > 1, "six courts do not all speak on the same turn")

func test_the_cadence_is_the_same_after_a_reload() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = DialogueAgenda.seed_for(1500, 3)
	assert_eq(seed_value, DialogueAgenda.seed_for(1500, 3), "the seed is stable")
	var turn: int = _next_due(1500, 3)
	assert_true(DialogueAgenda.due(1500, 3, turn))
	assert_true(DialogueAgenda.due(1500, 3, turn + DialogueAgenda.CADENCE), "and comes round again")
	assert_false(DialogueAgenda.due(1500, 3, turn + 1))

func test_no_turn_before_the_first_speaks() -> void:
	_setup_dialogue_agenda()
	assert_false(DialogueAgenda.due(1500, 1, 0))
	assert_false(DialogueAgenda.due(1500, 1, -7))

func test_the_beat_waits_for_the_dossiers_evidence() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	assert_false(
		DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 1, seed_value, turn),
		"no evidence, no word about the motive"
	)
	assert_eq(_dialogue_agenda_kind_count(DialogueAgenda.SPOKE), 0)

func test_a_suspected_motive_is_voiced_by_the_court() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	assert_true(DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 1, seed_value, turn))
	var event: Dictionary = dialogue_agenda_state.events[dialogue_agenda_state.events.size() - 1]
	assert_eq(String(event["kind"]), DialogueAgenda.SPOKE)
	assert_eq(int(event["a"]), 0, "the crown records the word it hears")
	assert_eq(int(event["b"]), 1, "the rival speaks")
	assert_eq(String(event["data"]["agenda"]), AiAgenda.WARMONGER)
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_agenda_state, 0, 1)
	assert_eq(String(spoken["point"]), "agenda/warmonger")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_AGENDA)
	assert_eq(int(spoken["speaker"]), 1, "the reader never speaks its own agenda")
	assert_true(String(spoken["text"]).length() > 10)

func test_the_beat_is_the_weakest_word_of_the_turn() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	assert_true(DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 1, seed_value, turn))
	# A study of the crown's own turn is recorded after the beat and wins.
	assert_true(DialogueHome.record_tech_studied(dialogue_agenda_state, 0, "printing_press"))
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_agenda_state, 0, 1)["point"]),
		"event/tech_studied",
		"the court's newest word is not the veiled one"
	)

func test_a_court_the_crown_has_never_met_says_nothing() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(9, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 9)
	assert_false(
		DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 9, seed_value, turn),
		"a stranger is not on the court's list"
	)

func test_the_rival_does_not_quote_its_own_agenda() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 1, seed_value, turn)
	var event: Dictionary = dialogue_agenda_state.events[dialogue_agenda_state.events.size() - 1]
	assert_true(
		DialogueEvents.for_event(dialogue_agenda_state, event, 1).is_empty(),
		"only the crown that overheard it reads the word"
	)

func test_an_unknown_agenda_speaks_nothing() -> void:
	_setup_dialogue_agenda()
	var event: Dictionary = {
		"kind": DialogueAgenda.SPOKE,
		"a": 0,
		"b": 1,
		"turn": 3,
		"data": {"agenda": "warlord"},
	}
	assert_true(DialogueEvents.for_event(dialogue_agenda_state, event, 0).is_empty(), "no such motive, no words")
	assert_true(DialogueEvents.for_event(dialogue_agenda_state, {"kind": DialogueAgenda.SPOKE, "a": 0, "b": 1}, 0).is_empty())

func test_the_beat_survives_a_save_dialogue_agenda() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1)
	_wars_by(1, 3)
	DialogueAgenda.record(dialogue_agenda_state, WorldMap.new(), 0, 1, seed_value, turn)
	var before: Dictionary = DialogueEvents.for_pair(dialogue_agenda_state, 0, 1)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(dialogue_agenda_state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 1)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")

func test_the_map_records_the_agenda_beat_on_its_cadence_turn() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var play: PlaySession = _dialogue_agenda_play(seed_value, _next_due(seed_value, 1))
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_dialogue_agenda_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 1, "one rival speaks")
	assert_eq(
		String(DialogueEvents.for_pair(play.diplomacy, 0, 1)["point"]),
		"agenda/warmonger"
	)

func test_a_turn_off_the_cadence_says_nothing() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var turn: int = _next_due(seed_value, 1) + 1
	var play: PlaySession = _dialogue_agenda_play(seed_value, turn)
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_dialogue_agenda_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 0, "off the cadence, silence")

func test_an_observer_turn_raises_no_agenda_beat() -> void:
	_setup_dialogue_agenda()
	var seed_value: int = _seed_for(1, AiAgenda.WARMONGER)
	var play: PlaySession = _dialogue_agenda_play(seed_value, _next_due(seed_value, 1))
	play.observer_mode = true
	_wars_by(1, 3, play.diplomacy)
	MapPlayCourtVoice.record_turn(play, {})
	assert_eq(_dialogue_agenda_kind_count(DialogueAgenda.SPOKE, play.diplomacy), 0, "the observatory speaks to nobody")

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
	var log: DiplomacyState = share if share != null else dialogue_agenda_state
	for _i in range(3):
		log.record_event("warDeclared", subject, against)

func _dialogue_agenda_kind_count(kind: String, share: DiplomacyState = null) -> int:
	var log: DiplomacyState = share if share != null else dialogue_agenda_state
	var total: int = 0
	for event: Dictionary in log.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total

## The smallest session that reaches the court-voice pass: a crown, its log and
## a campaign clock. No army layer, so the seat stays silent.
func _dialogue_agenda_play(seed_value: int, turn: int) -> PlaySession:
	var play := PlaySession.new()
	play.player_faction = 0
	play.map_seed = seed_value
	play.turn = turn
	play.world = WorldMap.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	return play

# --- test_dialogue_rules ---

func test_every_point_is_authored_with_a_category_and_two_ways_to_say_it() -> void:
	_setup_dialogue_rules()
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
	_setup_dialogue_rules()
	assert_eq(DialogueMood.MOODS.size(), 8, "the eight documented moods")
	for mood: String in DialogueMood.MOODS:
		assert_eq(DialogueMood.MOODS.count(mood), 1, "%s appears once" % mood)

func test_no_line_carries_a_number_or_a_raw_placeholder() -> void:
	_setup_dialogue_rules()
	var digits := RegEx.new()
	digits.compile("\\d")
	for point: String in DialogueCatalog.points():
		for template: Variant in DialogueCatalog.lines_for(point):
			var text: String = DialogueCatalog.render(String(template), "Spain", "Genoa")
			assert_null(digits.search(text), "%s keeps numbers out" % point)
			assert_false(text.contains("{"), "%s fills every placeholder" % point)

func test_a_line_and_a_face_are_chosen_deterministically() -> void:
	_setup_dialogue_rules()
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
	_setup_dialogue_rules()
	assert_false(DialogueCatalog.has_point("diplomatic/never_written"))
	assert_eq(DialogueCatalog.line_for("diplomatic/never_written", 3), "")
	assert_eq(DialogueCatalog.category_for("diplomatic/never_written"), "")
	assert_eq(
		DialogueCatalog.mood_for("diplomatic/never_written", 3), DialogueMood.OPEN_MOOD,
		"a missing point falls back to the open face"
	)

func test_the_mood_machine_walks_the_documented_bands() -> void:
	_setup_dialogue_rules()
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
	_setup_dialogue_rules()
	assert_eq(DialogueMood.quality(DiplomacyCatalog.ALLIANCE_MIN_SCORE, 51.0), 0.0)
	assert_eq(DialogueMood.quality(92.0, 51.0), 1.0, "well above the floor is a full band")
	assert_eq(DialogueMood.quality(11.0, 51.0), -1.0, "well below it is the other")
	assert_true(DialogueMood.quality(61.0, 51.0) > 0.0)

func test_stall_counts_the_turns_an_offer_has_waited() -> void:
	_setup_dialogue_rules()
	assert_eq(DialogueMood.stall(4, 4), 0, "a fresh offer waits none")
	assert_eq(DialogueMood.stall(2, 6), 4)
	assert_eq(DialogueMood.stall(9, 6), 0, "a clock that went backwards waits none")

func test_a_declaration_is_spoken_by_the_court_that_makes_it() -> void:
	_setup_dialogue_rules()
	var event: Dictionary = _dialogue_rules_event("warDeclared", 6, 0)
	var spoken: Dictionary = DialogueEvents.for_event(dialogue_rules_state, event, 0)
	assert_eq(int(spoken["speaker"]), 6, "the declaring court answers")
	assert_eq(String(spoken["point"]), "diplomatic/war_declared_by_them")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_DIPLOMATIC)
	assert_true(String(spoken["text"]).length() > 10)

func test_the_declared_upon_court_answers_in_its_own_voice() -> void:
	_setup_dialogue_rules()
	var event: Dictionary = _dialogue_rules_event("warDeclared", 0, 6)
	assert_eq(
		String(DialogueEvents.for_event(dialogue_rules_state, event, 0)["point"]),
		"diplomatic/war_declared_by_you"
	)
	assert_eq(
		int(DialogueEvents.for_event(dialogue_rules_state, event, 0)["speaker"]), 6,
		"the reader never speaks its own line"
	)

func test_every_voiced_act_has_words_from_the_other_court() -> void:
	_setup_dialogue_rules()
	for kind: String in VOICED.keys():
		var event: Dictionary = _dialogue_rules_event(kind, 0, 6)
		var spoken: Dictionary = DialogueEvents.for_event(dialogue_rules_state, event, 0)
		assert_false(spoken.is_empty(), "%s is voiced" % kind)
		assert_eq(int(spoken["speaker"]), 6, "%s is spoken by the rival" % kind)
		assert_true(String(spoken["text"]).length() > 10, "%s has words" % kind)
		assert_false(String(spoken["text"]).contains("{"), "%s fills its names" % kind)

func test_bookkeeping_acts_stay_out_of_the_courts_mouth() -> void:
	_setup_dialogue_rules()
	for kind: String in SILENT:
		assert_true(
			DialogueEvents.for_event(dialogue_rules_state, _dialogue_rules_event(kind, 0, 6), 0).is_empty(),
			"%s is bookkeeping, not speech" % kind
		)
	assert_true(
		DialogueEvents.for_event(dialogue_rules_state, _dialogue_rules_event("notARealKind", 0, 6), 0).is_empty()
	)

func test_a_third_partys_act_is_not_this_pairs_word() -> void:
	_setup_dialogue_rules()
	assert_true(DialogueEvents.for_event(dialogue_rules_state, _dialogue_rules_event("peaceMade", 2, 3), 0).is_empty())

func test_the_newest_voiced_act_leads_the_pair() -> void:
	_setup_dialogue_rules()
	_declare_war_on_me()
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
	assert_eq(String(spoken["point"]), "diplomatic/war_declared_by_them")
	dialogue_rules_state.turn = 4
	DiplomacyRules.make_peace(dialogue_rules_state, 0, 6)
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "diplomatic/peace_made",
		"the newest word is the one on show"
	)

func test_a_quiet_court_still_has_a_word() -> void:
	_setup_dialogue_rules()
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
	assert_eq(String(spoken["point"]), "reactive/standing_neutral")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_REACTIVE)
	dialogue_rules_state.relation(0, 6).score = 92.0
	assert_eq(String(DialogueEvents.standing(dialogue_rules_state, 0, 6)["point"]), "reactive/standing_friendly")
	dialogue_rules_state.relation(0, 6).score = 2.0
	assert_eq(String(DialogueEvents.standing(dialogue_rules_state, 0, 6)["point"]), "reactive/standing_cold")
	dialogue_rules_state.relation(0, 6).score = 60.0
	dialogue_rules_state.relation(0, 6).formal_alliance = true
	assert_eq(String(DialogueEvents.standing(dialogue_rules_state, 0, 6)["point"]), "reactive/standing_alliance")
	dialogue_rules_state.relation(0, 6).formal_alliance = false
	dialogue_rules_state.relation(0, 6).at_war = true
	assert_eq(String(DialogueEvents.standing(dialogue_rules_state, 0, 6)["point"]), "reactive/standing_war")

func test_the_sealed_relation_number_never_reaches_the_words() -> void:
	_setup_dialogue_rules()
	var digits := RegEx.new()
	digits.compile("\\d")
	for score: float in [-60.0, 2.0, 40.0, 92.0]:
		dialogue_rules_state.relation(0, 6).score = score
		_declare_war_on_me()
		for text: Variant in [
			DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["text"],
			DialogueEvents.standing(dialogue_rules_state, 0, 6)["text"],
		]:
			assert_null(digits.search(String(text)), "a line carries no score")
		DiplomacyRules.make_peace(dialogue_rules_state, 0, 6)

func test_a_stranger_is_masked_in_the_word_of_a_court() -> void:
	_setup_dialogue_rules()
	var event: Dictionary = {"kind": "firstContact", "a": 0, "b": 9, "turn": 1, "data": {}}
	var spoken: Dictionary = DialogueEvents.for_event(dialogue_rules_state, event, 0)
	assert_false(spoken.is_empty())
	assert_true(
		String(spoken["text"]).contains(DiplomacyHistory.UNKNOWN_NAME)
		or not String(spoken["text"]).contains(FactionCatalog.name_of(9)),
		"an unmet court is never named"
	)
	assert_false(String(spoken["text"]).contains(FactionCatalog.name_of(9)))

func test_a_negotiation_beat_says_what_is_on_the_table() -> void:
	_setup_dialogue_rules()
	var alliance: Dictionary = {"from": 2, "kind": "alliance", "stage": "", "turn": 1}
	var spoken: Dictionary = DialogueEvents.for_offer(dialogue_rules_state, 0, alliance)
	assert_eq(String(spoken["point"]), "negotiation/proposal_alliance")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_NEGOTIATION)
	assert_eq(int(spoken["speaker"]), 2)
	assert_true(String(spoken["text"]).length() > 10)
	assert_eq(
		String(DialogueEvents.for_offer(dialogue_rules_state, 0, {"from": 2, "kind": "peace", "turn": 1})["point"]),
		"negotiation/proposal_peace"
	)
	assert_eq(
		String(
			DialogueEvents.for_offer(
				dialogue_rules_state, 0, {"from": 6, "kind": "overture", "stage": "consulate", "turn": 1}
			)["point"]
		),
		"negotiation/proposal_overture"
	)

func test_the_face_of_an_offer_reads_its_wait_and_its_generosity() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.relation(0, 2).score = 92.0
	var fresh: Dictionary = DialogueEvents.for_offer(
		dialogue_rules_state, 0, {"from": 2, "kind": "alliance", "turn": 1}
	)
	assert_true(
		[DialogueMood.PLEASED, DialogueMood.GRACIOUS].has(String(fresh["mood"])),
		"a rich alliance offer is welcome"
	)
	dialogue_rules_state.turn = 6
	var stale: Dictionary = DialogueEvents.for_offer(
		dialogue_rules_state, 0, {"from": 2, "kind": "alliance", "turn": 1}
	)
	assert_true(
		[DialogueMood.IMPATIENT, DialogueMood.SKEPTICAL].has(String(stale["mood"])),
		"five turns of silence tires the envoy"
	)
	dialogue_rules_state.relation(0, 2).score = 0.0
	var poor: Dictionary = DialogueEvents.for_offer(
		dialogue_rules_state, 0, {"from": 2, "kind": "peace", "stage": "", "turn": 6}
	)
	assert_true(
		[DialogueMood.IRRITATED, DialogueMood.DISMISSIVE].has(String(poor["mood"])),
		"a poor offer at a cold court stings"
	)
	var late: Dictionary = DialogueEvents.for_offer(
		dialogue_rules_state, 0, {"from": 2, "kind": "peace", "stage": "", "turn": 1}
	)
	assert_true(
		[DialogueMood.IMPATIENT, DialogueMood.SKEPTICAL].has(String(late["mood"])),
		"the wait speaks louder than the terms"
	)

func test_an_unknown_proposal_kind_has_no_beat() -> void:
	_setup_dialogue_rules()
	assert_true(
		DialogueEvents.for_offer(dialogue_rules_state, 0, {"from": 2, "kind": "trade", "turn": 1}).is_empty()
	)
	assert_true(DialogueEvents.for_offer(dialogue_rules_state, 0, {}).is_empty())
	assert_true(DialogueEvents.for_offer(null, 0, {"from": 2}).is_empty())

func test_the_court_speaks_the_same_words_after_a_save() -> void:
	_setup_dialogue_rules()
	_declare_war_on_me()
	var before: Dictionary = DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
	var captured: Dictionary = SaveCourt.capture_diplomacy(dialogue_rules_state)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(captured)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 6)
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")
	assert_eq(String(after["mood"]), String(before["mood"]))

func test_names_are_masked_before_they_reach_a_line() -> void:
	_setup_dialogue_rules()
	assert_eq(
		DialogueCatalog.render("{speaker} sends word to {other}.", "Spain", "Genoa"),
		"Spain sends word to Genoa."
	)
	assert_eq(
		DialogueCatalog.render("{other} is named.", DiplomacyHistory.UNKNOWN_NAME, "Spain"),
		"Spain is named."
	)
	var masked: String = DialogueCatalog.render(
		"{other}, is it?", "Genoa", DiplomacyHistory.name_for(dialogue_rules_state, 0, 9)
	)
	assert_true(masked.contains(DiplomacyHistory.UNKNOWN_NAME), "strangers stay masked")

func test_speaking_never_alters_the_court() -> void:
	_setup_dialogue_rules()
	_declare_war_on_me()
	var events: int = dialogue_rules_state.events.size()
	var score: float = dialogue_rules_state.relation(0, 6).score
	for _turn in 3:
		DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
		DialogueEvents.standing(dialogue_rules_state, 0, 6)
		DialogueEvents.for_offer(dialogue_rules_state, 0, {"from": 6, "kind": "peace", "turn": dialogue_rules_state.turn})
	assert_eq(dialogue_rules_state.events.size(), events, "words are never written into the log")
	assert_eq(dialogue_rules_state.relation(0, 6).score, score, "and never move a relation")

func test_no_court_talks_to_itself() -> void:
	_setup_dialogue_rules()
	assert_true(DialogueEvents.for_pair(dialogue_rules_state, 0, 0).is_empty())
	assert_true(DialogueEvents.standing(dialogue_rules_state, 0, 0).is_empty())
	assert_true(DialogueEvents.for_pair(null, 0, 6).is_empty())

## A battle is an event beat: the court that reads the verdict speaks it
## (wiki: dialogue-and-mood § Design intent — event: battle results; DR-20261111-01).
func test_the_beaten_court_answers_the_field() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	var spoken: Dictionary = DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
	assert_eq(String(spoken["point"]), "event/field_lost", "the loser owns the loss")
	assert_eq(int(spoken["speaker"]), 6, "the reader never speaks its own line")
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT)
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 6, 0, {"kind": "field", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/field_won",
		"a beaten reader hears the winner's line"
	)
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/field_won",
		"the court that won the field says so"
	)

func test_a_siege_names_the_part_each_court_played() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/siege_taken",
		"the reader carried the walls and the defender answers"
	)
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/siege_held",
		"the walls held against the reader"
	)
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 6, 0, {"kind": "siege", "winner": 6})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/siege_won",
		"the court that took the town boasts of it"
	)
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 6, 0, {"kind": "siege", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/siege_lost",
		"a siege raised is not a wall held"
	)

func test_the_water_answers_to_its_holder() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "sea", "winner": 0})
	assert_eq(String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/sea_lost")
	dialogue_rules_state.events.clear()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "sea", "winner": 6})
	assert_eq(String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/sea_won")

func test_a_battle_without_a_verdict_says_nothing() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": -1})
	assert_true(
		DialogueEvents.for_event(dialogue_rules_state, dialogue_rules_state.events[0], 0).is_empty(),
		"a standoff has no winner to speak for"
	)
	assert_true(
		DialogueEvents.for_event(
			dialogue_rules_state, {"kind": "battleFought", "a": 0, "b": 6, "turn": 1, "data": {}}, 0
		).is_empty(),
		"a beat without a verdict is silent"
	)
	assert_true(
		DialogueEvents.for_event(
			dialogue_rules_state,
			{"kind": "battleFought", "a": 0, "b": 6, "turn": 1,
			"data": {"kind": "field", "winner": 2}},
			0
		).is_empty(),
		"a third court's verdict is not this pair's word"
	)

func test_a_battle_is_kept_out_of_the_chronicle() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	assert_true(
		DiplomacyHistory.entries(dialogue_rules_state, 0, 6).is_empty(),
		"the field is the court's word, not a diplomatic act"
	)
	assert_false(DialogueEvents.for_pair(dialogue_rules_state, 0, 6).is_empty(), "but it is still spoken")

func test_a_battle_leads_the_pair_over_an_older_word() -> void:
	_setup_dialogue_rules()
	_declare_war_on_me()
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]),
		"diplomatic/war_declared_by_them"
	)
	dialogue_rules_state.turn = 3
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/field_lost",
		"the newest word is the one on show"
	)

func test_a_battle_is_recorded_only_for_the_reader() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "field", "winner": 0})
	var count: int = dialogue_rules_state.events.size()
	assert_true(
		DialogueEvents.record_land_battle(
			dialogue_rules_state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
		)
	)
	assert_eq(dialogue_rules_state.events.size(), count + 1, "the reader's own fight is kept")
	assert_false(
		DialogueEvents.record_land_battle(
			dialogue_rules_state, _land_battle(2, 3, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
		),
		"a fight the reader was not in is nobody's word"
	)
	assert_false(
		DialogueEvents.record_land_battle(
			dialogue_rules_state, _land_battle(0, 6, ArmyCombat.Outcome.STALEMATE), 0
		),
		"a standoff writes nothing"
	)
	assert_false(
		DialogueEvents.record_land_battle(
			dialogue_rules_state, _land_battle(0, 6, ArmyCombat.Outcome.MUTUAL_ANNIHILATION), 0
		),
		"mutual ruin writes nothing"
	)
	assert_eq(dialogue_rules_state.events.size(), count + 1, "only the verdict was written")

func test_a_siege_is_told_from_a_field_battle_by_the_report() -> void:
	_setup_dialogue_rules()
	DialogueEvents.record_land_battle(
		dialogue_rules_state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY, "siege"), 0
	)
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/siege_taken"
	)
	dialogue_rules_state.events.clear()
	DialogueEvents.record_land_battle(
		dialogue_rules_state, _land_battle(0, 6, ArmyCombat.Outcome.ATTACKER_VICTORY), 0
	)
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/field_lost"
	)

func test_a_beaten_squadron_that_withdraws_still_lost_the_water() -> void:
	_setup_dialogue_rules()
	DialogueEvents.record_naval_battle(
		dialogue_rules_state,
		{
			"attacker": 0, "defender": 6, "outcome": NavalCombat.Outcome.NONE,
			"retreat": {"success": true, "beaten": 6},
		},
		0
	)
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/sea_lost",
		"the court that quit the zone owns the loss"
	)
	dialogue_rules_state.events.clear()
	DialogueEvents.record_naval_battle(
		dialogue_rules_state,
		{
			"attacker": 0, "defender": 6,
			"outcome": NavalCombat.Outcome.SIDE2_VICTORY, "retreat": {},
		},
		0
	)
	assert_eq(
		String(DialogueEvents.for_pair(dialogue_rules_state, 0, 6)["point"]), "event/sea_won"
	)

func test_a_battle_speaks_the_same_words_after_a_save() -> void:
	_setup_dialogue_rules()
	dialogue_rules_state.record_event("battleFought", 0, 6, {"kind": "siege", "winner": 0})
	var before: Dictionary = DialogueEvents.for_pair(dialogue_rules_state, 0, 6)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(
		SaveCourt.capture_diplomacy(dialogue_rules_state)
	)
	var after: Dictionary = DialogueEvents.for_pair(restored, 0, 6)
	assert_eq(String(after["point"]), String(before["point"]), "the beat survives a load")
	assert_eq(String(after["text"]), String(before["text"]), "the same words reload")

## A war the reader did not start: the rival is the declarer.
func _declare_war_on_me() -> void:
	DiplomacyRules.declare_war(dialogue_rules_state, 6, 0)

func _dialogue_rules_event(kind: String, a: int, b: int) -> Dictionary:
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
