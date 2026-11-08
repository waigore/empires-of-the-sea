extends GdToolsTest
## Diplomatic orders: war, peace, alliances, overtures, aid and subsidies
## (wiki: diplomacy § Diplomatic Order Types).

var state: DiplomacyState
var economy: PlayerEconomy


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	economy = PlayerEconomy.starting()
	economy.tech_unlocked = {"diplomatic_expertise": true, "empire_building": true}


func test_declare_war_sets_war_and_keeps_gp_auto_embassy() -> void:
	state.relation(0, 1).score = 60.0
	state.set_overture(0, 1, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(1, 0, DiplomacyCatalog.STAGE_NAP)
	var result: Dictionary = _apply("declare_war", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(state.relation(0, 1).at_war)
	assert_eq(state.relation(0, 1).score, 60.0, "war freezes the score")
	assert_eq(state.overture(0, 1), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(state.overture(1, 0), DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(String(result["message"]).contains("declares war"))
	var again: Dictionary = _apply("declare_war", 1)
	assert_false(again["ok"])
	assert_true(String(again["reason"]).contains("already at war"))


func test_war_on_a_minor_clears_overtures_and_subsidy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_overture(6, 0, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(0, 6, 10)
	var result: Dictionary = _apply("declare_war", 6)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.overture(6, 0), DiplomacyCatalog.STAGE_NONE)
	assert_eq(state.subsidy(0, 6), 0)


func test_peace_requires_war_and_minors_never_refuse() -> void:
	var early: Dictionary = _apply("offer_peace", 6)
	assert_false(early["ok"])
	_apply("declare_war", 6)
	var peace: Dictionary = _apply("offer_peace", 6)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_true(bool(peace["accepted"]))
	assert_false(state.relation(0, 6).at_war)


func test_hostile_great_power_refuses_white_peace() -> void:
	state.relation(0, 2).score = 20.0
	_apply("declare_war", 2)
	var peace: Dictionary = _apply("offer_peace", 2)
	assert_true(peace["ok"], peace.get("reason", ""))
	assert_false(bool(peace["accepted"]))
	assert_true(state.relation(0, 2).at_war)


func test_alliance_clamps_into_the_allied_band() -> void:
	state.relation(0, 1).score = 80.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(state.relation(0, 1).formal_alliance)
	assert_eq(state.relation(0, 1).score, 80.0)
	var duplicate: Dictionary = _apply("alliance", 1)
	assert_false(duplicate["ok"])


func test_alliance_offer_can_be_refused_below_allied_standing() -> void:
	state.relation(0, 1).score = 60.0
	var result: Dictionary = _apply("alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(bool(result["accepted"]))
	assert_false(state.relation(0, 1).formal_alliance)
	assert_eq(state.relation(0, 1).score, 60.0)


func test_breaking_an_alliance_applies_the_unified_penalty() -> void:
	state.relation(0, 1).score = 76.0
	state.relation(0, 1).formal_alliance = true
	state.relation(0, 2).score = 80.0
	state.relation(0, 3).score = 70.0
	state.relation(0, 4).score = 90.0
	state.relation(0, 5).score = 50.0
	var result: Dictionary = _apply("break_alliance", 1)
	assert_true(result["ok"], result.get("reason", ""))
	assert_false(state.relation(0, 1).formal_alliance)
	assert_eq(state.relation(0, 1).score, 26.0)
	assert_eq(state.relation(0, 2).score, 70.0)
	assert_eq(state.relation(0, 3).score, 60.0)
	assert_eq(state.relation(0, 4).score, 80.0)
	assert_eq(state.relation(0, 5).score, 40.0)
	assert_false(_apply("break_alliance", 1)["ok"])


func test_alliance_needs_friendly_standing() -> void:
	state.relation(0, 1).score = 50.0
	var result: Dictionary = _apply("alliance", 1)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("friendly"))


func test_overture_chain_pays_once_per_stage_and_turn() -> void:
	var first: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(first["ok"], first.get("reason", ""))
	assert_eq(economy.treasury, 2000)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_CONSULATE)
	assert_eq(state.overture(6, 0), DiplomacyCatalog.STAGE_CONSULATE)
	var skipped: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_false(skipped["ok"], "one overture per target per turn")
	state.end_turn()
	var second: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(second["ok"], second.get("reason", ""))
	assert_eq(economy.treasury, 1000)
	state.end_turn()
	var third: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_NAP)
	assert_true(third["ok"], third.get("reason", ""))
	assert_eq(economy.treasury, 1000)
	assert_eq(state.overture(0, 6), DiplomacyCatalog.STAGE_NAP)


func test_embassy_to_a_minor_requires_diplomatic_expertise() -> void:
	economy.tech_unlocked = {}
	var consulate: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_CONSULATE)
	assert_true(consulate["ok"], consulate.get("reason", ""))
	state.end_turn()
	var refused: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("Diplomatic Expertise"))
	economy.tech_unlocked = {"diplomatic_expertise": true}
	var accepted: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(accepted["ok"], accepted.get("reason", ""))


