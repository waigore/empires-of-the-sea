extends GdToolsTest
## Cargo raids by patrol/blockade squadrons (wiki: ships-and-naval § Trade and
## Transport Interception; DR-20261109-16).

const NavalFixture = preload("res://tests/naval_fixture.gd")

var _model: MapModel = null


func before_each() -> void:
	_model = NavalFixture.build()


func _fleet(id: int, owner: int, zone: int, types: Array) -> FleetState:
	var fleet := FleetState.at_sea(id, owner, zone)
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for index in types.size():
		var hull_id: String = "ship_%d_%d" % [id, index]
		hull_ids.append(hull_id)
		hull_types[hull_id] = types[index]
	fleet.set_hulls(hull_ids, hull_types)
	return fleet


func _raider(mission: int = FleetState.Mission.PATROL) -> FleetState:
	var fleet := FleetState.at_sea(1, 1, 0, ["raider_1"], {"raider_1": "frigate"})
	fleet.mission = mission
	return fleet


func test_a_patrol_raider_skims_a_share_of_the_imports() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var result: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0
	)
	assert_true(bool(result["ok"]))
	assert_gt(int(result["lost_total"]), 0)
	assert_gt(int((result["losses"] as Dictionary)["grain"]), 0)
	assert_between(float(result["efficiency"]), NavalRaid.MIN_EFFICIENCY, NavalRaid.MAX_EFFICIENCY)
	assert_almost_eq(float(result["chance"]), 0.5 * 5.0 / 8.0, 0.0001)


func test_escorts_cut_the_raid_chance() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var alone: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	home.add_hull("home_2", "sloop")
	var escorted: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_lt(float(escorted["chance"]), float(alone["chance"]))
	assert_false(bool(escorted["ok"]))


func test_peace_and_distant_raiders_do_not_raid() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var peace := func(_a: int, _b: int) -> bool: return false
	assert_false(bool(NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 5}, peace, 1, 1, 0.0
	)["ok"]))
	raider.sea_zone = 1
	assert_false(bool(NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_model, [home, raider], 0, null, {"grain": 5}, Callable(), 1, 1, 0.0
	)["ok"]))
	assert_false(bool(NavalRaid.resolve(
		_model, [home, raider], 0, home, {}, Callable(), 1, 1, 0.0
	)["ok"]))


func test_a_blockade_raider_earns_the_bonus() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _raider()
	var blockade := _raider(FleetState.Mission.BLOCKADE)
	blockade.blockade_province = 0
	var patrolled: Dictionary = NavalRaid.resolve(
		_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var stopped: Dictionary = NavalRaid.resolve(
		_model, [home, blockade], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	assert_gt(float(stopped["chance"]), float(patrolled["chance"]))
	assert_almost_eq(
		float(stopped["chance"]), float(patrolled["chance"]) * NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


func test_privateers_improve_the_raid_chance() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var plain: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99
	)
	var charter := func(owner: int, tech_id: String) -> bool:
		return owner == 1 and tech_id == NavalInterception.PRIVATEERING_TECH
	var chartered: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.99, charter
	)
	assert_almost_eq(float(plain["chance"]), 0.5 * 5.0 / 8.0, 0.0001)
	# Σintercept 5 × 1.25 = 6.25 against the same flee score of 3.
	assert_almost_eq(float(chartered["chance"]), 0.5 * 6.25 / 9.25, 0.0001)
	assert_gt(float(chartered["chance"]), float(plain["chance"]))


## In the full-AI observer every crown answers from its AI ledger; the human
## ledger is frozen and must not answer for the observed crown (REQ-P2-03).
func test_the_observer_answers_tech_from_each_crowns_ledger() -> void:
	var play := PlaySession.new()
	play.player_faction = 0
	play.observer_mode = true
	play.ai = AiState.new()
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_false(
		play.has_tech(0, NavalInterception.PRIVATEERING_TECH),
		"the human ledger does not resolve in the observer"
	)
	play.ai.economy_for(0).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(2, NavalInterception.PRIVATEERING_TECH))
	economy.free()


