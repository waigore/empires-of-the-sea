extends GdToolsTest
## Research slots, funding, progress and knowledge (wiki: research-state,
## tech-tree § Research Model, tech-and-extraction-cap).
## Consolidated rulebook: test_research_slots, test_research_turn,
## test_tech_discovery, test_tech_icons, test_tech_order,
## test_research_panel (one Godot boot per domain).


const Fixture = preload("res://tests/civilian_fixture.gd")

var _state: ResearchState = null
var _economy: PlayerEconomy = null
var _turn_economy: PlayerEconomy = null
var _turn_state: ResearchState = null
var _world: WorldMap = null
var _model: MapModel = null
var _view: VisibilityModel = null
var _works: LandWorks = null
var _panel: ResearchPanel = null
var _panel_state: ResearchState = null


func before_each() -> void:
	_state = ResearchState.make()
	_economy = PlayerEconomy.starting()
	_turn_economy = PlayerEconomy.starting()
	_turn_state = _turn_economy.research
	_model = Fixture.build()
	_world = WorldMap.new()
	_world.add_region(_model)
	_works = LandWorks.new()
	_view = VisibilityModel.new()
	_view.setup(_model, 0)
	_view.apply_initial()
	_panel_state = ResearchState.make()
	_panel = ResearchPanel.new()
	add_child(_panel)


func after_each() -> void:
	if is_instance_valid(_panel):
		_panel.free()
	_panel = null


func test_a_fresh_crown_has_three_empty_slots() -> void:
	assert_eq(_state.slot_count(), ResearchState.DEFAULT_SLOTS)
	assert_eq(_state.slots.size(), 3)
	assert_eq(_state.researching(), [] as Array[Dictionary])
	assert_eq(_state.unlocked_ids(), [] as Array[String])
	assert_eq(_state.goal, "", "a new college carries no goal")
	for index in 3:
		assert_eq(_state.tech_at(index), ResearchState.EMPTY_TECH)
		assert_eq(_state.funding_at(index), ResearchFunding.DEFAULT)


## The ledger goal is client state kept with the campaign: it reorders the view
## and reaches no research arithmetic, but a copy must carry it (wiki: tech-tree
## § Goal slot; DR-20261111-21).
func test_a_copy_carries_the_ledger_goal() -> void:
	_state.goal = "bayonet"
	assert_eq(_state.copy().goal, "bayonet")


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


# --- late-gate military effects (DR-20261110-17) -----------------------------
func test_an_upgrade_path_reads_as_an_improvement() -> void:
	var row: Dictionary = _unlock("improved_iron_weapons", "upgrade_pikemen")
	assert_eq(int(row.get("kind", -1)), TechUnlocks.Kind.IMPROVE)
	assert_eq(String(row.get("name", "")), "Pikemen upgrade path")
	assert_true(_has_unlock("needle_guns", "upgrade_regulars"), "Regulars -> Rifle Infantry")
	assert_true(_has_unlock("high_grade_steel", "upgrade_heavy_artillery"))
	assert_false(
		_has_unlock("improved_cavalry_tactics", "upgrade_squires"),
		"the first heavy cavalry has nothing to replace"
	)
	assert_true(TechCatalog.effect_text("bayonet").contains("Halberdiers upgrade path"))


func test_the_attack_cost_techs_name_their_factor() -> void:
	var row: Dictionary = _unlock("industrial_machinery", "attack_cost")
	assert_eq(int(row.get("kind", -1)), TechUnlocks.Kind.IMPROVE)
	assert_eq(String(row.get("name", "")), "land-battle attack cost ×0.75")
	assert_true(_has_unlock("modern_military_funding", "attack_cost"))
	assert_true(TechCatalog.effect_text("industrial_machinery").contains("×0.75"))
	assert_false(
		TechCatalog.effect_text("banking").contains("attack cost"),
		"only the two funding techs move the price"
	)


# --- merged from tests/test_research_slots.gd ---


## Slot-assignment persistence (wiki: research-state § Slot Occupancy
## Persistence): loading drops what the catalog or the roster cannot hold and
## forfeits progress no slot binds.
func _load(research: Dictionary) -> ResearchState:
	_economy.apply_snapshot({"research": research})
	return _economy.research


