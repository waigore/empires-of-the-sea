extends GdToolsTest
## Integration: the map screen's ledger drives the real economy (REQ-P2-03).

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_the_screen_owns_a_starting_economy() -> void:
	assert_not_null(_screen.economy)
	assert_not_null(_screen.economy.economy)
	assert_not_null(_screen.economy.market)
	assert_eq(_screen.treasury, _screen.economy.economy.treasury)
	assert_eq(
		_screen.economy.economy.workers.count(WorkerPool.Tier.PEASANT),
		PlayerEconomy.START_PEASANTS
	)
	assert_gt(_screen.economy.extraction().size(), 0)


func test_the_ledger_opens_and_closes() -> void:
	assert_false(_screen.hud.panels.is_economy_open())
	_screen.economy.open_panel()
	assert_true(_screen.hud.panels.is_economy_open())
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	assert_not_null(panel)
	assert_gt(panel.get_combined_minimum_size().y, 100.0)
	_screen.hud.panels.hide_economy()
	assert_false(_screen.hud.panels.is_economy_open())


func test_buying_stages_a_bid_then_clears_it() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var treasury_before: int = economy.treasury
	var grain_before: int = economy.quantity("grain")
	var unit: int = _screen.economy.market.buy_price("grain")
	_screen.economy._on_trade("grain", 2, true)
	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), 2)
	assert_eq(economy.quantity("grain"), grain_before, "stock waits for the clearing")
	_clear_market()
	assert_eq(economy.quantity("grain"), grain_before + 2)
	assert_eq(economy.treasury, treasury_before - 2 * unit)
	assert_eq(_screen.treasury, economy.treasury)


func test_selling_needs_stock_and_clears_at_the_close() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 1
	var treasury_before: int = economy.treasury
	var unit: int = _screen.economy.market.sell_price("timber")
	_screen.economy._on_trade("timber", 1, false)
	assert_eq(economy.quantity("timber"), 1, "the offer waits for the clearing")
	assert_eq(economy.treasury, treasury_before)
	_clear_market()
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(economy.treasury, treasury_before + unit)


func test_production_assignment_reaches_the_projection() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy._on_production("lumber", 2)
	assert_eq(economy.assignment_units("lumber"), 2)
	var preview: Dictionary = _screen.economy.projected()
	assert_gt(int(preview["stockpile_delta"].get("lumber", 0)), 0)
	assert_lt(int(preview["stockpile_delta"].get("timber", 0)), 0)


func test_recruiting_a_peasant_through_the_ledger() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["fabric"] = 2
	var before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	_screen.economy._on_worker_action(WorkerPool.Tier.PEASANT, "recruit")
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), before + 1)
	assert_eq(economy.quantity("fabric"), 0)


func test_the_ledger_sends_a_trained_worker_back_to_the_fields() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.workers.set_count(WorkerPool.Tier.APPRENTICE, 1)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var key: String = "disband:%d" % WorkerPool.Tier.APPRENTICE
	var disband: Button = workers.action_buttons().get(key) as Button
	assert_not_null(disband, "a trained tier offers disband")
	assert_false(disband.disabled, "one apprentice can go home")
	assert_true(
		disband.tooltip_text.contains("no recruit cost is refunded"),
		"the promise is on the control: %s" % disband.tooltip_text
	)
	var peasants_before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	var treasury_before: int = economy.treasury
	disband.pressed.emit()
	assert_eq(economy.workers.count(WorkerPool.Tier.APPRENTICE), 0)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), peasants_before + 1)
	assert_eq(economy.treasury, treasury_before, "disband refunds and charges nothing")
	var rebuilt: Dictionary = (
		panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	).action_buttons()
	assert_true(
		(rebuilt.get(key) as Button).disabled,
		"the emptied tier goes inert"
	)
	assert_false(
		rebuilt.has("disband:%d" % WorkerPool.Tier.PEASANT),
		"a peasant is never disbanded"
	)


func test_ending_the_turn_resolves_the_economy() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var before: Dictionary = economy.stockpile.duplicate()
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.turn, turn_before + 1)
	assert_eq(_screen.treasury, economy.treasury)
	assert_true(economy.stockpile != before)
	assert_gt(economy.total_units(), 0)


# --- merchant cargo ----------------------------------------------------------


func test_the_opening_home_fleet_carries_four_holds() -> void:
	var cargo: Dictionary = _screen.economy.trade_cargo()
	assert_eq(int(cargo["holds"]), 4)
	assert_eq(int(cargo["used"]), 0)
	assert_eq(int(cargo["free"]), 4)
	var seat: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(seat)
	assert_not_null(home, "the opening muster moors a squadron at the seat")
	assert_eq(home.type_of(home.hulls[0]), "fluyte")


