extends GdToolsTest
## Rival world-market participation (wiki: world-market; docs/ai.md). Sells
## above the reserve and production inputs, bids with free holds, and keeps each
## crown's cargo separate.
## Consolidated rulebook: AiMarket + AiMerchant + AiCargo (one Godot boot per domain).

const CONFIG_FACTION: int = 1


func _config() -> AiConfig:
	return AiConfig.build(CONFIG_FACTION, 1500)


func _economy(stock: Dictionary, treasury: int = 5000) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.stockpile = stock.duplicate()
	return economy


func test_a_court_sells_surplus_above_the_reserve() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 0)
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
	var economy: PlayerEconomy = _economy({"lumber": 30, "grain": 100})
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 0, {}, {"lumber": 20}
	)
	for raw: Variant in plan["offers"]:
		var offer: Dictionary = raw
		assert_ne(String(offer["commodity"]), "lumber")


func test_bids_short_build_inputs_with_free_holds_and_the_purse() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var bids: Array = plan["bids"]
	assert_eq(bids.size(), 3, "baseline bid-type cap")
	for raw: Variant in bids:
		var bid: Dictionary = raw
		assert_true(int(bid["quantity"]) <= 5)
	var result: Dictionary = AiMarketPlanner.apply(economy, market, plan, CONFIG_FACTION)
	assert_eq((result["bought"] as Array).size(), 3)
	assert_true(economy.quantity("bronze") > 0)


func test_no_bid_can_break_the_minimum_treasury() -> void:
	var economy: PlayerEconomy = _economy({"lumber": 0, "castIron": 0}, 520)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
	var spend: int = 0
	for raw: Variant in plan["bids"]:
		var bid: Dictionary = raw
		spend += int(bid["quantity"]) * int(market.price(String(bid["commodity"])))
	assert_true(spend <= 20, "only the £20 above the floor may be bid")
	assert_true(economy.treasury - spend >= 500 - 1)


func test_trade_fairs_raise_the_bid_type_cap_to_six() -> void:
	var economy: PlayerEconomy = _economy(
		{"lumber": 0, "castIron": 0, "fabric": 0, "paper": 0, "steel": 0, "bronze": 0},
		100000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, market, 100, {"trade_fairs": true}
	)
	assert_eq((plan["bids"] as Array).size(), 6)


func test_a_buyer_spends_only_its_own_holds() -> void:
	var economy: PlayerEconomy = _economy({}, 5000)
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


func test_missing_inputs_make_the_plan_empty() -> void:
	var economy: PlayerEconomy = _economy({"grain": 100})
	var market := WorldMarket.with_default_prices()
	assert_true((AiMarketPlanner.plan(null, economy, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), null, market, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.plan(_config(), economy, null, 0)["offers"] as Array).is_empty())
	assert_true((AiMarketPlanner.apply(null, null, {})["sold"] as Array).is_empty())


func test_offers_stop_at_the_type_cap() -> void:
	var economy: PlayerEconomy = _economy({
		"grain": 100, "timber": 100, "iron": 100, "wool": 100,
	})
	var plan: Dictionary = AiMarketPlanner.plan(
		_config(), economy, WorldMarket.with_default_prices(), 0
	)
	assert_eq((plan["offers"] as Array).size(), 3)


func test_a_refused_trade_is_reported_not_swallowed() -> void:
	var economy: PlayerEconomy = _economy({"grain": 0}, 0)
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
	var economy: PlayerEconomy = _economy({"grain": 4})
	assert_false(bool(market.sell(economy, "grain", 0)["ok"]))


func test_a_legacy_book_attributes_bids_to_the_player() -> void:
	var market: WorldMarket = WorldMarket.from_dict({"bids": {"grain": 3}})
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 0)
	var economy: PlayerEconomy = _economy({}, 5000)
	assert_true(bool(market.buy(economy, "grain", 1, 1)["ok"]))
	assert_eq(market.bought_units_for(FactionCatalog.PLAYER_FACTION), 3)
	assert_eq(market.bought_units_for(1), 1)


func test_a_plan_stages_orders_for_the_turn_end_auction() -> void:
	var economy: PlayerEconomy = _economy(
		{"grain": 100, "lumber": 0, "castIron": 0, "fabric": 0, "paper": 0}, 5000
	)
	var market := WorldMarket.with_default_prices()
	var plan: Dictionary = AiMarketPlanner.plan(_config(), economy, market, 20)
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
	var economy: PlayerEconomy = _economy({"grain": 0}, 10)
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


