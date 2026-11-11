extends GdToolsTest
## Diplomacy relation model: initialization, bands, decay and subsidy upkeep
## (wiki: diplomacy § Relation Model).
## Consolidated rulebook: test_diplomacy_state, test_diplomacy_orders,
## test_diplomacy_power, test_diplomacy_proposals, test_diplomacy_history,
## test_diplomacy_trade (one Godot boot per domain).

var state: DiplomacyState

const AiFixture = preload("res://tests/ai_fixture.gd")


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(3)
	orders_state = DiplomacyState.new()
	orders_state.initialize(1)
	economy = PlayerEconomy.starting()
	economy.tech_unlocked = {"diplomatic_expertise": true, "empire_building": true}
	power_state = DiplomacyState.new()
	power_state.initialize(1)
	panel = DiplomacyPanel.new()
	add_child(panel)
	proposal_state = DiplomacyState.new()
	proposal_state.initialize(1)
	history_state = DiplomacyState.new()
	history_state.initialize(1)
	trade_state = DiplomacyState.new()
	trade_state.initialize(1)
	trade_economy = PlayerEconomy.starting()


func after_each() -> void:
	if is_instance_valid(panel):
		panel.free()
	panel = null


func test_initializes_same_region_pairs_only() -> void:
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

# --- from test_diplomacy_orders.gd ---
## Diplomatic orders: war, peace, alliances, overtures, aid and subsidies
## (wiki: diplomacy § Diplomatic Order Types).

var orders_state: DiplomacyState
var economy: PlayerEconomy


