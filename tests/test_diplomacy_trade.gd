extends GdToolsTest
## Trade diplomacy: favoured trading pacts, colonial boycotts and the market
## price terms they publish (wiki: diplomacy § GP–Tribe — Boycott; world-market
## § FTP, § Subsidy price adjustment).

var state: DiplomacyState
var economy: PlayerEconomy


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	economy = PlayerEconomy.starting()


func test_ftp_needs_a_great_power_and_an_embassy() -> void:
	assert_true(DiplomacyTrade.can_establish_ftp(state, 0, 1)["ok"], "GP auto-embassy")
	var minor: Dictionary = DiplomacyTrade.can_establish_ftp(state, 0, 6)
	assert_false(minor["ok"])
	assert_true(String(minor["reason"]).contains("Great Powers"))


func test_ftp_needs_friendly_standing_and_is_bilateral() -> void:
	var refused: Dictionary = DiplomacyTrade.establish_ftp(state, 0, 1)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]), "score 50 is below the pact threshold")
	assert_false(DiplomacyTrade.is_ftp(state, 0, 1))
	assert_false(DiplomacyTrade.is_ftp(state, 1, 0))

	state.end_turn()
	state.relation(0, 1).score = DiplomacyCatalog.FTP_MIN_SCORE
	var signed: Dictionary = DiplomacyTrade.establish_ftp(state, 0, 1)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed["accepted"]))
	assert_true(DiplomacyTrade.is_ftp(state, 0, 1), "one record serves both directions")
	assert_true(DiplomacyTrade.is_ftp(state, 1, 0))
	assert_true(DiplomacyTrade.ftps_of(state, 0).has(1))


func test_ftp_improves_both_crowns_terms_and_war_ends_it() -> void:
	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	var mine: Dictionary = DiplomacyTrade.faction_terms(state, {}, 0)
	var theirs: Dictionary = DiplomacyTrade.faction_terms(state, {}, 1)
	assert_almost_eq(float(mine["buy"]["*"]), 0.95, 0.001, "pact shaves imports")
	assert_almost_eq(float(mine["sell"]["*"]), 1.05, 0.001, "and lifts exports")
	assert_almost_eq(float(theirs["buy"]["*"]), 0.95, 0.001, "both sides gain")

	DiplomacyRules.declare_war(state, 0, 1)
	assert_false(DiplomacyTrade.is_ftp(state, 0, 1), "war severs the pact")
	var after: Dictionary = DiplomacyTrade.faction_terms(state, {}, 0)
	assert_almost_eq(float(after["buy"]["*"]), 1.0, 0.001, "terms return to the world price")


func test_boycott_needs_a_colony_and_cancels_the_targets_subsidies() -> void:
	var refused: Dictionary = DiplomacyTrade.can_boycott(state, 0, 2)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))

	state.set_colony(9, 0)
	state.ensure_relation(2, 9, state.turn)
	state.set_overture(2, 9, DiplomacyCatalog.STAGE_EMBASSY)
	state.set_subsidy(2, 9, 10)
	var applied: Dictionary = DiplomacyTrade.boycott(state, 0, 2)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(state, 0, 2))
	assert_eq(state.subsidy(2, 9), 0, "the boycotted crown loses its subsidy to our colony")
	assert_false(DiplomacyTrade.boycott(state, 0, 2)["ok"], "one boycott order per turn")
	state.end_turn()

	var lifted: Dictionary = DiplomacyTrade.revoke_boycott(state, 0, 2)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(state, 0, 2))


func test_boycott_worsens_the_targets_terms_and_war_revokes_it() -> void:
	state.set_colony(9, 0)
	DiplomacyTrade.boycott(state, 0, 2)
	var target: Dictionary = DiplomacyTrade.faction_terms(state, {}, 2)
	assert_almost_eq(float(target["buy"]["*"]), 1.10, 0.001, "boycotted imports cost more")
	assert_almost_eq(float(target["sell"]["*"]), 0.90, 0.001, "and exports earn less")
	var issuer: Dictionary = DiplomacyTrade.faction_terms(state, {}, 0)
	assert_almost_eq(float(issuer["buy"]["*"]), 1.0, 0.001, "the issuer keeps the world price")

	DiplomacyRules.declare_war(state, 0, 2)
	assert_false(DiplomacyTrade.is_boycotting(state, 0, 2), "war auto-revokes")


