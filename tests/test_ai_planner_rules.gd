extends GdToolsTest
## One boot for the rival planners: cargo, market, merchant, army reinforcement
## and the civilian work planners (wiki: civilian-units; docs/ai.md).

## Merged from test_ai_cargo, test_ai_market, test_ai_merchant,
## test_ai_army_reinforce, test_ai_builder_work, test_ai_engineer_work,
## test_ai_hospital_work, test_ai_town_roads, test_ai_civilian_dispatch.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const Fixture = preload("res://tests/civilian_fixture.gd")
const AiFixture = preload("res://tests/ai_fixture.gd")
const ai_engineer_work_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const Engineer = preload("res://scripts/ai/ai_engineer_work.gd")
const ai_civilian_dispatch_CivilianFixture = preload("res://tests/civilian_fixture.gd")
const Planner = preload("res://scripts/ai/ai_civilian_planner.gd")

const OWNER: int = 1
const CONFIG_FACTION: int = 1
const GRAIN: Vector2i = Vector2i(3, 1)
const IRON: Vector2i = Vector2i(2, 1)
const AWAY: Vector2i = Vector2i(1, 1)
const MINOR: int = 6
const ai_army_reinforce_OWNER: int = 2
const HUMAN: int = 1
const ai_builder_work_TOWN: Vector2i = Vector2i(0, 0)
const TIMBER: Vector2i = Vector2i(1, 0)
const TIMBER_FAR: Vector2i = Vector2i(2, 0)
const SEAT: Vector2i = Vector2i(0, 0)
const SEAT_ESTATE: Vector2i = Vector2i(1, 0)
const SEAT_ESTATE_FAR: Vector2i = Vector2i(2, 0)
const ai_engineer_work_BARE: Vector2i = Vector2i(0, 0)
const ai_hospital_work_CAPITAL: Vector2i = Vector2i(0, 1)
const OUTER_TOWN: Vector2i = Vector2i(4, 1)
const CAPITAL_PROVINCE: int = 0
const OUTER_PROVINCE: int = 1
const TECH: Dictionary = {
	"organised_regiments": true,
	"modern_military_funding": true,
}
const ai_town_roads_CAPITAL: Vector2i = Vector2i(0, 1)
const ai_town_roads_TOWN: Vector2i = Vector2i(4, 1)
const ai_civilian_dispatch_BARE: Vector2i = Vector2i(0, 0)
const RAIL_TECHS: Dictionary = {"early_steam_engine": true}

# --- test_ai_cargo ---

func _old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0 if x < 4 else 1
			if x < 4:
				tiles.append(tile)
	for x in 5:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
	var province := ProvinceState.create(
		0, "Seat", tiles, Vector2(2.0, 0.5), tiles.size(), OWNER, true
	)
	province.capital_tile = Vector2i(0, 0)
	province.port_tile = Vector2i(0, 1)
	province.coastal = true
	var harbour: Array[Vector2i] = [Vector2i(4, 0), Vector2i(4, 1)]
	var outport := ProvinceState.create(
		1, "Outport", harbour, Vector2(4.0, 0.5), harbour.size(), OWNER, false
	)
	outport.port_tile = Vector2i(4, 1)
	outport.coastal = true
	model.provinces = [province, outport]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model

func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)

func _economy(treasury: int = 2500) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy

func _merchant(fleet_id: int, type_id: String = "carrack") -> FleetState:
	var hull_id: String = "hull_%d" % fleet_id
	return FleetState.at_sea(fleet_id, OWNER, 0, [hull_id], {hull_id: type_id})

func test_an_idle_merchant_squadron_is_walked_home_and_docks() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(1)
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1, "one idle merchant squadron is ordered home")
	assert_true(bool(routes[0]["dock"]), "the seat's harbour borders the zone")
	var moved: Dictionary = AiCargoPlanner.apply_route(model, fleet, routes[0])
	assert_true(bool(moved["ok"]))
	assert_true(fleet.is_in_port())
	assert_eq(fleet.province, 0, "it berths at the crown's seat")
	assert_eq(int(plan["holds"]), 0, "the holds did not count afloat")
	assert_eq(int(plan["projected"]), 3, "the projected berths count its cargo")

func test_a_warship_is_never_a_cargo_route() -> void:
	var model: MapModel = _old_world()
	var sloop := FleetState.at_sea(2, OWNER, 0, ["hull_2"], {"hull_2": "sloop"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [sloop], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty(), "no purse for a hull yet")

func test_a_merchant_in_another_port_puts_to_sea_toward_the_seat() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1)
	assert_true(not bool(routes[0]["dock"]), "the outport is not the seat")
	assert_eq(int(routes[0]["zone"]), 0, "it puts to sea into the seat's water")

func test_hostile_water_holds_a_merchant_in_port() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5, {0: true}
	)
	assert_true((plan["routes"] as Array).is_empty(), "it waits for safer water")

func test_berths_at_the_seat_already_cover_the_need() -> void:
	var model: MapModel = _old_world()
	var fluyte := FleetState.in_port(3, OWNER, 0, ["hull_3"], {"hull_3": "fluyte"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(20000), model, [fluyte], 0, 4
	)
	assert_eq(int(plan["holds"]), 4, "a fluyte's four holds are home cargo")
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty())

func test_a_shortfall_that_pays_lays_down_a_merchant_hull() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(20000), model, [], 0, 10
	)
	var launch: Dictionary = plan["launch"]
	assert_eq(String(launch.get("kind", "")), "launch")
	assert_eq(String(launch.get("type_id", "")), "carrack", "the only buildable hull")
	assert_eq(int(launch.get("cargo", 0)), 3)

func test_the_better_merchant_wins_on_cargo_then_price() -> void:
	var model: MapModel = _old_world()
	var economy: PlayerEconomy = _economy(20000)
	economy.tech_unlocked["superior_hull_design"] = true
	var plan: Dictionary = AiCargoPlanner.plan(_config(), economy, model, [], 0, 10)
	assert_eq(
		String(plan["launch"].get("type_id", "")), "fluyte",
		"four holds for less money beats three"
	)

func test_the_purse_floor_keeps_the_yard_shut() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(9000), model, [], 0, 10
	)
	assert_true((plan["launch"] as Dictionary).is_empty(), "£1,000 left is not enough")

func test_a_squadron_carrying_an_expedition_keeps_its_course() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(4)
	fleet.embarked_army = 7
	var plan: Dictionary = AiCargoPlanner.plan(
		_config(), _economy(), model, [fleet], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())

func test_missing_inputs_make_the_plan_empty() -> void:
	var model: MapModel = _old_world()
	assert_true((AiCargoPlanner.plan(null, _economy(), model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_config(), null, model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_config(), _economy(), null, [], 0, 5)["routes"] as Array).is_empty())
	assert_true(not bool(AiCargoPlanner.apply_route(model, null, {})["ok"]))

func _session(model: MapModel, fleets: Array[FleetState]) -> Dictionary:
	var play := PlaySession.new()
	play.map_seed = 1
	play.player_faction = 0
	var world := WorldMap.new()
	world.add_region(model)
	play.world = world
	var ships := ShipLayer.new()
	ships.player_faction = 0
	ships.regions.set_region(model.region_id, fleets)
	play.ship_layer = ships
	return {"play": play, "ships": ships, "model": model}

func test_the_adapter_docks_a_rival_squadron_and_its_holds_count() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant(1)
	var built: Dictionary = _session(model, [fleet])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _economy()
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_in_port())
	assert_eq(
		TradeCargo.capacity(play.world, play.ship_layer.regions.snapshot(), OWNER),
		3, "the docked hull's three holds now count"
	)
	(built["ships"] as Node).free()

func test_the_adapter_puts_a_merchant_to_sea_for_the_crossing() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var built: Dictionary = _session(model, [fleet])
	var play: PlaySession = built["play"]
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _economy(), {"used": 0, "left_total": 2}
	)
	assert_eq((report["routes"] as Array).size(), 1)
	assert_true(fleet.is_at_sea(), "the outport merchant puts to sea")
	assert_eq(fleet.sea_zone, 0)
	(built["ships"] as Node).free()