func test_declare_war_sets_war_and_keeps_gp_auto_embassy() -> void:
	orders_state.relation(0, 1).score = 60.0
	orders_state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _apply("declare_war", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(orders_state.relation(0, 1).at_war)
	assert_eq(orders_state.relation(0, 1).score, 60.0, "war freezes the score")
	assert_eq(orders_state.overture(0, 1), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(orders_state.overture(1, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(String(result["message"]).contains("declares war"))
	var again: Dictionary = _apply("declare_war", 1)
	assert_false(again["ok"])
	assert_true(String(again["reason"]).contains("already at war"))


func test_war_on_a_minor_clears_overtures_and_subsidy() -> void:
	orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	orders_state.set_overture(6, 0, DiplomacyCatalog.STAGE_EMBASSY)
	orders_state.set_subsidy(0, 6, 10)
	var result: Dictionary = _apply("declare_war", 6)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(orders_state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(orders_state.overture(6, 0), DiplomacyCatalog.STAGE_NONE)
	assert_eq(orders_state.subsidy(0, 6), 0)


func test_peace_requires_war_and_minors_never_refuse() -> void:
	var early: Dictionary = _apply("offer_peace", 6)
	assert_false(early["ok"])
	_apply("declare_war", 6)
	var peace: Dictionary = _apply("offer_peace", 6)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_true(bool(peace["accepted"]))
	assert_false(orders_state.relation(0, 6).at_war)


func test_hostile_great_power_refuses_white_peace() -> void:
	orders_state.relation(0, 2).score = 20.0
	_apply("declare_war", 2)
	var peace: Dictionary = _apply("offer_peace", 2)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_false(bool(peace["accepted"]))
	assert_true(orders_state.relation(0, 2).at_war)


func test_alliance_clamps_into_the_allied_band() -> void:
	orders_state.relation(0, 1).score = 80.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(orders_state.relation(0, 1).formal_alliance)
	assert_eq(orders_state.relation(0, 1).score, 80.0)
	var duplicate: Dictionary = _apply("alliance", 1)
	assert_false(duplicate["ok"])


func test_alliance_offer_can_be_refused_below_allied_standing() -> void:
	orders_state.relation(0, 1).score = 60.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(bool(result["accepted"]))
	assert_false(orders_state.relation(0, 1).formal_alliance)
	assert_eq(orders_state.relation(0, 1).score, 60.0)


func test_breaking_an_alliance_applies_the_unified_penalty() -> void:
	orders_state.relation(0, 1).score = 76.0
	orders_state.relation(0, 1).formal_alliance = true
	orders_state.relation(0, 2).score = 80.0
	orders_state.relation(0, 3).score = 70.0
	orders_state.relation(0, 4).score = 90.0
	orders_state.relation(0, 5).score = 50.0
	var result: Dictionary = _apply("break_alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(orders_state.relation(0, 1).formal_alliance)
	assert_eq(orders_state.relation(0, 1).score, 26.0)
	assert_eq(orders_state.relation(0, 2).score, 70.0)
	assert_eq(orders_state.relation(0, 3).score, 60.0)
	assert_eq(orders_state.relation(0, 4).score, 80.0)
	assert_eq(orders_state.relation(0, 5).score, 40.0)
	assert_false(_apply("break_alliance", 1)["ok"])


func test_alliance_needs_friendly_standing() -> void:
	orders_state.relation(0, 1).score = 50.0
	var result: Dictionary = _apply("alliance", 1)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("friendly"))


func test_overture_chain_pays_once_per_stage_and_turn() -> void:
	var first: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(first["ok"], first.get("reason", ""))
	assert_eq(economy.treasury, 2000)
	assert_eq(orders_state.overture(0, 6), DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(orders_state.overture(6, 0), DiplomacyCatalog.STAGE_CONSULATE)
	var skipped: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_false(skipped["ok"], "one overture per target per turn")
	orders_state.end_turn()
	var second: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(second["ok"], second.get("reason", ""))
	assert_eq(economy.treasury, 1000)
	orders_state.end_turn()
	var third: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_NAP)
	assert_true(third["ok"], third.get("reason", ""))
	assert_eq(economy.treasury, 1000)
	assert_eq(orders_state.overture(0, 6), DiplomacyCatalog.STAGE_NAP)


func test_embassy_to_a_minor_requires_diplomatic_expertise() -> void:
	economy.tech_unlocked = {}
	var consulate: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(consulate["ok"], consulate.get("reason", ""))
	orders_state.end_turn()
	var refused: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("Diplomatic Expertise"))
	economy.tech_unlocked = {"diplomatic_expertise": true}
	var accepted: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(accepted["ok"], accepted.get("reason", ""))


func test_gp_join_empire_requires_empire_building() -> void:
	var world: WorldMap = _world([0, 2, 2, 2])
	orders_state.relation(0, 2).score = 60.0
	orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 30000
	economy.tech_unlocked = {"diplomatic_expertise": true}
	var refused: Dictionary = _apply(
		"overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world
	)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("Empire Building"))
	economy.tech_unlocked = {"diplomatic_expertise": true, "empire_building": true}
	var accepted: Dictionary = _apply(
		"overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world
	)
	assert_true(accepted["ok"], accepted.get("reason", ""))


func test_second_overture_to_a_different_target_is_still_legal() -> void:
	orders_state.claim(0, 7, "overture")
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(_apply("overture", 7, DiplomacyCatalog.STAGE_CONSULATE)["ok"])


func test_overtures_are_refused_at_war() -> void:
	_apply("declare_war", 6)
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("at war"))


func test_join_empire_absorbs_a_minor_and_its_provinces() -> void:
	var world: WorldMap = _world([0, 6, 6, 6])
	orders_state.relation(0, 6).score = 60.0
	orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(6, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 20000
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(bool(result.get("map_changed", false)))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_eq(DiplomacyRules.provinces_owned(world, 6), 0)
	assert_eq(economy.treasury, 9000)
	assert_false(orders_state.has_relation(0, 6))


func test_join_empire_makes_a_tribe_a_colony_without_transfer() -> void:
	var world: WorldMap = _world([0, 9, 9])
	orders_state.ensure_relation(0, 9, orders_state.turn)
	orders_state.relation(0, 9).score = 60.0
	orders_state.set_overture(0, 9, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(9, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 20000
	var result: Dictionary = _apply("overture", 9, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_eq(orders_state.colony_of(9), 0)
	assert_eq(DiplomacyRules.provinces_owned(world, 9), 2)
	assert_eq(economy.treasury, 11000)


func test_join_empire_absorbs_a_nearly_defeated_great_power() -> void:
	var world: WorldMap = _world([0, 2, 2, 2])
	orders_state.relation(0, 2).score = 60.0
	orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 30000
	assert_true(DiplomacyRules.nearly_defeated(world, 2))
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_false(orders_state.has_relation(0, 2))
	assert_eq(economy.treasury, 19000)


func test_join_empire_refuses_a_great_power_still_holding_its_capital() -> void:
	var world: WorldMap = _world([0, 2, 2, 2], [1])
	orders_state.relation(0, 2).score = 60.0
	orders_state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	orders_state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 30000
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("nearly defeated"))


func test_grant_aid_needs_embassy_step_and_fixed_relation_gain() -> void:
	var refused: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(refused["ok"], "no embassy yet")
	orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var aid: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_true(aid["ok"], aid.get("reason", ""))
	assert_eq(economy.treasury, 1500)
	assert_eq(orders_state.relation(0, 6).score, 55.0)
	var odd: Dictionary = _apply("grant_aid", 6, "", null, 1500)
	assert_false(odd["ok"])


func test_aid_is_refused_to_an_enemy() -> void:
	orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	_apply("declare_war", 6)
	var result: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(result["ok"])


func test_subsidies_are_minor_only_and_five_point_steps() -> void:
	var gp: Dictionary = _apply("set_subsidy", 1, "", null, 10)
	assert_false(gp["ok"])
	orders_state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(_apply("set_subsidy", 6, "", null, 7)["ok"])
	assert_false(_apply("set_subsidy", 6, "", null, 25)["ok"])
	var set_result: Dictionary = _apply("set_subsidy", 6, "", null, 10)
	assert_true(set_result["ok"], set_result.get("reason", ""))
	assert_eq(orders_state.subsidy(0, 6), 10)
	var cancel: Dictionary = _apply("cancel_subsidy", 6)
	assert_true(cancel["ok"], cancel.get("reason", ""))
	assert_eq(orders_state.subsidy(0, 6), 0)


func test_options_offer_war_overture_and_aid_with_reasons() -> void:
	var options: Array[Dictionary] = DiplomacyOrders.options(orders_state, null, 2500, 0, 1)
	var kinds: Array[String] = []
	for option: Dictionary in options:
		kinds.append(String(option["kind"]))
	assert_true(kinds.has("declare_war"))
	assert_true(kinds.has("alliance"))
	assert_true(kinds.has("overture"))
	assert_true(kinds.has("grant_aid"))
	var overture: Dictionary = _first(options, "overture")
	assert_eq(String(overture["arg"]), DiplomacyCatalog.STAGE_NAP)
	assert_eq(String(overture["cost_text"]), "free")
	var minor_options: Array[Dictionary] = DiplomacyOrders.options(orders_state, null, 2500, 0, 6)
	var consulate: Dictionary = _first(minor_options, "overture")
	assert_eq(String(consulate["arg"]), DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(String(consulate["cost_text"]), "£500")
	assert_false(bool(_first(minor_options, "grant_aid")["ok"]))


func _apply(
	kind: String, target: int, arg: String = "", world: WorldMap = null, amount: int = 0
) -> Dictionary:
	var order: Dictionary = {"kind": kind, "from": 0, "target": target}
	if kind == DiplomacyOrders.KIND_OVERTURE:
		order["stage"] = arg
	elif kind == DiplomacyOrders.KIND_AID or kind == DiplomacyOrders.KIND_SUBSIDY:
		order["amount"] = amount
	return DiplomacyOrders.apply(orders_state, world, economy, order, economy.tech_unlocked)


func _first(options: Array[Dictionary], kind: String) -> Dictionary:
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

# --- from test_diplomacy_power.gd ---
## The court's power standing: the published Great Power power score, the
## relative band the court reads and the line it draws under each crown's name
## (wiki: diplomacy § Great Power power score, § Acceptance criteria).


var power_state: DiplomacyState
var panel: DiplomacyPanel
## 0 = the reader (Spain), 1 = a stronger England, 2 = a weaker France,
## 6 = Genoa, a Minor Nation that never carries a band.
var power: Dictionary = {0: 100, 1: 140, 2: 60, 6: 90}


# --- the published score -----------------------------------------------------


func test_the_power_score_reads_provinces_strength_and_hulls() -> void:
	var world: WorldMap = AiFixture.world([3, 3, 1])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 3.0}, {3: 2})
	assert_eq(int(scores[3]), 33, "2 provinces × 10 + 3 strength + 2 hulls × 5")
	assert_eq(int(scores[1]), 10, "a crown with no field forces scores on land alone")
	assert_eq(int(scores[4]), 0, "a crown holding nothing scores nothing")


func test_the_score_rounds_a_fractional_order_of_battle() -> void:
	var world: WorldMap = AiFixture.world([3, 3])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 2.6}, {})
	assert_eq(int(scores[3]), 23, "20 land + round(2.6) strength")


func test_no_world_answers_no_scores() -> void:
	assert_true(DiplomacyPower.public_power(null, {0: 3.0}, {0: 1}).is_empty())


func test_the_ratio_and_its_signed_share() -> void:
	assert_almost_eq(DiplomacyPower.power_ratio(100, 140), 1.4, 0.0001)
	assert_eq(DiplomacyPower.power_percent(100, 140), 40)
	assert_eq(DiplomacyPower.power_percent(100, 80), -20)
	assert_eq(DiplomacyPower.power_percent(100, 100), 0, "an even court carries no sign")
	assert_almost_eq(DiplomacyPower.power_ratio(0, 50), 50.0, 0.0001)
	assert_eq(DiplomacyPower.power_percent(0, 50), 4900, "a crown with nothing is measured against 1")


# --- the line under each crown's name ----------------------------------------


func test_a_stronger_crown_reads_red_with_its_share() -> void:
	_refresh()
	var mark: Label = _find_label(panel._list, "STRONGER")
	assert_not_null(mark, "the band is named on the row")
	assert_true(String(mark.text).contains("+40%"), "and carries its signed share")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_WAR, "a stronger crown reads red")


func test_a_weaker_crown_reads_green_with_its_share() -> void:
	_refresh()
	var mark: Label = _find_label(panel._list, "FRAIL")
	assert_not_null(mark, "a crown at 0.6 of the reader is frail")
	assert_true(String(mark.text).contains("−40%"), "the share is signed down")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)


