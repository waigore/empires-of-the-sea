extends GdToolsTest
## Pure economy rules: workers, consumption, turn income, extraction and the
## world market.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).


# --- from test_worker_pool.gd ---
## Worker pool, recruiting and disbanding (wiki: workers-and-population).


func test_pool_counts_labour_and_food_by_tier() -> void:
	var pool: WorkerPool = WorkerPool.make(3, 2, 1, 1)
	assert_eq(pool.count(WorkerPool.Tier.PEASANT), 3)
	assert_eq(pool.count(WorkerPool.Tier.MASTER), 1)
	assert_eq(pool.total(), 7)
	assert_eq(pool.labour(), 3 * 1 + 2 * 4 + 1 * 6 + 1 * 8)
	assert_eq(pool.food_demand(), 3 * 1 + 2 * 2 + 1 * 2 + 1 * 2)


func test_pool_ignores_unknown_tiers_and_negative_counts() -> void:
	var pool: WorkerPool = WorkerPool.make(2)
	pool.set_count(-1, 5)
	pool.set_count(9, 5)
	pool.add(WorkerPool.Tier.PEASANT, -10)
	assert_eq(pool.total(), 0)
	assert_eq(pool.count(-1), 0)
	assert_false(pool.remove(WorkerPool.Tier.MASTER))
	assert_eq(pool.food_demand(), 0)


func test_luxury_and_tech_metadata_match_the_tiers() -> void:
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.PEASANT), "")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.APPRENTICE), "refinedSugar")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.JOURNEYMAN), "cigars")
	assert_eq(WorkerPool.luxury_for(WorkerPool.Tier.MASTER), "furHats")
	assert_eq(WorkerPool.required_techs(WorkerPool.Tier.PEASANT), [])
	assert_true(WorkerPool.techs_unlocked(WorkerPool.Tier.PEASANT, {}))
	assert_false(WorkerPool.techs_unlocked(WorkerPool.Tier.APPRENTICE, {}))
	assert_false(
		WorkerPool.techs_unlocked(WorkerPool.Tier.APPRENTICE, {"apprentice_workers": true})
	)
	assert_true(
		WorkerPool.techs_unlocked(
			WorkerPool.Tier.APPRENTICE,
			{"apprentice_workers": true, "sugar_refining": true}
		)
	)
	assert_eq(WorkerPool.tier_name(WorkerPool.Tier.JOURNEYMAN), "Journeymen")


func test_recruit_costs_match_the_v1_table() -> void:
	var peasant: Dictionary = {"treasury": 0, "materials": {"fabric": 2}}
	var apprentice: Dictionary = {"treasury": 200, "materials": {"paper": 2}}
	var journeyman: Dictionary = {"treasury": 500, "materials": {"paper": 5}}
	var master: Dictionary = {"treasury": 1000, "materials": {"paper": 10}}
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.PEASANT), peasant)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.APPRENTICE), apprentice)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.JOURNEYMAN), journeyman)
	assert_eq(WorkerPool.recruit_cost(WorkerPool.Tier.MASTER), master)
	assert_false(WorkerPool.RECRUIT_CONSUMES_PEASANTS[WorkerPool.Tier.PEASANT])
	assert_true(WorkerPool.RECRUIT_CONSUMES_PEASANTS[WorkerPool.Tier.MASTER])


func test_copy_is_independent() -> void:
	var pool: WorkerPool = WorkerPool.make(2, 1)
	var clone: WorkerPool = pool.copy()
	clone.add(WorkerPool.Tier.PEASANT, 3)
	assert_eq(pool.count(WorkerPool.Tier.PEASANT), 2)
	assert_eq(clone.count(WorkerPool.Tier.PEASANT), 5)
	assert_eq(clone.count(WorkerPool.Tier.APPRENTICE), 1)


