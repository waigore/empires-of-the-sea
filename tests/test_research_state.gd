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