func test_the_adapter_keeps_a_merchant_out_of_hostile_water() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var player := FleetState.at_sea(9, 0, 0, ["hull_9"], {"hull_9": "carrack"})
	var built: Dictionary = _session(model, [fleet, player])
	var play: PlaySession = built["play"]
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(OWNER, 0, 1)
	assert_true(bool(DiplomacyRules.declare_war(state, OWNER, 0)["ok"]))
	play.diplomacy = state
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, _economy(), {"used": 0, "left_total": 2}
	)
	assert_true((report["routes"] as Array).is_empty())
	assert_true(fleet.is_in_port(), "the merchant never enters the hostile zone")
	(built["ships"] as Node).free()

func test_the_adapter_founds_a_slip_when_no_squadron_is_in_port() -> void:
	var model: MapModel = _old_world()
	var built: Dictionary = _session(model, [])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _economy(20000)
	var report: Dictionary = MapPlayCargoAi.run(
		play, OWNER, economy, {"used": 0, "left_total": 8}
	)
	var launch: Dictionary = report["launch"]
	assert_eq(String(launch.get("type_id", "")), "carrack")
	assert_true(bool(launch.get("founded", false)), "the yard founds the home squadron")
	var roster: Array = play.ship_layer.regions.value(model.region_id, [])
	assert_eq(roster.size(), 1)
	var fleet: FleetState = roster[0]
	assert_true(fleet.is_in_port() and fleet.province == 0)
	assert_eq(economy.treasury, 12000, "the yard took its published price")
	(built["ships"] as Node).free()

# --- test_ai_market ---

func _ai_market_config() -> AiConfig:
	return AiConfig.build(CONFIG_FACTION, 1500)

func _ai_market_economy(stock: Dictionary, treasury: int = 5000) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.stockpile = stock.duplicate()
	return economy

func test_a_court_sells_surplus_above_the_reserve() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 0)
	var offers: Array = plan["offers"]
	assert_eq(offers.size(), 1)
	assert_eq(String(offers[0]["commodity"]), "grain")
	assert_eq(int(offers[0]["quantity"]), 10, "market.max_offer_units caps the lot")
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 1)
	assert_eq((result["bought"] as Array).size(), 0, "no holds means no imports")
	assert_eq(economy.quantity("grain"), 90)
	assert_true(economy.treasury > 5000)

func test_production_inputs_are_never_sold_under_the_court() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"lumber": 30, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 0, {}, {"lumber": 20}
	)
	for raw: Variant in plan["offers"]:
		var offer: Dictionary = raw
		assert_ne(String(offer["commodity"]), "lumber")

func test_bids_short_build_inputs_with_free_holds_and_the_purse() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	var bids: Array = plan["bids"]
	assert_eq(bids.size(), 3, "baseline bid-type cap")
	for raw: Variant in bids:
		var bid: Dictionary = raw
		assert_true(int(bid["quantity"]) <= 5)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["bought"] as Array).size(), 3)
	assert_true(economy.quantity("bronze") > 0)

func test_no_bid_can_break_the_minimum_treasury() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"lumber": 0, "castIron": 0}, 520)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	var spend: int = 0
	for raw: Variant in plan["bids"]:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
	assert_true(spend <= 20, "only the £20 above the floor may be bid")
	assert_true(economy.treasury - spend >= 500 - 1)

func test_trade_fairs_raise_the_bid_type_cap_to_six() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		100000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, market, 100, {"trade_fairs": true}
	)
	assert_eq((plan["bids"] as Array).size(), 6)

func test_a_buyer_spends_only_its_own_holds() -> void:
	var economy: PlayerEconomy = _ai_market_economy({}, 5000)
	var market := WorldMarket.with_default_prices()
	assert_true(bool(market.buy(economy, "grain", 2, 1)["ok"]))
	assert_eq(market.bought_units_for(1), 2)
	assert_eq(market.bought_units_for(0), 0)
	assert_eq(market.bought_units(), 2, "the price book still sees the tonnage")
	assert_true(bool(market.buy(economy, "grain", 1)["ok"]))
	assert_eq(market.bought_units_for(0), 1)
	assert_eq(TradeCargo.used(market, 1), 2)
	assert_eq(TradeCargo.used(market, 0), 1)
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	assert_eq(restored.bought_units_for(1), 2)
	assert_eq(restored.bought_units_for(0), 1)

func test_missing_inputs_make_the_plan_empty_ai_market() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	assert_true((AiMarketPlanner.plan(null, economy, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_ai_market_config(), null, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_ai_market_config(), economy, null, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.apply(null, null, {})["sold"] as Array).is_empty())

func test_offers_stop_at_the_type_cap() -> void:
	var economy: PlayerEconomy = _ai_market_economy({
		"grain": 100, "timber": 100, "iron": 100, "wool": 100,
	})
	var plan: Dictionary = AiMarketPlanner.plan(
		_ai_market_config(), economy, WorldMarket.with_default_prices(), 0
	)
	assert_eq((plan["offers"] as Array).size(), 3)

func test_a_refused_trade_is_reported_not_swallowed() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 0}, 0)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "lumber", "quantity": 5, "unit_price": 60}],
	}
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["sold"] as Array).size(), 0)
	assert_eq((result["bought"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)

func test_price_falls_back_to_the_catalog_and_zero_sales_are_refused() -> void:
	var market := WorldMarket.with_default_prices()
	market.prices.erase("grain")
	assert_eq(market.price("grain"), CommodityCatalog.base_price("grain"))
	var economy: PlayerEconomy = _ai_market_economy({"grain": 4})
	assert_false(bool(market.sell(economy, "grain", 0)["ok"]))

func test_a_legacy_book_attributes_bids_to_the_player() -> void:
	var market: WorldMarket = WorldMarket.from_dict({"bids": {"grain": 3}})
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 0)
	var economy: PlayerEconomy = _ai_market_economy({}, 5000)
	assert_true(bool(market.buy(economy, "grain", 1, 1)["ok"]))
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 1)

func test_a_plan_stages_orders_for_the_turn_end_auction() -> void:
	var economy: PlayerEconomy = _ai_market_economy(
		{"grain": 100, "lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_ai_market_config(), economy, market, 20)
	plan["free_holds"] = 20
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, CONFIG_FACTION, {}
	)
	assert_eq((result["refused"] as Array).size(), 0)
	assert_gt((result["staged"] as Array).size(), 0)
	assert_eq(economy.quantity("grain"), 100, "nothing moves before the clearing")
	assert_gt(market.book.pending_buy_units(CONFIG_FACTION), 0)
	var cleared: Dictionary = MarketClearing.clear(
		market, WorldMap.new(), {CONFIG_FACTION: economy}, {CONFIG_FACTION: 20}
	)
	assert_gt((cleared["deals"] as Array).size(), 0)
	assert_gt(economy.total_units(), 100)

func test_a_stage_refuses_what_the_book_cannot_cover() -> void:
	var economy: PlayerEconomy = _ai_market_economy({"grain": 0}, 10)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = {
		"free_holds": 0,
		"offers": [{"commodity": "grain", "quantity": 5}],
		"bids": [{"commodity": "timber", "quantity": 5}],
	}
	var result: Dictionary = AiMarketPlanner.stage(
		economy, market, plan, CONFIG_FACTION, {}
	)
	assert_eq((result["staged"] as Array).size(), 0)
	assert_eq((result["refused"] as Array).size(), 2)

# --- test_ai_merchant ---

func test_a_merchant_on_a_genoese_grain_tile_signs_the_deed() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _ai_merchant_merchant(GRAIN)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "purchase_land")
	assert_eq(Vector2i(plan["orders"][0]["tile"]), GRAIN)
	assert_true((plan["moves"] as Array).is_empty(), "standing on the tile, it works")

func test_a_merchant_away_from_the_offer_walks_toward_it() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _ai_merchant_merchant(AWAY)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "the tile is out of reach")
	var moves: Array = plan["moves"]
	assert_eq(moves.size(), 1)
	var move_tile: Vector2i = moves[0]["tile"]
	assert_eq(move_tile, IRON, "one step into the Minor's land")

