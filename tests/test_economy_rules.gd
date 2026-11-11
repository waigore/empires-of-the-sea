extends GdToolsTest
## Pure economy rules: workers, consumption, turn income, extraction and the
## world market.
## Merged into one suite so coverage pays a single Godot boot per theme
## (docs/testing.md speed rules).
## Consolidated rulebook: test_market_engine, test_ledger_text,
## test_ledger_helpers, test_commodity_icons, test_trade_cargo,
## test_economy_overseas (one Godot boot per domain).


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


## The ledger asks the rules why a disband is inert instead of guessing
## (wiki: workers-and-population § Disband; REQ-P2-03).
func test_disband_names_its_blocked_reasons() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.Tier.PEASANT),
		"Only a trained worker returns to the fields"
	)
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.Tier.MASTER),
		"No master to send back"
	)
	economy.workers.set_count(WorkerPool.Tier.MASTER, 1)
	assert_eq(economy.disband_blocked_reason(WorkerPool.Tier.MASTER), "")
	assert_eq(
		economy.disband_blocked_reason(WorkerPool.TIER_COUNT), "Only a trained worker returns to the fields"
	)
	assert_eq(WorkerPool.tier_one(WorkerPool.Tier.APPRENTICE), "Apprentice")

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


## Fully fed hulls over hulls, not food units over food units: three food for
## two hulls feeds one hull in full, so the coverage is 0.5, not 0.75
## (wiki: workers-and-population § Consumption).
func test_navy_coverage_counts_fully_fed_hulls() -> void:
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 4}), 1.0, 0.0001
	)
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 3}), 0.5, 0.0001
	)
	assert_almost_eq(
		EconomyConsumption.navy_coverage({"navy_demand": 4, "navy_fed": 0}), 0.0, 0.0001
	)
	assert_almost_eq(EconomyConsumption.navy_coverage({}), 1.0, 0.0001)


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


# --- Minor/Tribe town manufacturing offers -----------------------------------
## A developed Minor or Tribe town turns its own estates' raw into manufactures
## and publishes them under its own name (wiki: extraction-and-improvements
## § Town manufacturing bonus).


## A two-province map: a Great Power holds the west, Minor Nation 6 (or a Tribe)
## holds four estates in the east with one province town.
func _town_world(owner: int, resource: int, estates: int, town_level: int) -> WorldMap:
	var model := MapModel.new()
	model.setup(4, 2)
	for y in 2:
		for x in 4:
			model.province[model.index_of(x, y)] = 0 if x < 2 else 1
	var gp_tiles: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)
	]
	var minor_tiles: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)
	]
	var gp := ProvinceState.create(0, "P0", gp_tiles, Vector2.ZERO, 4, 0)
	var minor := ProvinceState.create(1, "P1", minor_tiles, Vector2.ZERO, 4, owner)
	minor.town_tile = Vector2i(2, 0)
	minor.town_development = town_level
	model.provinces = [gp, minor]
	for tile: Vector2i in minor_tiles.slice(0, estates):
		model.resource[model.index_of(tile.x, tile.y)] = resource
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _auto_offer(orders: Array[MarketOrder], commodity: String) -> MarketOrder:
	for order: MarketOrder in orders:
		if order.commodity == commodity:
			return order
	return null


## Units one commodity carries across every auto-offer in the book.
func _offered_units(orders: Array[MarketOrder], commodity: String) -> int:
	var total: int = 0
	for order: MarketOrder in orders:
		if order.commodity == commodity:
			total += order.remaining()
	return total


func test_a_level_two_minor_town_offers_one_manufacture() -> void:
	var world: WorldMap = _town_world(6, 0, 4, 2)
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	var lumber: MarketOrder = _auto_offer(orders, "lumber")
	assert_not_null(lumber, "four timber estates feed a level-2 town")
	assert_eq(lumber.faction, 6)
	assert_eq(lumber.quantity, 1)
	assert_eq(lumber.priority, 1)
	assert_true(lumber.auto)
	assert_eq(
		lumber.origin_index, world.region(0).index_of(2, 0), "the province town is the source"
	)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offers: Array[Dictionary] = MinorMarket.emit(world, market, 0)
	assert_eq(int(offers[MinorMarket.index_of(offers, "6:lumber")]["quantity"]), 1)
	assert_eq(
		int(offers[MinorMarket.index_of(offers, "6:timber")]["quantity"]), 4,
		"the bonus spends none of the timber"
	)


func test_a_level_four_minor_town_doubles_the_bonus() -> void:
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 4, 4))
	assert_eq(_auto_offer(orders, "lumber").quantity, 2)


func test_odd_and_plain_town_levels_pay_nothing() -> void:
	for level: int in [1, 3]:
		var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 4, level))
		assert_null(_auto_offer(orders, "lumber"), "level %d pays no bonus" % level)
		assert_eq(_offered_units(orders, "timber"), 4, "the harvest still sells")


func test_a_town_needs_four_estates_to_manufacture() -> void:
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(_town_world(6, 0, 3, 4))
	assert_null(_auto_offer(orders, "lumber"))
	assert_eq(_offered_units(orders, "timber"), 3)


func test_a_tribe_town_offers_its_manufactures_too() -> void:
	var world: WorldMap = _town_world(9, 5, 4, 2)
	var fabric: MarketOrder = _auto_offer(MinorMarket.emit_orders(world), "fabric")
	assert_not_null(fabric, "four wool estates feed a Tribe town")
	assert_eq(fabric.faction, 9)
	assert_eq(fabric.quantity, 1)


## Minors and Tribes never prospect, so a mineral estate is neither sold nor fed
## to the town (wiki: extraction-and-improvements § Non-Great-Power extraction).
func test_mineral_estates_never_feed_a_minor_town() -> void:
	var world: WorldMap = _town_world(6, 1, 4, 4)
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	assert_eq(orders.size(), 0, "no iron in the ground, no cast iron on the market")
	var model: MapModel = world.region(0)
	assert_eq(MinorMarket.province_raw(model, model.provinces[1]), {})


## The offers are ordinary system-authored supply: a crown bids, the matcher
## fills it, and the Minor's receipt leaves the Great-Power pool as a sink.
func test_a_minor_town_offer_clears_in_the_auction() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _town_world(6, 0, 4, 2)
	var buyer: PlayerEconomy = PlayerEconomy.starting()
	var before: int = buyer.treasury
	var stock_before: int = buyer.quantity("lumber")
	MarketOrders.submit(
		market,
		0, "lumber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": before}
	)
	var report: Dictionary = MarketClearing.clear(market, world, {0: buyer}, {0: 4})
	var mine: Array[Dictionary] = []
	for raw: Variant in report["deals"]:
		if int((raw as Dictionary).get("buyer", -2)) == 0:
			mine.append(raw as Dictionary)
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["seller"]), 6)
	assert_eq(String(mine[0]["commodity"]), "lumber")
	assert_eq(buyer.quantity("lumber"), stock_before + 1)
	assert_eq(buyer.treasury, before - 60, "one lumber at the published price")


