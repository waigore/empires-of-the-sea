extends GdToolsTest
## A rival court's war footing (wiki: phase-planner-architecture,
## phase-planner-dispatch § Playable slice; DR-20261113-15) and its money goal
## (wiki: ai-architecture § Money first; DR-20261113-19): the phase and goal each
## court reads before its planners run, and the dispatches they open — no new
## colonisation voyage on a war footing unless the court is on earn, and a white
## peace taken by a court that fights two fronts.

const AiFixture = preload("res://tests/ai_fixture.gd")

const OWNER: int = 0
const RIVAL: int = 1
const THIRD: int = 2
const MINOR: int = 6
const SEED: int = 1500


func _config(faction: int = OWNER) -> AiConfig:
	return AiConfig.build(faction, SEED)


func _court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OWNER, RIVAL, 1)
	state.ensure_relation(OWNER, THIRD, 1)
	return state


func _war(state: DiplomacyState, target: int) -> void:
	assert_true(bool(DiplomacyRules.declare_war(state, OWNER, target)["ok"]))


# --- phase selection ---------------------------------------------------------


func test_a_court_at_peace_reads_the_published_behaviour() -> void:
	var plan: Dictionary = AiPhasePlanner.plan(_config(), _court())

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_PEACE)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "at peace")
	assert_eq(int(plan["factors"]["great_power_wars"]), 0)
	assert_false(AiPhasePlanner.is_war_footing(AiPhasePlanner.PHASE_PEACE))
	assert_false(AiPhasePlanner.takes_any_peace(AiPhasePlanner.PHASE_PEACE))


func test_one_great_power_war_is_a_war_footing() -> void:
	var state: DiplomacyState = _court()
	_war(state, RIVAL)
	var plan: Dictionary = AiPhasePlanner.plan(_config(), state)

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "at war")
	assert_eq(int(plan["factors"]["great_power_wars"]), 1)
	assert_true(AiPhasePlanner.is_war_footing(String(plan["phase"])))
	assert_false(AiPhasePlanner.takes_any_peace(String(plan["phase"])))


