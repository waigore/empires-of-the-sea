extends GdToolsTest
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