func test_gp_join_empire_requires_empire_building() -> void:
	var world: WorldMap = _world([0, 2, 2, 2])
	state.relation(0, 2).score = 60.0
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
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
	state.claim(0, 7, "overture")
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
	state.relation(0, 6).score = 60.0
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(6, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 20000
	var result: Dictionary = _apply("overture", 6, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_true(bool(result.get("map_changed", false)))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_eq(DiplomacyRules.provinces_owned(world, 6), 0)
	assert_eq(economy.treasury, 9000)
	assert_false(state.has_relation(0, 6))


func test_join_empire_makes_a_tribe_a_colony_without_transfer() -> void:
	var world: WorldMap = _world([0, 9, 9])
	state.ensure_relation(0, 9, state.turn)
	state.relation(0, 9).score = 60.0
	state.set_overture(0, 9, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(9, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 20000
	var result: Dictionary = _apply("overture", 9, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_true(bool(result["accepted"]))
	assert_eq(state.colony_of(9), 0)
	assert_eq(DiplomacyRules.provinces_owned(world, 9), 2)
	assert_eq(economy.treasury, 11000)


func test_join_empire_absorbs_a_nearly_defeated_great_power() -> void:
	var world: WorldMap = _world([0, 2, 2, 2])
	state.relation(0, 2).score = 60.0
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 30000
	assert_true(DiplomacyRules.nearly_defeated(world, 2))
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_true(result["ok"], result.get("reason", ""))
	assert_eq(DiplomacyRules.provinces_owned(world, 0), 4)
	assert_false(state.has_relation(0, 2))
	assert_eq(economy.treasury, 19000)


func test_join_empire_refuses_a_great_power_still_holding_its_capital() -> void:
	var world: WorldMap = _world([0, 2, 2, 2], [1])
	state.relation(0, 2).score = 60.0
	state.set_overture(0, 2, DiplomacyCatalog.STAGE_NAP)
	state.set_overture(2, 0, DiplomacyCatalog.STAGE_NAP)
	economy.treasury = 30000
	var result: Dictionary = _apply("overture", 2, DiplomacyCatalog.STAGE_JOIN_EMPIRE, world)
	assert_false(result["ok"])
	assert_true(String(result["reason"]).contains("nearly defeated"))


func test_grant_aid_needs_embassy_step_and_fixed_relation_gain() -> void:
	var refused: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(refused["ok"], "no embassy yet")
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	var aid: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_true(aid["ok"], aid.get("reason", ""))
	assert_eq(economy.treasury, 1500)
	assert_eq(state.relation(0, 6).score, 55.0)
	var odd: Dictionary = _apply("grant_aid", 6, "", null, 1500)
	assert_false(odd["ok"])


func test_aid_is_refused_to_an_enemy() -> void:
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	_apply("declare_war", 6)
	var result: Dictionary = _apply("grant_aid", 6, "", null, 1000)
	assert_false(result["ok"])


func test_subsidies_are_minor_only_and_five_point_steps() -> void:
	var gp: Dictionary = _apply("set_subsidy", 1, "", null, 10)
	assert_false(gp["ok"])
	state.set_overture(0, 6, DiplomacyCatalog.STAGE_EMBASSY)
	assert_false(_apply("set_subsidy", 6, "", null, 7)["ok"])
	assert_false(_apply("set_subsidy", 6, "", null, 25)["ok"])
	var set_result: Dictionary = _apply("set_subsidy", 6, "", null, 10)
	assert_true(set_result["ok"], set_result.get("reason", ""))
	assert_eq(state.subsidy(0, 6), 10)
	var cancel: Dictionary = _apply("cancel_subsidy", 6)
	assert_true(cancel["ok"], cancel.get("reason", ""))
	assert_eq(state.subsidy(0, 6), 0)


func test_options_offer_war_overture_and_aid_with_reasons() -> void:
	var options: Array[Dictionary] = DiplomacyOrders.options(state, null, 2500, 0, 1)
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
	var minor_options: Array[Dictionary] = DiplomacyOrders.options(state, null, 2500, 0, 6)
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
	return DiplomacyOrders.apply(state, world, economy, order, economy.tech_unlocked)


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