func test_without_an_embassy_the_merchant_stays_home() -> void:
	var model: MapModel = Fixture.build_minor()
	var court := DiplomacyState.new()
	court.initialize(1)
	court.ensure_relation(0, MINOR, 1)
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_a_war_with_the_seller_closes_the_market() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var court: DiplomacyState = Fixture.merchant_court()
	assert_true(
		bool(DiplomacyRules.declare_war(court, 0, MINOR, true, world).get("ok", false))
	)
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_a_deeded_tile_is_offered_to_nobody_again() -> void:
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(GRAIN, 1), "a rival's deed")
	var plan: Dictionary = _ai_merchant_plan(model, [_ai_merchant_merchant(GRAIN)])

	assert_true((plan["orders"] as Array).is_empty())
	assert_true(
		(plan["moves"] as Array).is_empty(),
		"the only other offer needs a prospect, so the merchant idles"
	)

func test_a_mineral_waits_for_the_explorers_prospect() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _ai_merchant_merchant(IRON)
	var plan: Dictionary = _ai_merchant_plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "iron is not prospected yet")
	var move_tile: Vector2i = (plan["moves"] as Array)[0]["tile"]
	assert_eq(move_tile, GRAIN, "the grain deed wins")

	works.set_prospected(0, model, IRON)
	var ready: Dictionary = _ai_merchant_plan(model, [merchant], null, works)
	assert_eq((ready["orders"] as Array).size(), 1)
	assert_eq(Vector2i(ready["orders"][0]["tile"]), IRON)

func test_a_court_with_a_deed_on_offer_trains_one_merchant() -> void:
	var model: MapModel = Fixture.build_minor()
	var roster: Array = _staffed_roster()
	var context: Dictionary = _ai_merchant_context(model, Fixture.merchant_court())
	var plan: Dictionary = _ai_merchant_plan(model, roster, Fixture.merchant_court(), null, context)

	assert_true(bool(plan["training"].get("ok", false)))
	assert_eq(String(plan["training"]["type_id"]), "merchant")

	var techless: Dictionary = _ai_merchant_context(model, Fixture.merchant_court())
	techless["tech_unlocked"] = {}
	var plain: Dictionary = _ai_merchant_plan(model, roster, Fixture.merchant_court(), null, techless)
	assert_eq(String(plain["training"]["type_id"]), "builder", "no merchant companies")

func test_one_merchant_is_enough() -> void:
	var model: MapModel = Fixture.build_minor()
	var roster: Array = [
		CivilianState.create(1, 0, "builder", Vector2i(0, 0)),
		CivilianState.create(3, 0, "engineer", Vector2i(0, 1)),
		CivilianState.create(4, 0, "explorer", Vector2i(1, 1)),
		CivilianState.create(5, 0, "spy", Vector2i(0, 2)),
		CivilianState.create(9, 0, "merchant", Vector2i(0, 2)),
	]
	var plan: Dictionary = _ai_merchant_plan(model, roster)

	assert_eq(String(plan["training"]["type_id"]), "builder")

## The Build/Work pass answers each owner with its own ledger: the rival's deed
## debits the rival, and the human crown's purse is untouched (wiki:
## civilian-units § Merchant — "debit at completion").
func test_a_rivals_deed_is_charged_to_the_rival_ledger() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", GRAIN)
	var court: DiplomacyState = Fixture.merchant_court()
	court.ensure_relation(1, MINOR, 1)
	court.set_overture(1, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": court}
	var check: Dictionary = CivilianWork.assign(
		model, merchant, "purchase_land", layer.works, units, Fixture.stockpile(),
		null, GRAIN, {}, {}, context
	)
	assert_true(bool(check.get("ok", false)), String(check.get("reason", "")))

	var human: PlayerEconomy = _ledger(5000)
	var rival: PlayerEconomy = _ledger(5000)
	var reports: Array[Dictionary] = CivilianTurnPass.resolve(
		layer, world, null, {0: human, 1: rival}
	)
	assert_true(bool(reports[0]["completed"]))
	assert_eq(rival.treasury, 4250, "the rival paid the price")
	assert_eq(human.treasury, 5000, "the human purse is untouched")
	assert_true(model.is_purchased_tile(GRAIN))
	assert_eq(model.owner_at(GRAIN.x, GRAIN.y), 1)
	layer.free()

## A deed is never recorded without a purse to close it (wiki: § Merchant —
## the price is debited when the work completes).
func test_a_deed_without_a_ledger_is_not_signed() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _ai_merchant_merchant(GRAIN)
	var units: Array[CivilianState] = [merchant]
	var context: Dictionary = {"treasury": 5000, "diplomacy": Fixture.merchant_court()}
	assert_true(bool(CivilianWork.assign(
		model, merchant, "purchase_land", works, units, Fixture.stockpile(), null,
		GRAIN, {}, {}, context
	).get("ok", false)))

	var reports: Array[Dictionary] = CivilianWork.resolve_turn(model, units, works)
	assert_true(bool(reports[0]["completed"]))
	assert_false(model.is_purchased_tile(GRAIN), "no ledger, no deed")
	assert_false(LandPurchase.complete(model, GRAIN, 0, null))

## A court that could sign a deed wants the envoy chain: the Consulate outranks
## the small peaceful orders it competes with (wiki: civilian-units § Merchant;
## docs/ai.md — land purchase needs the envoy first).
func test_a_deed_on_offer_makes_the_consulate_worth_more() -> void:
	var model: MapModel = Fixture.build_minor()
	var world := WorldMap.new()
	world.add_region(model)
	var state := DiplomacyState.new()
	state.initialize(1)
	var config: AiConfig = AiConfig.build(0, 1500)
	config.personality = AiPersonality.NEUTRAL
	config.agenda_traits = AiAgenda.NEUTRAL

	var plain: Dictionary = _overture(world, state, config, {})
	var merchant_tech: Dictionary = _overture(world, state, config, {
		"merchant_companies": true,
	})
	assert_true(bool(plain.get("ok", false)), "the Consulate is legal either way")
	assert_true(bool(merchant_tech.get("ok", false)))
	assert_eq(
		int(merchant_tech["utility"]) - int(plain["utility"]),
		AiDiplomacyOffers.LAND_ENVOY_BONUS,
		"a deed worth buying lifts the envoy"
	)
	assert_eq(String(merchant_tech["stage"]), DiplomacyCatalog.STAGE_CONSULATE)

## The whole rival pass: the economy adapter musters the order for a court that
## already holds the embassy and the tech, and the next Build/Work signs it from
## that court's own purse (wiki: civilian-units § Merchant; docs/ai.md).
func test_the_rival_turn_signs_the_deed_for_its_own_crown() -> void:
	var model: MapModel = Fixture.build_minor()
	model.provinces[0].owner = 1
	model.faction_ids.append(1)
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var merchant: CivilianState = layer.add_unit(1, "merchant", GRAIN)
	# `spawn(place_units=false)` prepares the works only; the adapter walks the
	# region table, so the roster must be registered like a mustered crew.
	layer.regions.set_region(model.region_id, layer.units)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.civilian_layer = layer
	play.map_seed = 1500
	play.ai = AiState.new()
	play.diplomacy = Fixture.merchant_court()
	play.diplomacy.ensure_relation(1, MINOR, 1)
	play.diplomacy.set_overture(1, MINOR, DiplomacyCatalog.STAGE_EMBASSY)
	var ledger: PlayerEconomy = play.ai.economy_for(1)
	ledger.tech_unlocked["merchant_companies"] = true
	ledger.treasury = 5000

	MapPlayEconomyAi.run(play)
	assert_true(merchant.is_working(), "the rival turn musters the purchase")
	assert_eq(merchant.work_action(), "purchase_land")
	assert_eq(merchant.work_tile(), GRAIN)

	var purse: int = ledger.treasury
	CivilianTurnPass.resolve(layer, world, null, {1: ledger})
	assert_true(model.is_purchased_tile(GRAIN), "the deed is signed next turn")
	assert_eq(ledger.treasury, purse - 750, "the buyer's own purse paid")

## Only a Merchant carries the order, and a tile another crew already holds is
## not offered twice (wiki: civilian-units § Per-player tile exclusivity).
func test_only_a_merchant_and_an_unreserved_tile_get_the_order() -> void:
	var model: MapModel = Fixture.build_minor()
	var context: Dictionary = _ai_merchant_context(model, Fixture.merchant_court())
	var builder: CivilianState = CivilianState.create(1, 0, "builder", GRAIN)
	var none: Dictionary = AiMerchantWork.best_candidate(
		AiConfig.build(0, 1500), model, builder, [builder], LandWorks.new(),
		Fixture.stockpile(), {}, {}, context, {}
	)
	assert_true(none.is_empty(), "a builder cannot buy land")
	var merchant: CivilianState = _ai_merchant_merchant(GRAIN)
	var taken: Dictionary = AiMerchantWork.best_candidate(
		AiConfig.build(0, 1500), model, merchant, [merchant], LandWorks.new(),
		Fixture.stockpile(), {}, {}, context, {GRAIN: true}
	)
	assert_true(taken.is_empty(), "another crew already has this tile")

## An empty purse or an unaffordable price leaves nothing on offer, and a deed
## is never a Great Power's to sell (wiki: civilian-units § Merchant).
func test_an_empty_purse_and_a_great_power_land_offer_nothing() -> void:
	var model: MapModel = Fixture.build_minor()
	var court: DiplomacyState = Fixture.merchant_court()
	assert_true(
		AiMerchantWork.buyable_tiles(model, 0, LandWorks.new(), {
			"treasury": 0, "diplomacy": court,
		}).is_empty(),
		"no treasury, no offer"
	)
	var gp: MapModel = Fixture.build()
	var gp_court := DiplomacyState.new()
	gp_court.initialize(1)
	gp_court.ensure_relation(0, 1, 1)
	gp_court.set_overture(0, 1, DiplomacyCatalog.STAGE_EMBASSY)
	assert_true(
		AiMerchantWork.buyable_tiles(gp, 0, LandWorks.new(), {
			"treasury": 5000, "diplomacy": gp_court,
		}).is_empty(),
		"only Minor Nations and Tribes sell land"
	)
	assert_eq(AiMerchantWork.cheapest_offer(gp, 0, 1, 5000), 0)
	assert_true(AiMerchantWork.best_move(gp, _ai_merchant_merchant(GRAIN), LandWorks.new()).is_empty())

func _ai_merchant_merchant(tile: Vector2i, owner: int = 0) -> CivilianState:
	return CivilianState.create(1, owner, "merchant", tile)

func _ledger(treasury: int) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy

## Two builders, an engineer, an explorer and a spy: every earlier training slot
## is filled, so the merchant is the next craft the court would want.
func _staffed_roster() -> Array:
	return [
		CivilianState.create(1, 0, "builder", Vector2i(0, 0)),
		CivilianState.create(2, 0, "builder", Vector2i(1, 0)),
		CivilianState.create(3, 0, "engineer", Vector2i(0, 1)),
		CivilianState.create(4, 0, "explorer", Vector2i(1, 1)),
		CivilianState.create(5, 0, "spy", Vector2i(0, 2)),
	]

func _ai_merchant_context(
	model: MapModel, court: DiplomacyState, treasury: int = 5000
) -> Dictionary:
	return {
		"treasury": treasury,
		"paper": 8,
		"capital_province": 0,
		"capital_tile": Vector2i(0, 0),
		"at_war": false,
		"diplomacy": court,
		"tech_unlocked": {"merchant_companies": true},
		"visibility": Fixture.visibility(model),
	}

func _ai_merchant_plan(
	model: MapModel,
	units: Array,
	court: DiplomacyState = null,
	works: LandWorks = null,
	context: Dictionary = {}
) -> Dictionary:
	var diplomacy: DiplomacyState = court if court != null else Fixture.merchant_court()
	return AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, units, works if works != null else LandWorks.new(),
		Fixture.stockpile(), {}, {"merchant_companies": true},
		context if not context.is_empty() else _ai_merchant_context(model, diplomacy)
	)