func test_economy_recruits_peasants_with_fabric() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["fabric"] = 2
	var result: Dictionary = economy.recruit(WorkerPool.Tier.PEASANT)
	assert_true(bool(result["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS + 1)
	assert_eq(economy.quantity("fabric"), 0)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)


func test_recruiting_a_peasant_needs_fabric() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	# The opening stock now carries cloth for the muster; drain it to test the gate.
	economy.stockpile["fabric"] = 0
	var result: Dictionary = economy.recruit(WorkerPool.Tier.PEASANT)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Insufficient materials")
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS)


func test_trained_tiers_are_tech_gated_and_consume_a_peasant() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["paper"] = 4
	var blocked: Dictionary = economy.recruit(WorkerPool.Tier.APPRENTICE)
	assert_false(bool(blocked["ok"]))
	assert_eq(String(blocked["reason"]), "Required technology not unlocked")
	assert_eq(economy.quantity("paper"), 4)

	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	var result: Dictionary = economy.recruit(WorkerPool.Tier.APPRENTICE)
	assert_true(bool(result["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.APPRENTICE), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS - 1)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 200)
	assert_eq(economy.quantity("paper"), 2)


func test_training_needs_a_peasant_and_treasury() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.tech_unlocked = {
		"master_artisans": true,
		"hat_production": true,
	}
	economy.stockpile["paper"] = 10
	var poor: PlayerEconomy = economy.copy()
	poor.treasury = 999
	assert_eq(String(poor.recruit(WorkerPool.Tier.MASTER)["reason"]), "Insufficient treasury")

	economy.workers.set_count(WorkerPool.Tier.PEASANT, 0)
	assert_eq(String(economy.recruit(WorkerPool.Tier.MASTER)["reason"]), "Insufficient workers")
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 1)
	assert_true(bool(economy.recruit(WorkerPool.Tier.MASTER)["ok"]))
	assert_eq(economy.workers.count(WorkerPool.Tier.MASTER), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 0)


func test_disband_demotes_one_tier_to_peasant_without_refund() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers.set_count(WorkerPool.Tier.JOURNEYMAN, 2)
	assert_true(economy.disband(WorkerPool.Tier.JOURNEYMAN))
	assert_eq(economy.workers.count(WorkerPool.Tier.JOURNEYMAN), 1)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), PlayerEconomy.START_PEASANTS + 1)
	assert_false(economy.disband(WorkerPool.Tier.PEASANT))
	assert_false(economy.disband(WorkerPool.Tier.MASTER))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)

# --- from test_economy_consumption.gd ---
## Consumption phase: army, navy, navy, worker food and luxuries
## (wiki: workers-and-population § Consumption).


func test_navy_eats_before_workers_and_two_units_per_ship() -> void:
	var pool: WorkerPool = WorkerPool.make(3)
	var stock: Dictionary = {"grain": 10, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 2)
	assert_eq(report["navy_demand"], 4)
	assert_eq(report["navy_fed"], 4)
	assert_eq(stock["grain"], 3)
	assert_eq(report["fed_workers"], 3)
	assert_eq(report["strikers"], 0)
	assert_eq(report["idle_labour"], 3)


func test_food_is_eaten_from_grain_before_meat() -> void:
	var pool: WorkerPool = WorkerPool.make(0)
	var stock: Dictionary = {"grain": 1, "meat": 5}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 2)
	assert_eq(report["navy_fed"], 4)
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 2)


func test_army_rations_come_first() -> void:
	var pool: WorkerPool = WorkerPool.make(1)
	var stock: Dictionary = {"grain": 2, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0, 2)
	assert_eq(report["army_fed"], 2)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["strikers"], 1)
	assert_eq(stock["grain"], 0)


func test_trained_workers_need_grain_and_meat() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 1)
	var stock: Dictionary = {"grain": 4, "meat": 0}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["strikers"], 1)
	assert_eq(report["idle_labour"], 0)
	assert_eq(stock["grain"], 4)

	var fed_stock: Dictionary = {"grain": 1, "meat": 1, "refinedSugar": 1}
	var fed: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0, 1), fed_stock, 0)
	assert_eq(fed["fed_workers"], 1)
	assert_eq(fed["luxury_spent"], {"refinedSugar": 1})
	assert_eq(fed["idle_labour"], 4)
	assert_eq(fed_stock["grain"], 0)
	assert_eq(fed_stock["meat"], 0)