# --- from test_market_engine.gd ---
## World-market matching engine: order validation, priority tiers, first right
## of refusal, relation tiebreaks, profit shares, embassy kickbacks, subsidy
## steps, carry-forward and price discovery (wiki: world-market;
## world-market-first-right-of-refusal).

var _seq: int = 0


func _order(
	faction: int,
	commodity: String,
	side: String,
	quantity: int,
	priority: int = 1,
	origin_region: int = MarketOrder.NO_ORIGIN,
	origin_index: int = MarketOrder.NO_ORIGIN,
	auto_offer: bool = false
) -> MarketOrder:
	_seq += 1
	var order: MarketOrder = MarketOrder.create(
		faction, commodity, side, quantity, priority, origin_region, origin_index, auto_offer
	)
	order.id = "t%d" % _seq
	return order


func _context(overrides: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"prices": {"timber": 30, "grain": 10},
		"free_holds": {0: 10, 1: 10, 2: 10, 6: 10, 9: 10},
		"treasuries": {0: 10000, 1: 10000, 2: 10000, 6: 0, 9: 0},
		"stock": {0: {"timber": 10}, 1: {"timber": 10}, 2: {"timber": 10}, 3: {"timber": 10}},
	}
	for key: Variant in overrides.keys():
		out[key] = overrides[key]
	return out


# --- validation --------------------------------------------------------------


func test_one_side_per_commodity() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var bid: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1, {"cargo_free": 4, "treasury": 500}
	)
	assert_true(bool(bid["ok"]), String(bid.get("reason", "")))
	var offer: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_OFFER, 1, {"stock": 4}
	)
	assert_false(bool(offer["ok"]))
	assert_eq(String(offer["code"]), "trade_order_mutual_exclusion")


func test_bid_type_cap_is_three_and_trade_fairs_raise_it_to_six() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var ids: Array[String] = ["timber", "iron", "wool", "grain"]
	for index in 3:
		var result: Dictionary = MarketOrders.submit(
			market,
			0, ids[index], MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
		)
		assert_true(bool(result["ok"]), String(result.get("reason", "")))
	var fourth: Dictionary = MarketOrders.submit(
			market,
		0, ids[3], MarketOrder.SIDE_BID, 1, {"cargo_free": 8, "treasury": 9000}
	)
	assert_false(bool(fourth["ok"]))
	assert_eq(String(fourth["code"]), "trade_order_bid_type_cap_exceeded")
	var fair: WorldMarket = WorldMarket.with_default_prices()
	for index in 4:
		var result: Dictionary = MarketOrders.submit(
		fair,
			0, ids[index], MarketOrder.SIDE_BID, 1,
			{"cargo_free": 8, "treasury": 9000, "tech_unlocked": {"trade_fairs": true}}
		)
		assert_true(bool(result["ok"]), String(result.get("reason", "")))


func test_offer_is_capped_by_stock_and_bid_by_cargo() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var offer: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_OFFER, 3, {"stock": 2}
	)
	assert_false(bool(offer["ok"]))
	assert_eq(String(offer["code"]), "trade_order_stock_insufficient")
	var bid: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 3, {"cargo_free": 2, "treasury": 500}
	)
	assert_false(bool(bid["ok"]))
	assert_eq(String(bid["code"]), "trade_order_cargo_insufficient")


# --- priority and ties -------------------------------------------------------


func test_higher_priority_bid_clears_the_offer_first() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 2),
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var result: Dictionary = MarketMatcher.match(orders, _context())
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0)
	assert_eq(int(deals[0]["quantity"]), 5)
	var left: Array = result["residuals"]
	assert_eq(left.size(), 1)
	assert_eq(int(left[0]["faction"]), 1)


func test_favoured_partner_wins_a_tie() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(3, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["ftp_for"] = func(a: int, b: int) -> bool: return a == 1 and b == 3
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 1)
	assert_true(bool(deals[0]["is_ftp"]))


func test_minor_sale_prefers_a_consulate_holder_then_higher_relation() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return true
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 70.0 if gp == 2 else 25.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 2, "higher relation with the seller wins")


func test_a_consulate_holder_beats_a_higher_relation_without_one() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return gp == 1
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 80.0 if gp == 2 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 1)


# --- favoured trading partner (wiki: diplomacy § R7.1) ------------------------


func test_the_suzerain_is_a_colonys_favoured_partner() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(1, 12, 0).set_score(90.0)
	state.set_colony(12, 0)
	assert_eq(MarketFavoured.of(state, 12), 0, "a colony ignores the warmer rival")
	assert_true(MarketFavoured.is_suzerain(state, 12, 0))
	assert_false(MarketFavoured.is_suzerain(state, 12, 1))


func test_the_warmest_court_is_an_independent_courts_favoured_partner() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(2, 7, 0).set_score(72.0)
	state.ensure_relation(1, 7, 0).set_score(68.0)
	assert_eq(MarketFavoured.of(state, 7), 2)


func test_an_equal_relation_breaks_to_the_smaller_court_id() -> void:
	var state := DiplomacyState.new()
	state.ensure_relation(2, 7, 0).set_score(60.0)
	state.ensure_relation(1, 7, 0).set_score(60.0)
	assert_eq(MarketFavoured.of(state, 7), 1)


func test_a_court_no_one_knows_has_no_favoured_partner() -> void:
	assert_eq(MarketFavoured.of(DiplomacyState.new(), 7), MarketFavoured.UNDEFINED)
	assert_eq(MarketFavoured.of(null, 7), MarketFavoured.UNDEFINED)


func test_a_colonys_suzerain_clears_the_tier_before_a_warmer_rival() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["favoured_for"] = func(_seller: int) -> int: return 0
	context["consulate_for"] = func(_gp: int, _minor: int) -> bool: return true
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 90.0 if gp == 1 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0, "the suzerain trades first whatever its relation")
	assert_true(bool(deals[0]["is_favoured"]))
	assert_false(bool(deals[0]["is_ftp"]))


func test_a_favoured_colony_never_crosses_a_priority_tier() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 5, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(12, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	context["favoured_for"] = func(_seller: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 1, "favour stays inside its tier")


func test_an_independent_seller_keeps_the_consulate_order() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(2, "timber", MarketOrder.SIDE_BID, 5, 1),
		_order(7, "timber", MarketOrder.SIDE_OFFER, 5, 1),
	]
	var context: Dictionary = _context()
	# The independent court's R7.1 partner is its warmest buyer, and the auction
	# leaves that arm to R7.3: the Consulate holder is served first.
	context["favoured_for"] = func(_seller: int) -> int: return MarketFavoured.UNDEFINED
	context["consulate_for"] = func(gp: int, _minor: int) -> bool: return gp == 1
	context["relation_for"] = func(gp: int, _minor: int) -> float:
		return 90.0 if gp == 2 else 10.0
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 1)


# --- first right of refusal --------------------------------------------------


func test_first_right_overrides_a_higher_priority_rival() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 1)
	assert_eq(int(deals[0]["buyer"]), 0)
	assert_true(bool(deals[0]["is_frr"]))
	assert_eq(int((result["residuals"] as Array)[0]["faction"]), 1)