func test_imports_stop_when_the_holds_are_full() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var grain_before: int = economy.quantity("grain")
	var free: int = int(_screen.economy.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy._on_trade("grain", 1, true)
	assert_eq(economy.quantity("grain"), grain_before, "imports clear at the close")
	assert_eq(_screen.economy.trade_cargo()["free"], 0)

	_screen.economy._on_trade("grain", 1, true)

	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), free)
	_clear_market()
	assert_eq(economy.quantity("grain"), grain_before + free, "one more hold is refused")


func test_selling_still_works_with_full_holds() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 1
	var free: int = int(_screen.economy.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy._on_trade("grain", 1, true)
	var grain_before: int = economy.quantity("grain")

	_screen.economy._on_trade("timber", 1, false)
	_clear_market()

	assert_eq(economy.quantity("grain"), grain_before + free)
	assert_eq(economy.quantity("timber"), 0)


func test_the_ledger_names_the_cargo_and_disables_full_imports() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var line: Label = _find_label(market_body, "CARGO")
	assert_not_null(line)
	assert_true(line.text.contains("4 holds"))

	var free: int = int(_screen.economy.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy._on_trade("grain", 1, true)

	var buys: Array[Button] = []
	_collect_buttons(market_body, buys)
	assert_false(buys.is_empty())
	assert_true(buys[buys.size() - 1].disabled, "a full hold locks the Bid rows")


## A controller that never got a map or a ship layer still answers the ledger:
## no holds, no overseas crossing, no home yield — never a crash.
func test_a_bare_controller_reports_an_empty_ledger() -> void:
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()

	assert_eq(controller.cargo_holds(), 0)
	assert_eq(controller.extraction(), {})
	assert_eq(int(controller.overseas_plan()["holds"]), 0)
	assert_eq(int(controller.trade_cargo()["free"]), 0)
	controller.free()


func test_a_crown_without_a_home_fleet_cannot_import() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.refresh(
		_screen.economy.economy, _screen.economy.market, _screen.economy.projected(),
		{"holds": 0, "used": 0, "free": 0}
	)
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var hint: Label = _find_label(market_body, "No cargo holds")
	assert_not_null(hint)
	var buy: Button = _find_button(market_body, "Bid")
	assert_not_null(buy)
	assert_true(buy.disabled)


func test_a_new_world_port_ships_its_yield_on_the_home_holds() -> void:
	var world: WorldMap = _screen.world
	var snapshot: Array = Fixture.snapshot(world)
	var nw: MapModel = world.region(WorldMap.NEW_WORLD)
	var province: ProvinceState = nw.provinces[0]
	var tile: Vector2i = province.tiles[0]
	var resource_index: int = nw.index_of(tile.x, tile.y)
	var old_resource: int = nw.resource[resource_index]
	var home_before: Dictionary = _screen.economy.extraction().duplicate()
	province.owner = _screen.player_faction
	nw.resource[resource_index] = 0
	var works := LandWorks.new()
	works.add_port(nw, tile)
	works.set_improvement(nw, tile, 1)
	_screen.play.civilian_layer.works_regions.set_region(WorldMap.NEW_WORLD, works)

	var plan: Dictionary = _screen.economy.overseas_plan()
	var cargo: Dictionary = _screen.economy.trade_cargo()

	assert_eq(int(plan["used"]), 1, "one connected estate ships one ton")
	assert_eq(plan["shipped"], {"timber": 1})
	assert_eq(
		int(_screen.economy.extraction().get("timber", 0)),
		int(home_before.get("timber", 0)) + 1,
		"the colonial ton reaches the stockpile"
	)
	assert_eq(int(cargo["reserved"]), 1)
	assert_eq(int(cargo["free"]), int(cargo["holds"]) - 1)

	Fixture.restore(world, snapshot)
	nw.resource[resource_index] = old_resource


func test_the_ledger_lists_minor_and_tribe_offers() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, LedgerMarket.OFFER_HEADER))
	assert_gt(
		_screen.economy.market.minor_offers.size(), 0,
		"the Old World's minor courts publish their harvest"
	)


func test_bidding_from_an_offer_row_enters_the_auction() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var stock_before: int = economy.quantity("timber")
	var treasury_before: int = economy.treasury
	_screen.economy.market.minor_offers = [{
		"id": "7:timber",
		"faction": 7,
		"commodity": "timber",
		"quantity": 2,
		"unit_price": _screen.economy.market.price("timber"),
	}]

	_screen.hud.panels.economy_panel.emit_signal("offer_requested", "7:timber", 1)

	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), 1)
	assert_eq(economy.quantity("timber"), stock_before)
	assert_eq(economy.treasury, treasury_before)
	_clear_market()
	assert_eq(economy.quantity("timber"), stock_before + 1)
	assert_eq(
		economy.treasury,
		treasury_before - _screen.economy.market.buy_price("timber")
	)


