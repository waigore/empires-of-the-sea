extends GdToolsTest
## Research slots, funding, progress and knowledge (wiki: research-state,
## tech-tree § Research Model, tech-and-extraction-cap).

var _state: ResearchState = null


func before_each() -> void:
	_state = ResearchState.make()


func test_a_fresh_crown_has_three_empty_slots() -> void:
	assert_eq(_state.slot_count(), ResearchState.DEFAULT_SLOTS)
	assert_eq(_state.slots.size(), 3)
	assert_eq(_state.researching(), [] as Array[Dictionary])
	assert_eq(_state.unlocked_ids(), [] as Array[String])
	for index in 3:
		assert_eq(_state.tech_at(index), ResearchState.EMPTY_TECH)
		assert_eq(_state.funding_at(index), ResearchFunding.DEFAULT)


func test_university_opens_a_fourth_slot() -> void:
	_state.unlock("university")
	assert_eq(_state.slot_count(), 4)
	assert_eq(_state.slots.size(), 4)


func test_assigning_fills_the_first_free_slot() -> void:
	var result: Dictionary = _state.assign("crop_rotation")
	assert_true(bool(result["ok"]), String(result["message"]))
	assert_eq(_state.tech_at(0), "crop_rotation")
	assert_eq(_state.funding_at(0), "medium")
	assert_eq(_state.progress_of("crop_rotation"), 0)
	assert_eq(_state.researching().size(), 1)


func test_prerequisites_gate_the_tree() -> void:
	var result: Dictionary = _state.assign("iron_mining")
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("prerequisite"))
	_state.unlock("mine_engineering")
	assert_true(bool(_state.assign("iron_mining")["ok"]))


func test_a_tech_holds_one_slot_at_a_time() -> void:
	assert_true(bool(_state.assign("crop_rotation")["ok"]))
	var again: Dictionary = _state.assign("crop_rotation")
	assert_false(bool(again["ok"]))
	assert_true(String(again["reason"]).contains("slot"))


func test_three_slots_are_the_limit_until_university() -> void:
	for tech_id: String in ["crop_rotation", "saw_mill", "land_enclosure"]:
		assert_true(bool(_state.assign(tech_id)["ok"]))
	var fourth: Dictionary = _state.assign("printing_press")
	assert_false(bool(fourth["ok"]))
	assert_true(String(fourth["reason"]).contains("All research slots"))
	_state.unlock("university")
	assert_true(bool(_state.assign("printing_press")["ok"]))
	assert_eq(_state.tech_at(3), "printing_press")


func test_cancelling_forfeits_progress() -> void:
	assert_true(bool(_state.assign("crop_rotation")["ok"]))
	_state.add_progress("crop_rotation", 900)
	var result: Dictionary = _state.cancel(0)
	assert_true(bool(result["ok"]))
	assert_eq(_state.progress_of("crop_rotation"), 0)
	assert_eq(_state.tech_at(0), ResearchState.EMPTY_TECH)
	assert_false(bool(_state.cancel(0)["ok"]))


func test_funding_cycles_through_the_presets() -> void:
	assert_true(bool(_state.assign("crop_rotation", "low")["ok"]))
	assert_eq(_state.cycle_funding(0), "medium")
	assert_eq(_state.cycle_funding(0), "high")
	assert_true(_state.set_funding(0, "maximum"))
	assert_eq(_state.funding_at(0), "maximum")
	assert_false(_state.set_funding(0, "lavish"))
	assert_eq(ResearchFunding.gold("maximum"), 1000)
	assert_eq(ResearchFunding.rp("maximum"), 2500)


func test_discovery_techs_wait_for_the_resource() -> void:
	assert_false(_state.researchable().has("discovery_of_sugar"))
	assert_false(bool(_state.assign("discovery_of_sugar")["ok"]))
	_state.set_revealed({"sugarCane": true})
	assert_true(_state.researchable().has("discovery_of_sugar"))
	assert_true(bool(_state.assign("discovery_of_sugar")["ok"]))


func test_researchable_grows_as_the_tree_opens() -> void:
	assert_true(_state.researchable().has("land_enclosure"))
	assert_false(_state.researchable().has("seed_drill"))
	_state.unlock("land_enclosure")
	assert_true(_state.researchable().has("seed_drill"))
	assert_false(_state.researchable().has("land_enclosure"))


func test_unlocking_clears_the_slot() -> void:
	assert_true(bool(_state.assign("land_enclosure")["ok"]))
	_state.add_progress("land_enclosure", 1800)
	_state.unlock("land_enclosure")
	assert_true(_state.is_unlocked("land_enclosure"))
	assert_eq(_state.tech_at(0), ResearchState.EMPTY_TECH)
	assert_false(_state.progress.has("land_enclosure"))


func test_research_floor_follows_money_lending_and_banking() -> void:
	assert_eq(_state.treasury_floor(), 0)
	_state.unlock("money_lending")
	assert_eq(_state.treasury_floor(), ResearchFunding.DEBT_FLOOR)
	_state.unlock("banking")
	assert_eq(_state.treasury_floor(), ResearchFunding.BANK_DEBT_FLOOR)


func test_copy_is_independent() -> void:
	assert_true(bool(_state.assign("crop_rotation")["ok"]))
	var clone: ResearchState = _state.copy()
	clone.add_progress("crop_rotation", 500)
	clone.unlock("saw_mill")
	assert_eq(_state.progress_of("crop_rotation"), 0)
	assert_false(_state.is_unlocked("saw_mill"))
	assert_eq(clone.tech_at(0), "crop_rotation")