func test_two_great_power_wars_are_an_overstretched_court() -> void:
	var state: DiplomacyState = _court()
	_war(state, RIVAL)
	_war(state, THIRD)
	var plan: Dictionary = AiPhasePlanner.plan(_config(), state)

	assert_eq(String(plan["phase"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(AiPhasePlanner.label(String(plan["phase"])), "overstretched")
	assert_eq(int(plan["factors"]["great_power_wars"]), 2)
	assert_true(AiPhasePlanner.is_war_footing(String(plan["phase"])))
	assert_true(AiPhasePlanner.takes_any_peace(String(plan["phase"])))


func test_the_front_threshold_is_a_registry_knob() -> void:
	var state: DiplomacyState = _court()
	_war(state, RIVAL)

	assert_eq(AiParameterRegistry.default_of("phase.overstretch_fronts"), 2)
	assert_eq(
		String(AiPhasePlanner.phase_for(_config(), state)),
		AiPhasePlanner.PHASE_WAR,
		"one war is under the published threshold"
	)
	assert_eq(
		AiParameterRegistry.resolve(
			"phase.overstretch_fronts", {"phase.overstretch_fronts": 1}
		),
		1,
		"a profile may tighten the threshold to a single front"
	)
	assert_false(
		bool(AiParameterRegistry.validate({"phase.overstretch_fronts": 0})["ok"]),
		"no court is overstretched at zero fronts"
	)
	assert_false(
		bool(AiParameterRegistry.validate({"phase.overstretch_fronts": 7})["ok"]),
		"the catalog holds at most six Great Power rivals"
	)


func test_a_colonial_war_leaves_the_court_at_peace() -> void:
	var state: DiplomacyState = _court()
	var minor: DiplomacyRelation = state.ensure_relation(OWNER, MINOR, 1)
	minor.at_war = true

	assert_eq(
		String(AiPhasePlanner.phase_for(_config(), state)),
		AiPhasePlanner.PHASE_PEACE,
		"a war on a Minor Nation is colonial business, not a fleet war"
	)
	assert_eq(AiPhasePlanner.great_power_wars(state, OWNER), 0)


func test_null_inputs_conclude_nothing() -> void:
	assert_eq(
		String(AiPhasePlanner.phase_for(null, _court())), AiPhasePlanner.PHASE_UNKNOWN
	)
	assert_eq(
		String(AiPhasePlanner.phase_for(_config(), null)), AiPhasePlanner.PHASE_UNKNOWN
	)
	assert_eq(AiPhasePlanner.label(AiPhasePlanner.PHASE_UNKNOWN), "—")
	assert_false(AiPhasePlanner.is_war_footing(AiPhasePlanner.PHASE_UNKNOWN))


func test_the_same_state_reads_the_same_footing() -> void:
	var first: Dictionary = AiPhasePlanner.plan(_config(), _court())
	var second: Dictionary = AiPhasePlanner.plan(_config(), _court())

	assert_eq(first, second, "replay-safe: the footing is a pure function")


# --- dispatch: no new voyage on a war footing ---------------------------------


## A court with a harbour at home, an idle Explorer and a squadron in port: the
## published embark step, which the war footing closes.
func _old_world() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 3)
	model.region_id = WorldMap.OLD_WORLD
	model.region_key = "old_world"
	var tiles: Array[Vector2i] = []
	for y in 2:
		for x in 5:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			model.province[model.index_of(x, y)] = 0
			tiles.append(Vector2i(x, y))
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
	model.provinces = [province]
	var sea: Array[Vector2i] = []
	for x in 5:
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Home Waters", sea, Vector2(2.0, 2.0), 5)]
	return model


func _new_world() -> MapModel:
	var model := MapModel.new()
	model.setup(4, 3)
	model.region_id = WorldMap.NEW_WORLD
	model.region_key = "new_world"
	for y in 2:
		for x in 4:
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
	var sea: Array[Vector2i] = []
	for x in 4:
		var index: int = model.index_of(x, 2)
		model.terrain[index] = MapModel.Terrain.OCEAN
		model.sea_zone[index] = 0
		sea.append(Vector2i(x, 2))
	model.sea_zones = [SeaZoneState.create(0, "Far Shore", sea, Vector2(1.5, 2.0), 4)]
	return model


func _world() -> WorldMap:
	var map := WorldMap.new()
	map.add_region(_old_world())
	map.add_region(_new_world())
	map.warp_links = [
		{"from_region": 0, "from_zone": 0, "to_region": 1, "to_zone": 0},
		{"from_region": 1, "from_zone": 0, "to_region": 0, "to_zone": 0},
	]
	return map


## The same court and voyage under one footing. `wants_income` is the court's
## money goal (DR-20261113-19).
func _voyage(
	posture: String, embarked: bool = false, wants_income: bool = false
) -> Dictionary:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet := FleetState.in_port(1, OWNER, 0)
	var unit := CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	if embarked:
		assert_true(bool(CivilianVoyage.embark(old_world, unit, fleet)["ok"]))
	return AiColonisationPlanner.plan(
		_config(), world, 0, old_world, [fleet], [unit], {}, null, posture, wants_income
	)


func test_a_court_at_peace_opens_the_published_voyage() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_PEACE).get("kind", "")), "embark"
	)


func test_a_war_footing_closes_a_new_voyage() -> void:
	assert_true(_voyage(AiPhasePlanner.PHASE_WAR).is_empty(), "the hulls stay home")
	assert_true(
		_voyage(AiPhasePlanner.PHASE_FRONTS).is_empty(),
		"two fronts do not free a squadron either"
	)


func test_an_expedition_already_afloat_keeps_sailing() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_WAR, true).get("kind", "")), "sail",
		"a voyage under way is not abandoned"
	)


func test_an_earning_court_sails_even_on_a_war_footing() -> void:
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_WAR, false, true).get("kind", "")), "embark",
		"the gold that ends the impasse is overseas (DR-20261113-19)"
	)
	assert_eq(
		String(_voyage(AiPhasePlanner.PHASE_FRONTS, false, true).get("kind", "")), "embark",
		"two fronts do not close the one voyage that pays for the war"
	)