func test_an_even_crown_reads_green() -> void:
	power = {0: 100, 1: 100}
	_refresh()
	var mark: Label = _find_label(panel._list, "EVEN")
	assert_not_null(mark)
	assert_true(String(mark.text).contains("0%"), "an even court carries no sign")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)


func test_a_far_stronger_crown_is_overwhelming() -> void:
	power = {0: 100, 1: 160}
	_refresh()
	var mark: Label = _find_label(panel._list, "OVERWHELMING")
	assert_not_null(mark, "a crown half again the reader's size is named so")
	assert_true(String(mark.text).contains("+60%"))


func test_a_minor_nation_carries_no_power_line() -> void:
	_refresh()
	var row: VBoxContainer = _row_for("Genoa")
	assert_not_null(row, "the minor's row is in the list")
	assert_eq(row.get_child_count(), 1, "name and stand only: no score for a minor")


func test_a_court_without_scores_shows_no_line() -> void:
	power = {}
	_refresh()
	var row: VBoxContainer = _row_for("England")
	assert_not_null(row)
	assert_eq(row.get_child_count(), 1, "a fixture without orders draws nothing")


func test_the_detail_names_the_figures_behind_the_band() -> void:
	_refresh()
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Power 140"), "the rival's own score")
	assert_true(_has_text(panel._detail, "yours 100"), "beside the reader's")
	assert_true(_has_text(panel._detail, "Stronger"), "and the band in words")


func _refresh() -> void:
	panel.refresh(power_state, null, 0, 2500, {}, {}, power)


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