func test_an_empty_offer_book_says_so() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.refresh(
		_screen.economy.economy, _screen.economy.market, _screen.economy.projected(),
		{"holds": 2, "used": 0, "free": 2}, []
	)
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "No court has goods for sale"))


func test_the_ledger_shows_trade_terms_and_charges_the_adjusted_price() -> void:
	var market: WorldMarket = _screen.economy.market
	market.set_terms(_screen.player_faction, {"buy": {"*": 0.9}, "sell": {"*": 1.1}})
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var line: Label = _find_label(market_body, "imports at 90%")
	assert_not_null(line, "the ledger explains the court's trade terms")

	var economy: PlayerEconomy = _screen.economy.economy
	var before: int = economy.treasury
	var unit: int = market.buy_price("grain", _screen.player_faction)
	_screen.economy._on_trade("grain", 1, true)
	_clear_market()
	assert_eq(
		economy.treasury,
		before - unit,
		"the clearing charges the pact-adjusted price"
	)


func _clear_market() -> Dictionary:
	var cargo: Dictionary = _screen.economy.trade_cargo()
	return MarketClearing.clear(
		_screen.economy.market,
		_screen.world,
		{_screen.player_faction: _screen.economy.economy},
		{_screen.player_faction: int(cargo.get("clear_free", cargo.get("free", 0)))},
		{"diplomacy": _screen.play.diplomacy}
	)


func _find_label(node: Node, needle: String) -> Label:
	if node is Label and (node as Label).text.contains(needle):
		return node
	for child: Node in node.get_children():
		var found: Label = _find_label(child, needle)
		if found != null:
			return found
	return null


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).text == "Bid":
		out.append(node)
	for child: Node in node.get_children():
		_collect_buttons(child, out)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null



func test_the_ledger_names_the_last_clearing() -> void:
	_screen.economy.market.book.last_deals = [{
		"buyer": _screen.player_faction,
		"seller": 6,
		"commodity": "timber",
		"quantity": 1,
		"price": 30,
	}]
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "LAST CLEARING"))
	assert_not_null(_find_label(body, "Bought 1 Timber"))


## A colony's fill that went to its suzerain says so beside the sale, so the
## tiebreak is never a mystery (wiki: diplomacy § R7.1; DR-20261111-11).
func test_the_ledger_names_a_favoured_partner_fill() -> void:
	_screen.economy.market.book.last_deals = [{
		"buyer": _screen.player_faction,
		"seller": 12,
		"commodity": "timber",
		"quantity": 2,
		"price": 30,
		"is_favoured": true,
	}]
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "as its favoured partner"))


## The crown's ledger cannot offer what its own production will eat: the AI
## planners already reserve those inputs (wiki: world-market § Trade orders —
## validation rule 7; REQ-P2-03 one rule for player and AI).
func test_an_offer_cannot_sell_what_production_will_eat() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy._on_production("lumber", 2)  # 2 runs x 2 timber = all of it
	var refused: Dictionary = _screen.economy._on_trade("timber", 1, false)
	assert_false(bool(refused.get("ok", true)), "the assigned runs have claimed the timber")
	assert_eq(economy.quantity("timber"), 4, "a refused offer leaves the stock alone")
	assert_eq(_screen.economy.market.offer_volume("timber"), 0, "nothing is staged")
	_screen.economy._on_production("lumber", 0)
	var admitted: Dictionary = _screen.economy._on_trade("timber", 1, false)
	assert_true(bool(admitted.get("ok", false)), String(admitted.get("reason", "")))
	assert_eq(_screen.economy.market.offer_volume("timber"), 1)
	# The admitted ton really ships at the close.
	var unit: int = _screen.economy.market.sell_price("timber")
	var purse: int = economy.treasury
	_clear_market()
	assert_eq(economy.quantity("timber"), 3, "the offered ton left the stockpile")
	assert_eq(economy.treasury, purse + unit, "and the sale paid")


## The MARKET tab's Offer chip is gated by what the court's own production runs
## leave behind, and the tooltip says how much is claimed (wiki: world-market
## § Trade orders — the per-commodity sellable readout).
func test_the_offer_chip_names_what_production_claims() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy._on_production("lumber", 2)
	assert_eq(LedgerMarket.claimed_by_production(economy, "timber"), 4)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var chips: Array[Button] = []
	_collect_offer_chips(body, chips)
	var claimed_chip: Button = null
	for chip: Button in chips:
		if chip.tooltip_text.contains("claimed by production"):
			claimed_chip = chip
	assert_not_null(claimed_chip, "the chip explains the claim")
	assert_true(claimed_chip.disabled, "nothing is left to offer")
	assert_true(claimed_chip.tooltip_text.contains("0 sellable"))


func _collect_offer_chips(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).text == "Offer":
		out.append(node)
	for child: Node in node.get_children():
		_collect_offer_chips(child, out)