## The ledger goal rides the research snapshot so a load reopens the same queue;
## an absent or unreadable goal opens catalog order (wiki: tech-tree § Goal slot;
## campaign-persistence § Snapshot contract; DR-20261111-21).
func test_the_goal_rides_the_snapshot() -> void:
	_economy.research.goal = "bayonet"
	var saved: Dictionary = _economy.snapshot()
	assert_eq(
		String((saved["research"] as Dictionary).get("goal", "")),
		"bayonet",
		"the snapshot carries the goal"
	)
	assert_eq(_load(saved["research"]).goal, "bayonet", "the loaded ledger keeps its goal")


func test_a_missing_or_unreadable_goal_opens_catalog_order() -> void:
	assert_eq(_load({}).goal, "", "a save that carries none has no goal")
	assert_eq(_load({"goal": "no_such_tech"}).goal, "", "an unreadable id has no goal")


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


# --- merged from tests/test_research_turn.gd ---


## The Research phase: funding, points, completion and the economy hand-off
## (wiki: tech-tree § Research Model; tech-and-extraction-cap).
func _resolve(turns: int) -> Dictionary:
	var report: Dictionary = {}
	for _turn in turns:
		report = ResearchTurn.resolve(_turn_state, _turn_economy)
	return report


func test_a_tier_one_tech_takes_six_medium_turns() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	_resolve(5)
	assert_false(_turn_state.is_unlocked("land_enclosure"))
	assert_eq(_turn_state.progress_of("land_enclosure"), 1500)
	_resolve(1)
	assert_true(_turn_state.is_unlocked("land_enclosure"))
	assert_eq(_turn_state.tech_at(0), ResearchState.EMPTY_TECH)


func test_a_tier_four_tech_takes_twelve_medium_turns() -> void:
	_turn_state.unlock("large_coal_mines")
	_turn_state.unlock("dynamite")
	assert_true(bool(_turn_state.assign("safety_lamp", "medium")["ok"]))
	_resolve(11)
	assert_false(_turn_state.is_unlocked("safety_lamp"))
	assert_eq(_turn_state.progress_of("safety_lamp"), 3300)
	_resolve(1)
	assert_true(_turn_state.is_unlocked("safety_lamp"))


func test_low_funding_earns_one_hundred_points() -> void:
	var report: Dictionary = {}
	assert_true(bool(_turn_state.assign("land_enclosure", "low")["ok"]))
	report = ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(_turn_state.progress_of("land_enclosure"), 100)
	assert_eq(int(report["spent"]), 50)
	assert_false(_turn_state.is_unlocked("land_enclosure"))


func test_a_spy_network_lifts_a_funded_slot_by_fifteen_percent() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "low")["ok"]))
	var report: Dictionary = ResearchTurn.resolve(
		_turn_state, _turn_economy, {"land_enclosure": SpyNetworks.BOOST_PERCENT}
	)
	assert_eq(_turn_state.progress_of("land_enclosure"), 115)
	assert_eq(int((report["slots"] as Array)[0]["boost"]), 15)
	assert_eq((report["boosted"] as Array).size(), 1, "the ledger names the study")


func test_spies_do_not_lift_an_unfunded_slot() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "none")["ok"]))
	var report: Dictionary = ResearchTurn.resolve(
		_turn_state, _turn_economy, {"land_enclosure": SpyNetworks.BOOST_PERCENT}
	)
	assert_eq(_turn_state.progress_of("land_enclosure"), 0)
	assert_eq(int((report["slots"] as Array)[0]["boost"]), 0)
	assert_eq((report["boosted"] as Array).size(), 0)


func test_a_spy_network_only_lifts_the_techs_it_covers() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "low")["ok"]))
	ResearchTurn.resolve(_turn_state, _turn_economy, {"saw_mill": SpyNetworks.BOOST_PERCENT})
	assert_eq(_turn_state.progress_of("land_enclosure"), 100, "no share for an uncovered tech")


func test_the_spy_share_adds_to_industrial_funding_before_rounding() -> void:
	_turn_state.unlock("industrial_funding_of_research")
	_turn_state.unlock("land_enclosure")
	assert_true(bool(_turn_state.assign("organised_regiments", "medium")["ok"]))
	ResearchTurn.resolve(_turn_state, _turn_economy, {"organised_regiments": 15})
	assert_eq(_turn_state.progress_of("organised_regiments"), 405, "300 × 1.35")
	assert_eq(
		ResearchTurn.points_for(_turn_state, "organised_regiments", "medium", 15), 405
	)


func test_industrial_funding_boosts_military_techs() -> void:
	_turn_state.unlock("industrial_funding_of_research")
	_turn_state.unlock("land_enclosure")
	assert_true(bool(_turn_state.assign("organised_regiments", "medium")["ok"]))
	ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(_turn_state.progress_of("organised_regiments"), 360)
	assert_eq(ResearchTurn.points_for(_turn_state, "organised_regiments", "medium"), 360)
	assert_eq(ResearchTurn.points_for(_turn_state, "land_enclosure", "medium"), 300)