# --- from test_diplomacy_proposals.gd ---
## Rival proposals to the human court: an AI court offers an alliance or the
## next overture, the turn waits for the court, and the human's answer runs
## through the shared diplomacy rules (wiki: diplomacy § GP AI policy).


var proposal_state: DiplomacyState


func test_accepting_an_alliance_proposal_signs_the_treaty() -> void:
	proposal_state.relation(0, 2).score = 80.0
	var queued: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(DiplomacyProposals.has_pending(proposal_state, 0))
	assert_false(proposal_state.relation(0, 2).formal_alliance, "nothing is signed before the answer")
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_true(proposal_state.relation(0, 2).formal_alliance, "the human answer forms the treaty")
	assert_false(DiplomacyProposals.has_pending(proposal_state, 0))
	assert_true(_proposal_event("allianceFormed"))
	assert_true(_proposal_event("proposalAccepted"))


func test_refusing_an_alliance_proposal_leaves_the_courts_at_peace() -> void:
	proposal_state.relation(0, 2).score = 80.0
	DiplomacyProposals.queue(proposal_state, null, 2, DiplomacyProposals.KIND_ALLIANCE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, false)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_false(bool(answer["accepted"]))
	assert_false(proposal_state.relation(0, 2).formal_alliance)
	assert_eq(proposal_state.relation(0, 2).score, 80.0, "a refusal costs no relation")
	assert_true(_proposal_event("proposalRefused"))


func test_accepting_an_overture_advances_both_directions_for_free() -> void:
	var queued: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_eq(proposal_state.overture(2, 0), DiplomacyCatalog.STAGE_NAP)
	assert_eq(proposal_state.overture(0, 2), DiplomacyCatalog.STAGE_NAP)
	assert_true(_proposal_event("overtureEstablished"))
	assert_true(_proposal_event("proposalAccepted"))


func test_refusing_an_overture_keeps_the_previous_stage() -> void:
	DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
	)
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_eq(proposal_state.overture(2, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(_proposal_event("overtureRejected"))
	assert_true(_proposal_event("proposalRefused"))


func test_only_one_proposal_waits_on_the_court() -> void:
	proposal_state.relation(0, 2).score = 80.0
	proposal_state.relation(0, 3).score = 80.0
	assert_true(
		DiplomacyProposals.queue(proposal_state, null, 2, DiplomacyProposals.KIND_ALLIANCE)["ok"]
	)
	var second: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 3, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(second["ok"], "the court answers one proposal at a time")
	assert_eq(proposal_state.pending_offers.size(), 1)


func test_no_proposal_is_offered_at_war_or_without_a_treaty_band() -> void:
	proposal_state.relation(0, 2).at_war = true
	var war: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(war["ok"])
	proposal_state.relation(0, 2).at_war = false
	proposal_state.relation(0, 2).score = 50.0
	var cool: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_ALLIANCE
	)
	assert_false(cool["ok"], "the Allied band gates a formal alliance")


func test_accepting_a_peace_proposal_ends_the_war() -> void:
	proposal_state.relation(0, 2).at_war = true
	var queued: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_true(queued["ok"], queued.get("reason", ""))
	assert_true(proposal_state.relation(0, 2).at_war, "the war holds until the court answers")
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, true)
	assert_true(answer["ok"], answer.get("reason", ""))
	assert_true(bool(answer["accepted"]))
	assert_false(proposal_state.relation(0, 2).at_war, "the human answer ends the war")
	assert_false(DiplomacyProposals.has_pending(proposal_state, 0))
	assert_true(_proposal_event("peaceMade"))
	assert_true(_proposal_event("proposalAccepted"))


func test_refusing_a_peace_proposal_keeps_the_war() -> void:
	proposal_state.relation(0, 2).at_war = true
	DiplomacyProposals.queue(proposal_state, null, 2, DiplomacyProposals.KIND_PEACE)
	var answer: Dictionary = DiplomacyProposals.resolve_human(proposal_state, null, false)
	assert_false(bool(answer["accepted"]))
	assert_true(proposal_state.relation(0, 2).at_war, "a refusal does not end the war")
	assert_eq(proposal_state.relation(0, 2).score, 50.0, "a refusal costs no relation")
	assert_true(_proposal_event("proposalRefused"))
	assert_false(_proposal_event("peaceMade"))


func test_a_peace_proposal_needs_a_war() -> void:
	var refused: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 2, DiplomacyProposals.KIND_PEACE
	)
	assert_false(refused["ok"], "white peace is offered only to a court at war")


func test_only_a_great_power_may_propose() -> void:
	proposal_state.relation(0, 6).at_war = true
	var minor: Dictionary = DiplomacyProposals.queue(
		proposal_state, null, 6, DiplomacyProposals.KIND_PEACE
	)
	assert_false(minor["ok"], "a Minor keeps no court to treat with")


func test_an_ai_court_proposes_peace_and_waits() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).at_war = true
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
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
		AiFixture.world([1, 1, 1, 1, 2]),
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
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
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
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.relation(0, 2).score = 80.0
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var config: AiConfig = AiConfig.build(2, 1500)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL
	var context: Dictionary = AiFixture.context({0: 10, 2: 10}, {}, {})
	context["player"] = 0
	var plan: Dictionary = AiDiplomacyPlanner.decide(
		config, fresh, AiState.new(), AiFixture.world([2, 2, 2, 2, 1]), 1, context
	)
	assert_eq(
		String(plan["action"]["kind"]), AiDiplomacyPlanner.KIND_ALLIANCE,
		"the Allied band and a neutral agenda prefer the treaty"
	)