func test_the_session_answers_tech_for_the_human_and_rivals() -> void:
	var play := PlaySession.new()
	play.player_faction = 0
	play.ai = AiState.new()
	assert_false(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	play.economy = economy
	economy.economy.tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(0, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	play.ai.economy_for(1).tech_unlocked[NavalInterception.PRIVATEERING_TECH] = true
	assert_true(play.has_tech(1, NavalInterception.PRIVATEERING_TECH))
	assert_false(play.has_tech(0, ""))
	economy.free()


func test_losses_never_exceed_the_imports() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var result: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 1}, Callable(), 1, 1, 0.0
	)
	assert_eq(int(result["lost_total"]), 1)
	assert_eq(int((result["losses"] as Dictionary)["grain"]), 1)


func test_a_blockade_bonus_does_not_cross_zones() -> void:
	# Both coasts answer to the victim, so both zones border its shore.
	_model.province_data(1).owner = 0
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var patrol := _fleet(1, 1, 1, ["sloop"])
	patrol.mission = FleetState.Mission.PATROL
	var blockader := _fleet(2, 1, 0, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 0
	var lone: Dictionary = NavalRaid.resolve(
		_model, [home, patrol], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3
	)
	assert_false(bool(lone["ok"]), "a lone patrol in the far zone misses at 0.30")
	var both: Dictionary = NavalRaid.resolve(
		_model, [home, patrol, blockader], 0, home, {"grain": 10}, Callable(), 1, 1, 0.3
	)
	assert_true(bool(both["ok"]))
	assert_eq(int(both["zone"]), 0, "the blockading squadron raids in its own zone")
	assert_almost_eq(
		float(both["chance"]),
		NavalInterception.chance([blockader], [home], FleetState.Mission.PATROL)
		* NavalRaid.BLOCKADE_BONUS,
		0.0001
	)


func test_the_market_reports_this_turns_imports() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = 5000
	assert_true(bool(market.buy(economy, "grain", 3)["ok"]))
	assert_eq(int(market.imports_this_turn().get("grain", 0)), 3)
	assert_eq(market.bought_units(), 3)


func test_the_map_raid_pass_takes_the_losses_from_the_ledger() -> void:
	var play := PlaySession.new()
	play.model = _model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.map_seed = 1
	while NavalInterception.roll(play.map_seed, play.turn, 0, 1, 77) >= 0.3:
		play.map_seed += 1
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_model.region_id, fleets)
	var world := WorldMap.new()
	world.add_region(_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.treasury = 5000
	assert_true(bool(economy.market.buy(economy.economy, "grain", 4)["ok"]))
	play.ship_layer = ships
	play.economy = economy
	var before: int = economy.economy.quantity("grain")

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_true(bool(result.get("ok", false)))
	assert_gt(int(result.get("taken", 0)), 0)
	assert_lt(economy.economy.quantity("grain"), before)
	ships.free()
	economy.free()


# --- a raid takes cargo, never hulls (DR-20261110-13) -----------------------


func test_a_raid_takes_cargo_and_leaves_every_hull_afloat() -> void:
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _raider()
	var hulls_before: int = home.hulls.size() + raider.hulls.size()
	var result: Dictionary = NavalRaid.resolve(
		_model, [home, raider], 0, home, {"grain": 10}, Callable(), 1, 1, 0.0
	)
	assert_true(bool(result["ok"]))
	assert_eq((result["hulls_lost"] as Array).size(), 0)
	assert_eq(
		home.hulls.size() + raider.hulls.size(), hulls_before,
		"a raid never sinks a hull on either side"
	)


func test_a_prize_takes_the_rivals_cargo_off_its_home_fleet() -> void:
	var crown := _fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0
	)
	assert_eq(raids.size(), 1)
	assert_eq(int(raids[0]["victim"]), 1)
	assert_eq(int(raids[0]["raider"]), 0)
	assert_gt(int(raids[0]["lost_total"]), 0)
	assert_eq((raids[0]["hulls_lost"] as Array).size(), 0)
	assert_eq(laden.hulls.size(), 1, "the prize never costs the merchant a hull")


