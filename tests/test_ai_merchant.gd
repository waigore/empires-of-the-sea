extends GdToolsTest
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
