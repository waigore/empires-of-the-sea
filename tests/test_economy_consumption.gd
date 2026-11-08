extends GdToolsTest
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