## Victoria's funding multiplier lifts the base funding RP before the spy share
## and Industrial Funding are applied, and the phase and the ledger read one
## figure (wiki: leader-bonuses § Bonus Table — Victoria ×1.15).
func test_the_leader_funding_multiplier_lifts_base_rp_before_the_shares() -> void:
	assert_eq(ResearchTurn.funded_rp("medium"), 300)
	assert_eq(ResearchTurn.funded_rp("medium", "victoria"), 345, "300 × 1.15")
	assert_eq(ResearchTurn.funded_rp("medium", "napoleon"), 300, "no funding row for France")
	_turn_state.unlock("land_enclosure")
	assert_true(bool(_turn_state.assign("organised_regiments", "medium")["ok"]))
	assert_eq(
		ResearchTurn.points_for(_turn_state, "organised_regiments", "medium", 0, "victoria"),
		345
	)
	assert_eq(
		ResearchTurn.points_for(_turn_state, "organised_regiments", "medium", 15, "victoria"),
		396, "345 plus the spy's 15%"
	)
	_turn_state.unlock("industrial_funding_of_research")
	assert_eq(
		ResearchTurn.points_for(_turn_state, "organised_regiments", "medium", 15, "victoria"),
		448, "345 plus the 30% shares"
	)
	var plan: Dictionary = ResearchTurn.preview(
		_turn_state, "organised_regiments", "medium", 5000, 15, "victoria"
	)
	assert_eq(int(plan["rp"]), 448, "the ledger shows the same figure")
	ResearchTurn.resolve(_turn_state, _turn_economy, {}, "victoria")
	assert_eq(_turn_state.progress_of("organised_regiments"), 448)


func test_none_funding_spends_and_earns_nothing() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "none")["ok"]))
	var treasury: int = _turn_economy.treasury
	var report: Dictionary = ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(int(report["spent"]), 0)
	assert_eq(_turn_economy.treasury, treasury)
	assert_eq(_turn_state.progress_of("land_enclosure"), 0)


func test_an_unpayable_slot_earns_nothing() -> void:
	_turn_economy.treasury = 100
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	var report: Dictionary = ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_false(bool((report["slots"] as Array[Dictionary])[0]["paid"]))
	assert_eq(_turn_state.progress_of("land_enclosure"), 0)
	assert_eq(_turn_economy.treasury, 100)
	assert_eq((report["unpaid"] as Array[String]).size(), 1)


## The phase reports the floor it paid against, so the turn's despatch can name
## the rule that left a study unpaid instead of only counting it (wiki:
## tech-tree-labour-economy § money_lending, banking; REQ-P5-05).
func test_the_phase_reports_the_floor_it_paid_against() -> void:
	_turn_state.unlock("money_lending")
	_turn_economy.treasury = ResearchFunding.DEBT_FLOOR + 20
	assert_true(bool(_turn_state.assign("land_enclosure", "low")["ok"]))
	var report: Dictionary = ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(int(report["floor"]), ResearchFunding.DEBT_FLOOR)
	assert_eq((report["unpaid"] as Array[String]).size(), 1, "20 short of a 50 payment")
	assert_eq(_turn_economy.treasury, ResearchFunding.DEBT_FLOOR + 20, "nothing left the purse")


# --- the ledger's preview ----------------------------------------------------
## The college ledger draws its spend line and gauge from `preview`, so the
## figures it shows must be the ones the phase then applies (REQ-P1-05).
func test_the_preview_matches_what_the_phase_spends_and_earns() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "high")["ok"]))
	var plan: Dictionary = ResearchTurn.preview(
		_turn_state, "land_enclosure", "high", _turn_economy.treasury
	)
	assert_eq(int(plan["gold"]), 400)
	assert_eq(int(plan["rp"]), 800)
	assert_true(bool(plan["paid"]))
	assert_eq(int(plan["cost"]), 1800)
	var row: Dictionary = (ResearchTurn.resolve(_turn_state, _turn_economy)["slots"] as Array)[0]
	assert_eq(int(row["gold"]), int(plan["gold"]))
	assert_eq(int(row["rp"]), int(plan["rp"]))