func _overture(
	world: WorldMap, state: DiplomacyState, config: AiConfig, tech: Dictionary
) -> Dictionary:
	var context: Dictionary = {
		"treasury": {config.faction: 5000},
		"tech": {config.faction: tech},
		"player": -1,
	}
	var entries: Array[Dictionary] = AiDiplomacyOffers.candidates(
		config, state, AiState.new(), world, 1, MINOR, 50, context
	)
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == AiDiplomacyOffers.KIND_OVERTURE:
			return entry
	return {}

# --- test_ai_army_reinforce ---

func _ai_army_reinforce_config() -> AiConfig:
	return AiConfig.build(ai_army_reinforce_OWNER, 1500)

## A court with its own ledger: treasury and the opening stock of fabric and
## cast iron the line rows need.
func _ai_army_reinforce_economy(treasury: int = 12000, peasants: int = 6) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.workers = WorkerPool.make(peasants)
	return economy

func test_a_rival_musters_the_strongest_line_it_can_pay_for() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(), 5, false)

	assert_eq(String(plan["muster"]), "arquebusiers", "the strongest era-1 line")
	var candidates: Array = plan["candidates"]
	assert_true(candidates.size() > 0)
	assert_eq(String(candidates[0]["type_id"]), "arquebusiers")
	for entry: Dictionary in candidates:
		assert_true(
			RegimentCatalog.category(String(entry["type_id"]))
			in AiArmyReinforce.LINE_CATEGORIES,
			"a mustered regiment is a line regiment"
		)

func test_the_war_chest_keeps_the_court_from_overspending() -> void:
	# 4,000 ducats covers a pike, but that would empty the purse; the 2,000 levy
	# is the only line that leaves the court's thousand-ducat floor in the bank.
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(4000), 5, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(1500), 5, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))

func test_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var peace: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(), 8, false)
	assert_eq(String(peace["muster"]), "", "eight regiments is the peace target")
	assert_eq(int(peace["target"]), 8)

	var war: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(), 8, true)
	assert_eq(int(war["target"]), 12, "the war footing raises the target by four")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(), 12, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")

func test_a_thin_labour_pool_stops_the_muster() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), _ai_army_reinforce_economy(12000, 3), 5, false)

	assert_eq(String(plan["muster"]), "", "the fields keep their hands")
	assert_true((plan["reasons"] as Array).has("labour floor"))

func test_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _ai_army_reinforce_economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_ai_army_reinforce_config(), economy, 5, false)

	assert_eq(String(plan["muster"]), "musketeers", "the newest legal line wins")

## One peace-time world: England's seat at province 0, France's at province 1,
## with a rival ledger already resolved for France. `extra` appends the caller's
## field armies to the region roster.
func _play(
	treasury: int = 12000, with_ledger: bool = true, extra: Array[ArmyState] = []
) -> PlaySession:
	var world: WorldMap = AiFixture.land_world([HUMAN, ai_army_reinforce_OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(
			2, ai_army_reinforce_OWNER, 1, true, ["peasant_levies", "peasant_levies"] as Array[String], 101
		),
	]
	armies.append_array(extra)
	var layer := ArmyLayer.new()
	layer.model = model
	layer.next_army = 100
	layer.next_regiment = 1000
	layer.regions.set_region(0, armies)
	var play := PlaySession.new()
	play.player_faction = HUMAN
	play.world = world
	play.model = model
	var court := DiplomacyState.new()
	court.reset(HUMAN)
	court.ensure_relation(HUMAN, ai_army_reinforce_OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	if with_ledger:
		play.ai = AiState.new()
		play.ai.economies[ai_army_reinforce_OWNER] = _ai_army_reinforce_economy(treasury)
	return play

func test_the_map_pass_musters_a_rival_from_its_own_ledger() -> void:
	var play: PlaySession = _play(12000)
	var economy: PlayerEconomy = play.ai.economies[ai_army_reinforce_OWNER]
	var before: int = play.army_layer.regiment_count_all(ai_army_reinforce_OWNER)
	var peasants: int = economy.available_peasants()

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "a muster and nothing else in peace")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_REINFORCE)
	assert_eq(String(trace[0]["type"]), "arquebusiers")
	assert_eq(play.army_layer.regiment_count_all(ai_army_reinforce_OWNER), before + 1)
	assert_eq(economy.available_peasants(), peasants - 1, "one peasant joins the colours")
	assert_true(
		economy.treasury < 12000, "the court's own purse pays, never the crown's"
	)
	var home: ArmyState = ArmyTraining.home_army(play.army_layer.armies, ai_army_reinforce_OWNER)
	assert_not_null(home)
	assert_true(
		home.regiments.has(String(trace[0]["regiment"])),
		"the new regiment wears France's colours in the Home Army"
	)
	play.army_layer.free()