func test_the_improve_relations_cooldown_blocks_a_second_offer() -> void:
	var fresh := DiplomacyState.new()
	fresh.reset(1)
	fresh.ensure_relation(0, 2, 1)
	fresh.set_overture(2, 0, DiplomacyCatalog.STAGE_EMBASSY)
	var ai := AiState.new()
	ai.note_overture(2, 0, 1)
	var result: Dictionary = AiTurn.run(
		fresh,
		AiFixture.world([0, 0, 0, 0, 2]),
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


func _proposal_event(kind: String) -> bool:
	for event: Dictionary in proposal_state.events:
		if String(event["kind"]) == kind:
			return true
	return false

# --- from test_diplomacy_history.gd ---
## The court chronicle (wiki: diplomacy § Diplomatic History): pair scope,
## newest-first order, sealed relation numbers, masked strangers, full
## retention and save round-trip (REQ-P2-01, REQ-P2-04).

var history_state: DiplomacyState

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
	"spyTaken": {"province": "Coro"},
}


func test_the_chronicle_is_pair_scoped_and_newest_first() -> void:
	DiplomacyRules.declare_war(history_state, 0, 6)
	DiplomacyRules.declare_war(history_state, 2, 7)
	history_state.turn = 5
	DiplomacyRules.make_peace(history_state, 0, 6)
	var entries: Array[Dictionary] = DiplomacyHistory.entries(history_state, 0, 6)
	assert_eq(entries.size(), 2, "only the pair's own two acts")
	assert_eq(int(entries[0]["turn"]), 5, "the newest act leads")
	assert_true(String(entries[0]["text"]).contains("peace"))
	assert_false(_joined(entries).contains("Venice"), "another court's war stays out")


func test_the_chronicle_is_symmetric_for_either_court() -> void:
	DiplomacyRules.declare_war(history_state, 0, 6)
	assert_eq(
		DiplomacyHistory.entries(history_state, 0, 6).size(),
		DiplomacyHistory.entries(history_state, 6, 0).size(),
		"the same page is read from either side"
	)


func test_the_calendar_stamp_names_the_year_and_turn() -> void:
	assert_eq(DiplomacyHistory.stamp_for_turn(1), "Year 1500 (Turn 1)")
	assert_eq(
		DiplomacyHistory.stamp_for_turn(12),
		"Year %d (Turn 12)" % TurnTime.year_for_turn(12)
	)


func test_a_stranger_is_masked_in_the_viewing_courts_chronicle() -> void:
	history_state.record_event("callToArmsAccepted", 0, 6, {"aggressor": 9})
	var line: String = _joined(DiplomacyHistory.entries(history_state, 0, 6))
	assert_true(line.contains("Spain"), "the viewing crown reads its own name")
	assert_true(line.contains("Genoa"), "a known court is named")
	assert_true(line.contains(DiplomacyHistory.UNKNOWN_NAME), "an unmet court is masked")
	assert_false(line.contains(FactionCatalog.name_of(9)), "its name never leaks")


func test_the_sealed_relation_number_never_reaches_the_page() -> void:
	history_state.record_event("interventionProtest", 0, 2, {"target": 6})
	var line: String = _joined(DiplomacyHistory.entries(history_state, 0, 2))
	assert_false(line.contains("relation"))
	var digits := RegEx.new()
	digits.compile("\\d")
	assert_null(digits.search(line), "a chronicle line carries no score")


func test_a_war_records_the_overtures_it_ends() -> void:
	history_state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	DiplomacyRules.declare_war(history_state, 0, 6)
	assert_true(_has_event("overturesCleared"), "the lost NAP is written down")
	assert_true(
		_joined(DiplomacyHistory.entries(history_state, 0, 6)).contains("ended the overtures")
	)


func test_a_war_that_ends_no_overture_writes_no_note() -> void:
	# Great Powers hold the auto-embassy, which war keeps: nothing is cleared.
	DiplomacyRules.declare_war(history_state, 0, 1)
	assert_false(_has_event("overturesCleared"), "no empty note for an untouched treaty")


func test_history_is_never_truncated() -> void:
	for _index in 300:
		history_state.record_event("firstContact", 0, 6)
	assert_eq(history_state.events.size(), 300, "a campaign keeps every entry")


func test_the_chronicle_survives_a_save_and_load() -> void:
	DiplomacyRules.declare_war(history_state, 0, 6)
	var captured: Dictionary = SaveCourt.capture_diplomacy(history_state)
	var restored: DiplomacyState = SaveCourt._diplomacy_from(captured)
	assert_eq(restored.events.size(), history_state.events.size())
	assert_eq(
		DiplomacyHistory.entries(restored, 0, 6).size(),
		DiplomacyHistory.entries(history_state, 0, 6).size(),
		"the page loads back whole"
	)


func test_every_narrated_kind_has_a_sentence() -> void:
	assert_eq(
		SAMPLES.size(), DiplomacyHistory.NARRATED.size(), "the sample table is complete"
	)
	for kind: String in DiplomacyHistory.NARRATED:
		assert_true(SAMPLES.has(kind), "%s has a sample" % kind)
		var text: String = DiplomacyHistory.describe(
			history_state, _event(kind), FactionCatalog.PLAYER_FACTION
		)
		assert_false(text.is_empty(), "%s is narrated" % kind)
		assert_false(text.contains("%s"), "%s fills every name" % kind)