func test_a_subsidy_sets_rates_on_the_subsidised_courts_goods() -> void:
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	state.ensure_relation(0, 9, state.turn)
	state.set_overture(0, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyAid.set_subsidy(state, 0, 9, 10)
	var terms: Dictionary = DiplomacyTrade.terms_for_court(state, world, 0)
	assert_almost_eq(float(terms["buy"]["timber"]), 1.10, 0.001, "surcharge on their goods")
	assert_almost_eq(float(terms["sell"]["timber"]), 0.90, 0.001, "discount on our goods")
	assert_almost_eq(float(terms["buy"]["*"]), 1.0, 0.001, "only that court's goods move")
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, terms)
	assert_eq(
		market.buy_price("timber", 0),
		roundi(float(market.price("timber")) * 1.10)
	)
	assert_eq(market.buy_price("grain", 0), market.price("grain"))
	assert_eq(market.sell_price("timber", 1), market.price("timber"), "other crowns untouched")
	var direct: int = maxi(int(floor(float(market.price("timber")) * MinorMarket.DISCOUNT)), 1)
	assert_eq(
		MinorMarket.unit_price(market, "timber", 0),
		roundi(float(direct) * 1.10),
		"a direct offer from that court carries the surcharge too"
	)


func test_the_market_charges_a_crowns_buy_and_sell_terms() -> void:
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 1.1}, "sell": {"*": 0.9}})
	var base: int = market.price("timber")
	var before: int = economy.treasury
	var bought: Dictionary = market.buy(economy, "timber", 1, 0)
	assert_eq(int(bought["unit_price"]), roundi(float(base) * 1.1))
	assert_eq(economy.treasury, before - int(bought["cost"]))

	economy.stockpile["timber"] = 1
	before = economy.treasury
	var sold: Dictionary = market.sell(economy, "timber", 1, 0)
	assert_eq(int(sold["unit_price"]), roundi(float(base) * 0.9))
	assert_eq(economy.treasury, before + roundi(float(base) * 0.9))
	assert_eq(market.buy_price("timber", 1), base, "a crown without terms pays the world price")


func test_terms_survive_a_save_round_trip() -> void:
	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	state.set_colony(9, 0)
	DiplomacyTrade.boycott(state, 0, 2)
	var play := PlaySession.new()
	SaveCourt.restore_diplomacy(
		play, {"diplomacy": SaveCourt.capture_diplomacy(state)}
	)
	assert_true(DiplomacyTrade.is_ftp(play.diplomacy, 0, 1))
	assert_true(DiplomacyTrade.is_boycotting(play.diplomacy, 0, 2))


func test_court_orders_offer_trade_actions_and_the_way_back() -> void:
	var options: Array[Dictionary] = DiplomacyOrders.options(state, null, 2500, 0, 1)
	var offer: Dictionary = _first(options, DiplomacyOrders.KIND_FTP)
	assert_eq(String(offer["group"]), DiplomacyOrders.GROUP_TRADE)
	assert_true(String(offer["hint"]).contains("5%"))
	assert_eq(
		String(_first(options, DiplomacyOrders.KIND_BOYCOTT)["group"]),
		DiplomacyOrders.GROUP_TRADE
	)

	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	var after: Array[Dictionary] = DiplomacyOrders.options(state, null, 2500, 0, 1)
	assert_true(_first(after, DiplomacyOrders.KIND_FTP).is_empty())
	assert_false(_first(after, DiplomacyOrders.KIND_REVOKE_FTP).is_empty())


func test_court_orders_sign_and_end_the_pact() -> void:
	state.relation(0, 1).score = 80.0
	var signed: Dictionary = DiplomacyOrders.apply(
		state, null, economy, {"kind": DiplomacyOrders.KIND_FTP, "from": 0, "target": 1}
	)
	assert_true(signed["ok"], signed.get("reason", ""))
	assert_true(bool(signed.get("accepted", false)))
	assert_true(DiplomacyTrade.is_ftp(state, 0, 1))
	state.end_turn()
	var ended: Dictionary = DiplomacyOrders.apply(
		state, null, economy, {"kind": DiplomacyOrders.KIND_REVOKE_FTP, "from": 0, "target": 1}
	)
	assert_true(ended["ok"], ended.get("reason", ""))
	assert_false(DiplomacyTrade.is_ftp(state, 0, 1))