func test_a_prize_needs_a_declared_war() -> void:
	var crown := _fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var peace := func(_a: int, _b: int) -> bool: return false
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, peace, 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "peace takes no prize")


func test_a_prize_comes_only_from_the_crowns_own_squadrons() -> void:
	var rival_ship := _fleet(1, 2, 1, ["sloop"])
	rival_ship.mission = FleetState.Mission.BLOCKADE
	rival_ship.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_model, [rival_ship, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), 1, 1, Callable(), 0.0
	)
	assert_true(raids.is_empty(), "another crown's blockade is not the crown's prize")


func test_a_prize_rolls_on_its_own_salt() -> void:
	var crown := _fleet(1, 0, 1, ["sloop"])
	crown.mission = FleetState.Mission.BLOCKADE
	crown.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var seed_value: int = 1
	var expected: float = NavalInterception.roll(
		seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
	)
	while expected >= 0.2:
		seed_value += 1
		expected = NavalInterception.roll(
			seed_value, 3, 1, 0, NavalRaid.PRIZE_TAG_BASE + 1
		)
	var raids: Array[Dictionary] = NavalRaid.resolve_prizes(
		_model, [crown, laden], 0,
		{1: {"imports": {"grain": 10}, "home": laden}}, Callable(), seed_value, 3
	)
	assert_eq(raids.size(), 1)
	assert_almost_eq(float(raids[0]["roll"]), expected, 0.0001)


func test_the_market_keeps_each_crowns_cargo_apart() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	rival.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	assert_eq(int(market.imports_for(0).get("grain", 0)), 2)
	assert_eq(int(market.imports_for(0).get("timber", 0)), 0)
	assert_eq(int(market.imports_for(1).get("timber", 0)), 3)
	assert_eq(
		int(market.imports_this_turn().get("grain", 0)), 2,
		"price discovery still pools every buyer's demand"
	)
	var expected: Array[int] = [0, 1]
	assert_eq(market.importing_factions(), expected)


func test_the_book_closes_with_the_turn() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var mine: PlayerEconomy = PlayerEconomy.starting()
	mine.treasury = 5000
	assert_true(bool(market.buy(mine, "grain", 2, 0)["ok"]))
	market.advance_prices()
	assert_true(
		market.imports_for(0).is_empty(),
		"price discovery closes the cargo book the raid pass reads"
	)
	assert_true(market.importing_factions().is_empty())


func test_a_saved_book_keeps_each_crowns_cargo() -> void:
	var market: WorldMarket = WorldMarket.with_default_prices()
	var rival: PlayerEconomy = PlayerEconomy.starting()
	rival.treasury = 5000
	assert_true(bool(market.buy(rival, "timber", 3, 1)["ok"]))
	var restored: WorldMarket = WorldMarket.from_dict(market.to_dict())
	restored = WorldMarket.from_dict(
		JSON.parse_string(JSON.stringify(restored.to_dict())) as Dictionary
	)
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 3)
	assert_true(bool(restored.buy(rival, "timber", 1, 1)["ok"]))
	assert_eq(int(restored.imports_for(1).get("timber", 0)), 4, "a reload keeps filling the row")


func test_the_map_pass_pays_the_crown_for_its_blockade() -> void:
	var play := PlaySession.new()
	play.model = _model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var blockader := _fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var rival: PlayerEconomy = play.ledger_for(1)
	rival.add("grain", 6)
	var rival_before: int = rival.quantity("grain")
	var crown_before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	var salt: int = NavalRaid.PRIZE_TAG_BASE + 1
	while NavalInterception.roll(play.map_seed, 1, 1, 0, salt) >= NavalInterception.MIN_CHANCE:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	assert_gt(int(result.get("prize", 0)), 0)
	assert_gt(
		economy.economy.quantity("grain"), crown_before,
		"the prize lands in the crown's stockpile"
	)
	assert_lt(rival.quantity("grain"), rival_before, "the rival's cargo is what paid for it")
	assert_eq(laden.hulls.size(), 1, "the merchant hull came home")
	ships.free()
	economy.free()


