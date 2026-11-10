extends GdToolsTest
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
