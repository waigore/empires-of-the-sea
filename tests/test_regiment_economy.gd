extends GdToolsTest
## Regiment training economy (wiki: military-units § Training Costs,
## military-generals § Regiment Economy, tech-tree-military § Unlocks).


func test_every_regiment_has_a_training_row() -> void:
	for type_id: String in RegimentCatalog.ids():
		assert_true(RegimentEconomy.TECH.has(type_id), "%s has a tech row" % type_id)
		var tech: String = RegimentEconomy.tech_for(type_id)
		if not tech.is_empty():
			assert_true(TechCatalog.known(tech), "%s maps to a real tech" % type_id)


func test_cavalry_inputs_match_the_published_table() -> void:
	var squires: Dictionary = RegimentEconomy.training_inputs("squires")
	assert_eq(int(squires["fabric"]), 1)
	assert_eq(int(squires["castIron"]), 1)
	assert_eq(int(squires["horses"]), 2)
	var knights: Dictionary = RegimentEconomy.training_inputs("knights")
	assert_eq(int(knights["castIron"]), 2)
	assert_eq(int(knights["horses"]), 2)
	var lancers: Dictionary = RegimentEconomy.training_inputs("lancers")
	assert_false(lancers.has("horses"), "lancers need no horses")


func test_start_regiments_are_buildable_and_later_ones_are_tech_gated() -> void:
	assert_true(RegimentEconomy.buildable("peasant_levies", {}))
	assert_true(RegimentEconomy.buildable("culverin", {}))
	assert_false(RegimentEconomy.buildable("lancers", {}))
	assert_true(RegimentEconomy.buildable("lancers", {"organised_regiments": true}))
	assert_false(RegimentEconomy.buildable("guards", {"needle_guns": true}))
	assert_true(RegimentEconomy.buildable("guards", {"elite_military_training": true}))


func test_blocked_reasons_follow_the_ledger() -> void:
	var stock: Dictionary = {"fabric": 5, "castIron": 5, "bronze": 5}
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 0, stock, 5, {}),
		"Insufficient treasury"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, {}, 5, {}),
		"Insufficient materials"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("pikemen", 99999, stock, 0, {}),
		"Insufficient workers"
	)
	assert_eq(
		RegimentEconomy.blocked_reason("lancers", 99999, stock, 5, {}),
		"Requires Organised Regiments"
	)
	assert_eq(RegimentEconomy.blocked_reason("pikemen", 99999, stock, 5, {}), "")


func test_cost_text_lists_cash_materials_and_the_worker() -> void:
	var text: String = RegimentEconomy.cost_text("peasant_levies")
	assert_true(text.contains("2,000 ducats"), text)
	assert_true(text.contains("Fabric"), text)
	assert_true(text.contains("1 worker"), text)


func test_recruit_deducts_the_ledger_and_joins_the_home_army() -> void:
	var economy := PlayerEconomy.starting()
	var home := ArmyState.muster(1, 0, 4, true, [] as Array[String], 1)
	var treasury: int = economy.treasury
	var fabric: int = economy.quantity("fabric")
	var peasants: int = economy.available_peasants()

	var result: Dictionary = ArmyTraining.recruit(economy, home, "peasant_levies", "unit_9")

	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(home.count(), 1)
	assert_eq(home.type_of("unit_9"), "peasant_levies")
	assert_eq(economy.treasury, treasury - RegimentCatalog.treasury_cost("peasant_levies"))
	assert_eq(economy.quantity("fabric"), fabric - 1)
	assert_eq(economy.available_peasants(), peasants - 1)


func test_recruit_refuses_a_field_army() -> void:
	var economy := PlayerEconomy.starting()
	var field := ArmyState.muster(2, 0, 4, false, [] as Array[String], 1)
	var result: Dictionary = ArmyTraining.recruit(economy, field, "peasant_levies", "unit_9")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Regiments muster only in the Home Army.")
	assert_eq(field.count(), 0)


func test_rows_lead_with_what_the_crown_can_muster_today() -> void:
	var economy := PlayerEconomy.starting()
	var rows: Array[Dictionary] = ArmyTraining.rows(economy)
	assert_eq(rows.size(), RegimentCatalog.ROWS.size())
	assert_true(bool(rows[0]["ok"]), "first row is buildable")
	var seen_locked: bool = false
	for row: Dictionary in rows:
		if not bool(row["ok"]):
			seen_locked = true
		elif seen_locked:
			assert_true(false, "buildable rows must come before locked rows")