# --- tech unlocks ---
## One tech -> one answer for every build order it opens (wiki: tech-tree
## § Effect Types; tech-tree-military, -naval, -transport, civilian-units).
## The ledger text and the gate tables are checked against each other so a
## researched tech can never open a door the player was not told about.


func test_regiments_derive_from_the_training_catalog() -> void:
	assert_true(_has_unlock("organised_regiments", "lancers"), "Lancers")
	assert_true(_has_unlock("bayonet", "regulars"), "Regulars")
	assert_false(_has_unlock("organised_regiments", "regulars"), "a tech names only its own row")
	assert_true(TechUnlocks.lines("organised_regiments")[0].contains("Lancers regiment"))


func test_every_gated_regiment_is_named_by_its_tech() -> void:
	for type_id: String in RegimentEconomy.TECH.keys():
		var tech_id: String = String(RegimentEconomy.TECH[type_id])
		if tech_id.is_empty():
			continue
		assert_true(_has_unlock(tech_id, type_id), "%s must name %s" % [tech_id, type_id])


func test_every_gated_hull_is_named_by_its_tech() -> void:
	for type_id: String in ShipEconomy.TECH.keys():
		var tech_id: String = String(ShipEconomy.TECH[type_id])
		if tech_id.is_empty():
			continue
		assert_true(_has_unlock(tech_id, type_id), "%s must name %s" % [tech_id, type_id])
	assert_true(_has_unlock("superior_hull_design", "fluyte"))
	assert_true(TechUnlocks.lines("superior_hull_design")[0].contains("Fluyte hull"))


func test_civilians_and_worker_tiers_are_named() -> void:
	assert_true(_has_unlock("merchant_companies", "merchant"))
	assert_true(_has_unlock("early_steam_engine", "rail_builder"))
	for tier in range(1, WorkerPool.TIER_COUNT):
		for tech_id: String in WorkerPool.required_techs(tier):
			assert_true(
				_has_unlock(tech_id, "worker_%d" % tier),
				"%s names tier %d" % [tech_id, tier]
			)


func test_forts_and_emplaced_batteries_are_enables() -> void:
	var fort: Dictionary = _unlock("mine_engineering", "fort_2")
	assert_eq(int(fort.get("kind", -1)), TechUnlocks.Kind.ENABLE)
	assert_true(_has_unlock("modern_forts", "fort_3"))
	assert_true(_has_unlock("heavy_emplaced_artillery", "emplaced_heavy_artillery"))
	assert_true(_has_unlock("emplaced_siege_guns", "emplaced_siege_guns"))
	assert_true(TechUnlocks.lines("modern_forts")[0].contains("fort level 3"))


func test_rail_and_road_orders_follow_the_terrain_techs() -> void:
	assert_true(_has_unlock("road_construction", "road_level_2"), "improved roads")
	assert_true(_has_unlock("early_steam_engine", "rail_flat"), "flat terrain")
	assert_true(_has_unlock("later_steam_engine", "rail_hills"), "hills and swamps")
	assert_true(_has_unlock("dynamite", "rail_mountains"), "mountains")
	assert_false(_has_unlock("early_steam_engine", "rail_hills"), "hills need the later engine")
	assert_eq(CivilianTransport.rail_tech_for(MapModel.Terrain.MOUNTAINS), "dynamite")
	assert_eq(CivilianTransport.rail_tech_for(MapModel.Terrain.PLAINS), "early_steam_engine")


func test_the_general_cap_is_an_improvement() -> void:
	var cap: Dictionary = _unlock("organised_regiments", "general_cap")
	assert_eq(int(cap.get("kind", -1)), TechUnlocks.Kind.IMPROVE)
	assert_eq(String(cap.get("name", "")), "general cap to 2")
	assert_true(_has_unlock("nationalism", "general_cap"), "Nationalism raises the cap to 4")


func test_effect_text_names_the_unlocked_orders() -> void:
	var troops: String = TechCatalog.effect_text("organised_regiments")
	assert_true(troops.contains("Lancers regiment"), troops)
	assert_true(troops.contains("general cap to 2"), troops)
	assert_true(TechCatalog.effect_text("superior_hull_design").contains("Fluyte hull"))
	assert_true(TechCatalog.effect_text("road_construction").contains("transport level 2"))
	assert_true(TechCatalog.effect_text("later_steam_engine").contains("hills and swamps"))


## Wiki: tech-tree-gathering § Acceptance Criteria — every row carries at least
## one fixed-field phrase and no generic fallback.
func test_every_tech_has_a_fixed_field_phrase() -> void:
	var phrases: Array[String] = ["Unlocks:", "Improves:", "Enables:", "Prerequisite-only:"]
	for tech_id: String in TechCatalog.ids():
		var text: String = TechCatalog.effect_text(tech_id)
		var found: bool = false
		for phrase: String in phrases:
			found = found or text.contains(phrase)
		assert_true(found, tech_id)


func test_gate_tables_only_name_catalog_techs() -> void:
	var errors: Array[String] = TechAudit.validate()
	assert_true(errors.is_empty(), ", ".join(errors))


func _unlock(tech_id: String, id: String) -> Dictionary:
	for row: Dictionary in TechUnlocks.entries(tech_id):
		if String(row["id"]) == id:
			return row
	return {}


func _has_unlock(tech_id: String, id: String) -> bool:
	return not _unlock(tech_id, id).is_empty()