func test_the_preview_calls_an_unaffordable_slot_unpaid() -> void:
	_turn_economy.treasury = 100
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	var plan: Dictionary = ResearchTurn.preview(
		_turn_state, "land_enclosure", "medium", _turn_economy.treasury
	)
	assert_false(bool(plan["paid"]))
	assert_eq(int(plan["gold"]), 0)
	assert_eq(int(plan["rp"]), 0, "an unpaid slot buys nothing")


## Money Lending lets the preview spend down to the floor, exactly as the phase
## does — one ducat short of it, the slot is unpaid.
func test_the_preview_spends_down_to_the_research_floor() -> void:
	_turn_state.unlock("money_lending")
	var exact: Dictionary = ResearchTurn.preview(
		_turn_state, "land_enclosure", "maximum", 500
	)
	assert_true(bool(exact["paid"]), "500 gold reaches the −500 floor exactly")
	assert_eq(int(exact["gold"]), 1000)
	var short: Dictionary = ResearchTurn.preview(
		_turn_state, "land_enclosure", "maximum", 499
	)
	assert_false(bool(short["paid"]), "one ducat short of the floor")


func test_the_preview_carries_the_spy_and_industrial_shares() -> void:
	_turn_state.unlock("industrial_funding_of_research")
	_turn_state.unlock("land_enclosure")
	var plan: Dictionary = ResearchTurn.preview(
		_turn_state, "organised_regiments", "medium", 5000, SpyNetworks.BOOST_PERCENT
	)
	assert_eq(int(plan["boost"]), 15)
	assert_eq(int(plan["rp"]), 405, "300 × 1.35")


func test_the_preview_of_an_idle_slot_is_empty() -> void:
	var plan: Dictionary = ResearchTurn.preview(_turn_state, "", "medium", 5000)
	assert_eq(int(plan["cost"]), 0)
	assert_eq(int(plan["rp"]), 0)
	assert_eq(int(plan["gold"]), 0)


func test_money_lending_lets_research_borrow() -> void:
	_turn_state.unlock("money_lending")
	_turn_economy.treasury = 100
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(_turn_economy.treasury, -50)
	assert_eq(_turn_state.progress_of("land_enclosure"), 300)


func test_banking_extends_the_research_floor() -> void:
	_turn_state.unlock("money_lending")
	_turn_state.unlock("banking")
	_turn_economy.treasury = 100
	assert_true(bool(_turn_state.assign("land_enclosure", "maximum")["ok"]))
	ResearchTurn.resolve(_turn_state, _turn_economy)
	assert_eq(_turn_economy.treasury, -900)
	assert_true(_turn_state.is_unlocked("land_enclosure"))


func test_the_economy_turn_runs_research_after_production() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	var report: Dictionary = EconomyTurn.resolve(
		_turn_economy, WorldMarket.with_default_prices(), {}, 0
	)
	var research: Dictionary = report["research"]
	assert_eq(int(research["spent"]), 150)
	assert_eq(_turn_state.progress_of("land_enclosure"), 300)
	assert_eq((research["slots"] as Array[Dictionary]).size(), 3)


func test_projection_leaves_research_untouched() -> void:
	assert_true(bool(_turn_state.assign("land_enclosure", "medium")["ok"]))
	var treasury: int = _turn_economy.treasury
	var report: Dictionary = EconomyTurn.project(
		_turn_economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(_turn_economy.treasury, treasury)
	assert_eq(_turn_state.progress_of("land_enclosure"), 0)
	assert_lt(int(report["treasury_delta"]), 0)


func test_a_researched_gathering_tech_lifts_the_extraction_cap() -> void:
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_RAIL)
	works.set_transport(model, Fixture.TIMBER_TILE, LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Fixture.TIMBER_TILE, 2)
	var capped: Dictionary = Extraction.yields(
		model, 0, -1, TechCatalog.extraction_caps({}), works, Fixture.BARE_TILE
	)
	assert_eq(capped, {"timber": 1})
	_turn_state.unlock("saw_mill")
	var lifted: Dictionary = Extraction.yields(
		model, 0, -1, TechCatalog.extraction_caps(_turn_state.unlocked), works, Fixture.BARE_TILE
	)
	assert_eq(lifted, {"timber": 2})


# --- merged from tests/test_tech_discovery.gd ---


## Which resources count as discovered for a player (wiki: tech-tree
## § Discovery prerequisites; fog-and-exploration).
func test_revealed_tiles_discover_their_resource() -> void:
	var found: Dictionary = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_true(found.has("timber"))
	# The region opens charted (every tile starts fogged), so foreign grain is
	# known too; only prospected minerals stay hidden until an Explorer digs.
	assert_true(found.has("grain"))
	assert_false(found.has("horses"), "no tile holds horses on this map")