func test_workers_are_fed_masters_before_peasants() -> void:
	var pool: WorkerPool = WorkerPool.make(1, 0, 0, 1)
	var stock: Dictionary = {"grain": 1, "meat": 1, "furHats": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_counts"], [0, 0, 0, 1])
	assert_eq(report["strikers"], 1)
	assert_eq(report["idle_labour"], 8)
	assert_eq(report["luxury_spent"], {"furHats": 1})
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 0)


func test_peasants_take_one_food_unit_of_either_kind() -> void:
	var stock: Dictionary = {"grain": 1, "meat": 3}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(3), stock, 0)
	assert_eq(report["fed_workers"], 3)
	assert_eq(stock["grain"], 0)
	assert_eq(stock["meat"], 1)


func test_luxury_is_all_or_nothing_per_food_fed_worker() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 2)
	var stock: Dictionary = {"grain": 2, "meat": 2, "refinedSugar": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 2)
	assert_eq(report["luxury_spent"], {"refinedSugar": 1})
	assert_eq(stock["refinedSugar"], 0)
	assert_eq(report["idle_counts"], [0, 1, 0, 0])
	assert_eq(report["idle_labour"], 4)
	assert_eq(report["strikers"], 1)


func test_starving_trained_workers_do_not_claim_luxury() -> void:
	var stock: Dictionary = {"grain": 0, "meat": 0, "cigars": 3}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0, 0, 1), stock, 0)
	assert_eq(report["fed_workers"], 0)
	assert_eq(report["luxury_spent"], {})
	assert_eq(stock["cigars"], 3)
	assert_eq(report["strikers"], 1)


func test_luxury_is_deducted_masters_first() -> void:
	var pool: WorkerPool = WorkerPool.make(0, 1, 1, 1)
	var stock: Dictionary = {"grain": 3, "meat": 3, "furHats": 1, "cigars": 1}
	var report: Dictionary = EconomyConsumption.resolve(pool, stock, 0)
	assert_eq(report["fed_workers"], 3)
	assert_eq(report["luxury_spent"], {"cigars": 1, "furHats": 1})
	assert_eq(report["idle_counts"], [0, 0, 1, 1])
	assert_eq(report["idle_labour"], 14)
	assert_eq(report["strikers"], 1)


func test_empty_pool_and_no_upkeep_is_a_clean_pass() -> void:
	var stock: Dictionary = {"grain": 0}
	var report: Dictionary = EconomyConsumption.resolve(WorkerPool.make(0), stock, 0)
	assert_eq(report["strikers"], 0)
	assert_eq(report["idle_labour"], 0)
	assert_eq(report["food_eaten"], 0)
	assert_eq(stock, {"grain": 0})

# --- from test_economy_turn.gd ---
## Turn resolution: Extraction -> Riches -> Consumption -> Production, then prices
## (wiki: stockpiles-and-production § Production flow).


func test_turn_runs_all_four_phases_in_order() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.set_assignment("lumber", 1)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var report: Dictionary = EconomyTurn.resolve(
		economy, market, {"grain": 10, "timber": 4}, 0
	)
	assert_eq(report["extraction"], {"grain": 10, "timber": 4})
	assert_eq(int(report["consumption"]["food_eaten"]), 2)
	assert_eq(report["production"]["runs"], {"lumber": 1})
	assert_eq(economy.quantity("grain"), 8)
	assert_eq(economy.quantity("timber"), 2)
	assert_eq(economy.quantity("lumber"), 1)
	assert_eq(economy.quantity("wool"), 2)


func test_gold_clears_into_treasury() -> void:
	var economy: PlayerEconomy = _economy(1)
	economy.stockpile["gold"] = 2
	economy.stockpile["spices"] = 1
	var before: int = economy.treasury
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(int(report["riches_treasury"]), 2 * 166 + 50)
	assert_eq(economy.treasury, before + 2 * 166 + 50)
	assert_eq(economy.quantity("gold"), 0)
	assert_eq(economy.quantity("spices"), 0)


func test_starving_workers_produce_nothing() -> void:
	var economy: PlayerEconomy = _economy(2)
	economy.stockpile["grain"] = 0
	economy.stockpile["timber"] = 6
	economy.set_assignment("lumber", 3)
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(int(report["consumption"]["strikers"]), 2)
	assert_eq(report["production"]["runs"], {})
	assert_eq(economy.quantity("timber"), 6)
	assert_eq(economy.quantity("lumber"), 0)


