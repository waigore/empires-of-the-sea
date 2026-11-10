extends GdToolsTest
## Slot-assignment persistence (wiki: research-state § Slot Occupancy
## Persistence): loading drops what the catalog or the roster cannot hold and
## forfeits progress no slot binds.

var _economy: PlayerEconomy = null


func before_each() -> void:
	_economy = PlayerEconomy.starting()


func _load(research: Dictionary) -> ResearchState:
	_economy.apply_snapshot({"research": research})
	return _economy.research


func test_a_positional_array_restores_each_slot() -> void:
	var state: ResearchState = _load({
		"slots": [
			{"tech": "crop_rotation", "funding": "high"},
			{"tech": "saw_mill", "funding": "low"},
		],
	})
	assert_eq(state.tech_at(0), "crop_rotation")
	assert_eq(state.funding_at(0), "high")
	assert_eq(state.tech_at(1), "saw_mill")
	assert_eq(state.funding_at(1), "low")
	assert_eq(state.tech_at(2), ResearchState.EMPTY_TECH)
	assert_eq(state.slots.size(), ResearchState.DEFAULT_SLOTS)


func test_the_object_form_keys_slots_by_index() -> void:
	var state: ResearchState = _load({
		"slots": {
			"0": {"tech": "crop_rotation", "funding": "medium"},
			"2": {"tech": "mine_engineering", "funding": "maximum"},
		},
	})
	assert_eq(state.tech_at(0), "crop_rotation")
	assert_eq(state.tech_at(1), ResearchState.EMPTY_TECH)
	assert_eq(state.tech_at(2), "mine_engineering")
	assert_eq(state.funding_at(2), "maximum")


func test_a_negative_slot_index_is_dropped() -> void:
	var state: ResearchState = _load({
		"slots": {"-1": {"tech": "crop_rotation", "funding": "medium"}},
	})
	assert_eq(state.researching().size(), 0)


func test_an_empty_tech_id_is_dropped() -> void:
	var state: ResearchState = _load({
		"slots": [{"tech": "", "funding": "medium"}, {"tech": "saw_mill", "funding": "low"}],
	})
	assert_eq(state.tech_at(0), ResearchState.EMPTY_TECH)
	assert_eq(state.tech_at(1), "saw_mill")


func test_a_missing_funding_level_defaults_to_none() -> void:
	var state: ResearchState = _load({"slots": [{"tech": "crop_rotation"}]})
	assert_eq(state.funding_at(0), "none")


func test_an_unknown_funding_level_defaults_to_none() -> void:
	var state: ResearchState = _load({
		"slots": [{"tech": "crop_rotation", "funding": "extravagant"}],
	})
	assert_eq(state.funding_at(0), "none")


func test_an_unknown_tech_is_dropped() -> void:
	var state: ResearchState = _load({
		"slots": [{"tech": "steam_punkery", "funding": "medium"}],
	})
	assert_eq(state.researching().size(), 0)


func test_a_slot_beyond_the_roster_is_dropped() -> void:
	var state: ResearchState = _load({
		"slots": {"3": {"tech": "crop_rotation", "funding": "medium"}},
	})
	assert_eq(state.researching().size(), 0, "three slots by default; index 3 cannot hold one")


func test_university_widens_the_roster_before_slots_load() -> void:
	var state: ResearchState = _load({
		"unlocked": {"university": true},
		"slots": {"3": {"tech": "crop_rotation", "funding": "medium"}},
	})
	assert_eq(state.slots.size(), ResearchState.UNIVERSITY_SLOTS)
	assert_eq(state.tech_at(3), "crop_rotation")


func test_a_tech_already_known_is_not_left_in_a_slot() -> void:
	var state: ResearchState = _load({
		"unlocked": {"crop_rotation": true},
		"slots": [{"tech": "crop_rotation", "funding": "medium"}],
	})
	assert_eq(state.researching().size(), 0)


func test_one_slot_per_tech() -> void:
	var state: ResearchState = _load({
		"slots": [
			{"tech": "crop_rotation", "funding": "medium"},
			{"tech": "crop_rotation", "funding": "low"},
		],
	})
	assert_eq(state.researching().size(), 1)


func test_progress_bound_to_a_slot_survives() -> void:
	var state: ResearchState = _load({
		"progress": {"crop_rotation": 900},
		"slots": [{"tech": "crop_rotation", "funding": "medium"}],
	})
	assert_eq(state.progress_of("crop_rotation"), 900)


func test_orphaned_progress_is_forfeited() -> void:
	var state: ResearchState = _load({
		"progress": {"crop_rotation": 900, "saw_mill": 400},
		"slots": [{"tech": "crop_rotation", "funding": "medium"}],
	})
	assert_eq(state.progress_of("crop_rotation"), 900)
	assert_eq(state.progress_of("saw_mill"), 0, "no slot binds it, so its RP is lost")
	assert_false(state.progress.has("saw_mill"))


func test_a_legacy_save_without_slots_loads_no_study() -> void:
	var state: ResearchState = _load({"progress": {"crop_rotation": 900}})
	assert_eq(state.researching().size(), 0)
	assert_eq(state.progress_of("crop_rotation"), 0)
	assert_eq(state.slots.size(), ResearchState.DEFAULT_SLOTS)


func test_revealed_commodities_survive_a_round_trip() -> void:
	_economy.research.set_revealed({"sugarCane": true})
	_economy.apply_snapshot(_economy.snapshot())
	assert_true(bool(_economy.research.revealed.get("sugarCane", false)))