func test_prospect_minerals_need_prospecting() -> void:
	var found: Dictionary = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_false(found.has("iron"))
	_works.set_prospected(0, _model, Fixture.IRON_TILE)
	found = TechDiscovery.revealed(_world, {0: _view}, _works, 0)
	assert_true(found.has("iron"))


func test_an_unseen_tile_reveals_nothing() -> void:
	var view := VisibilityModel.new()
	view.setup(_model, 0)
	view.levels.fill(VisibilityModel.Level.UNKNOWN)
	var found: Dictionary = TechDiscovery.revealed(_world, {0: view}, _works, 0)
	assert_eq(found, {})


func test_missing_world_or_region_is_harmless() -> void:
	assert_eq(TechDiscovery.revealed(null, {}, _works, 0), {})
	assert_eq(TechDiscovery.revealed(_world, {}, _works, 0), {})


# --- merged from tests/test_tech_icons.gd ---


## Every tech carries a series medallion, and every plate ships (REQ-P1-02;
## tools/art/tech-medallions.md).
func test_every_catalog_tech_names_a_series() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.series_of(tech_id).is_empty():
			missing.append(tech_id)
	assert_eq(missing.size(), 0, "techs without a plate: %s" % ", ".join(missing))


func test_every_series_ships_a_texture() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.texture(tech_id) == null:
			missing.append(TechIcons.series_of(tech_id))
	assert_eq(missing.size(), 0, "plates missing from assets/art/tech: %s" % ", ".join(missing))


func test_a_chain_shares_one_plate() -> void:
	assert_eq(TechIcons.series_of("crop_rotation"), TechIcons.series_of("land_enclosure"))
	assert_eq(TechIcons.series_of("sugar_planting"), TechIcons.series_of("sugar_industry"))


func test_a_long_chain_may_grow_a_grander_plate() -> void:
	assert_ne(TechIcons.series_of("saw_mill"), TechIcons.series_of("circular_saw"))


func test_an_unknown_tech_has_no_plate() -> void:
	assert_eq(TechIcons.series_of("no_such_tech"), "")
	assert_null(TechIcons.texture("no_such_tech"))


func test_no_plate_is_listed_twice() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for tech_id: String in TechIcons.covered_ids():
		if seen.has(tech_id):
			clashes.append(tech_id)
		seen[tech_id] = true
	assert_eq(clashes.size(), 0, "techs claimed by two plates: %s" % ", ".join(clashes))


# --- merged from tests/test_tech_order.gd ---


## Goal-first ordering of the research queue (wiki: tech-tree § Research Model —
## the goal slot sorts the display only).
func test_the_goal_sits_at_depth_zero() -> void:
	assert_eq(TechOrder.chain_depth("bayonet", "bayonet"), 0)


func test_direct_prerequisites_sit_one_step_back() -> void:
	assert_eq(TechOrder.chain_depth("improved_iron_weapons", "bayonet"), 1)
	assert_eq(TechOrder.chain_depth("crucible_process", "bayonet"), 1)


func test_deeper_ancestors_count_their_steps() -> void:
	assert_eq(TechOrder.chain_depth("organised_regiments", "bayonet"), 2)
	assert_eq(TechOrder.chain_depth("iron_mining", "bayonet"), 2)


func test_a_tech_off_the_path_has_no_depth() -> void:
	assert_eq(TechOrder.chain_depth("crop_rotation", "bayonet"), -1)


func test_an_empty_or_unknown_goal_leaves_every_tech_off_path() -> void:
	assert_eq(TechOrder.chain_depth("bayonet", ""), -1)
	assert_eq(TechOrder.chain_depth("bayonet", "no_such_tech"), -1)
	assert_eq(TechOrder.chain_depth("no_such_tech", "bayonet"), -1)


## The goal a ledger or a snapshot carries is a catalog tech or nothing; an id
## this build cannot read opens the queue in catalog order (wiki: tech-tree
## § Goal slot; DR-20261111-21).
func test_a_goal_is_a_known_catalog_tech_or_none() -> void:
	assert_eq(TechOrder.normalize("bayonet"), "bayonet")
	assert_eq(TechOrder.normalize(""), "", "no goal means catalog order")
	assert_eq(TechOrder.normalize("no_such_tech"), "", "an unreadable id means catalog order")


