extends GdToolsTest
## Espionage rules (wiki: civilian-units § Spy, research-state § Spy RP boost,
## diplomacy § Spy-death penalty) and the rival AI's spy/research policy.

const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const PLAYER: int = 0
const RIVAL: int = 1
const SEED: int = 7


class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String) -> void:
		toasts.append(text)


# --- roster and movement -----------------------------------------------------


func test_spy_is_playable_and_keeps_its_wiki_costs() -> void:
	assert_true(CivilianCatalog.is_implemented("spy"))
	assert_eq(CivilianCatalog.treasury_cost("spy"), 2000)
	assert_eq(CivilianCatalog.paper_cost("spy"), 4)
	assert_in("spy", CivilianCatalog.playable_types())
	assert_eq(CivilianCatalog.works("spy"), [SpyRules.WORK_COUNTER])


func test_spy_may_walk_into_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	assert_true(
		CivilianMovement.may_enter(model, "spy", PLAYER, CivilianFixture.RIVAL_GRAIN_TILE)
	)
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", Vector2i(2, 0)
	)
	var result: Dictionary = CivilianMovement.apply_move(
		model, spy, CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_true(bool(result.get("ok", false)))
	assert_eq(spy.tile, CivilianFixture.RIVAL_GRAIN_TILE)


func test_presence_holds_a_charted_province_for_its_owner_only() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_eq(CivilianMovement.held_provinces(model, [spy], PLAYER), [RIVAL])
	assert_eq(CivilianMovement.held_provinces(model, [spy], RIVAL), [])
	assert_eq(
		SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [RIVAL],
		"a spy on a rival court's land shadows that court"
	)


func test_a_spy_in_its_own_land_observes_nothing() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	assert_eq(SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [])


# --- counter-espionage -------------------------------------------------------


func test_counter_spy_is_an_ongoing_owned_order() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	var units: Array[CivilianState] = [spy]
	var check: Dictionary = CivilianWork.validate(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	)
	assert_true(bool(check.get("ok", false)), "an owned province is a legal screen")
	assert_eq(CivilianWork.assign(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	).get("ok", false), true)
	assert_true(spy.is_working())
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, units, LandWorks.new()
	)
	assert_true(reports.is_empty(), "the screen never advances or completes")
	assert_true(spy.is_working(), "counter-espionage stays up until cancelled")
	var rival_tile: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var rival_check: Dictionary = CivilianWork.validate(
		model, rival_tile, SpyRules.WORK_COUNTER, LandWorks.new(),
		[rival_tile] as Array[CivilianState], CivilianFixture.stockpile()
	)
	assert_false(
		bool(rival_check.get("ok", false)), "a foreign province is not a legal target"
	)


# --- research intelligence ---------------------------------------------------


func test_research_bonus_stacks_per_observed_rival() -> void:
	var bonus: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{RIVAL: {"crop_rotation": true}, 2: {"crop_rotation": true, "saw_mill": true}}
	)
	assert_eq(int(bonus.get("crop_rotation", 0)), 30, "two rivals, two +15%")
	assert_eq(int(bonus.get("saw_mill", 0)), 15)
	var none: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"saw_mill": true}}
	)
	assert_eq(int(none.get("crop_rotation", 0)), 0, "a tech the rival lacks earns nothing")


func test_research_turn_applies_the_spy_bonus() -> void:
	var state := ResearchState.make()
	state.assign("crop_rotation", "medium")
	var economy := PlayerEconomy.starting()
	assert_eq(ResearchTurn.points_for(state, "crop_rotation", "medium"), 300)
	assert_eq(
		ResearchTurn.points_for(state, "crop_rotation", "medium", 15), 345,
		"a 15% network lifts 300 RP to 345"
	)
	var report: Dictionary = ResearchTurn.resolve(
		state, economy, {"crop_rotation": 15}
	)
	assert_eq(int(report["slots"][0]["rp"]), 345)
	assert_eq(state.progress_of("crop_rotation"), 345)


func test_map_phase_prepares_the_player_spy_bonus() -> void:
	var play: PlaySession = _play_with_spy()
	var controller: EconomyController = play.economy
	controller.economy.research.slots[0] = {"tech": "crop_rotation", "funding": "medium"}
	var rival_economy: PlayerEconomy = play.ai.economy_for(RIVAL)
	rival_economy.research.unlocked["crop_rotation"] = true
	var bonus: Dictionary = MapPlayEspionage.research_boost(play)
	assert_eq(int(bonus.get("crop_rotation", 0)), 15)
	controller.research_boost = bonus
	assert_eq(int(controller.research_boost.get("crop_rotation", 0)), 15)
	play.hud.free()
	controller.free()