func test_first_right_partial_fill_exposes_the_residual() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(1, "timber", MarketOrder.SIDE_BID, 6, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 10, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	var result: Dictionary = MarketMatcher.match(orders, context)
	var deals: Array = result["deals"]
	assert_eq(deals.size(), 2)
	assert_true(bool(deals[0]["is_frr"]))
	assert_eq(int(deals[0]["quantity"]), 4)
	assert_false(bool(deals[1]["is_frr"]))
	assert_eq(int(deals[1]["quantity"]), 6)


# --- profit share and kickbacks ---------------------------------------------


func test_profit_is_relation_linear_with_no_cap() -> void:
	assert_eq(FirstRight.profit(0.0, 4, 2.5), 0.0)
	assert_eq(FirstRight.profit(100.0, 4, 2.5), 10.0)
	assert_eq(FirstRight.profit(75.0, 10, 5.0), 37.5)
	assert_eq(FirstRight.profit(-5.0, 10, 5.0), 0.0)
	assert_eq(FirstRight.profit(200.0, 10, 5.0), 50.0, "clamped to 100")


func test_embassy_kickback_is_ten_percent_of_the_relation_portion() -> void:
	assert_eq(FirstRight.kickback(100.0, 10, 20.0), 20.0)
	assert_eq(FirstRight.kickback(50.0, 10, 20.0), 10.0)


func test_credits_separate_the_owner_share_from_kickbacks() -> void:
	var deals: Array[Dictionary] = [{
		"seller": 6, "buyer": 1, "commodity": "timber",
		"quantity": 10, "price": 20.0, "seller_is_minor": true,
		"origin_region": 0, "origin_index": 1,
	}]
	var result: Dictionary = FirstRight.credits(
		deals,
		func(_region: int, _index: int) -> int: return 0,
		func(gp: int, _minor: int) -> float: return 75.0 if gp == 0 else 50.0,
		func(gp: int, _minor: int) -> bool: return gp in [1, 2]
	)
	var by_gp: Dictionary = result["by_gp"]
	assert_eq(float(by_gp[0]), 150.0, "owner full share, no 40% cap")
	assert_eq(float(by_gp[1]), 10.0, "buyer also holds an embassy")
	assert_eq(float(by_gp[2]), 10.0)
	assert_eq(float(result["sink"]), 30.0)


# --- clearing, settlement and carry-forward ---------------------------------


func _world(second_owner: int = 6) -> WorldMap:
	var model: MapModel = MapModel.new()
	model.setup(3, 2)
	for x in 2:
		model.province[model.index_of(x, 0)] = 0
	model.province[model.index_of(2, 0)] = 1
	model.province[model.index_of(0, 1)] = 1
	var tiles0: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tiles1: Array[Vector2i] = [Vector2i(2, 0), Vector2i(0, 1)]
	var p0 := ProvinceState.create(0, "P0", tiles0, Vector2.ZERO, 2, 0)
	var p1 := ProvinceState.create(1, "P1", tiles1, Vector2.ZERO, 2, second_owner)
	model.provinces.append(p0)
	model.provinces.append(p1)
	model.resource[model.index_of(0, 0)] = 0
	model.resource[model.index_of(2, 0)] = 0
	model.resource[model.index_of(0, 1)] = 4
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _economies() -> Dictionary:
	return {
		0: PlayerEconomy.starting(),
		1: PlayerEconomy.starting(),
	}


func test_a_bid_buys_the_minor_harvest_and_books_cargo() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	var buyer: PlayerEconomy = economies[0]
	var before: int = buyer.treasury
	var staged: Dictionary = MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": before, "buy_price": 30}
	)
	assert_true(bool(staged["ok"]), String(staged.get("reason", "")))
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}
	)
	var deals: Array = report["deals"]
	var mine: Array = []
	for raw: Variant in deals:
		if int((raw as Dictionary).get("buyer", -99)) == 0:
			mine.append(raw)
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["seller"]), 6)
	assert_eq(int(mine[0]["quantity"]), 1)
	assert_eq(buyer.treasury, before - 30)
	assert_eq(buyer.quantity("timber"), 1)
	assert_eq(int(((report["fills"] as Dictionary).get(0, {}) as Dictionary).get("bought", 0)), 1)


func test_no_purchased_tile_means_no_profit_share() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var before: int = (economies[1] as PlayerEconomy).treasury
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}
	)
	assert_eq(int((report["credits"] as Dictionary)["by_gp"].get(1, 0)), 0)
	assert_eq((economies[1] as PlayerEconomy).treasury, before)


func test_first_right_pays_the_tile_owner_on_a_rival_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = Vector2i(2, 0)
	assert_true(model.purchase_tile(tile, 0))
	var economies: Dictionary = _economies()
	var owner: PlayerEconomy = economies[0]
	var owner_before: int = owner.treasury
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(0, 6, 0).set_score(75.0)
	MarketOrders.submit(
			market,
		1, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var credited: int = roundi(float((report["credits"] as Dictionary)["by_gp"].get(0, 0)))
	assert_eq(credited, 23, "1 x 30 x 75% = 22.5, rounded once")
	assert_eq(owner.treasury, owner_before + 23)
	assert_false((economies[1] as PlayerEconomy).treasury == PlayerEconomy.START_TREASURY)


## The colony's harvest clears to its suzerain inside the tier even though the
## rival is the warmer, better-known court (wiki: diplomacy § R7.1;
## DR-20261111-11).
func test_the_suzerain_clears_a_colonys_harvest_at_turn_end() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var tribe: int = int(FactionCatalog.TRIBES[3]["id"])
	var world: WorldMap = _world(tribe)
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_colony(tribe, 0)
	for gp: int in [0, 1]:
		diplomacy.ensure_relation(gp, tribe, 0).set_score(10.0 if gp == 0 else 90.0)
		diplomacy.set_overture(gp, tribe, DiplomacyCatalog.STAGE_EMBASSY)
	# The rival speaks first, so the deal proves the tiebreak, not the book order.
	for gp: int in [1, 0]:
		MarketOrders.submit(
			market,
			gp, "timber", MarketOrder.SIDE_BID, 1,
			{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
		)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy}
	)
	var from_colony: Array[Dictionary] = []
	var from_world: Array[Dictionary] = []
	for raw: Variant in report["deals"]:
		var deal: Dictionary = raw
		if String(deal.get("commodity", "")) != "timber":
			continue
		if int(deal.get("seller", -2)) == tribe:
			from_colony.append(deal)
		elif int(deal.get("seller", -2)) == MarketOrder.WORLD:
			from_world.append(deal)
	assert_eq(from_colony.size(), 1, "the colony's one timber auto-offer")
	assert_eq(int(from_colony[0]["buyer"]), 0, "the suzerain takes its colony's goods")
	assert_true(bool(from_colony[0]["is_favoured"]))
	assert_eq(from_world.size(), 1, "the rival buys at the published price instead")
	assert_eq(int(from_world[0]["buyer"]), 1)
	assert_false(bool(from_world[0]["is_favoured"]))