func test_the_queue_puts_the_goal_path_first() -> void:
	var queue: Array[String] = ["crop_rotation", "iron_mining", "bayonet", "crucible_process"]
	var ordered: Array[String] = TechOrder.sorted(queue, "bayonet")
	assert_eq(ordered[0], "bayonet", "the goal leads")
	assert_eq(ordered[1], "crucible_process", "its prerequisite comes next")
	assert_eq(ordered[2], "iron_mining", "then the deeper ancestor")
	assert_eq(ordered[3], "crop_rotation", "off-path techs trail")


func test_techs_at_one_depth_keep_catalog_order() -> void:
	var queue: Array[String] = ["crucible_process", "improved_iron_weapons"]
	assert_eq(TechOrder.sorted(queue, "bayonet"), ["improved_iron_weapons", "crucible_process"])


func test_without_a_goal_the_queue_keeps_catalog_order() -> void:
	var queue: Array[String] = ["superior_hull_design", "crop_rotation", "printing_press"]
	assert_eq(
		TechOrder.sorted(queue), ["crop_rotation", "printing_press", "superior_hull_design"]
	)


func test_catalog_order_runs_category_then_era_then_name() -> void:
	assert_true(TechOrder.before("saw_mill", "wind_saw_mill"), "era 1 before era 2 in gathering")
	assert_true(TechOrder.before("crop_rotation", "saw_mill"), "same era sorts by name")
	assert_true(TechOrder.before("crop_rotation", "printing_press"), "gathering before labour")
	assert_false(TechOrder.before("printing_press", "crop_rotation"))


# --- merged from tests/test_research_panel.gd ---


## The research ledger renders live research state and emits intents
## (wiki: research-state; REQ-P2-03, REQ-P3-03).
func test_the_panel_lists_every_slot() -> void:
	_panel.refresh(_panel_state, 2500)
	var idle: Array[Label] = _labels("Slot")
	assert_eq(idle.size(), ResearchState.DEFAULT_SLOTS)
	assert_gt(_panel.get_combined_minimum_size().y, 200.0)


func test_open_advances_are_listed_and_startable() -> void:
	_panel.refresh(_panel_state, 2500)
	var picked: Array[String] = []
	_panel.assign_requested.connect(func(tech_id: String) -> void: picked.append(tech_id))
	var button: Button = _button("Research")
	assert_not_null(button)
	button.pressed.emit()
	assert_eq(picked.size(), 1)
	assert_true(TechCatalog.known(picked[0]))
	assert_true(_panel_state.researchable().has(picked[0]))


func test_a_full_roster_disables_new_studies() -> void:
	for tech_id: String in ["crop_rotation", "saw_mill", "land_enclosure"]:
		_panel_state.assign(tech_id)
	_panel.refresh(_panel_state, 2500)
	for button: Button in _buttons():
		if button.text == "Research":
			assert_true(button.disabled)


func test_slots_show_progress_funding_and_cancel() -> void:
	_panel_state.assign("land_enclosure", "high")
	_panel_state.add_progress("land_enclosure", 800)
	_panel.refresh(_panel_state, 2500)
	var cancelled: Array[int] = []
	_panel.cancel_requested.connect(func(slot: int) -> void: cancelled.append(slot))
	var funding: Array[int] = []
	_panel.funding_requested.connect(func(slot: int) -> void: funding.append(slot))
	var high: Button = _button("High")
	assert_not_null(high)
	high.pressed.emit()
	assert_eq(funding, [0])
	var cancel: Button = _button("Cancel")
	assert_not_null(cancel)
	cancel.pressed.emit()
	assert_eq(cancelled, [0])
	var progress: Label = _label_containing("800 / 1,800 RP")
	assert_not_null(progress)


# --- spend and the gauge -----------------------------------------------------
## The slot line must say what the study costs and what the next phase buys
## (REQ-P1-05 — gold a study spends is never silent).
func test_a_slot_names_its_spend_and_its_next_gain() -> void:
	_panel_state.assign("land_enclosure", "medium")
	_panel_state.add_progress("land_enclosure", 800)
	_panel.refresh(_panel_state, 2500)
	assert_not_null(_label_containing("150 ducats"), "the gold the slot spends a turn")
	assert_not_null(_label_containing("800 / 1,800 RP"), "banked against the cost")
	assert_not_null(_label_containing("+300 → 1,100"), "next turn's gain and where it lands")


