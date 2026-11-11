extends GdToolsTest
## Rival land reinforcement (wiki: ai-architecture § Land reinforcement,
## growth-stage-planner § Recruitment modulation; DR-20261111-04). A rival court
## raises a line regiment from its own ledger through the same muster the human
## drill yard uses — one a turn, the strongest legal pattern, and only while its
## economy can carry the price (REQ-P2-03, REQ-P3-03).

const OWNER: int = 2
const HUMAN: int = 1

const AiFixture = preload("res://tests/ai_fixture.gd")


func _config() -> AiConfig:
	return AiConfig.build(OWNER, 1500)


## A court with its own ledger: treasury and the opening stock of fabric and
## cast iron the line rows need.
func _economy(treasury: int = 12000, peasants: int = 6) -> PlayerEconomy:
	var economy := PlayerEconomy.starting()
	economy.treasury = treasury
	economy.workers = WorkerPool.make(peasants)
	return economy


# --- planner ----------------------------------------------------------------


func test_a_rival_musters_the_strongest_line_it_can_pay_for() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 5, false)

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
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(4000), 5, false)

	assert_eq(String(plan["muster"]), "peasant_levies")
	var priced: Dictionary = AiArmyReinforce.plan(_config(), _economy(1500), 5, false)
	assert_eq(String(priced["muster"]), "", "nothing payable leaves the floor alone")
	assert_true((priced["reasons"] as Array).has("nothing payable"))


func test_a_court_at_target_strength_waits_and_a_war_lifts_the_target() -> void:
	var peace: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 8, false)
	assert_eq(String(peace["muster"]), "", "eight regiments is the peace target")
	assert_eq(int(peace["target"]), 8)

	var war: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 8, true)
	assert_eq(int(war["target"]), 12, "the war footing raises the target by four")
	assert_eq(String(war["muster"]), "arquebusiers", "a court at war arms up")

	var full: Dictionary = AiArmyReinforce.plan(_config(), _economy(), 12, true)
	assert_eq(String(full["muster"]), "", "the war target is a ceiling too")


func test_a_thin_labour_pool_stops_the_muster() -> void:
	var plan: Dictionary = AiArmyReinforce.plan(_config(), _economy(12000, 3), 5, false)

	assert_eq(String(plan["muster"]), "", "the fields keep their hands")
	assert_true((plan["reasons"] as Array).has("labour floor"))


func test_a_researched_pattern_is_the_one_that_musters() -> void:
	var economy: PlayerEconomy = _economy()
	economy.tech_unlocked["weapon_craftsmanship"] = true
	var plan: Dictionary = AiArmyReinforce.plan(_config(), economy, 5, false)

	assert_eq(String(plan["muster"]), "musketeers", "the newest legal line wins")


# --- map adapter ------------------------------------------------------------


## One peace-time world: England's seat at province 0, France's at province 1,
## with a rival ledger already resolved for France.
func _play(treasury: int = 12000, with_ledger: bool = true) -> PlaySession:
	var world: WorldMap = AiFixture.land_world([HUMAN, OWNER], {0: true, 1: true})
	var model: MapModel = world.region(0)
	var armies: Array[ArmyState] = [
		ArmyState.muster(1, HUMAN, 0, true, ["peasant_levies"] as Array[String], 1),
		ArmyState.muster(
			2, OWNER, 1, true, ["peasant_levies", "peasant_levies"] as Array[String], 101
		),
	]
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
	court.ensure_relation(HUMAN, OWNER, 1)
	play.diplomacy = court
	play.army_layer = layer
	play.map_seed = 1500
	if with_ledger:
		play.ai = AiState.new()
		play.ai.economies[OWNER] = _economy(treasury)
	return play


func test_the_map_pass_musters_a_rival_from_its_own_ledger() -> void:
	var play: PlaySession = _play(12000)
	var economy: PlayerEconomy = play.ai.economies[OWNER]
	var before: int = play.army_layer.regiment_count_all(OWNER)
	var peasants: int = economy.available_peasants()

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 1, "a muster and nothing else in peace")
	assert_eq(String(trace[0]["kind"]), MapPlayArmyAi.KIND_REINFORCE)
	assert_eq(String(trace[0]["type"]), "arquebusiers")
	assert_eq(play.army_layer.regiment_count_all(OWNER), before + 1)
	assert_eq(economy.available_peasants(), peasants - 1, "one peasant joins the colours")
	assert_true(
		economy.treasury < 12000, "the court's own purse pays, never the crown's"
	)
	var home: ArmyState = ArmyTraining.home_army(play.army_layer.armies, OWNER)
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
		assert_eq(int(record["faction"]), OWNER, "the crown musters its own men")
	play.army_layer.free()


func test_a_court_without_a_ledger_never_musters() -> void:
	var play: PlaySession = _play(12000, false)
	var before: int = play.army_layer.regiment_count_all(OWNER)

	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)

	assert_eq(trace.size(), 0, "no ledger, no muster")
	assert_eq(play.army_layer.regiment_count_all(OWNER), before)
	play.army_layer.free()


func test_the_observer_log_reads_the_muster() -> void:
	var play: PlaySession = _play(12000)
	var trace: Array[Dictionary] = MapPlayArmies.run_ai(play)
	var merged: Dictionary = AiTurnLog.record(play, trace, [], {})
	var record: Dictionary = merged["factions"][OWNER]
	assert_eq(int(record["actions"].get("reinforce", 0)), 1, "one regiment raised")
	var lines: Array = record["events"]
	assert_true(lines.size() > 0, "the event list names the pattern")
	play.army_layer.free()