func test_navy_eats_before_production_labour() -> void:
	var economy: PlayerEconomy = _economy(3)
	economy.stockpile["grain"] = 2
	economy.stockpile["timber"] = 4
	economy.set_assignment("lumber", 1)
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 1
	)
	assert_eq(int(report["consumption"]["navy_fed"]), 2)
	assert_eq(int(report["consumption"]["navy_demand"]), 2)
	assert_eq(int(report["consumption"]["fed_workers"]), 0)
	assert_eq(report["production"]["runs"], {})


func test_projection_matches_the_live_resolution() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.stockpile["gold"] = 1
	economy.set_assignment("lumber", 2)
	var projection: Dictionary = EconomyTurn.project(
		economy, market, {"grain": 6, "timber": 6}, 1
	)
	var before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	EconomyTurn.resolve(economy, market, {"grain": 6, "timber": 6}, 1)
	assert_eq(int(projection["treasury_delta"]), economy.treasury - treasury_before)
	for id: String in CommodityCatalog.all_ids():
		var live: int = economy.quantity(id) - int(before.get(id, 0))
		assert_eq(int(projection["stockpile_delta"].get(id, 0)), live, id)


func test_projection_has_no_side_effects() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = _economy(2)
	economy.set_assignment("lumber", 1)
	var stock_before: Dictionary = economy.stockpile.duplicate()
	var treasury_before: int = economy.treasury
	EconomyTurn.project(economy, market, {"timber": 4}, 0)
	assert_eq(economy.stockpile, stock_before)
	assert_eq(economy.treasury, treasury_before)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 2)


func test_turn_advances_market_prices_but_projection_does_not() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices(0)
	var economy: PlayerEconomy = _economy(1)
	market.buy(economy, "grain", 10)
	var projection: Dictionary = EconomyTurn.project(economy, market, {"grain": 10}, 0)
	assert_eq(market.price("grain"), 50)
	assert_eq(projection["prices"], {})
	EconomyTurn.resolve(economy, market, {"grain": 10}, 0)
	assert_eq(market.price("grain"), 60)
	assert_eq(market.bid_volume("grain"), 0)