func test_court_orders_impose_and_lift_the_boycott() -> void:
	state.set_colony(9, 0)
	var applied: Dictionary = DiplomacyOrders.apply(
		state, null, economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(applied["ok"], applied.get("reason", ""))
	assert_true(DiplomacyTrade.is_boycotting(state, 0, 2))
	state.end_turn()
	var lifted: Dictionary = DiplomacyOrders.apply(
		state,
		null,
		economy,
		{"kind": DiplomacyOrders.KIND_REVOKE_BOYCOTT, "from": 0, "target": 2}
	)
	assert_true(lifted["ok"], lifted.get("reason", ""))
	assert_false(DiplomacyTrade.is_boycotting(state, 0, 2))


func test_validation_mirrors_the_trade_gates() -> void:
	var denied: Dictionary = DiplomacyOrders.validate(
		state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
	)
	assert_false(denied["ok"])
	assert_true(String(denied["reason"]).contains("colony"))
	state.set_colony(9, 0)
	assert_true(
		DiplomacyOrders.validate(
			state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_BOYCOTT, "target": 2}
		)["ok"]
	)
	assert_true(
		DiplomacyOrders.validate(
			state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_FTP, "target": 1}
		)["ok"]
	)
	assert_false(
		DiplomacyOrders.validate(
			state, null, 2500, 0, {"kind": DiplomacyOrders.KIND_REVOKE_FTP, "target": 1}
		)["ok"]
	)


func test_a_subsidy_without_an_embassy_explains_itself() -> void:
	state.ensure_relation(0, 6, state.turn)
	var options: Array[Dictionary] = DiplomacyOrders.options(state, null, 2500, 0, 6)
	var subsidy: Dictionary = _first(options, DiplomacyOrders.KIND_SUBSIDY)
	assert_false(bool(subsidy["ok"]))
	assert_true(String(subsidy["hint"]).contains("embassy"))


func test_terms_stay_inside_the_rails() -> void:
	for other: int in [10, 11, 12, 13, 14, 15]:
		state.ftps[state.pair_key(0, other)] = state.turn
	var terms: Dictionary = DiplomacyTrade.faction_terms(state, {}, 0)
	assert_almost_eq(
		float(terms["buy"]["*"]), DiplomacyCatalog.TERMS_BUY_MIN, 0.001, "buy floor"
	)
	assert_almost_eq(
		float(terms["sell"]["*"]), DiplomacyCatalog.TERMS_SELL_MAX, 0.001, "sell cap"
	)
	state.boycotts["2>2"] = state.turn
	assert_true(DiplomacyTrade.boycotts_against(state, 2).is_empty(), "self-boycott ignored")


func test_clearing_terms_returns_the_world_price() -> void:
	var market := WorldMarket.with_default_prices()
	market.set_terms(0, {"buy": {"*": 0.9}})
	var clone: WorldMarket = market.copy()
	assert_false(clone.terms_for(0).is_empty(), "a projection keeps the terms")
	market.clear_terms()
	assert_true(market.terms_for(0).is_empty())
	assert_eq(market.buy_price("timber", 0), market.price("timber"))


func test_absorbing_a_crown_clears_its_trade_ties() -> void:
	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	state.set_colony(9, 0)
	DiplomacyTrade.boycott(state, 0, 2)
	state.clear_relations_of(1)
	assert_false(DiplomacyTrade.is_ftp(state, 0, 1), "the pact dies with the court")
	state.clear_relations_of(2)
	assert_false(DiplomacyTrade.is_boycotting(state, 0, 2), "so does its boycott")


func test_every_trade_gate_says_why_it_refuses() -> void:
	assert_true(
		String(DiplomacyTrade.can_revoke_ftp(state, 0, 1)["reason"]).contains("No favoured")
	)
	assert_false(DiplomacyTrade.revoke_ftp(state, 0, 1)["ok"])
	assert_true(
		String(DiplomacyTrade.can_boycott(state, 0, 0)["reason"]).contains("itself")
	)
	assert_true(
		String(DiplomacyTrade.can_boycott(state, 0, 6)["reason"]).contains("Great Power")
	)
	assert_true(
		String(DiplomacyTrade.can_revoke_boycott(state, 0, 2)["reason"]).contains("No boycott")
	)
	state.set_colony(9, 0)
	DiplomacyRules.declare_war(state, 0, 2)
	assert_true(
		String(DiplomacyTrade.can_boycott(state, 0, 2)["reason"]).contains("at war")
	)
	DiplomacyRules.declare_war(state, 0, 1)
	assert_true(
		String(DiplomacyTrade.can_establish_ftp(state, 0, 1)["reason"]).contains("enemy")
	)