func test_the_human_crown_is_never_mustered_for() -> void:
	var play: PlaySession = _play(12000)
	var before: int = play.army_layer.regiment_count_all(HUMAN)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(play.army_layer.regiment_count_all(HUMAN), before)
	for record: Dictionary in trace:
		assert_eq(int(record["faction"]), ai_army_reinforce_OWNER, "the crown musters its own men")
	play.army_layer.free()

func test_a_court_without_a_ledger_never_musters() -> void:
	var play: PlaySession = _play(12000, false)
	var before: int = play.army_layer.regiment_count_all(ai_army_reinforce_OWNER)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 0, "no ledger, no muster")
	assert_eq(play.army_layer.regiment_count_all(ai_army_reinforce_OWNER), before)
	play.army_layer.free()

func test_the_observer_log_reads_the_muster() -> void:
	var play: PlaySession = _play(12000)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][ai_army_reinforce_OWNER]
	assert_eq(int(record["actions"].get("reinforce", 0)), 1, "one regiment raised")
	var lines: Array = record["events"]
	assert_true(lines.size() > 0, "the event list names the pattern")
	play.army_layer.free()

# --- test_ai_hospital_train_work ---

## France's ledger at war: enough lumber and cloth for a train and a yard's work
## behind it, Organised Regiments, and three peasants — so the fields keep their
## hands and the muster stays silent in these tests.
func _train_economy(lumber: int = 40, fabric: int = 12, tech: bool = true) -> PlayerEconomy:
	var economy: PlayerEconomy = _ai_army_reinforce_economy()
	economy.stockpile["lumber"] = lumber
	economy.stockpile["fabric"] = fabric
	economy.workers = WorkerPool.make(3)
	if tech:
		economy.tech_unlocked["organised_regiments"] = true
	return economy


## A worn field army of France's standing on France's own ground, and a war on.
## `extra` adds more field armies for the one-train-a-turn case.
func _train_play(
	worn_health: int = 12, war: bool = true, extra: Array[ArmyState] = []
) -> PlaySession:
	var field := ArmyState.muster(
		3, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 201
	)
	for regiment_id: String in field.regiments:
		field.regiment_health[regiment_id] = worn_health
	## It has marched already, so the turn's trace carries the surgeons alone.
	field.moved = true
	var armies: Array[ArmyState] = [field]
	armies.append_array(extra)
	var play: PlaySession = _play(12000, true, armies)
	play.ai.economies[ai_army_reinforce_OWNER] = _train_economy()
	if war:
		DiplomacyRules.declare_war(play.diplomacy, ai_army_reinforce_OWNER, HUMAN)
	return play


func _train_ledger(play: PlaySession) -> PlayerEconomy:
	return play.ai.economies[ai_army_reinforce_OWNER]


func _train_roster(play: PlaySession) -> Array[ArmyState]:
	var roster: Array[ArmyState] = []
	roster.assign(play.army_layer.regions.value(0, []))
	return roster


func _chosen(play: PlaySession, at_war: bool = true) -> ArmyState:
	return AiHospitalTrainWork.best_army(
		play.model, _train_roster(play), ai_army_reinforce_OWNER, _train_ledger(play), at_war
	)


func test_a_worn_field_army_gets_the_rivals_surgeons() -> void:
	var play: PlaySession = _train_play()
	var chosen: ArmyState = _chosen(play)

	assert_not_null(chosen, "a court at war will not leave a mauled host in the field")
	if chosen != null:
		assert_eq(chosen.id, 3, "the field army, not the Home Army at its seat")
		assert_true(
			AiHospitalTrainWork.worn(chosen) < AiHospitalTrainWork.WORN_SHARE,
			"one wound short of a rest is all the policy asks",
		)
	play.army_layer.free()


func test_peace_leaves_the_tents_in_the_wagon() -> void:
	var play: PlaySession = _train_play(12, false)

	assert_true(_chosen(play, false) == null, "nurses eat: no tents are pitched in peace")
	play.army_layer.free()


func test_a_fresh_army_needs_no_surgeon() -> void:
	var play: PlaySession = _train_play(9999)

	assert_true(_chosen(play) == null, "an unwounded host has nothing to mend")
	play.army_layer.free()


func test_a_province_ward_beats_the_train() -> void:
	var play: PlaySession = _train_play()
	for province: ProvinceState in play.model.provinces:
		if province.owner == ai_army_reinforce_OWNER:
			province.hospital_level = HospitalRules.MAX_LEVEL

	assert_true(_chosen(play) == null, "a General hospital already heals better")
	play.army_layer.free()


func test_the_train_waits_for_organised_regiments() -> void:
	var play: PlaySession = _train_play()
	_train_ledger(play).tech_unlocked.erase("organised_regiments")

	assert_true(_chosen(play) == null, "the rule's tech gate is the planner's too")
	play.army_layer.free()


func test_the_yard_keeps_its_timber() -> void:
	var play: PlaySession = _train_play()
	_train_ledger(play).stockpile["lumber"] = 3

	assert_true(_chosen(play) == null, "the price must leave a working stock behind")
	play.army_layer.free()


func test_the_map_pass_pitches_the_rivals_train() -> void:
	var play: PlaySession = _train_play()
	var economy: PlayerEconomy = _train_ledger(play)
	var lumber: int = economy.quantity("lumber")
	var fabric: int = economy.quantity("fabric")

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	var hops: Array[Dictionary] = []
	for record: Dictionary in trace:
		if String(record["kind"]) == MapPlayArmyAi.KIND_HOSPITAL:
			hops.append(record)
	assert_eq(hops.size(), 1, "one train in the turn")
	assert_eq(int(hops[0]["faction"]), ai_army_reinforce_OWNER)
	assert_eq(int(hops[0]["army"]), 3)
	assert_true(
		_field_army(play).field_hospital,
		"the standard carries the tents from now on"
	)
	assert_eq(economy.quantity("lumber"), lumber - 2, "the court's own timber pays")
	assert_eq(economy.quantity("fabric"), fabric - 1)
	play.army_layer.free()


## Two equally worn hosts: the lowest army id carries the tents, so a given
## roster always answers the same way.
func test_a_tie_goes_to_the_lowest_army_id() -> void:
	var twin := ArmyState.muster(
		4, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 301
	)
	for regiment_id: String in twin.regiments:
		twin.regiment_health[regiment_id] = 12
	twin.moved = true
	var play: PlaySession = _train_play(12, true, [twin] as Array[ArmyState])
	var chosen: ArmyState = _chosen(play)

	assert_not_null(chosen)
	if chosen != null:
		assert_eq(chosen.id, 3, "army 3 and army 4 are worn alike; the lower id wins")
	play.army_layer.free()


func test_the_court_brings_one_train_a_turn() -> void:
	var second := ArmyState.muster(
		4, ai_army_reinforce_OWNER, 1, false,
		["peasant_levies", "peasant_levies"] as Array[String], 301
	)
	for regiment_id: String in second.regiments:
		second.regiment_health[regiment_id] = 12
	second.moved = true
	var play: PlaySession = _train_play(12, true, [second] as Array[ArmyState])

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	var trained: int = 0
	for record: Dictionary in trace:
		if String(record["kind"]) == MapPlayArmyAi.KIND_HOSPITAL:
			trained += 1
	assert_eq(trained, 1, "a court equips one train a turn")
	var carrying: int = 0
	for army: ArmyState in _train_roster(play):
		if army != null and army.field_hospital:
			carrying += 1
	assert_eq(carrying, 1)
	play.army_layer.free()