func test_empty_turn_is_a_no_op() -> void:
	var economy: PlayerEconomy = _economy(0)
	var before: Dictionary = economy.stockpile.duplicate()
	var report: Dictionary = EconomyTurn.resolve(
		economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(report["extraction"], {})
	assert_eq(report["production"]["runs"], {})
	assert_eq(economy.stockpile, before)


func _economy(peasants: int) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(peasants)
	economy.stockpile = {"grain": 0, "wool": 2}
	economy.treasury = 1000
	return economy

# --- from test_extraction.gd ---
## Extraction phase (wiki: extraction-and-improvements).


func test_effective_yield_takes_the_minimum() -> void:
	assert_eq(Extraction.effective_yield(4, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(4, 1, 4, 4), 1)
	assert_eq(Extraction.effective_yield(2, 4, 1, 4), 1)
	assert_eq(Extraction.effective_yield(3, 4, 4, 2), 2)
	assert_eq(Extraction.effective_yield(0, 4, 4, 4), 0)
	assert_eq(Extraction.effective_yield(9, 4, 4, 4), 4)
	assert_eq(Extraction.effective_yield(-3, 4, 4, 4), 0)


func test_tech_cap_defaults_to_one() -> void:
	assert_eq(Extraction.tech_cap_for("timber", {}), 1)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": 3}), 3)
	assert_eq(Extraction.tech_cap_for("timber", {"timber": -1}), 0)


func test_map_resources_map_to_catalog_commodities() -> void:
	assert_eq(Extraction.commodity_for_resource(0), "timber")
	assert_eq(Extraction.commodity_for_resource(3), "gold")
	assert_eq(Extraction.commodity_for_resource(4), "grain")
	assert_eq(Extraction.commodity_for_resource(MapModel.NO_ID), "")


func test_seeded_map_resources_are_real_commodities() -> void:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	for entry: Dictionary in table:
		assert_true(
			CommodityCatalog.known(String(entry["commodity"])), String(entry["commodity"])
		)


func test_yields_sum_owned_resource_tiles_and_the_capital_bonus() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(totals, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})


func test_yields_ignore_tiles_owned_by_others() -> void:
	var model: MapModel = _fixture()
	var totals: Dictionary = Extraction.yields(model, 1, 1)
	assert_eq(totals, {"grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})
	var none: Dictionary = Extraction.yields(model, 2, -1)
	assert_eq(none, {})


func test_capital_bonus_needs_an_owned_capital() -> void:
	var model: MapModel = _fixture()
	var foreign: Dictionary = Extraction.yields(model, 0, 1)
	assert_eq(int(foreign.get("grain", 0)), 1)
	assert_eq(Extraction.yields(null, 0, 0), {})


func test_improved_tiles_use_the_works_level_and_connectivity() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(model, 0, 0, {}, works, Vector2i(0, 0))
	assert_eq(totals, {"timber": 1, "grain": Extraction.CAPITAL_GRAIN_BONUS})
	# The unimproved grain tile on (1, 0) no longer pays the placeholder level 1.
	var no_works: Dictionary = Extraction.yields(model, 0, 0)
	assert_eq(no_works, {"timber": 1, "grain": 1 + Extraction.CAPITAL_GRAIN_BONUS})


func test_disconnected_improvements_are_skipped() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 1)
	var totals: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(-1, -1)
	)
	assert_eq(totals, {})


func test_works_respect_prospecting_and_extraction_caps() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 0), 2)
	works.set_transport(model, Vector2i(0, 0), LandWorks.TRANSPORT_RAIL)
	var base: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(base, {"timber": 1})
	var capped: Dictionary = Extraction.yields(
		model, 0, -1, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(capped, {"timber": 2})

	model.resource[model.index_of(0, 0)] = 1
	works.set_improvement(model, Vector2i(0, 0), 1)
	var unprospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(unprospected, {})
	works.set_prospected(0, model, Vector2i(0, 0))
	var prospected: Dictionary = Extraction.yields(
		model, 0, -1, {}, works, Vector2i(0, 0)
	)
	assert_eq(prospected, {"iron": 1})


func test_tech_caps_lift_the_yield_per_tile() -> void:
	var model: MapModel = MapModel.new()
	model.setup(3, 1)
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	var tiles_a: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var province_a := ProvinceState.create(0, "P0", tiles_a, Vector2.ZERO, 2, 0)
	province_a.town_development = 4
	model.provinces.append(province_a)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 0
	var base: Dictionary = Extraction.yields(model, 0, -1)
	assert_eq(base, {"timber": 2})
	var capped: Dictionary = Extraction.yields(model, 0, -1, {"timber": 3})
	# Improvement level, not the tech cap, now limits the tiles in this slice.
	assert_eq(capped, {"timber": 2})


## Scrub forest timber is hard-capped at level 1; hardwood follows the tech cap.
func test_terrain_hard_cap_clamps_scrub_timber() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	var tile := Vector2i(0, 0)
	var index: int = model.index_of(tile.x, tile.y)
	model.terrain[index] = MapModel.Terrain.SCRUB_FOREST
	works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	var scrub: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, tile
	)
	assert_eq(int(scrub.get("timber", 0)), 1)
	model.terrain[index] = MapModel.Terrain.HARDWOOD_FOREST
	var hardwood: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, tile
	)
	assert_eq(int(hardwood.get("timber", 0)), 4)


## The path transport cap is the bottleneck of the chosen route, and the best of
## several routes wins (wiki: capital-and-connectivity).
func test_path_transport_uses_the_best_bottleneck() -> void:
	var model := MapModel.new()
	model.setup(3, 3)
	for y in 3:
		for x in 3:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 3:
			tiles.append(Vector2i(x, y))
	var province := ProvinceState.create(0, "P0", tiles, Vector2(1, 1), 9, 0, true)
	province.capital_tile = Vector2i(0, 0)
	province.town_development = 4
	model.provinces = [province]
	model.resource[model.index_of(0, 2)] = 0
	var works := LandWorks.new()
	works.set_improvement(model, Vector2i(0, 2), 2)
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, Vector2i(0, 2), LandWorks.TRANSPORT_RAIL)
	var bottleneck: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(bottleneck.get("timber", 0)), 1)
	# A second route along row 1 is rail all the way: max(min(paths)) = 4.
	for x in 3:
		works.set_transport(model, Vector2i(x, 1), LandWorks.TRANSPORT_RAIL)
	var best: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(best.get("timber", 0)), 2)