func test_a_court_can_refuse_the_pact() -> void:
	state.relation(0, 1).score = 80.0
	var refused: Dictionary = DiplomacyTrade.establish_ftp(
		state, 0, 1, DiplomacyRules.DECISION_REFUSE
	)
	assert_true(refused["ok"], refused.get("reason", ""))
	assert_false(bool(refused["accepted"]))
	assert_false(DiplomacyTrade.is_ftp(state, 0, 1))


func test_terms_are_published_to_the_market_and_cleared_again() -> void:
	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	var market := WorldMarket.with_default_prices()
	DiplomacyTrade.apply_terms(state, null, market)
	assert_almost_eq(market.term_multiplier(0, "timber", true), 0.95, 0.001)
	assert_almost_eq(market.term_multiplier(1, "timber", false), 1.05, 0.001)
	assert_eq(DiplomacyTrade.market_terms(state, null).size(), 6, "every crown is priced")
	DiplomacyTrade.apply_terms(null, null, market)
	assert_true(market.terms_for(0).is_empty(), "no court means the world price")


func test_a_court_that_grows_nothing_keeps_the_world_price() -> void:
	var world: WorldMap = _tribe_world(9, _resource_for("timber"))
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(state, null, 0)["buy"]["*"]), 1.0, 0.001
	)
	assert_almost_eq(
		float(DiplomacyTrade.terms_for_court(state, world, 3)["buy"]["*"]), 1.0, 0.001,
		"no produced goods, no extra rate"
	)


func test_war_narrates_the_broken_pact_and_boycott() -> void:
	state.relation(0, 1).score = 80.0
	DiplomacyTrade.establish_ftp(state, 0, 1)
	state.set_colony(9, 0)
	DiplomacyTrade.boycott(state, 0, 2)
	DiplomacyRules.declare_war(state, 0, 1)
	DiplomacyRules.declare_war(state, 0, 2)
	var pact: String = _joined(DiplomacyHistory.entries(state, 0, 1))
	assert_true(pact.contains("war ended the favoured trading pact"), pact)
	var boycott: String = _joined(DiplomacyHistory.entries(state, 0, 2))
	assert_true(boycott.contains("war ended Spain's boycott"), boycott)


func test_a_court_order_that_cannot_trade_says_so() -> void:
	var refused: Dictionary = DiplomacyOrders.apply(
		state, null, economy, {"kind": DiplomacyOrders.KIND_BOYCOTT, "from": 0, "target": 2}
	)
	assert_false(refused["ok"])
	assert_true(String(refused["reason"]).contains("colony"))


func test_a_boycott_bars_aid_and_subsidies_to_the_colony() -> void:
	state.set_colony(9, 0)
	for gp: int in [2, 3]:
		state.ensure_relation(gp, 9, state.turn)
		state.set_overture(gp, 9, DiplomacyCatalog.STAGE_EMBASSY)
	DiplomacyTrade.boycott(state, 0, 2)
	var aid: Dictionary = DiplomacyAid.can_grant_aid(state, 2, 9, 1000, 10000)
	assert_false(aid["ok"], "the boycotted crown may not aid our colony")
	assert_true(String(aid["reason"]).contains("boycott"))
	assert_false(DiplomacyAid.can_set_subsidy(state, 2, 9, 10)["ok"])
	assert_true(DiplomacyAid.can_grant_aid(state, 3, 9, 1000, 10000)["ok"], "others may")


func _joined(entries: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries:
		lines.append(String(entry["text"]))
	return " ".join(lines)


func _first(options: Array[Dictionary], kind: String) -> Dictionary:
	for option: Dictionary in options:
		if String(option["kind"]) == kind:
			return option
	return {}


func _resource_for(commodity: String) -> int:
	for index in 64:
		if Extraction.commodity_for_resource(index) == commodity:
			return index
	return -1


func _tribe_world(owner: int, resource_index: int) -> WorldMap:
	var model := MapModel.new()
	model.setup(4, 4)
	model.faction_ids = [owner]
	model.provinces.append(
		ProvinceState.create(
			0, "P0", [Vector2i(0, 0)], Vector2(0, 0), 1, owner, false
		)
	)
	model.resource[model.index_of(0, 0)] = resource_index
	var world := WorldMap.new()
	world.add_region(model)
	return world