func test_the_observer_log_reads_the_train() -> void:
	var play: PlaySession = _train_play()
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][ai_army_reinforce_OWNER]

	assert_eq(int(record["actions"].get("hospital", 0)), 1, "the train is its own act")
	assert_eq(int(record["actions"].get("march", 0)), 0, "never miscounted as a march")
	var named: bool = false
	for line: Dictionary in merged["events"]:
		if String(line.get("text", "")).contains("field hospital train"):
			named = true
	assert_true(named, "the log names the train and the ground")
	assert_true(
		AiTurnLog.headline(record).contains("field hospitals ×1"),
		"the observer panel headline counts the train",
	)
	play.army_layer.free()


func _field_army(play: PlaySession) -> ArmyState:
	for army: ArmyState in _train_roster(play):
		if army != null and army.id == 3:
			return army
	return null

# --- test_ai_builder_work ---

func _ai_builder_work_model(level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [ai_builder_work_TOWN, TIMBER, TIMBER_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Plantation", tiles, Vector2.ZERO, 3, 1)
	province.town_tile = ai_builder_work_TOWN
	province.town_development = level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model

func _ai_builder_work_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_builder_work_TOWN)
	for tile: Vector2i in [TIMBER, TIMBER_FAR]:
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works

func _ai_builder_work_stockpile() -> Dictionary:
	return {"timber": 200, "lumber": 40, "castIron": 40}

func _ai_builder_work_plan(model: MapModel, context: Dictionary = {}) -> Dictionary:
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _ai_builder_work_works(model), _ai_builder_work_stockpile(),
		{"timber": 4}, {"national_bureaucracy": true}, context
	)

## The estates are finished, so the town is the only order left; a level-1 town
## that would pay 4 lumber a turn is worth more than idling the Builder.
func test_a_developing_town_becomes_the_builders_order() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1))
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), ai_builder_work_TOWN)

## An overseas province is priced on the tons the holds landed, not on the far
## shore's harvest: with nothing delivered the town pays nothing and is left.
func test_an_overseas_town_with_nothing_landed_is_left_alone() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1), {"delivered_raw": {}})

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())

func test_an_overseas_town_is_upgraded_from_the_tons_that_landed() -> void:
	var plan: Dictionary = _ai_builder_work_plan(_ai_builder_work_model(1), {"delivered_raw": {0: {"timber": 8}}})
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")

func test_a_finished_town_is_left_alone() -> void:
	assert_true((_ai_builder_work_plan(_ai_builder_work_model(CivilianWorkPlan.MAX_TOWN))["orders"] as Array).is_empty())

func test_the_bureaucracy_gate_still_refuses_the_order() -> void:
	var model: MapModel = _ai_builder_work_model(1)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", TIMBER)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _ai_builder_work_works(model), _ai_builder_work_stockpile(),
		{"timber": 4}, {}, {}
	)

	assert_true((plan["orders"] as Array).is_empty(), "no national_bureaucracy")

func _seat_model(town_level: int, estate_level: int) -> MapModel:
	var model := MapModel.new()
	model.setup(3, 1)
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in [SEAT, SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = 0
		tiles.append(tile)
	var province := ProvinceState.create(0, "Seat", tiles, Vector2.ZERO, 3, 1, true)
	province.town_tile = SEAT
	province.capital_tile = SEAT
	province.town_development = town_level
	model.provinces = [province]
	model.faction_ids.append(1)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		model.resource[model.index_of(tile.x, tile.y)] = 0
	return model

func _seat_works(model: MapModel, estate_level: int) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, SEAT)
	for tile: Vector2i in [SEAT_ESTATE, SEAT_ESTATE_FAR]:
		if estate_level > 0:
			works.set_improvement(model, tile, estate_level)
		works.set_transport(model, tile, LandWorks.TRANSPORT_RAIL)
	return works

func _seat_plan(town_level: int, estate_level: int) -> Dictionary:
	var model: MapModel = _seat_model(town_level, estate_level)
	var builder: CivilianState = CivilianState.create(1, 1, "builder", SEAT_ESTATE)
	return AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [builder], _seat_works(model, estate_level),
		{"timber": 2, "lumber": 40, "castIron": 40}, {"timber": 4},
		{"national_bureaucracy": true}
	)

## Stores are short of timber, but a level-1 estate in a level-1 seat gathers
## nothing more at level 2: the town is the order that pays, so the Builder
## raises the town instead of buying a dead estate level.
func test_a_town_capping_its_estates_is_raised_before_the_estate() -> void:
	var plan: Dictionary = _seat_plan(1, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)

## Once the estate is fully improved the town is the only order left, and it is
## raised even though its manufactures are still short of one four-ton run: the
## estate levels it unlocks are what the Builder is buying.
func test_a_town_is_raised_for_the_estate_levels_it_unlocks() -> void:
	var plan: Dictionary = _seat_plan(1, LandWorks.MAX_IMPROVEMENT)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "upgrade_town")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT)

## A developed town no longer caps its estates, so the Builder raises the estate
## at once — the cap read must not idle a court that can gather.
func test_a_developed_town_frees_the_estate_order() -> void:
	var plan: Dictionary = _seat_plan(CivilianWorkPlan.MAX_TOWN, 1)
	var orders: Array = plan["orders"]

	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_improvement")
	assert_eq(Vector2i(orders[0]["tile"]), SEAT_ESTATE)

## An estate held back by the town cap earns no shortage premium: an estate the
## crown can gather from wins the Builder even when its commodity is abundant.
func test_a_capped_estate_earns_no_shortage_premium() -> void:
	var row: Dictionary = {
		"tile": SEAT_ESTATE, "province": 0, "commodity": "timber", "level": 1,
		"tech_cap": 4, "terrain_cap": 4, "transport": 4, "town_cap": 1,
		"output": 1, "connected": true,
	}
	var open_row: Dictionary = row.duplicate()
	open_row["town_cap"] = 4
	open_row["output"] = 1

	assert_eq(AiBuilderWork.paid_gain(row), 0, "the town cap pays nothing more")
	assert_eq(AiBuilderWork.paid_gain(open_row), 1, "the next level pays")
	assert_eq(AiBuilderWork.town_unlocks([row], 0), 1, "the town unlocks one level")
	assert_eq(AiBuilderWork.town_unlocks([open_row], 0), 0, "a free estate unlocks nothing")

# --- test_ai_engineer_work ---

func _ai_engineer_work_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": ai_engineer_work_CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": ai_engineer_work_BARE,
		"at_war": at_war,
	}

func _engineer_order(model: MapModel, works: LandWorks, at_war: bool = false) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	return Engineer.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		ai_engineer_work_CivilianFixture.stockpile(), {}, {}, _ai_engineer_work_context(at_war), {}
	)

## Every owned tile improved and ported, so the only work left is transport.
func _ai_engineer_work_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_engineer_work_CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	return works

func test_a_road_still_reaches_a_resource_without_one() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var order: Dictionary = _engineer_order(model, _ai_engineer_work_works(model))
	assert_eq(String(order.get("action", "")), "build_road")
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_ne(model.resource_at(tile.x, tile.y), MapModel.NO_ID, "the road reaches a resource")

func test_a_coastal_province_without_a_port_gets_one() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	for tile: Vector2i in model.provinces[0].tiles:
		model.resource[model.index_of(tile.x, tile.y)] = MapModel.NO_ID
	var order: Dictionary = _engineer_order(model, LandWorks.new())
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	assert_eq(String(order.get("action", "")), "build_port")
	assert_true(MapGeo.is_coastal_tile(model, tile.x, tile.y), "a port only rises on the coast")