## Town manufacturing bonus: level 2 -> x1, level 4 -> x2, level 3 -> none,
## never consuming the raw input (wiki: extraction-and-improvements).
func test_town_industry_multiplies_town_connected_raw() -> void:
	assert_eq(TownIndustry.bonus_for_province({"iron": 4}, 2, {}), {"castIron": 1})
	assert_eq(TownIndustry.bonus_for_province({"iron": 8}, 4, {}), {"castIron": 4})
	assert_eq(TownIndustry.bonus_for_province({"iron": 8}, 3, {}), {})
	assert_eq(TownIndustry.bonus_for_province({"iron": 3}, 4, {}), {})
	assert_eq(TownIndustry.bonus_for_province({"cotton": 4}, 2, {}), {})
	assert_eq(
		TownIndustry.bonus_for_province({"cotton": 4}, 2, {"cotton_weaving": true}),
		{"fabric": 1}
	)


## A court weighs a town upgrade by the manufactures the finished town would pay
## each turn, at base prices (wiki: extraction-and-improvements
## § Town manufacturing bonus; commodity-catalog § Manufactured base prices).
func test_town_industry_prices_the_finish_at_level_four() -> void:
	assert_eq(TownIndustry.value({"lumber": 2}), 120)
	assert_eq(TownIndustry.value({}), 0)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 1), 4 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 2), 2 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 3), 4 * 160)
	assert_eq(TownIndustry.marginal_gain({"iron": 8}, 4), 0)
	assert_eq(TownIndustry.marginal_gain({}, 1), 0, "no raw, no bonus")


## Extraction credits the bonus from a town-adjacent raw tile without spending it.
func test_extraction_adds_the_town_manufacturing_bonus() -> void:
	var model: MapModel = _fixture()
	var works := LandWorks.new()
	var province: ProvinceState = model.provinces[0]
	province.town_tile = Vector2i(0, 0)
	province.town_development = 2
	model.resource[model.index_of(1, 0)] = 0
	works.set_improvement(model, Vector2i(0, 0), 0)
	works.set_improvement(model, Vector2i(1, 0), 2)
	var totals: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(totals.get("timber", 0)), 2)
	assert_eq(int(totals.get("lumber", 0)), 0)
	works.set_improvement(model, Vector2i(1, 0), 4)
	var raised: Dictionary = Extraction.yields(
		model, 0, 0, {"timber": 4}, works, Vector2i(0, 0)
	)
	assert_eq(int(raised.get("timber", 0)), 4)
	assert_eq(int(raised.get("lumber", 0)), 1)


func test_treasury_ids_are_riches_plus_spices() -> void:
	assert_eq(
		CommodityCatalog.treasury_ids(),
		["gold", "silver", "gems", "diamonds", "spices"] as Array[String]
	)


func _fixture() -> MapModel:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var p0 := ProvinceState.create(0, "P0", tiles0, Vector2.ZERO, 2, 0)
	p0.town_development = 4
	var p1 := ProvinceState.create(1, "P1", tiles1, Vector2.ZERO, 2, 1)
	model.provinces.append(p0)
	model.provinces.append(p1)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(1, 0)] = 4
	model.resource[model.index_of(2, 0)] = 4
	return model

# --- from test_world_market.gd ---
## World market: prices, trades and price discovery (wiki: world-market).


func test_market_seeds_tradeable_catalog_prices() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(market.prices.size(), 23)
	assert_eq(market.price("timber"), 30)
	assert_eq(market.price("lumber"), 60)
	assert_eq(market.price("iron"), 80)
	assert_false(market.prices.has("gold"))
	# Spices is advanced and tradeable at its fixed 50 (DR-20261110-09).
	assert_eq(market.price("spices"), 50)
	assert_false(market.can_trade("gold"))
	assert_true(market.can_trade("lumber"))
	assert_true(market.can_trade("spices"))