func test_a_prompt_or_unknown_kind_stays_out_of_the_page() -> void:
	assert_eq(DiplomacyHistory.describe(history_state, _event("proposalMade"), 0), "")
	assert_eq(DiplomacyHistory.describe(history_state, _event("callToArmsOffered"), 0), "")
	assert_eq(DiplomacyHistory.describe(history_state, _event("notARealKind"), 0), "")


func test_no_history_between_equal_courts() -> void:
	assert_true(DiplomacyHistory.entries(history_state, 0, 0).is_empty())


func _event(kind: String) -> Dictionary:
	var data: Dictionary = SAMPLES.get(kind, {})
	return {"kind": kind, "a": 0, "b": 6, "turn": 1, "data": data}


func _joined(entries: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for entry: Dictionary in entries:
		parts.append(String(entry["text"]))
	return " | ".join(parts)


func _has_event(kind: String) -> bool:
	for event: Dictionary in history_state.events:
		if String(event.get("kind", "")) == kind:
			return true
	return false

# --- from test_diplomacy_trade.gd ---
## Trade diplomacy: favoured trading pacts, colonial boycotts and the market
## price terms they publish (wiki: diplomacy § GP–Tribe — Boycott; world-market
## § FTP, § Subsidy price adjustment).

var trade_state: DiplomacyState
var trade_economy: PlayerEconomy


func test_ftp_needs_a_great_power_and_an_embassy() -> void:
	assert_true(DiplomacyTrade.can_establish_ftp(trade_state, 0, 1)["ok"], "GP auto-embassy")
	var minor: Dictionary = DiplomacyTrade.can_establish_ftp(trade_state, 0, 6)
	assert_false(minor["ok"])
	assert_true(String(minor["reason"]).contains("Great Powers"))


func test_ftp_needs_friendly_standing_and_is_bilateral() -> void:
	var refused: Dictionary = DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]), "score 50 is below the pact threshold")
	assert_false(DiplomacyTrade.is_ftp(trade_state, 0, 1))
	assert_false(DiplomacyTrade.is_ftp(trade_state, 1, 0))

	trade_state.end_turn()
	trade_state.relation(0, 1).score = DiplomacyCatalog.FTP_MIN_SCORE
	var signed: Dictionary = DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed["accepted"]))
	assert_true(DiplomacyTrade.is_ftp(trade_state, 0, 1), "one record serves both directions")
	assert_true(DiplomacyTrade.is_ftp(trade_state, 1, 0))
	assert_true(DiplomacyTrade.ftps_of(trade_state, 0).has(1))


func test_ftp_improves_both_crowns_terms_and_war_ends_it() -> void:
	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	var mine: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 0)
	var theirs: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 1)
	assert_almost_eq(float(mine["buy"]["*"]), 0.95, 0.001, "pact shaves imports")
	assert_almost_eq(float(mine["sell"]["*"]), 1.05, 0.001, "and lifts exports")
	assert_almost_eq(float(theirs["buy"]["*"]), 0.95, 0.001, "both sides gain")

	DiplomacyRules.declare_war(trade_state, 0, 1)
	assert_false(DiplomacyTrade.is_ftp(trade_state, 0, 1), "war severs the pact")
	var after: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 0)
	assert_almost_eq(float(after["buy"]["*"]), 1.0, 0.001, "terms return to the world price")


func test_boycott_needs_a_colony_and_cancels_the_targets_subsidies() -> void:
	var refused: Dictionary = DiplomacyTrade.can_boycott(trade_state, 0, 2)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))

	trade_state.set_colony(9, 0)
	trade_state.ensure_relation(2, 9, trade_state.turn)
	trade_state.set_overture(2, 9, DiplomacyCatalog.STAGE_EMBASSY)
	trade_state.set_subsidy(2, 9, 10)
	var applied: Dictionary = DiplomacyTrade.boycott(trade_state, 0, 2)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(trade_state, 0, 2))
	assert_eq(trade_state.subsidy(2, 9), 0, "the boycotted crown loses its subsidy to our colony")
	assert_false(DiplomacyTrade.boycott(trade_state, 0, 2)["ok"], "one boycott order per turn")
	trade_state.end_turn()

	var lifted: Dictionary = DiplomacyTrade.revoke_boycott(trade_state, 0, 2)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(trade_state, 0, 2))


func test_boycott_worsens_the_targets_terms_and_war_revokes_it() -> void:
	trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(trade_state, 0, 2)
	var target: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 2)
	assert_almost_eq(float(target["buy"]["*"]), 1.10, 0.001, "boycotted imports cost more")
	assert_almost_eq(float(target["sell"]["*"]), 0.90, 0.001, "and exports earn less")
	var issuer: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 0)
	assert_almost_eq(float(issuer["buy"]["*"]), 1.0, 0.001, "the issuer keeps the world price")

	DiplomacyRules.declare_war(trade_state, 0, 2)
	assert_false(DiplomacyTrade.is_boycotting(trade_state, 0, 2), "war auto-revokes")