func test_an_invaded_court_prices_its_fort_with_wartime_urgency() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, ai_engineer_work_CivilianFixture.COAST_TILE)
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	var fort: Dictionary = Engineer.fort_candidate(
		AiConfig.build(0, 1500), model, unit, [unit] as Array, works,
		ai_engineer_work_CivilianFixture.stockpile(), {}, {}, _ai_engineer_work_context(true)
	)
	var road: Dictionary = _engineer_order(model, works)
	assert_eq(String(fort.get("action", "")), "build_fort")
	assert_eq(Vector2i(fort["tile"]), FortRules.site_tile(model, ai_engineer_work_CivilianFixture.PLAYER_PROVINCE))
	# An invaded court prices its fort above its other works as a floor: the fort
	# weight plus the wartime urgency, whatever the hinterland still owes.
	var weight: int = AiConfig.build(0, 1500).parameter("civilian.fort_weight")
	assert_true(int(fort["score"]) >= weight + 50, "the fort carries its wartime urgency")
	assert_eq(String(road.get("action", "")), "build_road")

func test_the_engineer_never_offers_a_rail() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var works: LandWorks = _ai_engineer_work_works(model)
	works.set_transport(model, ai_engineer_work_CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	for at_war: bool in [false, true]:
		var order: Dictionary = _engineer_order(model, works, at_war)
		assert_ne(String(order.get("action", "")), "build_rail", "a rail is the Rail Builder's work")

func test_no_engineer_work_without_a_config() -> void:
	var model: MapModel = ai_engineer_work_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_engineer_work_BARE)
	assert_true(Engineer.best_candidate(
		null, model, unit, [unit] as Array, LandWorks.new(),
		ai_engineer_work_CivilianFixture.stockpile(), {}, {}, _ai_engineer_work_context(), {}
	).is_empty())

# --- test_ai_hospital_work ---

## A capital province with a seat and a second owned town province; no resource
## tiles and no coast, so an Engineer's only other work is the town sweep.
func _ai_hospital_work_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var capital_tiles: Array[Vector2i] = []
	var outer_tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = CAPITAL_PROVINCE
				capital_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = OUTER_PROVINCE
				outer_tiles.append(tile)
	var capital := ProvinceState.create(
		CAPITAL_PROVINCE, "Cádiz", capital_tiles, Vector2(1.0, 1.0),
		capital_tiles.size(), 0, true
	)
	capital.capital_tile = ai_hospital_work_CAPITAL
	capital.town_tile = ai_hospital_work_CAPITAL
	var outer := ProvinceState.create(
		OUTER_PROVINCE, "Coro", outer_tiles, Vector2(4.0, 1.0),
		outer_tiles.size(), 0, false
	)
	outer.town_tile = OUTER_TOWN
	model.provinces = [capital, outer]
	return model

func _ai_hospital_work_stockpile() -> Dictionary:
	return {"lumber": 20, "fabric": 20, "steel": 20, "castIron": 20}

func _ai_hospital_work_context(at_war: bool = true) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CAPITAL_PROVINCE,
		"capital_tile": ai_hospital_work_CAPITAL,
		"at_war": at_war,
	}

func _best(
	model: MapModel, tech_unlocked: Dictionary = TECH, reserved: Dictionary = {}
) -> Dictionary:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	return AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), model, unit, [unit], LandWorks.new(),
		_ai_hospital_work_stockpile(), {}, tech_unlocked, _ai_hospital_work_context(), reserved
	)

func test_the_seat_raises_the_first_hospital() -> void:
	var best: Dictionary = _best(_ai_hospital_work_model())
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_hospital_work_CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("lumber", 0)), 3)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("fabric", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 1, "a field hospital takes one turn")

func test_the_seat_is_upgraded_before_a_new_province() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_hospital_work_CAPITAL)
	assert_eq(int((best.get("cost", {}) as Dictionary).get("steel", 0)), 2)
	assert_eq(int(best.get("duration", 0)), 2, "a general hospital takes two turns")

func test_a_field_hospital_waits_while_its_tech_is_unknown() -> void:
	var best: Dictionary = _best(_ai_hospital_work_model(), {})
	assert_true(best.is_empty(), "Organised Regiments gates the first hospital")

func test_a_general_hospital_waits_for_its_own_tech() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = 1
	var best: Dictionary = _best(model, {"organised_regiments": true})
	assert_eq(String(best.get("action", "")), "build_hospital")
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"the gated upgrade gives way to a field hospital elsewhere"
	)

func test_a_second_province_follows_the_seat() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var best: Dictionary = _best(model)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)

func test_a_reserved_town_waits_its_turn() -> void:
	var model: MapModel = _ai_hospital_work_model()
	var reserved: Dictionary = {ai_hospital_work_CAPITAL: true}
	var best: Dictionary = _best(model, TECH, reserved)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN)

func test_a_built_out_court_raises_no_more() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	assert_true(_best(model).is_empty())

func test_a_townless_province_is_skipped() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	var bare := ProvinceState.create(
		2, "Wilds", [Vector2i(2, 2)] as Array[Vector2i], Vector2(2.0, 2.0),
		1, 0, false
	)
	model.provinces.append(bare)
	var best: Dictionary = _best(model)
	assert_eq(
		Vector2i(best.get("tile", Vector2i(-1, -1))), OUTER_TOWN,
		"only the province with a town can host a hospital"
	)

func test_another_courts_province_is_never_planned() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).hospital_level = HospitalRules.MAX_LEVEL
	model.province_data(OUTER_PROVINCE).owner = 1
	assert_true(_best(model).is_empty())

func test_the_engineer_planner_raises_a_hospital_at_war() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _ai_hospital_work_stockpile(),
		{}, TECH, _ai_hospital_work_context(true)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_hospital")
	assert_eq(Vector2i(orders[0]["tile"]), ai_hospital_work_CAPITAL)

func test_peace_leaves_the_town_sweep_first() -> void:
	var model: MapModel = _ai_hospital_work_model()
	model.province_data(CAPITAL_PROVINCE).fort_level = FortRules.MAX_LEVEL
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(0, 1500), model, [unit], LandWorks.new(), _ai_hospital_work_stockpile(),
		{}, TECH, _ai_hospital_work_context(false)
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")

func test_nothing_is_planned_without_a_world() -> void:
	var unit: CivilianState = CivilianState.create(1, 0, "engineer", ai_hospital_work_CAPITAL)
	assert_true(AiHospitalWork.best_candidate(
		AiConfig.build(0, 1500), null, unit, [unit], null, _ai_hospital_work_stockpile(), {},
		TECH, _ai_hospital_work_context(), {}
	).is_empty())

func test_a_fort_always_holds_over_the_town_sweep() -> void:
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_fort"}, _ai_hospital_work_context(false)
	))
	assert_false(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _ai_hospital_work_context(false)
	))
	assert_true(AiHospitalWork.holds_over_town_link(
		{"action": "build_hospital"}, _ai_hospital_work_context(true)
	))
	assert_false(AiHospitalWork.holds_over_town_link({}, _ai_hospital_work_context(true)))

func test_the_tie_break_is_row_major_then_action_name() -> void:
	var upper: Dictionary = {"action": "build_hospital", "tile": Vector2i(1, 2), "score": 40}
	var lower: Dictionary = {"action": "build_hospital", "tile": Vector2i(4, 3), "score": 40}
	var left: Dictionary = {"action": "build_hospital", "tile": Vector2i(2, 3), "score": 40}
	var early: Dictionary = {"action": "build_fort", "tile": Vector2i(1, 2), "score": 40}
	assert_eq(Vector2i(AiHospitalWork._better(lower, upper)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(upper, lower)["tile"]), Vector2i(1, 2))
	assert_eq(Vector2i(AiHospitalWork._better(lower, left)["tile"]), Vector2i(2, 3))
	assert_eq(Vector2i(AiHospitalWork._better(left, lower)["tile"]), Vector2i(2, 3))
	assert_eq(String(AiHospitalWork._better(upper, early)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better(early, upper)["action"]), "build_fort")
	assert_eq(String(AiHospitalWork._better({}, upper)["action"]), "build_hospital")
	assert_eq(String(AiHospitalWork._better(upper, {})["action"]), "build_hospital")

