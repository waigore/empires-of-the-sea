extends GdToolsTest
## Regiment roster and economy values (wiki: military-units § Regiment Table,
## military-generals § Regiment treasury cost scale).


func test_catalog_lists_every_regiment_once() -> void:
	var ids: Array[String] = RegimentCatalog.ids()
	assert_eq(ids.size(), 29)
	var seen: Dictionary = {}
	for type_id: String in ids:
		assert_false(seen.has(type_id), "duplicate regiment %s" % type_id)
		seen[type_id] = true
		assert_eq(RegimentCatalog.display_name(type_id), String(RegimentCatalog.row(type_id)["name"]))


func test_tactical_stats_match_the_wiki_table() -> void:
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpn"), 0)
	assert_eq(RegimentCatalog.stat("peasant_levies", "fpm"), 3)
	assert_eq(RegimentCatalog.stat("guards", "fpn"), 12)
	assert_eq(RegimentCatalog.stat("guards", "fpm"), 10)
	assert_eq(RegimentCatalog.stat("siege_guns", "rng"), 12)
	assert_eq(RegimentCatalog.stat("carbine_cavalry", "mvr"), 9)
	assert_eq(RegimentCatalog.era("guards"), 4)
	assert_eq(RegimentCatalog.era("culverin"), 1)


func test_categories_drive_cavalry_and_infantry_rules() -> void:
	assert_true(RegimentCatalog.is_cavalry("squires"))
	assert_true(RegimentCatalog.is_cavalry("cuirassiers"))
	assert_false(RegimentCatalog.is_cavalry("guards"))
	assert_true(RegimentCatalog.is_artillery("royal_artillery"))
	assert_false(RegimentCatalog.is_infantry("field_artillery"))
	assert_true(RegimentCatalog.is_infantry("bowmen"))
	assert_true(RegimentCatalog.is_infantry("peasant_levies"))


func test_treasury_costs_follow_the_canonical_scale() -> void:
	assert_eq(RegimentCatalog.treasury_cost("peasant_levies"), 2000)
	assert_eq(RegimentCatalog.treasury_cost("arquebusiers"), 5000)
	assert_eq(RegimentCatalog.treasury_cost("siege_guns"), 22000)


func test_food_upkeep_keeps_cavalry_and_artillery_highest() -> void:
	assert_eq(RegimentCatalog.food_upkeep("peasant_levies"), 1)
	assert_eq(RegimentCatalog.food_upkeep("pikemen"), 2)
	assert_eq(RegimentCatalog.food_upkeep("guards"), 3)
	assert_eq(RegimentCatalog.food_upkeep("squires"), 3)
	assert_eq(RegimentCatalog.food_upkeep("culverin"), 3)


func test_unknown_types_fall_back_to_peasant_levies() -> void:
	assert_eq(RegimentCatalog.normalize("dragoons"), RegimentCatalog.DEFAULT_TYPE)
	assert_eq(RegimentCatalog.display_name("dragoons"), "Regiment")
	assert_false(RegimentCatalog.has_type("dragoons"))


func test_garrison_recovery_uses_the_most_advanced_infantry_for_the_era() -> void:
	assert_eq(RegimentCatalog.garrison_type_for(4), "guards")
	assert_eq(RegimentCatalog.garrison_type_for(1), "arquebusiers")
	assert_eq(RegimentCatalog.garrison_type_for(9), RegimentCatalog.DEFAULT_TYPE)