func test_a_subsidy_sets_rates_on_the_subsidised_courts_goods() -> void:
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	trade_state.ensure_relation(0, 9, trade_state.turn)
	trade_state.set_overture(0, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyAid.set_subsidy(trade_state, 0, 9, 10)
	var terms: Dictionary = DiplomacyTrade.terms_for_court(trade_state, world, 0)
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
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 1.1}, "sell": {"*": 0.9}})
	var base: int = market.price("timber")
	var before: int = trade_economy.treasury
	var bought: Dictionary = market.buy(trade_economy, "timber", 1, 0)
	assert_eq(int(bought["unit_price"]), roundi(float(base) * 1.1))
	assert_eq(trade_economy.treasury, before - int(bought["cost"]))

	trade_economy.stockpile["timber"] = 1
	before = trade_economy.treasury
	var sold: Dictionary = market.sell(trade_economy, "timber", 1, 0)
	assert_eq(int(sold["unit_price"]), roundi(float(base) * 0.9))
	assert_eq(trade_economy.treasury, before + roundi(float(base) * 0.9))
	assert_eq(market.buy_price("timber", 1), base, "a crown without terms pays the world price")


func test_terms_survive_a_save_round_trip() -> void:
	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(trade_state, 0, 2)
	var play := PlaySession.new()
	SaveCourt.restore_diplomacy(
		play, {"diplomacy": SaveCourt.capture_diplomacy(trade_state)}
	)
	assert_true(DiplomacyTrade.is_ftp(play.diplomacy, 0, 1))
	assert_true(DiplomacyTrade.is_boycotting(play.diplomacy, 0, 2))


func test_court_orders_offer_trade_actions_and_the_way_back() -> void:
	var options: Array[Dictionary] = DiplomacyOrders.options(trade_state, null, 2500, 0, 1)
	var offer: Dictionary = _trade_first(options, DiplomacyOrders.KIND_FTP)
	assert_eq(String(offer["group"]), DiplomacyOrders.GROUP_TRADE)
	assert_true(String(offer["hint"]).contains("5%"))
	assert_eq(
		String(_trade_first(options, DiplomacyOrders.KIND_BOYCOTT)["group"]),
		DiplomacyOrders.GROUP_TRADE
	)

	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	var after: Array[Dictionary] = DiplomacyOrders.options(trade_state, null, 2500, 0, 1)
	assert_true(_trade_first(after, DiplomacyOrders.KIND_FTP).is_empty())
	assert_false(_trade_first(after, DiplomacyOrders.KIND_REVOKE_FTP).is_empty())


func test_court_orders_sign_and_end_the_pact() -> void:
	trade_state.relation(0, 1).score = 80.0
	var signed: Dictionary = DiplomacyOrders.apply(
		trade_state, null, trade_economy, {"kind": DiplomacyOrders.KIND_FTP, "from": 0, "target": 1}
	)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed.get("accepted", false)))
	assert_true(DiplomacyTrade.is_ftp(trade_state, 0, 1))
	trade_state.end_turn()
	var ended: Dictionary = DiplomacyOrders.apply(
		trade_state,
		null,
		trade_economy,
		{"kind": DiplomacyOrders.KIND_REVOKE_FTP, "from": 0, "target": 1}
	)
	assert_true(ended["ok"], ended.get("reason", ""))
	assert_false(DiplomacyTrade.is_ftp(trade_state, 0, 1))


func test_court_orders_impose_and_lift_the_boycott() -> void:
	trade_state.set_colony(9, 0)
	var applied: Dictionary = DiplomacyOrders.apply(
		trade_state, null, trade_economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(trade_state, 0, 2))
	trade_state.end_turn()
	var lifted: Dictionary = DiplomacyOrders.apply(
		trade_state,
		null,
		trade_economy,
		{"kind": DiplomacyOrders.KIND_REVOKE_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(trade_state, 0, 2))


func test_validation_mirrors_the_trade_gates() -> void:
	var denied: Dictionary = DiplomacyOrders.validate(
		trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
	)
	assert_false(denied["ok"])
	assert_true(String(denied["reason"]).contains("colony"))
	trade_state.set_colony(9, 0)
	assert_true(
		DiplomacyOrders.validate(
			trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
		)["ok"]
	)
	assert_true(
		DiplomacyOrders.validate(
			trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_FTP, "target": 1}
		)["ok"]
	)
	assert_false(
		DiplomacyOrders.validate(
			trade_state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_REVOKE_FTP, "target": 1}
		)["ok"]
	)


func test_a_subsidy_without_an_embassy_explains_itself() -> void:
	trade_state.ensure_relation(0, 6, trade_state.turn)
	var options: Array[Dictionary] = DiplomacyOrders.options(trade_state, null, 2500, 0, 6)
	var subsidy: Dictionary = _trade_first(options, DiplomacyOrders.KIND_SUBSIDY)
	assert_false(bool(subsidy["ok"]))
	assert_true(String(subsidy["hint"]).contains("embassy"))


func test_terms_stay_inside_the_rails() -> void:
	for other: int in [10, 11, 12, 13, 14, 15]:
		trade_state.ftps[trade_state.pair_key(0, other)] = trade_state.turn
	var terms: Dictionary = DiplomacyTrade.faction_terms(trade_state, {}, 0)
	assert_almost_eq(
		float(terms["buy"]["*"]), DiplomacyCatalog.TERMS_BUY_MIN, 0.001, "buy floor"
	)
	assert_almost_eq(
		float(terms["sell"]["*"]), DiplomacyCatalog.TERMS_SELL_MAX, 0.001, "sell cap"
	)
	trade_state.boycotts["2>2"] = trade_state.turn
	assert_true(DiplomacyTrade.boycotts_against(trade_state, 2).is_empty(), "self-boycott ignored")