## Rival Merchants buy Minor and Tribe land (wiki: civilian-units § Merchant,
## § Work Order Summary; civilian-work-planner § Merchant tasks). The court
## answers the same gates as the player — embassy, no war, prospected minerals,
## 15 x base price — and the deed is charged to its own ledger, never the human
## crown's (REQ-P2-03, REQ-P3-03).

const Fixture = preload("res://tests/civilian_fixture.gd")

const GRAIN: Vector2i = Vector2i(3, 1)
const IRON: Vector2i = Vector2i(2, 1)
const AWAY: Vector2i = Vector2i(1, 1)
const MINOR: int = 6


func test_a_merchant_on_a_genoese_grain_tile_signs_the_deed() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _merchant(GRAIN)
	var plan: Dictionary = _plan(model, [merchant])

	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), "purchase_land")
	assert_eq(Vector2i(plan["orders"][0]["tile"]), GRAIN)
	assert_true((plan["moves"] as Array).is_empty(), "standing on the tile, it works")


func test_a_merchant_away_from_the_offer_walks_toward_it() -> void:
	var model: MapModel = Fixture.build_minor()
	var merchant: CivilianState = _merchant(AWAY)
	var plan: Dictionary = _plan(model, [merchant])

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
	var plan: Dictionary = _plan(model, [_merchant(GRAIN)], court)

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
	var plan: Dictionary = _plan(model, [_merchant(GRAIN)], court)

	assert_true((plan["orders"] as Array).is_empty())
	assert_true((plan["moves"] as Array).is_empty())


func test_a_deeded_tile_is_offered_to_nobody_again() -> void:
	var model: MapModel = Fixture.build_minor()
	assert_true(model.purchase_tile(GRAIN, 1), "a rival's deed")
	var plan: Dictionary = _plan(model, [_merchant(GRAIN)])

	assert_true((plan["orders"] as Array).is_empty())
	assert_true(
		(plan["moves"] as Array).is_empty(),
		"the only other offer needs a prospect, so the merchant idles"
	)


func test_a_mineral_waits_for_the_explorers_prospect() -> void:
	var model: MapModel = Fixture.build_minor()
	var works := LandWorks.new()
	var merchant: CivilianState = _merchant(IRON)
	var plan: Dictionary = _plan(model, [merchant])

	assert_true((plan["orders"] as Array).is_empty(), "iron is not prospected yet")
	var move_tile: Vector2i = (plan["moves"] as Array)[0]["tile"]
	assert_eq(move_tile, GRAIN, "the grain deed wins")

	works.set_prospected(0, model, IRON)
	var ready: Dictionary = _plan(model, [merchant], null, works)
	assert_eq((ready["orders"] as Array).size(), 1)
	assert_eq(Vector2i(ready["orders"][0]["tile"]), IRON)


func test_a_court_with_a_deed_on_offer_trains_one_merchant() -> void:
	var model: MapModel = Fixture.build_minor()
	var roster: Array = _staffed_roster()
	var context: Dictionary = _context(model, Fixture.merchant_court())
	var plan: Dictionary = _plan(model, roster, Fixture.merchant_court(), null, context)

	assert_true(bool(plan["training"].get("ok", false)))
	assert_eq(String(plan["training"]["type_id"]), "merchant")

	var techless: Dictionary = _context(model, Fixture.merchant_court())
	techless["tech_unlocked"] = {}
	var plain: Dictionary = _plan(model, roster, Fixture.merchant_court(), null, techless)
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
	var plan: Dictionary = _plan(model, roster)

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
	var merchant: CivilianState = _merchant(GRAIN)
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
	var context: Dictionary = _context(model, Fixture.merchant_court())
	var builder: CivilianState = CivilianState.create(1, 0, "builder", GRAIN)
	var none: Dictionary = AiMerchantWork.best_candidate(
		AiConfig.build(0, 1500), model, builder, [builder], LandWorks.new(),
		Fixture.stockpile(), {}, {}, context, {}
	)
	assert_true(none.is_empty(), "a builder cannot buy land")
	var merchant: CivilianState = _merchant(GRAIN)
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
	assert_true(AiMerchantWork.best_move(gp, _merchant(GRAIN), LandWorks.new()).is_empty())


# --- fixtures ----------------------------------------------------------------

func _merchant(tile: Vector2i, owner: int = 0) -> CivilianState:
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