func test_buy_pays_the_current_price_and_records_a_bid() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var result: Dictionary = market.buy(economy, "timber", 2)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["cost"]), 60)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 60)
	assert_eq(economy.quantity("timber"), 2)
	assert_eq(market.bid_volume("timber"), 2)
	assert_eq(market.offer_volume("timber"), 0)


func test_buy_rejects_unaffordable_and_untradeable_rows() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 10
	var poor: Dictionary = market.buy(economy, "timber", 1)
	assert_false(bool(poor["ok"]))
	assert_eq(String(poor["reason"]), "Insufficient treasury")
	assert_eq(economy.quantity("timber"), 0)
	var riches: Dictionary = market.buy(economy, "gold", 1)
	assert_false(bool(riches["ok"]))
	assert_eq(String(riches["reason"]), "Not traded on the world market")
	assert_false(bool(market.buy(economy, "timber", 0)["ok"]))


func test_sell_credits_treasury_and_records_an_offer() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["timber"] = 3
	var result: Dictionary = market.sell(economy, "timber", 2)
	assert_true(bool(result["ok"]))
	assert_eq(int(result["revenue"]), 60)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY + 60)
	assert_eq(economy.quantity("timber"), 1)
	assert_eq(market.offer_volume("timber"), 2)
	assert_false(bool(market.sell(economy, "timber", 5)["ok"]))
	assert_false(bool(market.sell(economy, "spices", 1)["ok"]))
	economy.stockpile["spices"] = 2
	var crop: Dictionary = market.sell(economy, "spices", 2)
	assert_true(bool(crop["ok"]), "a crown may sell its spices")
	assert_eq(int(crop["revenue"]), 100)


func test_price_discovery_uses_the_published_formula() -> void:
	assert_eq(WorldMarket.next_price(30, 30, 0, 0), 30)
	assert_eq(WorldMarket.next_price(30, 30, 10, 10), 30)
	assert_eq(WorldMarket.next_price(30, 30, 10, 0), 36)
	assert_eq(WorldMarket.next_price(30, 30, 0, 10), 24)
	assert_eq(WorldMarket.next_price(30, 30, 100, 0), 36)
	assert_eq(WorldMarket.next_price(30, 30, 0, 100), 24)


func test_price_is_floored_at_thirty_percent_of_base() -> void:
	assert_eq(WorldMarket.next_price(10, 100, 0, 10), 30)
	assert_eq(WorldMarket.next_price(0, 100, 10, 0), 30)


func test_world_depth_damps_one_sided_trades() -> void:
	var shallow: int = WorldMarket.next_price(30, 30, 10, 0, 100)
	assert_eq(shallow, 30)
	var capped: int = WorldMarket.next_price(30, 30, 1000, 0, 0)
	assert_eq(capped, 36)


func test_advance_prices_publishes_and_resets_volumes() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices(0)
	var economy: PlayerEconomy = PlayerEconomy.starting()
	market.buy(economy, "grain", 10)
	var changed: Dictionary = market.advance_prices()
	assert_eq(int(market.price("grain")), 60)
	assert_eq(int(changed["grain"]), 60)
	assert_eq(market.bid_volume("grain"), 0)
	assert_eq(market.price("timber"), 30)
	assert_false(changed.has("timber"))


func test_copy_keeps_prices_and_volumes_separate() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	market.buy(economy, "timber", 10)
	var clone: WorldMarket = market.copy()
	clone.advance_prices()
	assert_eq(market.price("timber"), 30)
	assert_eq(clone.price("timber"), 35)
	assert_eq(market.bid_volume("timber"), 10)
	assert_eq(clone.bid_volume("timber"), 0)


# --- from test_minor_market.gd ---
## Minor Nation and Tribe market offers: the harvest they publish, the courts'
## discount, cargo and treasury gates, and the turn's book (wiki: world-market
## § Minor and tribe auto-sell; DR-20261110-08).


## A two-province region: Spain ashore, one Minor Nation (or Tribe) holding the
## other with a grain field and a timber estate.
func _offer_world(owner: int = 6) -> WorldMap:
	var model: MapModel = _fixture()
	model.provinces[1].owner = owner
	model.resource[model.index_of(0, 1)] = 0
	var world := WorldMap.new()
	world.add_region(model)
	return world