# --- test_ai_town_roads ---

func _ai_town_roads_model() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	var tiles: Array[Vector2i] = []
	for y in 3:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(tile)
	var province := ProvinceState.create(
		0, "Townshire", tiles, Vector2(2.0, 1.0), tiles.size(), 1, true
	)
	province.capital_tile = ai_town_roads_CAPITAL
	province.town_tile = ai_town_roads_TOWN
	model.provinces = [province]
	return model

func _ai_town_roads_stockpile() -> Dictionary:
	return {"lumber": 20, "castIron": 20}

func _connected(model: MapModel, tiles: Array[Vector2i]) -> Dictionary:
	var seen: Dictionary = {}
	for tile: Vector2i in tiles:
		seen[model.index_of(tile.x, tile.y)] = true
	return seen

func test_an_unconnected_town_targets_its_own_tile_first() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _ai_town_roads_stockpile(),
		{}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {}
	)
	assert_eq(String(best.get("action", "")), "build_road")
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), ai_town_roads_TOWN)

func test_the_next_step_follows_the_shortest_owned_path() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	works.set_transport(model, ai_town_roads_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _ai_town_roads_stockpile(),
		{}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {}
	)
	assert_eq(Vector2i(best.get("tile", Vector2i(-1, -1))), Vector2i(3, 1))

func test_a_connected_town_is_left_alone() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var best: Dictionary = AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_ai_town_roads_stockpile(), {}, {}, {},
		_connected(model, [ai_town_roads_CAPITAL, ai_town_roads_TOWN]), {}
	)
	assert_true(best.is_empty())

func test_the_engineer_planner_emits_the_town_road_order() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], works, _ai_town_roads_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		model.resource_at(Vector2i(orders[0]["tile"]).x, Vector2i(orders[0]["tile"]).y),
		MapModel.NO_ID
	)

func test_without_a_capital_network_no_order_is_offered() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_ai_town_roads_stockpile(), {}, {}, {}, {}, {}
	).is_empty())

func test_a_reserved_town_is_left_for_another_crew() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_ai_town_roads_stockpile(), {}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {ai_town_roads_TOWN: true}
	).is_empty())

func test_a_foreign_town_is_ignored() -> void:
	var model: MapModel = _ai_town_roads_model()
	model.provinces[0].owner = 2
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_ai_town_roads_stockpile(), {}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {}
	).is_empty())

func test_missing_inputs_are_guarded() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		null, model, unit, LandWorks.new(), [unit], _ai_town_roads_stockpile(), {}, {}, {},
		_connected(model, [ai_town_roads_CAPITAL]), {}
	).is_empty())

func test_a_reserved_path_tile_is_left_alone() -> void:
	var model: MapModel = _ai_town_roads_model()
	var works := LandWorks.new()
	works.set_transport(model, ai_town_roads_TOWN, LandWorks.TRANSPORT_ROAD)
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, works, [unit], _ai_town_roads_stockpile(),
		{}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {Vector2i(3, 1): true}
	).is_empty())

func test_a_working_engineer_gets_no_second_order() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	unit.start_work("build_road", ai_town_roads_TOWN, 1)
	assert_true(AiTownRoads.best_candidate(
		AiConfig.build(1, 1500), model, unit, LandWorks.new(), [unit],
		_ai_town_roads_stockpile(), {}, {}, {}, _connected(model, [ai_town_roads_CAPITAL]), {}
	).is_empty())

## Wiki: ai-architecture § Town-per-province roads — a town road outranks
## incidental works, so a resource road next to the capital never pre-empts the
## link that lets the Town rule connect the province's estates.
func test_a_town_road_outranks_an_incidental_resource_road() -> void:
	var model: MapModel = _ai_town_roads_model()
	var grain: Vector2i = Vector2i(1, 1)
	model.resource[model.index_of(grain.x, grain.y)] = 4
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(), _ai_town_roads_stockpile(), {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_road")
	assert_eq(
		Vector2i(orders[0]["tile"]), ai_town_roads_TOWN, "the town link comes before an incidental road"
	)

## Wiki: ai-architecture § Town-per-province roads — the court's own fort still
## comes first when it is invaded. The fort stands on the province's own site
## (CivilianWork sites it on the town), so this pins the choice, not the seat.
func test_an_invaded_court_raises_its_fort_before_a_town_road() -> void:
	var model: MapModel = _ai_town_roads_model()
	var unit: CivilianState = CivilianState.create(1, 1, "engineer", ai_town_roads_CAPITAL)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(1, 1500), model, [unit], LandWorks.new(),
		{"lumber": 20, "castIron": 20, "bronze": 20}, {}, {},
		{
			"treasury": 2500,
			"paper": 8,
			"capital_province": 0,
			"capital_tile": ai_town_roads_CAPITAL,
			"at_war": true,
		}
	)
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1)
	assert_eq(String(orders[0]["action"]), "build_fort")
	assert_eq(
		Vector2i(orders[0]["tile"]),
		FortRules.site_tile(model, 0),
		"the fort stands where the rules site it"
	)

# --- test_ai_civilian_dispatch ---

func _ai_civilian_dispatch_context(at_war: bool = false) -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": ai_civilian_dispatch_CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": ai_civilian_dispatch_BARE,
		"at_war": at_war,
	}

func _ai_civilian_dispatch_plan(model: MapModel, unit: CivilianState, works: LandWorks) -> Dictionary:
	return Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, works,
		ai_civilian_dispatch_CivilianFixture.stockpile(), {}, RAIL_TECHS, _ai_civilian_dispatch_context()
	)

func _roaded_works(model: MapModel) -> LandWorks:
	var works := LandWorks.new()
	works.add_port(model, ai_civilian_dispatch_CivilianFixture.COAST_TILE)
	for tile: Vector2i in model.ownership.owned_tiles(model, 0):
		works.set_improvement(model, tile, LandWorks.MAX_IMPROVEMENT)
	works.set_transport(model, ai_civilian_dispatch_CivilianFixture.TIMBER_TILE, LandWorks.TRANSPORT_ROAD)
	return works

func test_a_rail_builder_lays_a_rail_on_an_existing_road() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", ai_civilian_dispatch_CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = _ai_civilian_dispatch_plan(model, unit, _roaded_works(model))
	var orders: Array = plan["orders"]
	assert_eq(orders.size(), 1, "the Engineer policy answers for a Rail Builder")
	assert_eq(String(orders[0]["action"]), "build_rail")
	assert_eq(Vector2i(orders[0]["tile"]), ai_civilian_dispatch_CivilianFixture.TIMBER_TILE)

func test_a_rival_without_steam_never_orders_a_rail() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var unit: CivilianState = CivilianState.create(
		1, 0, "rail_builder", ai_civilian_dispatch_CivilianFixture.TIMBER_TILE
	)
	var plan: Dictionary = Planner.plan(
		AiConfig.build(0, 1500), model, [unit] as Array, _roaded_works(model),
		ai_civilian_dispatch_CivilianFixture.stockpile(), {}, {}, _ai_civilian_dispatch_context()
	)
	for order: Dictionary in plan["orders"]:
		assert_ne(String(order["action"]), "build_rail", "no rail without its tech")

func test_every_dispatched_order_is_a_work_the_unit_may_do() -> void:
	var model: MapModel = ai_civilian_dispatch_CivilianFixture.build()
	var works := LandWorks.new()
	works.add_port(model, ai_civilian_dispatch_CivilianFixture.COAST_TILE)
	for type_id: String in ["builder", "engineer", "explorer", "rail_builder"]:
		var unit: CivilianState = CivilianState.create(1, 0, type_id, ai_civilian_dispatch_BARE)
		for order: Dictionary in _ai_civilian_dispatch_plan(model, unit, works)["orders"]:
			assert_true(
				CivilianCatalog.works(type_id).has(String(order["action"])),
				"%s may work %s" % [type_id, order["action"]]
			)