func _context(
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


func _plan(
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
		context if not context.is_empty() else _context(model, diplomacy)
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


## Rival cargo routes (wiki: economy-planner § Cargo; DR-20261110-26): idle
## merchant squadrons sail home so their holds count at the seat, and a court
## whose colonial tonnage and trade holds outrun the berths lays down one more
## hull through the same yard and movement gates the human uses.

const OWNER: int = 1


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


func _cargo_config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


func _cargo_economy(treasury: int = 2500) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func _merchant_fleet(fleet_id: int, type_id: String = "carrack") -> FleetState:
	var hull_id: String = "hull_%d" % fleet_id
	return FleetState.at_sea(fleet_id, OWNER, 0, [hull_id], {hull_id: type_id})


func test_an_idle_merchant_squadron_is_walked_home_and_docks() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant_fleet(1)
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
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
		_cargo_config(), _cargo_economy(), model, [sloop], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty(), "no purse for a hull yet")


func test_a_merchant_in_another_port_puts_to_sea_toward_the_seat() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
	)
	var routes: Array = plan["routes"]
	assert_eq(routes.size(), 1)
	assert_true(not bool(routes[0]["dock"]), "the outport is not the seat")
	assert_eq(int(routes[0]["zone"]), 0, "it puts to sea into the seat's water")


func test_hostile_water_holds_a_merchant_in_port() -> void:
	var model: MapModel = _old_world()
	var fleet := FleetState.in_port(5, OWNER, 1, ["hull_5"], {"hull_5": "carrack"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5, {0: true}
	)
	assert_true((plan["routes"] as Array).is_empty(), "it waits for safer water")


func test_berths_at_the_seat_already_cover_the_need() -> void:
	var model: MapModel = _old_world()
	var fluyte := FleetState.in_port(3, OWNER, 0, ["hull_3"], {"hull_3": "fluyte"})
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(20000), model, [fluyte], 0, 4
	)
	assert_eq(int(plan["holds"]), 4, "a fluyte's four holds are home cargo")
	assert_true((plan["routes"] as Array).is_empty())
	assert_true((plan["launch"] as Dictionary).is_empty())


func test_a_shortfall_that_pays_lays_down_a_merchant_hull() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(20000), model, [], 0, 10
	)
	var launch: Dictionary = plan["launch"]
	assert_eq(String(launch.get("kind", "")), "launch")
	assert_eq(String(launch.get("type_id", "")), "carrack", "the only buildable hull")
	assert_eq(int(launch.get("cargo", 0)), 3)


func test_the_better_merchant_wins_on_cargo_then_price() -> void:
	var model: MapModel = _old_world()
	var economy: PlayerEconomy = _cargo_economy(20000)
	economy.tech_unlocked["superior_hull_design"] = true
	var plan: Dictionary = AiCargoPlanner.plan(_cargo_config(), economy, model, [], 0, 10)
	assert_eq(
		String(plan["launch"].get("type_id", "")), "fluyte",
		"four holds for less money beats three"
	)


func test_the_purse_floor_keeps_the_yard_shut() -> void:
	var model: MapModel = _old_world()
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(9000), model, [], 0, 10
	)
	assert_true((plan["launch"] as Dictionary).is_empty(), "£1,000 left is not enough")


func test_a_squadron_carrying_an_expedition_keeps_its_course() -> void:
	var model: MapModel = _old_world()
	var fleet: FleetState = _merchant_fleet(4)
	fleet.embarked_army = 7
	var plan: Dictionary = AiCargoPlanner.plan(
		_cargo_config(), _cargo_economy(), model, [fleet], 0, 5
	)
	assert_true((plan["routes"] as Array).is_empty())


func test_cargo_missing_inputs_make_the_plan_empty() -> void:
	var model: MapModel = _old_world()
	assert_true((AiCargoPlanner.plan(null, _cargo_economy(), model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_cargo_config(), null, model, [], 0, 5)["routes"] as Array).is_empty())
	assert_true((AiCargoPlanner.plan(_cargo_config(), _cargo_economy(), null, [], 0, 5)["routes"] as Array).is_empty())
	assert_true(not bool(AiCargoPlanner.apply_route(model, null, {})["ok"]))


# --- applied orders (MapPlayCargoAi) ----------------------------------------


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
	var fleet: FleetState = _merchant_fleet(1)
	var built: Dictionary = _session(model, [fleet])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _cargo_economy()
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
		play, OWNER, _cargo_economy(), {"used": 0, "left_total": 2}
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
		play, OWNER, _cargo_economy(), {"used": 0, "left_total": 2}
	)
	assert_true((report["routes"] as Array).is_empty())
	assert_true(fleet.is_in_port(), "the merchant never enters the hostile zone")
	(built["ships"] as Node).free()


func test_the_adapter_founds_a_slip_when_no_squadron_is_in_port() -> void:
	var model: MapModel = _old_world()
	var built: Dictionary = _session(model, [])
	var play: PlaySession = built["play"]
	var economy: PlayerEconomy = _cargo_economy(20000)
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