func test_minor_offers_publish_their_estates_at_the_world_price() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	assert_eq(offers.size(), 2, "one row per commodity the estates yield")
	var timber: Dictionary = offers[MinorMarket.index_of(offers, "6:timber")]
	assert_eq(int(timber["faction"]), 6)
	assert_eq(String(timber["commodity"]), "timber")
	assert_eq(int(timber["quantity"]), 1)
	assert_eq(int(timber["unit_price"]), 30, "deals clear at the published price")
	assert_eq(MinorMarket.unit_price(market, "timber"), 30)
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)
	assert_eq(MinorMarket.index_of(offers, "6:gold"), -1)


func test_tribes_offer_their_harvest_too() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(9), market, 0)
	assert_eq(offers.size(), 2)
	assert_true(MinorMarket.index_of(offers, "9:timber") >= 0)


func test_offers_skip_riches() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	for offer: Dictionary in offers:
		assert_true(CommodityCatalog.is_tradeable(String(offer["commodity"])))
	# A gold seam is a rich, not a market good.
	world.region(0).resource[world.region(0).index_of(0, 1)] = 3
	var after: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	assert_eq(after.size(), 1, "the grain estate still sells")
	assert_eq(String(after[0]["commodity"]), Extraction.GRAIN)
	assert_eq(MinorMarket.index_of(after, "6:gold"), -1)


func test_offers_belong_to_one_global_market() -> void:
	var world: WorldMap = _offer_world()
	var market: WorldMarket = WorldMarket.with_default_prices()
	assert_eq(world.owned_provinces(0, 5), 0)
	assert_eq(MinorMarket.emit(world, market, 5).size(), 2, "the book is global")
	assert_eq(MinorMarket.emit(null, market, 0), [])
	assert_eq(MinorMarket.emit(world, null, 0), [])


func test_buying_a_minor_offer_pays_the_court_and_fills_a_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var result: Dictionary = MinorMarket.buy(
		market, economy, offers, "6:timber", 1, 5
	)
	assert_true(bool(result["ok"]), String(result.get("reason", "")))
	assert_eq(int(result["cost"]), 30)
	assert_eq(int(result["faction"]), 6)
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY - 30)
	assert_eq(economy.quantity("timber"), 1)
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(market.bid_volume("timber"), 1)
	# The timber row is spent; the grain estate still has goods.
	assert_eq(offers.size(), 1)
	assert_false(bool(MinorMarket.buy(market, economy, offers, "6:timber", 1, 5)["ok"]))


func test_a_minor_offer_needs_a_free_cargo_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var result: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 1, 0)
	assert_false(bool(result["ok"]))
	assert_true(String(result["reason"]).contains("cargo holds"))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)


func test_a_minor_offer_cannot_be_overbought_or_bought_without_treasury() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var offers: Array[Dictionary] = MinorMarket.emit(_offer_world(), market, 0)
	var greedy: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 2, 5)
	assert_false(bool(greedy["ok"]))
	assert_true(String(greedy["reason"]).contains("Only 1"))
	assert_eq(economy.treasury, PlayerEconomy.START_TREASURY)
	economy.treasury = 5
	var poor: Dictionary = MinorMarket.buy(market, economy, offers, "6:timber", 1, 5)
	assert_false(bool(poor["ok"]))
	assert_eq(String(poor["reason"]), "Insufficient treasury")
	assert_eq(MinorMarket.remaining(offers, "6:timber"), 1)
	assert_false(bool(MinorMarket.buy(market, economy, offers, "6:timber", 0, 5)["ok"]))


func test_offers_expire_with_the_turn_but_survive_a_save() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	market.minor_offers = MinorMarket.emit(_offer_world(), market, 0)
	var clone: WorldMarket = market.copy()
	assert_eq(clone.minor_offers, market.minor_offers)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.minor_offers, market.minor_offers)
	assert_eq(int(restored.minor_offers[0]["unit_price"]), 50)
	market.advance_prices()
	assert_eq(market.minor_offers, [])