func test_clearing_terms_returns_the_world_price() -> void:
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 0.9}})
	var clone: WorldMarket = market.copy()
	assert_false(clone.terms_for(0).is_empty(), "a projection keeps the terms")
	market.clear_terms()
	assert_true(market.terms_for(0).is_empty())
	assert_eq(market.buy_price("timber", 0), market.price("timber"))


func test_absorbing_a_crown_clears_its_trade_ties() -> void:
	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(trade_state, 0, 2)
	trade_state.clear_relations_of(1)
	assert_false(DiplomacyTrade.is_ftp(trade_state, 0, 1), "the pact dies with the court")
	trade_state.clear_relations_of(2)
	assert_false(DiplomacyTrade.is_boycotting(trade_state, 0, 2), "so does its boycott")


func test_every_trade_gate_says_why_it_refuses() -> void:
	assert_true(
		String(DiplomacyTrade.can_revoke_ftp(trade_state, 0, 1)["reason"]).contains("No favoured")
	)
	assert_false(DiplomacyTrade.revoke_ftp(trade_state, 0, 1)["ok"])
	assert_true(
		String(DiplomacyTrade.can_boycott(trade_state, 0, 0)["reason"]).contains("itself")
	)
	assert_true(
		String(DiplomacyTrade.can_boycott(trade_state, 0, 6)["reason"]).contains("Great Power")
	)
	assert_true(
		String(DiplomacyTrade.can_revoke_boycott(trade_state, 0, 2)["reason"]).contains("No boycott")
	)
	trade_state.set_colony(9, 0)
	DiplomacyRules.declare_war(trade_state, 0, 2)
	assert_true(
		String(DiplomacyTrade.can_boycott(trade_state, 0, 2)["reason"]).contains("at war")
	)
	DiplomacyRules.declare_war(trade_state, 0, 1)
	assert_true(
		String(DiplomacyTrade.can_establish_ftp(trade_state, 0, 1)["reason"]).contains("enemy")
	)


func test_a_court_can_refuse_the_pact() -> void:
	trade_state.relation(0, 1).score = 80.0
	var refused: Dictionary = DiplomacyTrade.establish_ftp(
		trade_state, 0, 1, DiplomacyRules.DECISION_REFUSE
	)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]))
	assert_false(DiplomacyTrade.is_ftp(trade_state, 0, 1))


func test_terms_are_published_to_the_market_and_cleared_again() -> void:
	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	var market := WorldMarket.with_default_prices()
	DiplomacyTrade.apply_terms(trade_state, null, market)
	assert_almost_eq(market.term_multiplier(0, "timber", true), 0.95, 0.001)
	assert_almost_eq(market.term_multiplier(1, "timber", false), 1.05, 0.001)
	assert_eq(DiplomacyTrade.market_terms(trade_state, null).size(), 6, "every crown is priced")
	DiplomacyTrade.apply_terms(null, null, market)
	assert_true(market.terms_for(0).is_empty(), "no court means the world price")


func test_a_court_that_grows_nothing_keeps_the_world_price() -> void:
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(trade_state, null, 0)["buy"]["*"]), 1.0, 0.001
	)
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(trade_state, world, 3)["buy"]["*"]), 1.0, 0.001,
		"no produced goods, no extra rate"
	)


func test_war_narrates_the_broken_pact_and_boycott() -> void:
	trade_state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(trade_state, 0, 1)
	trade_state.set_colony(9, 0)
	DiplomacyTrade.boycott(trade_state, 0, 2)
	DiplomacyRules.declare_war(trade_state, 0, 1)
	DiplomacyRules.declare_war(trade_state, 0, 2)
	var pact: String = _trade_joined(DiplomacyHistory.entries(trade_state, 0, 1))
	assert_true(pact.contains("war ended the favoured trading pact"), pact)
	var boycott: String = _trade_joined(DiplomacyHistory.entries(trade_state, 0, 2))
	assert_true(boycott.contains("war ended Spain's boycott"), boycott)


func test_a_court_order_that_cannot_trade_says_so() -> void:
	var refused: Dictionary = DiplomacyOrders.apply(
		trade_state, null, trade_economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))


func test_a_boycott_bars_aid_and_subsidies_to_the_colony() -> void:
	trade_state.set_colony(9, 0)
	for gp: int in [2, 3]:
		trade_state.ensure_relation(gp, 9, trade_state.turn)
		trade_state.set_overture(gp, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyTrade.boycott(trade_state, 0, 2)
	var aid: Dictionary = DiplomacyAid.can_grant_aid(trade_state, 2, 9, 1000, 10000)
	assert_false(aid["ok"], "the boycotted crown may not aid our colony")
	assert_true(String(aid["reason"]).contains("boycott"))
	assert_false(DiplomacyAid.can_set_subsidy(trade_state, 2, 9, 10)["ok"])
	assert_true(DiplomacyAid.can_grant_aid(trade_state, 3, 9, 1000, 10000)["ok"], "others may")


func _trade_joined(entries: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		lines.append(String(entry["text"]))
	return " ".join(lines)


func _trade_first(options: Array[Dictionary], kind: String) -> Dictionary:
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
