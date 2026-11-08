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


func test_buying_moves_treasury_and_stock() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var treasury_before: int = economy.treasury
	var grain_before: int = economy.quantity("grain")
	_screen.economy._on_trade("grain", 2, true)
	assert_eq(economy.quantity("grain"), grain_before + 2)
	assert_eq(economy.treasury, treasury_before - 2 * _screen.economy.market.price("grain"))
	assert_eq(_screen.treasury, economy.treasury)


func test_selling_needs_stock() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 1
	var treasury_before: int = economy.treasury
	_screen.economy._on_trade("timber", 1, false)
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(economy.treasury, treasury_before + _screen.economy.market.price("timber"))


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
	_screen.economy._on_recruit(WorkerPool.Tier.PEASANT)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), before + 1)
	assert_eq(economy.quantity("fabric"), 0)


func test_ending_the_turn_resolves_the_economy() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var before: Dictionary = economy.stockpile.duplicate()
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.turn, turn_before + 1)
	assert_eq(_screen.treasury, economy.treasury)
	assert_true(economy.stockpile != before)
	assert_gt(economy.total_units(), 0)
