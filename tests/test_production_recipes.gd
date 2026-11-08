extends GdToolsTest
## Production recipes (wiki: production-recipes).


func test_catalog_has_the_published_recipes() -> void:
	assert_eq(ProductionRecipes.ids().size(), 10)
	assert_eq(ProductionRecipes.output("lumber"), "lumber")
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})
	assert_eq(ProductionRecipes.labour("lumber"), 2)
	assert_eq(ProductionRecipes.inputs("bronze"), {"copper": 1, "tin": 1})
	assert_eq(ProductionRecipes.labour("bronze"), 3)
	assert_eq(ProductionRecipes.output("fabric_from_wool"), "fabric")
	assert_false(ProductionRecipes.known("silk_gown"))


func test_inputs_are_returned_as_a_copy() -> void:
	var inputs: Dictionary = ProductionRecipes.inputs("lumber")
	inputs["timber"] = 99
	assert_eq(ProductionRecipes.inputs("lumber"), {"timber": 2})


func test_cotton_fabric_needs_its_technology() -> void:
	assert_true(ProductionRecipes.available("fabric_from_wool", {}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {}))
	assert_true(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": true}))
	assert_false(ProductionRecipes.available("fabric_from_cotton", {"cotton_weaving": false}))
	var gated: Array[String] = ProductionRecipes.available_ids({})
	assert_false(gated.has("fabric_from_cotton"))
	assert_true(gated.has("fabric_from_wool"))
	assert_true(ProductionRecipes.available("steel", {}))


func test_max_runs_is_limited_by_inputs_and_labour() -> void:
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 10}, 6), 3)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 3}, 20), 1)
	assert_eq(ProductionRecipes.max_runs("lumber", {"timber": 0}, 20), 0)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 9), 2)
	assert_eq(ProductionRecipes.max_runs("bronze", {"copper": 5, "tin": 2}, 2), 0)
	assert_eq(ProductionRecipes.max_runs("unknown", {"timber": 10}, 10), 0)


func test_plan_runs_whole_recipes_and_scales_io() -> void:
	var stock: Dictionary = {"timber": 5}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 3}], stock, 6, {}
	)
	assert_eq(report["runs"], {"lumber": 2})
	assert_eq(report["consumed"], {"timber": 4})
	assert_eq(report["produced"], {"lumber": 2})
	assert_eq(report["labour_used"], 4)
	assert_eq(stock["timber"], 1)
	assert_eq(stock["lumber"], 2)


func test_plan_skips_recipes_it_cannot_run_once() -> void:
	var stock: Dictionary = {"timber": 1}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "lumber", "units": 4}], stock, 10, {}
	)
	assert_eq(report["runs"], {})
	assert_eq(report["produced"], {})
	assert_eq(stock["timber"], 1)
	assert_eq(report["labour_used"], 0)


func test_plan_respects_assignment_order_and_labour_budget() -> void:
	var stock: Dictionary = {"iron": 4, "coal": 2}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "steel", "units": 2},
			{"recipe": "castIron", "units": 2},
		],
		stock,
		4,
		{}
	)
	assert_eq(report["runs"], {"steel": 2})
	assert_eq(stock["steel"], 2)
	assert_eq(stock["iron"], 2)
	assert_eq(stock["coal"], 0)
	assert_eq(report["labour_used"], 4)


func test_plan_ignores_unavailable_and_zero_unit_rows() -> void:
	var stock: Dictionary = {"cotton": 4, "timber": 4}
	var report: Dictionary = ProductionRecipes.plan(
		[
			{"recipe": "fabric_from_cotton", "units": 2},
			{"recipe": "lumber", "units": 0},
			{"recipe": "lumber", "units": -3},
		],
		stock,
		10,
		{}
	)
	assert_eq(report["runs"], {})
	assert_eq(stock["cotton"], 4)
	assert_eq(stock["timber"], 4)
	var allowed: Dictionary = ProductionRecipes.plan(
		[{"recipe": "fabric_from_cotton", "units": 2}], stock, 10, {"cotton_weaving": true}
	)
	assert_eq(allowed["runs"], {"fabric_from_cotton": 2})
	assert_eq(stock["cotton"], 0)
	assert_eq(stock["fabric"], 2)


func test_plan_cannot_drive_quantities_negative() -> void:
	var stock: Dictionary = {"iron": 1, "coal": 1, "timber": 0}
	var report: Dictionary = ProductionRecipes.plan(
		[{"recipe": "steel", "units": 5}], stock, 3, {}
	)
	assert_eq(report["runs"], {"steel": 1})
	assert_eq(stock["iron"], 0)
	assert_eq(stock["coal"], 0)