func test_subsidy_surcharge_lands_on_the_minor_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.set_subsidy(0, 6, 10)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var before: int = (economies[0] as PlayerEconomy).treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4}, {"diplomacy": diplomacy})
	assert_eq((economies[0] as PlayerEconomy).treasury, before - 33)


func test_unfilled_bid_carries_or_drops_when_cargo_is_short() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "grain", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 10, "treasury": 5000, "buy_price": 10}
	)
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 2, 1: 4}
	)
	assert_eq((report["carry"] as Array).size(), 0)
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_true(codes.has("carry_forward_dropped_cargo_insufficient"))


func test_unfilled_bid_carries_when_cargo_can_still_cover_it() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "grain", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 10, "treasury": 5000, "buy_price": 10}
	)
	var before: int = (economies[0] as PlayerEconomy).quantity("grain")
	var report: Dictionary = MarketClearing.clear(
		market, world, economies, {0: 8, 1: 4}
	)
	# The world maker fills all five, so nothing carries; a fresh book stays clean.
	assert_eq((report["carry"] as Array).size(), 0)
	assert_eq((economies[0] as PlayerEconomy).quantity("grain"), before + 5)


func test_price_discovery_reads_filled_bids_and_submitted_offers() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	(economies[1] as PlayerEconomy).stockpile["timber"] = 10
	MarketOrders.submit(
			market,
		1, "timber", MarketOrder.SIDE_OFFER, 10,
		{"stock": 10}
	)
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 5,
		{"cargo_free": 8, "treasury": 5000, "buy_price": 30}
	)
	MarketClearing.clear(market, world, economies, {0: 8, 1: 8})
	assert_eq(market.price("timber"), 27, "5 filled bids against 10 submitted offers")


func test_purchased_tile_still_publishes_its_harvest() -> void:
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	var tile: Vector2i = Vector2i(2, 0)
	assert_true(model.purchase_tile(tile, 0))
	var orders: Array[MarketOrder] = MinorMarket.emit_orders(world)
	var found: bool = false
	for order: MarketOrder in orders:
		if order.commodity == "timber" and order.origin_index == model.index_of(tile.x, tile.y):
			found = true
			assert_eq(order.faction, 6)
			assert_true(order.auto)
	assert_true(found, "a deed keeps the seller's tile in the book for FRR")


func test_clearing_is_deterministic() -> void:
	var first: Dictionary = _clear_once()
	var second: Dictionary = _clear_once()
	assert_eq(first["deals"], second["deals"])


func _clear_once() -> Dictionary:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var economies: Dictionary = _economies()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	return MarketClearing.clear(market, world, economies, {0: 4, 1: 4})


func test_the_order_book_survives_a_save_round_trip() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	MarketOrders.submit(
			market,
		0, "timber", MarketOrder.SIDE_BID, 2,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.book.submitted.size(), 1)
	var order: MarketOrder = restored.book.submitted[0]
	assert_eq(order.commodity, "timber")
	assert_eq(order.remaining(), 2)
	assert_eq(restored.book.pending_buy_units(0), 2)
	assert_eq(MarketOrders.cancel(restored, 0, order.id), true)
	assert_eq(restored.book.pending_buy_units(0), 0)


func test_first_right_beats_a_favoured_partner() -> void:
	var orders: Array[MarketOrder] = [
		_order(0, "timber", MarketOrder.SIDE_BID, 4, 5),
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context()
	context["purchased_for"] = func(_region: int, _index: int) -> int: return 0
	context["ftp_for"] = func(a: int, b: int) -> bool: return a == 1 and b == 6
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int((result["deals"] as Array)[0]["buyer"]), 0)
	assert_true(bool((result["deals"] as Array)[0]["is_frr"]))


func test_an_embassy_kickback_is_paid_from_the_minor_sale() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	var model: MapModel = world.region(0)
	model.resource[model.index_of(0, 1)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	var diplomacy := DiplomacyState.new()
	diplomacy.ensure_relation(2, 6, 0).set_score(50.0)
	diplomacy.set_overture(2, 6, DiplomacyCatalog.STAGE_EMBASSY)
	MarketOrders.submit(
		market,
		1, "timber", MarketOrder.SIDE_BID, 1,
		{"cargo_free": 4, "treasury": 5000, "buy_price": 30}
	)
	# Give the kickback recipient a ledger so the credit is observable.
	var embassy_court: PlayerEconomy = PlayerEconomy.starting()
	economies[2] = embassy_court
	var before: int = embassy_court.treasury
	MarketClearing.clear(market, world, economies, {0: 4, 1: 4, 2: 4}, {"diplomacy": diplomacy})
	assert_eq(embassy_court.treasury, before + 2, "1 x 30 x 50% x 10% = 1.5, rounded once")


func test_a_bid_beyond_the_purse_is_refused_before_the_book() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var result: Dictionary = MarketOrders.submit(
		market,
		0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 100, "buy_price": 30}
	)
	assert_false(bool(result["ok"]))
	assert_eq(String(result["code"]), "trade_order_bid_exceeds_treasury_budget")


func test_cancelling_an_offer_returns_its_submitted_volume() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var staged: Dictionary = MarketOrders.submit(
		market,
		1, "timber", MarketOrder.SIDE_OFFER, 3, {"stock": 3}
	)
	assert_true(bool(staged["ok"]))
	assert_eq(market.offer_volume("timber"), 3)
	assert_true(MarketOrders.cancel(market, 1, String(staged["order_id"])))
	assert_eq(market.offer_volume("timber"), 0)
	assert_false(MarketOrders.cancel(market, 1, "missing"))


# --- what the auction promises and what it settles ---------------------------


## A bid cut short by cargo holds keeps its MarketActivityNote in the clearing
## report, so the Deal Book can audit the truncation (wiki: world-market
## § Treasury budget for bids — MarketActivityNote attribution).
func test_a_truncated_bid_keeps_its_audit_note() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	# No Minor harvest: the only supply is the Great Power offer below.
	world.region(0).resource[world.region(0).index_of(2, 0)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	(economies[1] as PlayerEconomy).stockpile["timber"] = 10
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 10, {"stock": 10}
	)["ok"]))
	assert_true(bool(MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 5000, "buy_price": 30}
	)["ok"]))
	# The turn's overseas extraction reserves most of the holds before the
	# auction clears, so the bid can only take two tons.
	var report: Dictionary = MarketClearing.clear(market, world, economies, {0: 2, 1: 10})
	assert_eq(int((report["fills"] as Dictionary).get(0, {}).get("bought", 0)), 2)
	var codes: Array[String] = []
	for note: Dictionary in report["notes"]:
		codes.append(String(note.get("code", "")))
	assert_true(
		codes.has("bid_partial_fill_cargo_insufficient"),
		"the cargo truncation reaches the Deal Book: %s" % str(codes)
	)
	var booked: Array = market.book.last_notes
	assert_eq(booked.size(), report["notes"].size(), "the book keeps the same notes")