func test_the_gauge_previews_the_next_phase() -> void:
	_panel_state.assign("land_enclosure", "high")
	_panel_state.add_progress("land_enclosure", 800)
	_panel.refresh(_panel_state, 2500)
	var bar: ResearchBar = _slot_row(0).bar()
	assert_eq(bar.target_progress(), 800)
	assert_eq(bar.next_gain(), 800)
	assert_almost_eq(bar.next_fraction(), 1600.0 / 1800.0, 0.001)
	assert_true(bar.is_paid())


## A funding change repaints the slot the player is looking at; rebuilding it
## would lose the button and restart the gauge (REQ-P1-05).
func test_changing_the_priority_repaints_the_same_row() -> void:
	_panel_state.assign("land_enclosure", "medium")
	_panel.refresh(_panel_state, 2500)
	var row: ResearchSlotRow = _slot_row(0)
	var funding: Array[int] = []
	_panel.funding_requested.connect(func(slot: int) -> void: funding.append(slot))
	var medium: Button = _button("Medium")
	assert_not_null(medium)
	medium.pressed.emit()
	assert_eq(funding, [0], "the row asks the controller to cycle the preset")
	_panel_state.cycle_funding(0)
	_panel.refresh(_panel_state, 2500)
	assert_is(row, _slot_row(0), "the funding change must not rebuild the slot")
	assert_not_null(_button("High"))
	assert_eq(row.bar().next_gain(), 800, "the gauge follows the new preset")
	assert_eq(_panel._slots_body.get_child_count(), ResearchState.DEFAULT_SLOTS)


func test_the_heading_totals_what_the_college_spends() -> void:
	_panel_state.assign("crop_rotation", "low")
	_panel_state.assign("saw_mill", "medium")
	_panel.refresh(_panel_state, 2500)
	assert_not_null(_label_containing("200 ducats & 400 RP a turn"))


## The treasury cannot cover a Maximum slot here, so the row must say so rather
## than promise points the phase will not pay for (wiki: tech-tree § Research
## Model — no partial funding).
func test_a_slot_the_treasury_cannot_cover_reads_unpaid() -> void:
	_panel_state.assign("land_enclosure", "maximum")
	_panel.refresh(_panel_state, 100)
	assert_not_null(_label_containing("unpaid next turn"))
	assert_eq(_slot_row(0).gold_next(), 0)
	assert_eq(_slot_row(0).bar().next_gain(), 0)


## A starved study must read as the borrowing rule, not as a broken purse: the
## college names the floor under its summary, on every form factor, and the row
## says the same thing on a long press (wiki: tech-tree-labour-economy
## § money_lending, banking; REQ-P5-05).
func test_the_college_names_the_floor_that_leaves_a_study_unpaid() -> void:
	_panel_state.assign("land_enclosure", "maximum")
	_panel.refresh(_panel_state, 0)
	var notice: Label = _label_containing("unpaid —")
	assert_not_null(notice, "the college names what stops the study")
	assert_true(notice.text.contains("stops at 0 ducats"), notice.text)
	assert_true(notice.text.contains("Money Lending"), notice.text)
	assert_true(_slot_row(0).unpaid_next())


## Money Lending moves the floor, so the same college names −500 and the tech
## that would push it to −1,000 (wiki: tech-tree-labour-economy § banking).
func test_the_college_names_the_lending_floor_a_purse_may_reach() -> void:
	_panel_state.unlock("money_lending")
	_panel_state.assign("land_enclosure", "maximum")
	_panel.refresh(_panel_state, ResearchFunding.DEBT_FLOOR)
	var notice: Label = _label_containing("unpaid —")
	assert_not_null(notice)
	assert_true(notice.text.contains("-500"), notice.text)
	assert_true(notice.text.contains("Banking"), notice.text)


## A funded college says nothing about the floor: the notice belongs to the turn
## the purse cannot pay, not to every visit.
func test_a_paid_college_carries_no_floor_notice() -> void:
	_panel_state.assign("land_enclosure", "low")
	_panel.refresh(_panel_state, 2500)
	assert_null(_label_containing("unpaid —"))
	assert_false(_slot_row(0).unpaid_next())


func test_known_techs_move_to_the_known_tab() -> void:
	_panel_state.unlock("crop_rotation")
	_panel.refresh(_panel_state, 2500)
	_panel.select_tab(1)
	var known: Label = _label_containing("Crop Rotation")
	assert_not_null(known)


func test_closing_emits_the_close_signal() -> void:
	var closed: Array[bool] = []
	_panel.close_pressed.connect(func() -> void: closed.append(true))
	var close: Button = _button("Close")
	assert_not_null(close)
	close.pressed.emit()
	assert_eq(closed.size(), 1)