## One observer session with the crown's harbour, squadron and Explorer. The
## session is rebuilt per case: a voyage moves the roster it is built from.
func _session(diplomacy: DiplomacyState) -> PlaySession:
	var world: WorldMap = _world()
	var old_world: MapModel = world.region(0)
	var fleet := FleetState.in_port(1, OWNER, 0)
	var unit := CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))
	var play := PlaySession.new()
	play.player_faction = RIVAL
	play.region_index = 0
	play.map_seed = SEED
	play.world = world
	play.model = old_world
	play.diplomacy = diplomacy
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = old_world
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [fleet])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = old_world
	play.civilian_layer.units = [unit]
	play.civilian_layer.regions.set_region(0, [unit])
	play.civilian_layer.regions.set_region(1, [])
	# The court's ledger is read for its money goal (DR-20261113-19).
	play.ensure_ai()
	return play


func test_the_map_adapter_keeps_the_earning_court_s_voyage_open() -> void:
	var peace: PlaySession = _session(_court())
	var quiet: Array[Dictionary] = MapPlayColonisationAi.run(peace)
	assert_eq(quiet.size(), 1, "with no war the published voyage opens")
	assert_eq(String(quiet[0]["kind"]), "embark")
	peace.ship_layer.free()
	peace.civilian_layer.free()

	# A court at war with a thin purse is on earn: the gold across the water is
	# the only thing that ends its impasse (DR-20261113-19).
	var war: DiplomacyState = _court()
	_war(war, RIVAL)
	var poor: PlaySession = _session(war)
	poor.ai.economy_for(OWNER).treasury = 1000
	var earning: Array[Dictionary] = MapPlayColonisationAi.run(poor)
	assert_eq(earning.size(), 1, "a court on earn still reaches for the New World")
	assert_eq(String(earning[0]["kind"]), "embark")
	poor.ship_layer.free()
	poor.civilian_layer.free()


func test_the_map_adapter_closes_the_voyage_of_a_court_that_can_pay() -> void:
	var war: DiplomacyState = _court()
	_war(war, RIVAL)
	var play: PlaySession = _session(war)
	play.ensure_ai()
	play.ai.economy_for(OWNER).treasury = 20000
	var footing: Array[Dictionary] = MapPlayColonisationAi.run(play)
	assert_true(footing.is_empty(), "a funded court keeps its hulls for the fleet")
	assert_false(play.civilian_layer.units[0].is_embarked(), "the Explorer stays ashore")
	play.ship_layer.free()
	play.civilian_layer.free()


# --- dispatch: an overstretched court takes the white peace -------------------


## A declaration by the warmonger at one or two Great Power fronts, then a full
## rival pass where the isolationist puts a white peace to it.
func _offer_peace_to(wars: int) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(RIVAL, OWNER, 1)
	state.relation(RIVAL, OWNER).score = 35.0
	assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, OWNER)["ok"]))
	if wars > 1:
		state.ensure_relation(RIVAL, THIRD, 1)
		assert_true(bool(DiplomacyRules.declare_war(state, RIVAL, THIRD)["ok"]))
	var ai_state := AiState.new()
	ai_state.agendas[RIVAL] = AiAgenda.WARMONGER
	ai_state.agendas[OWNER] = AiAgenda.ISOLATIONIST
	# The declarations above bypass the planner, so the pair cooldown the pass
	# would have written is recorded here: a warmonger may not re-declare the war
	# it just signed away (wiki: diplomacy § Cooldowns).
	ai_state.note_war(RIVAL, OWNER, 1)
	ai_state.note_war(RIVAL, THIRD, 1)
	var posture: String = AiPhasePlanner.phase_for(_config(RIVAL), state)
	var result: Dictionary = AiTurn.run(
		state, AiFixture.world([OWNER, RIVAL, RIVAL, RIVAL]), ai_state,
		1, 4, SEED, {"regiments": {}, "ships": {}}
	)
	return {"state": state, "posture": posture, "trace": result["trace"]}


## The offering court's record in the turn trace.
func _record(trace: Array, faction: int) -> Dictionary:
	for raw: Dictionary in trace:
		if int(raw.get("faction", -1)) == faction:
			return raw
	return {}