## The Deal Book names the constraint that actually stopped the bid: a purse
## that cannot buy one more ton is a treasury truncation, not a cargo shortfall
## (wiki: world-market § Treasury budget for bids; REQ-P5-05 never a wrong reason).
func test_a_bid_cut_by_the_purse_names_the_purse() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 4, 1),
		_order(6, "timber", MarketOrder.SIDE_OFFER, 4, 1, 0, 1, true),
	]
	var context: Dictionary = _context({"treasuries": {1: 40}, "free_holds": {1: 10}})
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq(int(((result["deals"] as Array)[0] as Dictionary)["quantity"]), 1)
	var codes: Array[String] = []
	for note: Variant in result["notes"]:
		codes.append(String((note as Dictionary).get("code", "")))
	assert_true(codes.has("bid_partial_fill_treasury_insufficient"), str(codes))
	assert_false(codes.has("bid_partial_fill_cargo_insufficient"), str(codes))


## A bid with holds and purse to spare that no offer could fill is not a
## truncation; the Deal Book stays silent rather than blaming cargo.
func test_a_bid_with_no_offer_carries_without_a_note() -> void:
	var orders: Array[MarketOrder] = [
		_order(1, "timber", MarketOrder.SIDE_BID, 2, 1),
	]
	var context: Dictionary = _context({"treasuries": {1: 5000}, "free_holds": {1: 10}})
	var result: Dictionary = MarketMatcher.match(orders, context)
	assert_eq((result["notes"] as Array).size(), 0, str(result["notes"]))


## A Great Power offer the seller can no longer cover is not a deal, and the
## dropped units are named (wiki: world-market § Trade orders — an offer sells
## only what the ledger still holds; REQ-P5-05 never a silent outcome).
func test_an_offer_the_seller_spent_does_not_mint_goods() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var world: WorldMap = _world()
	world.region(0).resource[world.region(0).index_of(2, 0)] = MapModel.NO_ID
	var economies: Dictionary = _economies()
	var seller: PlayerEconomy = economies[1]
	var buyer: PlayerEconomy = economies[0]
	seller.stockpile["timber"] = 10
	assert_true(bool(MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 10, {"stock": 10}
	)["ok"]))
	# Production runs before the auction and eats every ton offered.
	assert_true(seller.take("timber", 10))
	assert_true(bool(MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 10,
		{"cargo_free": 20, "treasury": 5000, "buy_price": 30}
	)["ok"]))
	var seller_purse: int = seller.treasury
	var buyer_purse: int = buyer.treasury
	var report: Dictionary = MarketClearing.clear(market, world, economies, {0: 20, 1: 20})
	assert_eq(seller.treasury, seller_purse, "no pay for timber the seller no longer holds")
	assert_eq(buyer.treasury, buyer_purse, "no charge for a deal that cannot ship")
	assert_eq(buyer.quantity("timber"), 0, "the auction never mints goods")
	var noted: bool = false
	for note: Dictionary in report["notes"]:
		if String(note.get("code", "")) == "offer_partial_fill_stock_insufficient":
			noted = true
	assert_true(noted, "the dropped fill is on the deal book")


## The offer cap is the post-production stockpile minus the inputs the assigned
## runs will eat (wiki: world-market § Trade orders — validation rule 7).
func test_an_offer_is_capped_by_the_production_that_will_eat_it() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var reserved: Dictionary = ProductionRecipes.reserved_inputs(
		[{"recipe": "lumber", "units": 3}]
	)
	assert_eq(int(reserved.get("timber", 0)), 6, "3 runs x 2 timber")
	var refused: Dictionary = MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 5,
		{"stock": 10, "reserved": reserved}
	)
	assert_false(bool(refused["ok"]))
	assert_eq(String(refused["code"]), "trade_order_stock_insufficient")
	var admitted: Dictionary = MarketOrders.submit(
		market, 1, "timber", MarketOrder.SIDE_OFFER, 4,
		{"stock": 10, "reserved": reserved}
	)
	assert_true(bool(admitted["ok"]), String(admitted.get("reason", "")))


# --- from test_ledger_text.gd ---
## Ledger copy: the market clearing line and its quiet empty case.


func test_a_quiet_market_prints_nothing() -> void:
	assert_eq(LedgerText.market_summary({}, 0), "")


## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).
func test_the_disband_hint_names_the_promise_and_the_saving() -> void:
	var hint: String = LedgerText.disband_hint(WorkerPool.Tier.APPRENTICE)
	assert_true(hint.contains("no recruit cost is refunded"), hint)
	assert_true(hint.contains("An apprentice eats 2 food"), hint)
	assert_true(hint.contains("a unit of Refined Sugar"), hint)
	var master: String = LedgerText.disband_hint(WorkerPool.Tier.MASTER)
	assert_true(master.contains("A master eats 2 food and a unit of Fur Hats"), master)


func test_fills_carry_and_lapse_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"bought": 2, "spent": 60, "sold": 1}},
		"carry": [{"commodity": "timber"}],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 0,
			"commodity": "grain",
		}],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("bought 2 for 60 ducats"))
	assert_true(line.contains("sold 1"))
	assert_true(line.contains("1 order carried"))
	assert_true(line.contains("1 order lapsed"))


func test_another_courts_lapse_is_not_ours() -> void:
	var report: Dictionary = {
		"fills": {},
		"carry": [],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 1,
			"commodity": "grain",
		}],
	}
	assert_eq(LedgerText.market_summary(report, 0), "")


# --- from test_ledger_helpers.gd ---
## Unit: the pure helpers extracted from the ledger and estates panels
## (REQ-P3-01, REQ-P3-04). No scene tree, so the rules stay testable.


# --- TextFormat --------------------------------------------------------------


func test_thousands_groups_and_keeps_the_sign() -> void:
	assert_eq(TextFormat.thousands(0), "0")
	assert_eq(TextFormat.thousands(999), "999")
	assert_eq(TextFormat.thousands(1000), "1,000")
	assert_eq(TextFormat.thousands(1234567), "1,234,567")
	assert_eq(TextFormat.thousands(-1234), "-1,234")


# --- LedgerText --------------------------------------------------------------


func test_recipe_title_names_the_single_input() -> void:
	var recipe_id: String = ProductionRecipes.available_ids({})[0]
	var title: String = LedgerText.recipe_title(recipe_id)
	assert_true(title.contains(CommodityCatalog.label(ProductionRecipes.output(recipe_id))))
	assert_true(LedgerText.recipe_tooltip(recipe_id).contains("→"))


func test_the_summary_reads_the_report() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 1234
	var report: Dictionary = {
		"consumption": {"idle_labour": 3, "strikers": 2, "navy_demand": 5},
	}
	var line: String = LedgerText.summary(economy, report)
	assert_true(line.contains("1,234 ducats"))
	assert_true(line.contains("labour 3 /"))
	assert_true(line.contains("strikes 2"))


func test_the_preview_reports_deltas_or_calm() -> void:
	assert_eq(LedgerText.preview({}), "Next turn: no stock changes.")
	var line: String = LedgerText.preview(
		{"stockpile_delta": {"grain": 3}, "treasury_delta": -10}
	)
	assert_true(line.contains("+3"))
	assert_true(line.contains("ducats -10"))