func test_rival_spies_are_invisible_on_the_map() -> void:
	var model: MapModel = CivilianFixture.build()
	var layer := CivilianLayer.new()
	layer.viewer_faction = PLAYER
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	var rival_spy: CivilianState = layer.add_unit(
		RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var own_spy: CivilianState = layer.add_unit(PLAYER, "spy", CivilianFixture.BARE_TILE)
	assert_false(layer.marker_for(rival_spy).visible, "a rival spy leaves no marker")
	assert_true(layer.marker_for(own_spy).visible)
	var rival_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.RIVAL_GRAIN_TILE.x, CivilianFixture.RIVAL_GRAIN_TILE.y,
		PlaySession.TILE_SIZE
	)
	var own_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.BARE_TILE.x, CivilianFixture.BARE_TILE.y, PlaySession.TILE_SIZE
	)
	assert_null(layer.unit_at(rival_point), "a rival spy is not selectable")
	assert_eq(layer.unit_at(own_point), own_spy)
	layer.free()


# --- kill and defection ------------------------------------------------------


func test_counter_espionage_kills_and_turns_spies() -> void:
	var model: MapModel = CivilianFixture.build()
	var rolls: Dictionary = _find_rolls(model)
	assert_true(int(rolls["kill"]) > 0, "5% kill chance lands within the search")
	assert_true(int(rolls["defect"]) > 0, "10% defection lands within the search")
	var units: Array[CivilianState] = _spy_pair()
	var events: Array[Dictionary] = SpyRules.resolve_turn(
		model, units, int(rolls["kill"]), SEED
	)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_eq(units.size(), 1, "the killed spy leaves the roster")
	var defectors: Array[CivilianState] = _spy_pair()
	var defected: Array[Dictionary] = SpyRules.resolve_turn(
		model, defectors, int(rolls["defect"]), SEED
	)
	assert_eq(String(defected[0]["kind"]), "defected")
	assert_eq(int(defected[0]["unit"].owner), RIVAL, "the survivor changes coat")


func test_a_killed_spy_cools_relations_by_eight() -> void:
	var play: PlaySession = _play_with_spy()
	play.turn = int(_find_rolls(play.model)["kill"])
	play.diplomacy.ensure_relation(PLAYER, RIVAL, 1)
	play.diplomacy.relation(PLAYER, RIVAL).score = 60.0
	play.civilian_layer.units = _spy_pair()
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	var events: Array[Dictionary] = MapPlaySpies.resolve(play)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_almost_eq(play.diplomacy.relation(PLAYER, RIVAL).score, 52.0, 0.001)
	play.hud.free()
	play.economy.free()


func test_an_unscreened_spy_is_never_touched() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array[CivilianState] = [spy]
	for turn in 50:
		assert_true(SpyRules.resolve_turn(model, units, turn, SEED).is_empty())
	assert_eq(units.size(), 1, "no counter-spy means no kill or defection roll")


# --- rival AI ----------------------------------------------------------------


func test_ai_spy_walks_toward_a_rival_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array = [spy]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_eq((plan["moves"] as Array).size(), 1)
	assert_eq((plan["orders"] as Array).size(), 0)
	var step: Vector2i = plan["moves"][0]["tile"]
	assert_true(step.x > CivilianFixture.RIVAL_GRAIN_TILE.x - 2)


func test_ai_spy_holds_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_true((plan["moves"] as Array).is_empty())
	assert_true((plan["orders"] as Array).is_empty(), "presence duty, not a work order")


func test_ai_spy_raises_a_counter_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)


func test_ai_war_screen_frees_the_second_spy_to_observe() -> void:
	var model: MapModel = CivilianFixture.build()
	var first: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var second: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [first, second], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1, "one spy keeps the screen")
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)
	assert_eq((plan["moves"] as Array).size(), 1, "the other walks abroad")


func test_ai_recalls_a_spy_to_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_true((plan["orders"] as Array).is_empty())
	assert_eq((plan["moves"] as Array).size(), 1, "the spy walks home to screen")
	assert_true(Vector2i(plan["moves"][0]["tile"]).x > CivilianFixture.BARE_TILE.x)


func test_ai_trains_a_spy_after_its_base_roster() -> void:
	var roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
		CivilianState.create(4, RIVAL, "explorer", CivilianFixture.BARE_TILE),
	]
	var order: Dictionary = AiCivilianPlanner.training_order(
		AiConfig.build(RIVAL, 1500), roster, _context()
	)
	assert_true(bool(order.get("ok", false)))
	assert_eq(String(order["type_id"]), "spy")
	var war_roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
	]
	var war_context: Dictionary = _context()
	war_context["at_war"] = true
	var war_order: Dictionary = AiCivilianPlanner.training_order(
		AiConfig.build(RIVAL, 1500), war_roster, war_context
	)
	assert_eq(String(war_order["type_id"]), "spy", "a war court wants a screen first")


func test_ai_research_planner_opens_a_study() -> void:
	var economy := PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(
		AiConfig.build(RIVAL, 1500), economy, {}
	)
	var assignments: Array = plan["assignments"]
	assert_false(assignments.is_empty(), "the planner fills a free slot")
	var tech: String = String(assignments[0]["tech"])
	assert_false(tech.is_empty())
	assert_true(ResearchFunding.known(String(assignments[0]["funding"])))
	var before: int = economy.research.progress_of(tech)
	ResearchTurn.resolve(economy.research, economy)
	assert_true(
		economy.research.progress_of(tech) > before
		or economy.research.is_unlocked(tech),
		"the Research phase advances the assigned study"
	)


