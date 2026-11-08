extends GdToolsTest
## The static tech catalog and its audit (wiki: tech-tree § Catalog,
## tech-and-extraction-cap § Static catalog validation).


func test_catalog_holds_the_full_wiki_tree() -> void:
	assert_eq(TechCatalog.TECHS.size(), TechAudit.EXPECTED_COUNT)
	assert_eq(TechCatalog.ids().size(), TechCatalog.TECHS.size())
	assert_eq(TechAudit.validate(), [] as Array[String])
	assert_true(TechCatalog.roots().size() >= 7, "several starting techs")


func test_costs_follow_the_era_formula() -> void:
	var costs: Dictionary = {}
	for tech_id: String in TechCatalog.ids():
		costs[TechCatalog.cost(tech_id)] = true
	assert_eq(costs.size(), 4)
	assert_true(costs.has(1800))
	assert_true(costs.has(2400))
	assert_true(costs.has(3000))
	assert_true(costs.has(3600))
	assert_eq(TechCatalog.cost("crop_rotation"), 1800)
	assert_eq(TechCatalog.cost("saw_mill"), 1800)
	assert_eq(TechCatalog.cost("wind_saw_mill"), 2400)
	assert_eq(TechCatalog.cost("circular_saw"), 3000)
	assert_eq(TechCatalog.cost("safety_lamp"), 3600)


func test_prerequisites_cross_categories() -> void:
	assert_has(TechCatalog.prerequisites("circular_saw"), "university")
	assert_has(TechCatalog.prerequisites("dynamite"), "banking")
	assert_has(TechCatalog.prerequisites("dynamite"), "explosives")
	assert_has(TechCatalog.prerequisites("large_tobacco_plantations"), "seed_drill")
	assert_has(TechCatalog.dependents("university"), "advanced_hull_design")
	assert_eq(TechCatalog.prerequisites("crop_rotation"), [] as Array[String])


func test_extraction_caps_default_to_one() -> void:
	assert_eq(TechCatalog.extraction_caps({}), {})
	assert_eq(TechCatalog.cap_for("grain", {}), 1)
	assert_eq(TechCatalog.cap_for("timber", {"land_enclosure": true}), 1)
	assert_eq(TechCatalog.cap_for("horses", {"crop_rotation": true}), 1)


func test_gathering_techs_lift_the_cap_per_resource() -> void:
	var unlocked: Dictionary = {"land_enclosure": true}
	assert_eq(TechCatalog.cap_for("grain", unlocked), 2)
	unlocked["seed_drill"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 3)
	unlocked["moldboard_plow"] = true
	assert_eq(TechCatalog.cap_for("grain", unlocked), 4)
	assert_eq(TechCatalog.extraction_caps(unlocked), {"grain": 4})


func test_cap_chains_stop_at_the_wiki_exceptions() -> void:
	var wool: Dictionary = {"sheep_ranching": true, "scientific_sheep_breeding": true}
	assert_eq(TechCatalog.cap_for("wool", wool), TechCatalog.CAP_EXCEPTIONS["wool"])
	assert_eq(TechCatalog.CAP_EXCEPTIONS["horses"], 1)
	var iron: Dictionary = {
		"iron_mining": true, "steam_in_mining": true, "industrial_iron_mining": true,
	}
	assert_eq(TechCatalog.cap_for("iron", iron), 4)
	var copper: Dictionary = {
		"copper_and_tin_mining": true, "large_copper_and_tin_mines": true,
		"efficient_extraction_of_copper_and_tin": true,
	}
	assert_eq(TechCatalog.cap_for("copper", copper), 4)
	assert_eq(TechCatalog.cap_for("tin", copper), 4)


func test_discovery_techs_name_their_resources() -> void:
	assert_eq(TechCatalog.discovery_resources("discovery_of_sugar"), ["sugarCane"])
	assert_eq(
		TechCatalog.discovery_resources("discovery_of_gold_or_silver"),
		["gold", "silver"]
	)
	assert_eq(TechCatalog.discovery_resources("saw_mill"), [] as Array[String])
	assert_eq(TechCatalog.display_name("discovery_of_sugar"), "Discovery of Sugar")


func test_effect_text_uses_the_fixed_phrases() -> void:
	assert_true(TechCatalog.effect_text("saw_mill").contains("Improves:"))
	assert_true(TechCatalog.effect_text("saw_mill").to_lower().contains("timber"))
	assert_true(TechCatalog.effect_text("land_enclosure").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("discovery_of_sugar").contains("Enables:"))
	assert_true(TechCatalog.effect_text("clipper_ships").contains("Unlocks:"))
	assert_true(TechCatalog.effect_text("crop_rotation").contains("Unlocks:"))