func test_the_cargo_banner_covers_three_states() -> void:
	assert_true(LedgerText.cargo_line({}).contains("unknown"))
	var empty: Dictionary = {"holds": 0, "free": 0}
	assert_true(LedgerText.cargo_line(empty).contains("No cargo holds"))
	assert_eq(LedgerText.cargo_color(empty), Palette.GOLD_PALE)
	var laden: Dictionary = {"holds": 4, "free": 1}
	assert_true(LedgerText.cargo_line(laden).contains("4 holds"))
	assert_eq(LedgerText.cargo_color(laden), Palette.TEXT)


func test_report_counters_default_to_zero() -> void:
	assert_eq(LedgerText.idle_labour({}), 0)
	assert_eq(LedgerText.navy_food({"consumption": {"navy_demand": 7}}), 7)


# --- EstateLedger ------------------------------------------------------------


func _group(id: int, name: String, rows: Array) -> Dictionary:
	var producing: int = 0
	for row: Dictionary in rows:
		if int(row.get("output", 0)) > 0:
			producing += 1
	return {"id": id, "name": name, "rows": rows, "producing": producing}


func _rows() -> Array:
	return [
		{"output": 2, "working": false, "status": "producing"},
		{"output": 0, "working": true, "status": "building"},
		{"output": 0, "working": false, "status": "vacant"},
		{"output": 0, "working": false, "status": "disconnected"},
	]


func test_groups_keep_province_order_and_merge_duplicates() -> void:
	var snapshot: Dictionary = {
		"groups": [
			_group(4, "OLD", _rows().slice(0, 2)),
			_group(4, "OLD", _rows().slice(2)),
			_group(9, "NEW", _rows().slice(0, 1)),
		],
	}
	var groups: Array[Dictionary] = EstateLedger.grouped(snapshot)
	assert_eq(groups.size(), 2)
	assert_eq(groups[0]["name"], "OLD")
	assert_eq((groups[0]["rows"] as Array).size(), 4)


func test_province_filter_keeps_one_group() -> void:
	var groups: Array[Dictionary] = EstateLedger.grouped(
		{"groups": [_group(1, "A", _rows()), _group(2, "B", _rows())]}
	)
	assert_eq(EstateLedger.in_province(groups, -1).size(), 2)
	assert_eq(EstateLedger.in_province(groups, 2).size(), 1)


func test_each_filter_selects_its_rows() -> void:
	var rows: Array = _rows()
	assert_eq(EstateLedger.matching(rows, "all").size(), 4)
	assert_eq(EstateLedger.matching(rows, "producing").size(), 1)
	assert_eq(EstateLedger.matching(rows, "building").size(), 1)
	assert_eq(EstateLedger.matching(rows, "vacant").size(), 1)
	assert_eq(EstateLedger.matching(rows, "issues").size(), 1)


func test_total_output_sums_every_yield() -> void:
	assert_eq(EstateLedger.total_output({"lumber": 2, "iron": 3}), 5)
	assert_eq(EstateLedger.total_output({}), 0)


# --- UiRowBuilder ------------------------------------------------------------


func test_row_builder_builds_themed_widgets() -> void:
	var row: HBoxContainer = UiRowBuilder.row(38.0)
	assert_eq(row.custom_minimum_size.y, 38.0)
	var label: Label = UiRowBuilder.label("hi", 14, Palette.TEXT)
	assert_eq(label.text, "hi")
	var caption: Label = UiRowBuilder.caption("x", 10, Palette.TEXT_DIM, 44.0)
	assert_eq(caption.custom_minimum_size.x, 44.0)
	var button: Button = UiRowBuilder.button("Go", 38.0, 70.0)
	assert_eq(button.text, "Go")
	assert_eq(button.custom_minimum_size, Vector2(70, 38))
	row.free()
	label.free()
	caption.free()
	button.free()


func test_clear_empties_a_container() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	UiRowBuilder.spacer(box)
	box.add_child(UiRowBuilder.label("gone", 12, Palette.TEXT))
	box.add_child(UiRowBuilder.label("gone too", 12, Palette.TEXT))
	assert_eq(box.get_child_count(), 3)
	UiRowBuilder.clear(box)
	assert_eq(box.get_child_count(), 0)
	box.queue_free()


# --- from test_commodity_icons.gd ---
## Every commodity carries its own medallion and every plate ships, so no two
## goods share one picture in the ledger (REQ-P1-02; tools/art/goods-medallions.md).


func test_every_catalog_commodity_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if CommodityIcons.texture(id) == null:
			missing.append(id)
	assert_eq(missing.size(), 0, "goods with no plate: %s" % ", ".join(missing))


func test_two_goods_never_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		var art: Texture2D = CommodityIcons.texture(id)
		if art == null:
			continue
		if seen.has(art.resource_path):
			clashes.append("%s/%s" % [seen[art.resource_path], id])
		seen[art.resource_path] = id
	assert_eq(clashes.size(), 0, "goods sharing a plate: %s" % ", ".join(clashes))


func test_an_unknown_good_has_no_plate() -> void:
	assert_null(CommodityIcons.texture("no_such_good"))
	assert_null(CommodityIcons.texture(""))


func test_a_badge_draws_the_good_at_the_row_size() -> void:
	var badge: Control = CommodityIcons.badge("grain")
	var art: TextureRect = badge as TextureRect
	assert_not_null(art, "a known good draws a texture")
	assert_eq(art.texture, CommodityIcons.texture("grain"))
	assert_eq(art.custom_minimum_size, Vector2(CommodityIcons.ROW_SIZE, CommodityIcons.ROW_SIZE))
	badge.free()


func test_a_missing_plate_leaves_a_gap_of_the_same_width() -> void:
	var gap: Control = CommodityIcons.badge("no_such_good", 18)
	assert_null(gap as TextureRect, "a missing plate is not a texture")
	assert_eq(gap.custom_minimum_size, Vector2(18, 18), "the row keeps its columns")
	gap.free()


func test_a_name_cell_keeps_the_column_width() -> void:
	var cell: HBoxContainer = CommodityIcons.cell("timber", 132.0)
	assert_eq(cell.custom_minimum_size.x, 132.0, "the cell owns the column width")
	var labels: Array[Node] = cell.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1, "one label per cell")
	assert_eq((labels[0] as Label).text, CommodityCatalog.label("timber"))
	var art: Array[Node] = cell.find_children("*", "TextureRect", true, false)
	assert_eq(art.size(), 1, "the medallion rides inside the cell")
	assert_eq((art[0] as TextureRect).texture, CommodityIcons.texture("timber"))
	cell.free()


## The plate is 128 px so it survives the phone's 3× draw scale.
func test_a_plate_is_a_128_px_source() -> void:
	var art: Texture2D = CommodityIcons.texture("coal")
	assert_not_null(art)
	assert_eq(art.get_width(), 128)
	assert_eq(art.get_height(), 128)


# --- from test_trade_cargo.gd ---
## Merchant cargo: the home fleet's holds cap world-market imports (wiki:
## ships-and-naval § Cargo holds and capacity; world-market § Cargo;
## DR-20261109-03). Pure rules, so no scene is needed.

const NavalFixture = preload("res://tests/naval_fixture.gd")