func test_ai_research_is_deterministic() -> void:
	var first := PlayerEconomy.starting()
	var second := PlayerEconomy.starting()
	var config: AiConfig = AiConfig.build(RIVAL, 1500)
	var left: Dictionary = AiResearchPlanner.plan(config, first, {})
	var right: Dictionary = AiResearchPlanner.plan(config, second, {})
	assert_eq(
		String(left["assignments"][0]["tech"]),
		String(right["assignments"][0]["tech"])
	)


# --- court reports -----------------------------------------------------------


func test_court_report_names_battles_and_techs() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": RIVAL,
		"defender": PLAYER,
		"captured": true,
	}
	var sea: Dictionary = {"region": 0, "zone": 0, "attacker": RIVAL, "defender": PLAYER}
	var report: Dictionary = {
		"factions": {
			RIVAL: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [land], [sea], report)
	assert_eq(play.hud.toasts.size(), 1)
	var line: String = play.hud.toasts[0]
	assert_true(line.begins_with("Spy report — England"))
	assert_true(line.contains("took Coro from Spain"))
	assert_true(line.contains("squadron action in Mar Caribe"))
	assert_true(line.contains("Crop Rotation"))
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_lost_province() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": PLAYER,
		"defender": RIVAL,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(play.hud.toasts[0].contains("lost Coro to Spain"))
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_diplomatic_act() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(play.hud.toasts[0].contains("declares war"))
	play.hud.free()
	play.economy.free()


func test_court_report_is_silent_without_a_spy() -> void:
	var play: PlaySession = _play_with_spy()
	play.civilian_layer.units.clear()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_true(play.hud.toasts.is_empty())
	play.hud.free()
	play.economy.free()


# --- rules guards and dossier copy -------------------------------------------


func test_spy_rules_guards_skip_nulls_and_home_tiles() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var builder: CivilianState = CivilianState.create(
		2, PLAYER, "builder", CivilianFixture.BARE_TILE
	)
	assert_false(SpyRules.is_spy(null))
	assert_false(SpyRules.is_spy(builder))
	assert_false(SpyRules.hidden_from(null, PLAYER))
	assert_false(SpyRules.hidden_from(spy, -1))
	assert_false(SpyRules.hidden_from(spy, PLAYER))
	assert_true(SpyRules.hidden_from(spy, RIVAL))
	assert_false(SpyRules.is_foreign(null, spy))
	assert_false(SpyRules.is_foreign(model, builder))
	spy.embark_on(1)
	assert_false(SpyRules.is_foreign(model, spy))
	spy.put_ashore(Vector2i(0, 4))
	assert_eq(model.owner_at(0, 4), MapModel.NO_ID)
	assert_false(SpyRules.is_foreign(model, spy))
	assert_false(SpyRules.has_counter_spy([null, builder], PLAYER))
	assert_eq(SpyRules.resolve_turn(null, [spy], 1, SEED).size(), 0)


func test_civilian_panel_names_tradecraft_and_counter_status() -> void:
	var model: MapModel = CivilianFixture.build()
	var abroad: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(
		model, abroad, LandWorks.new(), [abroad], CivilianFixture.stockpile()
	)
	assert_true(panel._status.text.contains("At large"))
	panel.refresh(
		model, screen, LandWorks.new(), [screen], CivilianFixture.stockpile()
	)
	assert_eq(panel._status.text, "Counter-espionage · ongoing.")
	panel.free()


# --- fixtures ----------------------------------------------------------------


func _spy_pair() -> Array[CivilianState]:
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var units: Array[CivilianState] = [spy, screen]
	return units


func _find_rolls(model: MapModel) -> Dictionary:
	var kill: int = -1
	var defect: int = -1
	for turn in range(1, 2000):
		var units: Array[CivilianState] = _spy_pair()
		for event: Dictionary in SpyRules.resolve_turn(model, units, turn, SEED):
			if String(event["kind"]) == "killed" and kill < 0:
				kill = turn
			elif String(event["kind"]) == "defected" and defect < 0:
				defect = turn
		if kill > 0 and defect > 0:
			break
	return {"kill": kill, "defect": defect}


func _play_with_spy() -> PlaySession:
	var model: MapModel = CivilianFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	layer.add_unit(PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE)
	var play := PlaySession.new()
	play.player_faction = PLAYER
	play.world = world
	play.model = model
	play.region_index = model.region_id
	play.civilian_layer = layer
	play.map_seed = SEED
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.ai = AiState.new()
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	play.hud = StubHud.new()
	add_child(play.hud)
	return play


func _context() -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": CivilianFixture.BARE_TILE,
		"at_war": false,
	}