func test_a_court_at_one_front_refuses_the_white_peace() -> void:
	var run: Dictionary = _offer_peace_to(1)
	var record: Dictionary = _record(run["trace"], OWNER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_true(
		String(record["message"]).contains("refuses a white peace"),
		"a warmonger at one front keeps its war"
	)
	assert_true((run["state"] as DiplomacyState).relation(RIVAL, OWNER).at_war)


func test_an_overstretched_court_takes_the_white_peace() -> void:
	var run: Dictionary = _offer_peace_to(2)
	var record: Dictionary = _record(run["trace"], OWNER)

	assert_eq(String(run["posture"]), AiPhasePlanner.PHASE_FRONTS)
	assert_eq(String(record["action"]["kind"]), AiDiplomacyPlanner.KIND_OFFER_PEACE)
	assert_false(
		(run["state"] as DiplomacyState).relation(RIVAL, OWNER).at_war,
		"two fronts are one too many: the offer is signed"
	)
	assert_false(
		String(record["message"]).contains("refuses"),
		"the court answers the offer instead of refusing it"
	)


# --- money first: the goal a court reads before its planners ------------------


## The court's purse at one balance; `PlayerEconomy.starting()` carries the
## workers and stores a running court has.
func _purse(treasury: int) -> PlayerEconomy:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.treasury = treasury
	return economy


func test_a_court_short_of_its_muster_reads_earn() -> void:
	var config: AiConfig = _config()
	var thin: PlayerEconomy = _purse(1200)
	var plan: Dictionary = AiIncome.plan(config, thin, true, 1)

	assert_eq(String(plan["goal"]), AiIncome.GOAL_EARN)
	assert_eq(
		int(plan["reserve"]), AiArmyReinforce.muster_floor(config, thin, 1, true),
		"the reserve is the muster the court is saving for"
	)
	assert_eq(int(plan["treasury"]), 1200)
	assert_eq(int(plan["regiments"]), 1)
	assert_eq(AiIncome.label(String(plan["goal"])), "earning")
	assert_true(AiIncome.wants_income(config, thin, true, 1))


func test_a_court_that_can_pay_plays_as_published() -> void:
	var config: AiConfig = _config()
	var rich: PlayerEconomy = _purse(8000)

	assert_eq(AiIncome.goal_for(config, rich, true, 1), AiIncome.GOAL_SPEND)
	assert_eq(AiIncome.label(AiIncome.GOAL_SPEND), "spending")
	assert_false(AiIncome.wants_income(config, rich, true, 1))


func test_a_court_at_peace_keeps_only_its_cash_floor() -> void:
	# The bench measured the peace-time muster reserve: it traded 23 provinces
	# for a standing army (DR-20261113-22), so only a war holds the war chest.
	var config: AiConfig = _config()
	var economy: PlayerEconomy = _purse(1000)
	var target: int = config.parameter("army.regiment_target")

	assert_eq(
		AiIncome.reserve(config, economy, false, 0),
		config.parameter("economy.min_treasury"),
		"a court at peace grows: only its own floor is held back"
	)
	assert_eq(
		AiIncome.reserve(config, economy, false, target),
		config.parameter("economy.min_treasury")
	)
	assert_eq(
		AiIncome.goal_for(config, economy, false, 0), AiIncome.GOAL_SPEND,
		"a thin purse at peace still spends"
	)


func test_a_court_with_no_ledger_keeps_the_published_behaviour() -> void:
	assert_eq(AiIncome.reserve(_config(), null, true, 0), 0)
	assert_eq(AiIncome.goal_for(_config(), null, true, 0), AiIncome.GOAL_SPEND)
	assert_eq(AiIncome.label(""), "spending", "an unknown goal reads as the published one")


func test_an_earning_court_funds_no_study() -> void:
	var config: AiConfig = _config()
	var economy: PlayerEconomy = _purse(1200)
	var reserve: int = AiIncome.reserve(config, economy, true, 1)

	assert_eq(AiResearchPlanner.funding_for(config, economy, reserve), "none")
	assert_ne(
		AiResearchPlanner.funding_for(config, _purse(reserve + 1000), reserve), "none",
		"the surplus above the reserve funds the study"
	)


func test_an_earning_court_bids_no_imports() -> void:
	var config: AiConfig = _config()
	var economy: PlayerEconomy = _purse(1200)
	var reserve: int = AiIncome.reserve(config, economy, true, 1)
	var market := WorldMarket.with_default_prices()

	assert_true(reserve > economy.treasury, "the purse is short of the reserve")
	var plan: Dictionary = AiMarketPlanner.plan(
		config, economy, market, 6, {}, {}, {}, reserve
	)
	assert_true((plan["bids"] as Array).is_empty(), "the reserve is not the auction's to spend")


