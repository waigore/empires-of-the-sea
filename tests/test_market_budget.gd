extends GdToolsTest
## The crown's bid budget: the purse the turn's auction may spend once the
## waiting Build/work orders are paid (wiki: world-market § Treasury budget for
## bids; DR-20261115-13). One boot for the projection, the validator's refusal
## and the ledger line.

const TIMBER_PRICE: int = 30


func _economy(treasury: int = PlayerEconomy.START_TREASURY) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func _market() -> WorldMarket:
	return WorldMarket.with_default_prices()


func test_no_waiting_order_leaves_the_whole_purse() -> void:
	var economy: PlayerEconomy = _economy(2500)
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["treasury"]), 2500)
	assert_eq(int(reading["promised"]), 0)
	assert_eq(int(reading["budget"]), 2500)
	assert_eq(MarketBudget.projected_non_bid_delta(economy), 0)
	assert_true(LedgerText.bid_budget_line(reading).contains("whole purse"))


func test_a_waiting_hull_is_promised_before_the_auction() -> void:
	var economy: PlayerEconomy = _economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["promised"]), ShipEconomy.treasury_cost("carrack"))
	assert_eq(int(reading["budget"]), 10000 - ShipEconomy.treasury_cost("carrack"))
	assert_eq(
		MarketBudget.projected_non_bid_delta(economy),
		-ShipEconomy.treasury_cost("carrack")
	)


func test_each_kind_is_priced_by_its_own_catalog() -> void:
	var economy: PlayerEconomy = _economy(20000)
	economy.queue_build(RecruitQueue.KIND_WORKER, "1")
	economy.queue_build(RecruitQueue.KIND_CIVILIAN, "builder")
	economy.queue_build(RecruitQueue.KIND_REGIMENT, RegimentCatalog.DEFAULT_TYPE)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var expected: int = (
		int(WorkerPool.recruit_cost(1)["treasury"])
		+ CivilianCatalog.treasury_cost("builder")
		+ RegimentCatalog.treasury_cost(RegimentCatalog.DEFAULT_TYPE)
		+ ShipEconomy.treasury_cost("carrack")
	)
	assert_eq(MarketBudget.promised(economy), expected)
	var rows: Array[Dictionary] = MarketBudget.pending(economy)
	assert_eq(rows.size(), 4)
	assert_eq(String(rows[0]["label"]), WorkerPool.tier_one(1))
	assert_eq(String(rows[3]["label"]), ShipStats.display_name("carrack"))


func test_an_unknown_order_costs_nothing() -> void:
	assert_eq(MarketBudget.order_cost("bogus", "nothing"), 0)
	assert_eq(MarketBudget.order_label("bogus", "nothing"), "")


func test_a_missing_ledger_asks_nothing_of_the_purse() -> void:
	assert_eq(MarketBudget.pending(null).size(), 0)
	assert_eq(MarketBudget.promised(null), 0)
	var reading: Dictionary = MarketBudget.budget(null)
	assert_eq(int(reading["treasury"]), 0)
	assert_eq(int(reading["budget"]), 0)


func test_a_promise_beyond_the_purse_leaves_nothing_to_bid() -> void:
	var economy: PlayerEconomy = _economy(2500)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var reading: Dictionary = MarketBudget.budget(economy)
	assert_eq(int(reading["budget"]), 0)
	assert_true(LedgerText.bid_budget_line(reading).contains("nothing this turn"))


func test_a_bid_the_promise_cannot_cover_is_refused() -> void:
	var economy: PlayerEconomy = _economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var market: WorldMarket = _market()
	var context: Dictionary = {
		"cargo_free": 200,
		"treasury": economy.treasury,
		"buy_price": TIMBER_PRICE,
		"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(economy),
	}
	var greedy: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 100, context
	)
	assert_false(bool(greedy["ok"]))
	assert_eq(String(greedy["code"]), "trade_order_bid_exceeds_treasury_budget")
	assert_true(String(greedy["reason"]).contains("waiting orders"))
	var modest: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 1, context
	)
	assert_true(bool(modest["ok"]), "one ton fits the purse the hull leaves")


func test_the_same_bid_clears_without_a_waiting_order() -> void:
	var economy: PlayerEconomy = _economy(10000)
	var market: WorldMarket = _market()
	var result: Dictionary = MarketOrders.submit(
		market, 0, "timber", MarketOrder.SIDE_BID, 100,
		{
			"cargo_free": 200,
			"treasury": economy.treasury,
			"buy_price": TIMBER_PRICE,
			"projected_non_bid_delta": MarketBudget.projected_non_bid_delta(economy),
		}
	)
	assert_true(bool(result["ok"]), "an uncommitted purse covers the same bid")


func test_the_line_names_the_promised_purse() -> void:
	var economy: PlayerEconomy = _economy(10000)
	economy.queue_build(RecruitQueue.KIND_SHIP, "carrack")
	var line: String = LedgerText.bid_budget_line(MarketBudget.budget(economy))
	assert_true(line.contains("2,000 of 10,000 ducats"))
	assert_true(line.contains("8,000 promised to 1 waiting order"))