# --- goal slot ---------------------------------------------------------------
func test_the_goal_strip_starts_empty() -> void:
	_panel.refresh(_panel_state, 2500)
	assert_eq(_panel.goal_tech(), "")
	assert_not_null(_label_containing("No goal"))


func test_setting_a_goal_names_it_and_sorts_the_queue() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "national_bureaucracy")
	assert_not_null(_label_containing("National Bureaucracy"))
	assert_eq(_first_available(), "Printing Press", "a prerequisite of the goal leads the queue")


func test_the_goal_marks_its_path() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("national_bureaucracy")
	await get_tree().process_frame
	var marked: int = 0
	for node: Node in _nodes():
		if node is Label and (node as Label).text == ResearchRow.GOAL_ON_PATH:
			marked += 1
	assert_gt(marked, 0, "prerequisites on the goal's path carry the mark")


func test_clearing_the_goal_restores_catalog_order() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("national_bureaucracy")
	var clear: Button = _button("Clear")
	assert_not_null(clear)
	clear.pressed.emit()
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "")
	assert_eq(_first_available(), "Crop Rotation")


func test_the_goal_button_steers_the_queue() -> void:
	_panel.refresh(_panel_state, 2500)
	var goal: Button = _button("Goal")
	assert_not_null(goal)
	var steered: Array[String] = []
	_panel.goal_changed.connect(func(tech_id: String) -> void: steered.append(tech_id))
	goal.pressed.emit()
	assert_eq(_panel.goal_tech(), "crop_rotation")
	assert_eq(steered, ["crop_rotation"])


func test_a_reached_goal_says_so() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("crop_rotation")
	_panel_state.unlock("crop_rotation")
	_panel.refresh(_panel_state, 2500)
	await get_tree().process_frame
	assert_not_null(_label_containing("reached"))


func test_an_unknown_goal_clears_it() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("crop_rotation")
	_panel.set_goal("no_such_tech")
	assert_eq(_panel.goal_tech(), "")


## The goal is kept with the campaign (DR-20261111-21): steering writes it into
## the research state, and the ledger reopens on it instead of catalog order.
func test_steering_writes_the_goal_into_the_campaign_state() -> void:
	_panel.refresh(_panel_state, 2500)
	_panel.set_goal("national_bureaucracy")
	assert_eq(_panel_state.goal, "national_bureaucracy", "the goal is state the save carries")
	_panel.set_goal("")
	assert_eq(_panel_state.goal, "", "clearing the goal clears it from the state")


func test_a_ledger_reopens_on_the_goal_the_campaign_carries() -> void:
	_panel_state.goal = "national_bureaucracy"
	_panel.refresh(_panel_state, 2500)
	await get_tree().process_frame
	assert_eq(_panel.goal_tech(), "national_bureaucracy")
	assert_not_null(_label_containing("National Bureaucracy"))
	assert_eq(_first_available(), "Printing Press", "the saved goal still sorts the queue")


# --- helpers -----------------------------------------------------------------
## The persistent row the panel keeps for one slot.
func _slot_row(index: int) -> ResearchSlotRow:
	return _panel._slots_body.get_child(index) as ResearchSlotRow


## The first name in the AVAILABLE tab, which is the goal-aware queue order.
func _first_available() -> String:
	var body: VBoxContainer = _panel._available_body
	if body.get_child_count() == 0:
		return ""
	for node: Node in _collect(body.get_child(0), [] as Array[Node]):
		if not node is Label:
			continue
		var text: String = (node as Label).text
		for tech_id: String in TechCatalog.ids():
			if TechCatalog.display_name(tech_id) == text:
				return text
	return ""


# --- helpers -----------------------------------------------------------------
func _nodes() -> Array[Node]:
	return _collect(_panel, [] as Array[Node])


func _collect(root: Node, into: Array[Node]) -> Array[Node]:
	for child in root.get_children():
		into.append(child)
		_collect(child, into)
	return into


func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node: Node in _nodes():
		if node is Button:
			out.append(node as Button)
	return out


func _button(text: String) -> Button:
	for button: Button in _buttons():
		if button.text == text:
			return button
	return null


func _labels(prefix: String) -> Array[Label]:
	var out: Array[Label] = []
	for node: Node in _nodes():
		if node is Label and (node as Label).text.begins_with(prefix):
			out.append(node as Label)
	return out


func _label_containing(text: String) -> Label:
	for node: Node in _nodes():
		if node is Label and (node as Label).text.contains(text):
			return node as Label
	return null