func _cargo_world() -> WorldMap:
	var world := WorldMap.new()
	world.add_region(NavalFixture.build())
	return world


func test_a_merchant_hull_carries_cargo_and_a_warship_does_not() -> void:
	var fluyte := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "sloop"})
	assert_eq(TradeCargo.fleet_holds(fluyte), 4)
	var galleon := FleetState.in_port(2, 0, 0, ["c"], {"c": "galleon"})
	assert_eq(TradeCargo.fleet_holds(galleon), 6)
	var line := FleetState.in_port(3, 0, 0, ["d"], {"d": "ship_of_the_line"})
	assert_eq(TradeCargo.fleet_holds(line), 0)
	assert_eq(TradeCargo.fleet_holds(null), 0)


func test_capacity_counts_only_the_crowns_squadrons_in_port_at_its_seat() -> void:
	var world: WorldMap = _cargo_world()
	var home := FleetState.in_port(1, 0, 0, ["a", "b"], {"a": "fluyte", "b": "carrack"})
	var at_sea := FleetState.at_sea(2, 0, 0, ["c"], {"c": "indiaman"})
	# A harbour that is not the seat carries nothing.
	var other_port := FleetState.in_port(3, 0, 1, ["d"], {"d": "indiaman"})
	var foreign := FleetState.in_port(4, 1, 1, ["e"], {"e": "galleon"})
	var fleets: Dictionary = {0: [home, at_sea, other_port], 1: [foreign]}

	assert_eq(TradeCargo.capacity(world, fleets, 0), 7)
	assert_eq(TradeCargo.capacity(world, fleets, 1), 0)


func test_a_crown_without_a_seat_has_no_cargo() -> void:
	var world: WorldMap = _cargo_world()
	var home := FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	assert_eq(TradeCargo.capacity(world, {0: [home]}, 6), 0)
	assert_eq(TradeCargo.capacity(null, {0: [home]}, 0), 0)


func test_status_reports_holds_used_and_free() -> void:
	var world: WorldMap = _cargo_world()
	var home := FleetState.in_port(1, 0, 0, ["a"], {"a": "fluyte"})
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 2)["ok"]))

	var status: Dictionary = TradeCargo.status(world, {0: [home]}, 0, market)

	assert_eq(int(status["holds"]), 4)
	assert_eq(int(status["used"]), 2)
	assert_eq(int(status["free"]), 2)


func test_imports_share_the_holds_across_commodities() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var fabric_before: int = economy.quantity("fabric")

	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 3)["ok"]))
	assert_true(bool(TradeCargo.buy(economy, market, 4, "timber", 1)["ok"]))
	var refused: Dictionary = TradeCargo.buy(economy, market, 4, "fabric", 1)

	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("4 cargo holds"))
	assert_eq(market.bought_units(), 4)
	assert_eq(economy.quantity("fabric"), fabric_before)


func test_no_home_fleet_refuses_with_its_own_reason() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	var refused: Dictionary = TradeCargo.buy(economy, market, 0, "grain", 1)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("No cargo holds"))
	assert_eq(market.bought_units(), 0)


func test_other_market_refusals_pass_through() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "gold", 1)["reason"]),
		"Not traded on the world market"
	)
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "grain", 0)["reason"]),
		"Quantity must be positive"
	)
	economy.treasury = 10
	assert_eq(
		String(TradeCargo.buy(economy, market, 4, "grain", 1)["reason"]),
		"Insufficient treasury"
	)


func test_sales_do_not_spend_a_hold() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.stockpile["timber"] = 2

	assert_true(bool(market.sell(economy, "timber", 2)["ok"]))

	assert_eq(market.bought_units(), 0)
	assert_eq(TradeCargo.free_holds(4, market), 4)


func test_next_turn_releases_the_holds() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 2, "grain", 2)["ok"]))
	assert_eq(TradeCargo.free_holds(2, market), 0)

	market.advance_prices()

	assert_eq(TradeCargo.free_holds(2, market), 2)
	assert_eq(market.bought_units(), 0)


func test_a_saved_market_remembers_the_laden_holds() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_true(bool(TradeCargo.buy(economy, market, 3, "grain", 2)["ok"]))

	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())

	assert_eq(restored.bought_units(), 2)
	assert_eq(TradeCargo.free_holds(3, restored), 1)


# --- from test_economy_overseas.gd ---
## Overseas cargo: colony yield crosses on the home fleet's holds, richest
## commodity first, and undelivered tonnage stays abroad (wiki:
## extraction-and-improvements § Flow to Stockpile; DR-20261109-17).


func _region(owner_resource: int = 0) -> MapModel:
	var model := MapModel.new()
	model.setup(2, 1)
	model.province[model.index_of(0, 0)] = 0
	model.province[model.index_of(1, 0)] = 0
	var tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var province := ProvinceState.create(0, "Colony", tiles, Vector2.ZERO, 2, 0)
	province.town_development = 4
	model.provinces.append(province)
	model.resource[model.index_of(0, 0)] = owner_resource
	model.resource[model.index_of(1, 0)] = 4
	return model


func _works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, Vector2i(0, 0))
	works.set_improvement(model, Vector2i(0, 0), 1)
	return works


func test_shipping_order_is_richest_per_hold_first() -> void:
	assert_eq(
		EconomyOverseas.priority(["grain", "diamonds", "gold", "castIron"]),
		["diamonds", "gold", "castIron", "grain"]
	)


func test_the_holds_cap_the_crossing_and_the_rest_stays_abroad() -> void:
	var plan: Dictionary = EconomyOverseas.plan(
		{0: {"grain": 3}, 1: {"gold": 2, "timber": 4}}, 4
	)

	assert_eq(int(plan["holds"]), 4)
	assert_eq(int(plan["used"]), 4)
	assert_eq(plan["shipped"], {"gold": 2, "grain": 2})
	assert_eq(plan["left"], {"grain": 1, "timber": 4})
	assert_eq(int(plan["left_total"]), 5)


func test_no_holds_lands_nothing() -> void:
	var plan: Dictionary = EconomyOverseas.plan({0: {"timber": 2}}, 0)

	assert_eq(int(plan["used"]), 0)
	assert_eq(plan["shipped"], {})
	assert_eq(int(plan["left_total"]), 2)
	assert_eq(EconomyOverseas.shipped_total(plan), 0)


func test_more_holds_than_cargo_ships_everything() -> void:
	var plan: Dictionary = EconomyOverseas.plan({0: {"timber": 2}}, 9)

	assert_eq(int(plan["used"]), 2)
	assert_eq(plan["left"], {})
	assert_eq(EconomyOverseas.shipped_total(plan), 2)


func test_region_totals_skip_the_home_region_and_need_a_port() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(4))
	var works := MapRegionTable.new()
	works.set_region(0, _works(world.region(0)))
	works.set_region(1, _works(world.region(1)))

	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {}, works
	)

	assert_false(by_region.has(0), "home yield never needs a hold")
	assert_eq(by_region.get(1, {}), {"grain": 1})


