extends GdToolsTest
## Diplomacy relation model: initialization, bands, decay and subsidy upkeep
## (wiki: diplomacy § Relation Model).

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(3)


func test_initializes_same_region_pairs_only() -> void:
	# Old World: 6 GPs + 3 Minors = 9 factions -> 36 pairs.
	# New World: 10 Tribes -> 45 pairs. Cross-region pairs stay unknown.
	assert_eq(state.relations.size(), 81)
	assert_true(state.has_relation(0, 5))
	assert_true(state.has_relation(6, 8))
	assert_true(state.has_relation(9, 18))
	assert_false(state.has_relation(0, 9))
	assert_false(state.has_relation(6, 18))
	var record: DiplomacyRelation = state.relation(0, 1)
	assert_false(record.at_war)
	assert_eq(record.score, 50.0)
	assert_eq(record.since_turn, 3)
	assert_eq(record.last_interaction_turn, 3)


func test_great_power_pairs_start_with_a_bilateral_auto_embassy() -> void:
	for gp_a: int in FactionCatalog.great_power_ids():
		for gp_b: int in FactionCatalog.great_power_ids():
			if gp_a == gp_b:
				continue
			assert_eq(state.overture(gp_a, gp_b), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)


func test_relation_bands_follow_the_wiki_thresholds() -> void:
	assert_eq(DiplomacyCatalog.relation_level(0.0), "Hostile")
	assert_eq(DiplomacyCatalog.relation_level(25.0), "Hostile")
	assert_eq(DiplomacyCatalog.relation_level(25.1), "Neutral")
	assert_eq(DiplomacyCatalog.relation_level(50.0), "Neutral")
	assert_eq(DiplomacyCatalog.relation_level(50.1), "Friendly")
	assert_eq(DiplomacyCatalog.relation_level(75.0), "Friendly")
	assert_eq(DiplomacyCatalog.relation_level(75.1), "Allied")
	assert_eq(DiplomacyCatalog.relation_level(100.0), "Allied")


func test_war_invariant_drops_the_alliance_flag_and_clamps_the_score() -> void:
	var record: DiplomacyRelation = DiplomacyRelation.create(1, 0)
	record.formal_alliance = true
	record.at_war = true
	record.score = 140.0
	record.normalize()
	assert_false(record.formal_alliance)
	assert_eq(record.score, 100.0)


func test_ten_step_meter_uses_half_open_bands() -> void:
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
	state.relation(0, 1).score = 40.0
	state.relation(0, 2).score = 40.0
	state.apply_delta(0, 1, 5.0, "grantAid")
	state.end_turn()
	assert_eq(state.relation(0, 1).score, 45.0, "no decay after an event delta")
	assert_eq(state.relation(0, 2).score, 44.0, "untouched pairs still drift")


func test_newly_created_relation_skips_its_creation_turn() -> void:
	var tribe: int = 9
	state.ensure_relation(0, tribe, state.turn)
	state.relation(0, tribe).score = 40.0
	state.touch(0, tribe, "firstContact")
	state.end_turn()
	assert_eq(state.relation(0, tribe).score, 40.0)


func test_subsidies_survive_while_the_embassy_stands() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	state.end_turn()
	assert_eq(state.subsidy(0, 6), 10)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NONE)
	var report: Dictionary = state.end_turn()
	assert_eq(state.subsidy(0, 6), 0)
	assert_eq(int(report["subsidies_cancelled"]), 1)


func test_a_subsidy_is_not_a_score_event_for_decay() -> void:
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
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 15)
	state.relation(0, 6).at_war = true
	state.end_turn()
	assert_eq(state.subsidy(0, 6), 0)


func test_absorbed_faction_leaves_no_relations_or_colonies() -> void:
	state.set_colony(9, 6)
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_subsidy(0, 6, 5)
	state.clear_relations_of(6)
	assert_false(state.has_relation(0, 6))
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.subsidy(0, 6), 0)
	assert_eq(state.colony_of(9), -1)


func test_consulate_gate_reads_the_overture_chain() -> void:
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