func test_the_crown_loses_only_its_own_cargo_to_raiders() -> void:
	var play := PlaySession.new()
	play.model = _model
	play.player_faction = 0
	play.capital_province = 0
	play.turn = 1
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.ensure_relation(0, 1, 1)
	DiplomacyRules.declare_war(play.diplomacy, 0, 1, false)
	var home := FleetState.in_port(10, 0, 0, ["home_1"], {"home_1": "fluyte"})
	var raider := _fleet(2, 1, 0, ["frigate"])
	raider.mission = FleetState.Mission.PATROL
	home.mission = FleetState.Mission.NONE
	home.moved = false
	var fleets: Array[FleetState] = [home, raider]
	var ships := ShipLayer.new()
	ships.model = _model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_model)
	play.world = world
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	economy.economy.add("grain", 20)
	play.economy = economy
	economy.market.record_import("grain", 4, 0)
	economy.market.record_import("grain", 40, 1)
	var before: int = economy.economy.quantity("grain")
	play.map_seed = 1
	while NavalInterception.roll(play.map_seed, 1, 0, 1, NavalRaid.ROLL_TAG) >= NavalInterception.MIN_CHANCE:
		play.map_seed += 1

	var result: Dictionary = MapPlayRaids.resolve(play)

	var taken: int = int(result.get("taken", 0))
	assert_gt(taken, 0)
	assert_lte(taken, 4, "the rival's forty units were never the crown's cargo")
	assert_eq(economy.economy.quantity("grain"), before - taken)
	assert_eq(home.hulls.size(), 1, "raiders pinch cargo, they do not sink the hull")
	ships.free()
	economy.free()


func test_the_dossier_prices_the_prize_before_the_move() -> void:
	var play := PlaySession.new()
	play.model = _model
	play.player_faction = 0
	play.turn = 1
	play.ai = AiState.new()
	var blockader := _fleet(1, 0, 1, ["sloop"])
	blockader.mission = FleetState.Mission.BLOCKADE
	blockader.blockade_province = 1
	var laden := FleetState.in_port(20, 1, 1, ["rival_1"], {"rival_1": "fluyte"})
	var fleets: Array[FleetState] = [blockader, laden]
	var ships := ShipLayer.new()
	ships.model = _model
	ships.player_faction = 0
	ships.fleets = fleets
	ships.regions.set_region(_model.region_id, fleets)
	play.ship_layer = ships
	var world := WorldMap.new()
	world.add_region(_model)
	play.world = world
	play.map_seed = 1
	var economy := EconomyController.new()
	economy.economy = PlayerEconomy.starting()
	economy.market = WorldMarket.with_default_prices()
	play.economy = economy
	economy.market.record_import("grain", 6, 1)
	var note: String = MapPlayFleetMissions.prize_note(play, blockader)
	var odds: Dictionary = NavalRaid.preview(
		[blockader], laden, {"grain": 6}, FleetState.Mission.BLOCKADE
	)
	assert_true(note.contains("Prize:"))
	assert_true(note.contains("no hull at risk"))
	assert_true(
		note.contains("%d%%" % int(round(float(odds["chance"]) * 100.0))),
		"the dossier reads the chance the rules roll"
	)
	assert_true(note.contains("~%d" % int(odds["expected"])))
	# With nothing bought this turn there is no cargo afloat to take.
	economy.market.advance_prices()
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("no cargo afloat")
	)
	# A crown that has taken the coast blockades its own shore: no prize.
	economy.market.record_import("grain", 4, 1)
	_model.province_data(1).owner = 0
	assert_eq(MapPlayFleetMissions.prize_note(play, blockader), "")
	_model.province_data(1).owner = 1
	# A rival whose merchant hulls are at sea has no laden home fleet to raid.
	laden.location = FleetState.Location.AT_SEA
	laden.sea_zone = 1
	laden.province = MapModel.NO_ID
	assert_true(
		MapPlayFleetMissions.prize_note(play, blockader).contains("at sea")
	)
	economy.free()