func test_an_unconnected_colony_yields_nothing_to_ship() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(0))
	var works := MapRegionTable.new()
	works.set_region(1, LandWorks.new())

	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {}, works
	)

	assert_eq(by_region, {})
	assert_eq(
		EconomyOverseas.region_totals(world, WorldMap.OLD_WORLD, 0, {}, null), {}
	)


func test_the_ledger_reserves_the_colony_cargo_before_imports() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	var home: FleetState = FleetState.in_port(
		1, 0, 0, ["a"], {"a": "fluyte"}
	)
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()

	assert_eq(
		int(TradeCargo.status(world, {0: [home]}, 0, market, 3)["reserved"]), 3
	)
	assert_eq(int(TradeCargo.status(world, {0: [home]}, 0, market, 3)["free"]), 1)
	assert_eq(TradeCargo.free_holds(4, market, 3), 1)
	assert_true(bool(TradeCargo.buy(economy, market, 4, "grain", 1, 3)["ok"]))
	var refused: Dictionary = TradeCargo.buy(economy, market, 4, "grain", 1, 3)
	assert_false(bool(refused["ok"]))
	assert_true(String(refused["reason"]).contains("promised to the colonies"))


func test_the_banner_names_the_colonial_reservation() -> void:
	var cargo: Dictionary = {"holds": 6, "used": 0, "reserved": 4, "free": 2}

	var line: String = LedgerText.cargo_line(cargo)

	assert_true(line.contains("6 holds"))
	assert_true(line.contains("4 for the colonies"))
	assert_true(line.contains("2 free"))
	assert_true(LedgerText.cargo_line({"holds": 6, "free": 2}).contains("2 free"))


## One rule for the player's ledger and a rival's economy: home yield lands
## directly and the other region's tonnage needs a hold (DR-20261109-17).
func test_delivered_adds_only_what_the_holds_carry() -> void:
	var world := WorldMap.new()
	world.add_region(_region(0))
	world.add_region(_region(4))
	var works := MapRegionTable.new()
	works.set_region(0, _works(world.region(0)))
	works.set_region(1, _works(world.region(1)))
	var home := {"grain": 3}

	var none: Dictionary = EconomyOverseas.delivered(
		home, world, WorldMap.OLD_WORLD, 0, {}, works, 0
	)
	var one: Dictionary = EconomyOverseas.delivered(
		home, world, WorldMap.OLD_WORLD, 0, {}, works, 1
	)

	assert_eq(none["extraction"], {"grain": 3}, "no hold, no colonial ton")
	assert_eq(int(none["used"]), 0)
	assert_eq(int(one["used"]), 1)
	assert_eq(one["extraction"], {"grain": 4})
	assert_eq(home, {"grain": 3}, "the home totals are not mutated")


# --- overseas town manufacturing ---------------------------------------------


## A colony of one town tile and two rail-linked timber estates, the estates
## already fully improved so the province's whole harvest is 8 timber.
func _plantation(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for x in 3:
		var tile := Vector2i(x, 0)
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(x, 0)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 0)
	province.town_tile = Vector2i(0, 0)
	province.town_development = level
	model.provinces.append(province)
	for x: int in [1, 2]:
		model.resource[model.index_of(x, 0)] = 0
	return model


func _plantation_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, Vector2i(0, 0))
	for x: int in [1, 2]:
		works.set_improvement(model, Vector2i(x, 0), LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, Vector2i(x, 0), LandWorks.TRANSPORT_RAIL)
	return works


## One home region empty of the crown's land plus one plantation region.
func _plantation_world(levels: Array) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_region(4))
	for level: int in levels:
		var model: MapModel = _plantation(level)
		world.add_region(model)
	return world


func _plantation_works_table(world: WorldMap) -> MapRegionTable:
	var table := MapRegionTable.new()
	for index in range(1, world.region_count()):
		table.set_region(index, _plantation_works(world.region(index)))
	return table


## Raw crosses and manufactures are earned on the far shore: no lumber leaves a
## colonial town before its input has landed (wiki: extraction-and-improvements
## § Town manufacturing bonus).
func test_overseas_totals_ship_raw_and_leave_the_bonus_to_delivery() -> void:
	var world: WorldMap = _plantation_world([4])
	var by_region: Dictionary = EconomyOverseas.region_totals(
		world, WorldMap.OLD_WORLD, 0, {"timber": 4}, _plantation_works_table(world)
	)

	assert_eq(by_region.get(1, {}), {"timber": 8}, "raw only — no lumber yet")


func test_landed_raw_pays_the_colonial_town_bonus() -> void:
	var world: WorldMap = _plantation_world([4])
	var plan: Dictionary = EconomyOverseas.delivered(
		{"grain": 3}, world, WorldMap.OLD_WORLD, 0, {"timber": 4},
		_plantation_works_table(world), 8
	)

	assert_eq(plan["shipped"], {"timber": 8})
	assert_eq(
		plan["manufactured"], {"lumber": 4, "paper": 4}, "level 4: floor(8 / 4) x 2"
	)
	assert_eq(plan["extraction"], {"grain": 3, "timber": 8, "lumber": 4, "paper": 4})
	assert_eq(int(plan["used"]), 8, "bonus output never spends a hold")
	assert_eq(plan["by_province"].get(1, {}).get(0, {}), {"timber": 8})


## Short holds leave tonnage on the far shore, and undelivered raw feeds no
## bonus recipe — four timber make one lumber, three make none.
func test_undelivered_tons_pay_no_colonial_bonus() -> void:
	var world: WorldMap = _plantation_world([4])
	var plan: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4},
		_plantation_works_table(world), 3
	)

	assert_eq(plan["shipped"], {"timber": 3})
	assert_eq(plan["manufactured"], {})
	assert_eq(plan["extraction"], {"timber": 3})
	assert_eq(int(plan["left_total"]), 5, "the rest stays abroad")


## Within one commodity the fuller town draws the holds first, so a level-4 town
## earns its bonus before a level-2 one (DR-20261111-*).
func test_the_better_town_draws_the_landed_tons_first() -> void:
	var world: WorldMap = _plantation_world([2, 4])
	var works: MapRegionTable = _plantation_works_table(world)

	var tight: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4}, works, 8
	)
	var roomy: Dictionary = EconomyOverseas.delivered(
		{}, world, WorldMap.OLD_WORLD, 0, {"timber": 4}, works, 16
	)

	assert_eq(
		tight["manufactured"], {"lumber": 4, "paper": 4}, "the level-4 town draws first"
	)
	assert_eq(
		roomy["manufactured"], {"lumber": 6, "paper": 6}, "then the level-2 town's x1"
	)


## A colonial town that manufactured says so in the turn summary, so the bonus is
## visible without opening a ledger (REQ-P5-05).
func test_the_turn_summary_names_colonial_manufactures() -> void:
	var report: Dictionary = {
		"overseas": {"used": 8, "left_total": 2, "manufactured": {"castIron": 2}},
	}
	var line: String = LedgerText.turn_summary(report)

	assert_true(line.contains("8 colonial tons landed"))
	assert_true(line.contains("2 cast iron made in colonial towns"))
	assert_true(line.contains("2 left on the far shore"))
	assert_false(LedgerText.turn_summary({}).contains("colonial towns"))
