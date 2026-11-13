extends GdToolsTest
## The rival objective ledger (docs/ai.md; issue #491 T1): one 0–100 currency,
## a rank pass and an allocate pass, the claims a court keeps, and the trace
## rows that explain a starved objective instead of hiding it.

const OWNER: int = 0
const RIVAL: int = 1
const SEED: int = 1500


func _config(faction: int = OWNER) -> AiConfig:
	return AiConfig.build(faction, SEED)


# --- the one currency --------------------------------------------------------


func test_every_planner_scale_normalizes_into_the_same_currency() -> void:
	assert_eq(AiUtility.clamp_utility(-10), 0)
	assert_eq(AiUtility.clamp_utility(140), 100)
	assert_eq(AiUtility.scale(50, 0, 100), 50)
	assert_eq(AiUtility.scale(0, 50, 150), 0)
	assert_eq(AiUtility.scale(150, 50, 150), 100)
	assert_eq(AiUtility.scale(7, 5, 5), 100, "a flat band tops out")
	assert_eq(AiUtility.ratio(1, 2), 50)
	assert_eq(AiUtility.ratio(3, 2), 100, "a ratio above the whole is clamped")
	assert_eq(AiUtility.ratio(0, 0), 0)
	assert_eq(AiUtility.ratio(2, 0), 100, "strength against nothing reads full")


func test_the_rank_modifier_is_per_mille_and_clamped() -> void:
	assert_eq(AiUtility.modified(80, 1000), 80)
	assert_eq(AiUtility.modified(80, 600), 48, "a war footing scales a voyage down")
	assert_eq(AiUtility.modified(80, 1500), 100, "a boost never passes the scale")
	assert_eq(AiUtility.modified(80, 0), 0)


# --- the allocate pass -------------------------------------------------------


func _hull_objective(objective_id: String, utility: int, hulls: int = 1) -> AiObjective:
	return AiObjective.create(objective_id, "expansion", utility, {"hull": hulls})


func test_claims_follow_rank_order() -> void:
	var top: AiObjective = _hull_objective("colonise.a", 80)
	var bottom: AiObjective = _hull_objective("colonise.b", 40)
	var report: Dictionary = AiObjectiveLedger.run([bottom, top], {"hull": 1})

	assert_eq(int(report["ranked"]), 2)
	assert_eq(int(report["funded"]), 1, "one hull funds exactly one voyage")
	assert_eq(top.status, AiObjective.STATUS_FUNDED)
	assert_eq(bottom.status, AiObjective.STATUS_DEFERRED)
	assert_eq(int(bottom.claim["hull"]), 0)
	assert_eq(int(bottom.shortfall()["hull"]), 1, "the shortfall is named")
	assert_eq(int(report["pools"]["hull"]), 0, "a grant spends the pool")


func test_a_deferred_objective_names_its_shortfall_in_the_line() -> void:
	var objective: AiObjective = AiObjective.create(
		"colonise.new_world", "expansion", 50, {"hull": 1, "civilian": 1}
	)
	var report: Dictionary = AiObjectiveLedger.run([objective], {"hull": 0, "civilian": 1})

	assert_eq(objective.status, AiObjective.STATUS_DEFERRED)
	assert_true(String(report["lines"][0]).contains("hull 0/1"))
	assert_true(String(report["lines"][0]).contains("civilian 1/1"))
	assert_eq(String(report["lines"][0]), "colonise.new_world u50 hull 0/1, civilian 1/1 deferred")


func test_a_blocked_objective_claims_nothing_and_keeps_its_reason() -> void:
	var pools: Dictionary = {"hull": 2}
	var blocked: AiObjective = _hull_objective("colonise.new_world", 50).block("no harbour")
	var report: Dictionary = AiObjectiveLedger.run([blocked], pools)

	assert_eq(blocked.status, AiObjective.STATUS_BLOCKED)
	assert_eq(int(report["blocked"]), 1)
	assert_eq(int(report["funded"]), 0)
	assert_eq(int(pools["hull"]), 2, "a blocked aim spends nothing")
	assert_eq(String(report["lines"][0]), "colonise.new_world u50 hull 0/1 blocked (no harbour)")


func test_children_are_walked_after_their_parent() -> void:
	var child: AiObjective = _hull_objective("expedition.hull", 60)
	var parent: AiObjective = AiObjective.create(
		"colonise.new_world", "expansion", 80, {"hull": 1}
	).with_child(child)
	var order: Array[AiObjective] = AiObjectiveLedger.walk([parent])

	assert_eq(order.size(), 2)
	assert_eq(order[0].id, "colonise.new_world")
	assert_eq(order[1].id, "expedition.hull")


func test_the_same_state_ranks_the_same_way() -> void:
	var first: Array[AiObjective] = [
		_hull_objective("b", 50), _hull_objective("a", 50), _hull_objective("c", 90),
	]
	var second: Array[AiObjective] = [
		_hull_objective("c", 90), _hull_objective("b", 50), _hull_objective("a", 50),
	]
	var left: Array[AiObjective] = AiObjectiveLedger.rank(first)
	var right: Array[AiObjective] = AiObjectiveLedger.rank(second)

	assert_eq(left[0].id, "c")
	assert_eq(left[1].id, "a", "the id breaks a utility tie")
	assert_eq(left[2].id, "b")
	assert_eq(left[1].id, right[1].id, "order of emission never decides the rank")


func test_a_modifier_reorders_the_rank_without_deleting_an_objective() -> void:
	var colony: AiObjective = _hull_objective("colonise.new_world", 50)
	var fleet: AiObjective = AiObjective.create("navy.sortie", "naval", 60, {"hull": 1})
	var ranked: Array[AiObjective] = AiObjectiveLedger.rank(
		[colony, fleet], {"expansion": 600, "naval": 1400}
	)

	assert_eq(ranked[0].id, "navy.sortie", "the war footing lifts the fleet")
	assert_eq(ranked[1].id, "colonise.new_world", "the voyage stays ranked, only cheaper")


# --- the emitter -------------------------------------------------------------


func _readings() -> Dictionary:
	return {
		"posture": AiPhasePlanner.PHASE_PEACE,
		"at_war": false,
		"war_desire": 40,
		"regiments": 1,
		"muster_due": true,
		"muster_floor": 300,
		"ships": 2,
		"warships": 4,
		"warship_price": 5500,
		"hostile_ships": 0,
		"hostile_warships": 0,
		"treasury": 2000,
		"reserve": 500,
		"goal": AiIncome.GOAL_SPEND,
		"colony_target": true,
		"harbour": true,
		"idle_hulls": 1,
		"explorer_ready": true,
		"voyage_afloat": false,
		"cargo_shortfall": 0,
		"research_slots": 1,
		"research_funding": 2,
		"research_cost": 150,
	}


## Walks the ledger tree: T2 prices the expedition on its children.
func _by_id(objectives: Array[AiObjective], objective_id: String) -> AiObjective:
	for objective: AiObjective in objectives:
		if objective.id == objective_id:
			return objective
		var found: AiObjective = _by_id(objective.children, objective_id)
		if found != null:
			return found
	return null


func _child_ids(objective: AiObjective) -> Array[String]:
	var ids: Array[String] = []
	for child: AiObjective in objective.children:
		ids.append(child.id)
	return ids


func test_the_plan_prices_the_expedition_the_muster_and_the_order() -> void:
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(_readings())

	var colony: AiObjective = _by_id(objectives, "colonise.new_world")
	assert_true(colony != null, "the expedition is always priced while it has a target")
	assert_eq(int(colony.utility), AiObjectivesPlan.W_PROVINCES_NEW)
	assert_eq(_child_ids(colony), ["expedition.hull", "expedition.explorer"])
	assert_eq(int(_by_id(objectives, "expedition.hull").cost["hull"]), 1)
	assert_eq(int(_by_id(objectives, "expedition.explorer").cost["civilian"]), 1)
	assert_eq(_by_id(objectives, "muster.line").cost["regiment"], 1)
	assert_eq(int(_by_id(objectives, "war.declare").cost["orders"]), 1)
	assert_eq(int(_by_id(objectives, "research.study").utility), 55, "the funding step lifts the study")


func test_a_war_footing_prices_the_peace_window_and_the_sortie() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["posture"] = AiPhasePlanner.PHASE_WAR
	readings["war_desire"] = 70
	readings["hostile_ships"] = 3
	readings["hostile_warships"] = 3
	var objectives: Array[AiObjective] = AiObjectivesPlan.build(readings)

	assert_eq(int(_by_id(objectives, "peace.window").utility), 30)
	assert_eq(
		int(_by_id(objectives, "expedition.peace").cost["orders"]), 1,
		"the expedition's peace window costs the court's order"
	)
	assert_true(_by_id(objectives, "navy.sortie") != null)
	assert_eq(_by_id(objectives, "navy.build"), null, "a court with hulls sorties instead of building")


func test_a_court_with_no_harbour_blocks_the_hull_with_a_reason() -> void:
	var readings: Dictionary = _readings()
	readings["harbour"] = false
	var hull: AiObjective = _by_id(AiObjectivesPlan.build(readings), "expedition.hull")

	assert_eq(hull.status, AiObjective.STATUS_BLOCKED)
	assert_eq(hull.blocked, "no harbour")


func test_a_starved_expedition_names_the_child_it_lacks() -> void:
	# No squadron to spare: the hull child defers and the trace says so, instead
	# of the voyage vanishing without a word (issue #476, #497).
	var readings: Dictionary = _readings()
	readings["idle_hulls"] = 0
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings), {"hull": 0, "civilian": 1, "orders": 1}
	)
	var line: String = ""
	for raw: Variant in report["lines"]:
		if String(raw).begins_with("expedition.hull"):
			line = String(raw)

	assert_true(line.contains("deferred"), "the starved hull is reported: %s" % line)
	assert_true(line.contains("hull 0/1"), "with its shortfall: %s" % line)


func test_a_court_with_no_fighting_hull_lays_one_down() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 0
	readings["hostile_warships"] = 2
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")

	assert_true(build != null, "a court at war with no fighting hull builds one")
	assert_eq(int(build.utility), AiObjectivesPlan.W_NAVY_BUILD, "the yard leads")
	assert_eq(int(build.cost["treasury"]), 5500, "priced at the cheapest warship")
	assert_eq(int(build.cost["hull"]), 1)


func test_a_court_outmatched_on_its_own_coast_replaces_before_it_expands() -> void:
	var readings: Dictionary = _readings()
	readings["at_war"] = true
	readings["warships"] = 1
	readings["hostile_warships"] = 3
	var build: AiObjective = _by_id(AiObjectivesPlan.build(readings), "navy.build")

	assert_true(build != null, "outmatched, the court replaces its hulls")
	assert_true(
		int(build.utility) > int(AiObjectivesPlan.W_NAVY),
		"and the replacement outranks a sortie"
	)


func test_a_court_at_peace_lays_down_nothing() -> void:
	var readings: Dictionary = _readings()
	readings["warships"] = 0
	assert_eq(_by_id(AiObjectivesPlan.build(readings), "navy.build"), null)


# --- the adapter and the trace ----------------------------------------------


func _court() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.reset(1)
	state.ensure_relation(OWNER, RIVAL, 1)
	return state


func _session(diplomacy: DiplomacyState) -> PlaySession:
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
	var new_world := MapModel.new()
	new_world.setup(3, 2)
	new_world.region_id = WorldMap.NEW_WORLD
	new_world.region_key = "new_world"
	var world := WorldMap.new()
	world.add_region(model)
	world.add_region(new_world)
	var play := PlaySession.new()
	play.player_faction = RIVAL
	play.map_seed = SEED
	play.world = world
	play.model = model
	play.diplomacy = diplomacy
	play.ship_layer = ShipLayer.new()
	play.ship_layer.model = model
	play.ship_layer.world = world
	play.ship_layer.regions.set_region(0, [FleetState.in_port(1, OWNER, 0)])
	play.ship_layer.regions.set_region(1, [])
	play.civilian_layer = CivilianLayer.new()
	play.civilian_layer.model = model
	play.civilian_layer.units = [CivilianState.create(1, OWNER, "explorer", Vector2i(0, 0))]
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	play.civilian_layer.regions.set_region(1, [])
	play.ensure_ai()
	return play


func test_the_adapter_stamps_a_ledger_for_every_planning_court() -> void:
	var play: PlaySession = _session(_court())
	var ledgers: Dictionary = MapPlayObjectivesAi.run(play)

	assert_true(ledgers.has(OWNER))
	var report: Dictionary = ledgers[OWNER]
	assert_true(int(report["ranked"]) > 0)
	assert_true((report["lines"] as Array).size() >= int(report["ranked"]))
	var colony: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "colonise.new_world":
			colony = row
	assert_false(colony.is_empty(), "the court with a harbour prices the expedition")
	assert_eq(String(colony["status"]), AiObjective.STATUS_FUNDED)
	var claim: Dictionary = play.ai.objectives_for(OWNER)
	assert_eq(int(claim["turn"]), play.turn, "the claim is kept on the court's state")
	assert_eq(int(claim["ranked"]), int(report["ranked"]))
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_turn_trace_carries_every_objective() -> void:
	var play: PlaySession = _session(_court())
	var ledgers: Dictionary = MapPlayObjectivesAi.run(play)
	var merged: Dictionary = AiTurnLog.record(play, [], [], {"factions": {}}, [], ledgers)
	var bucket: Dictionary = (merged["factions"] as Dictionary)[OWNER]

	assert_eq(String(bucket["phase"]), AiPhasePlanner.PHASE_PEACE)
	assert_eq(String(bucket["goal"]), AiIncome.GOAL_SPEND)
	var ledger: Dictionary = bucket["objectives"]
	assert_eq(int(ledger["ranked"]), int((ledgers[OWNER] as Dictionary)["ranked"]))
	for row: Dictionary in ledger["rows"]:
		assert_true(row.has("utility"), "every row carries its utility")
		assert_true(row.has("cost"), "every row carries its cost")
		assert_true(row.has("claim"), "every row carries its claim")
		assert_true(row.has("status"), "every row carries its status")
	play.ship_layer.free()
	play.civilian_layer.free()


func test_the_ledger_prices_the_standing_study_not_the_war_chest() -> void:
	# The surplus ladder reads the money-goal reserve, so at war no slot pays the
	# published preset; the one standing study at Low is what the court actually
	# spends, and the ledger must name that figure (issue #490).
	var court: DiplomacyState = _court()
	court.relation(OWNER, RIVAL).at_war = true
	var play: PlaySession = _session(court)
	play.ai.economy_for(OWNER).treasury = 500
	var report: Dictionary = MapPlayObjectivesAi.court(play, OWNER)
	var study: Dictionary = {}
	for row: Dictionary in report["objectives"]:
		if String(row["id"]) == "research.study":
			study = row
	assert_false(study.is_empty(), "the study is priced")
	assert_eq(
		int((study["cost"] as Dictionary).get("treasury", 0)), 50,
		"one standing study at Low, not three slots on the war chest"
	)


## The voyage musters behind the ledger's claim (issue #491 T2): a funded hull
## opens the harbour gate, a deferred one leaves the Explorer ashore.
func test_the_muster_gate_reads_the_ledger_hull_claim() -> void:
	var play: PlaySession = _session(_court())
	MapPlayObjectivesAi.run(play)
	var claim: Dictionary = play.ai.objectives_for(OWNER)
	assert_true((claim["funded_ids"] as Array).has("expedition.hull"))
	var open_port: Vector2i = MapPlayCivilianAi._muster_port(
		play, OWNER, play.model.region_id, play.model
	)
	assert_true(open_port.x >= 0, "a funded hull opens the muster")

	# The same ledger with the hull starved: the gate stays shut.
	play.ai.note_objectives(OWNER, {
		"phase": AiPhasePlanner.PHASE_PEACE, "ranked": 1, "funded": 0, "lines": [],
		"objectives": [{"id": "expedition.hull", "status": AiObjective.STATUS_DEFERRED}],
	}, play.turn)
	var shut: Vector2i = MapPlayCivilianAi._muster_port(
		play, OWNER, play.model.region_id, play.model
	)
	assert_eq(shut, CivilianState.NO_TILE, "a deferred hull keeps the Explorer ashore")
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #497's scripted case: a court at peace, with a harbour, a free hull and
## an Explorer, issues its colonisation order on the turn the ledger funds the
## claim — no 200 turns of luck.
func test_a_peaceful_court_with_a_funded_claim_issues_the_voyage() -> void:
	var play: PlaySession = _session(_court())
	MapPlayObjectivesAi.run(play)
	var trace: Array[Dictionary] = MapPlayColonisationAi.run(play)

	assert_eq(trace.size(), 1, "the court under way gets one step")
	assert_eq(String(trace[0]["kind"]), "embark")
	assert_eq(int(trace[0]["faction"]), OWNER)
	play.ship_layer.free()
	play.civilian_layer.free()


## Issue #500: a court at war with a hostile squadron and a funded build aim
## lays a warship down through the yard, not just on paper.
func test_a_funded_navy_build_lays_a_warship_down() -> void:
	var war: DiplomacyState = _court()
	war.relation(OWNER, RIVAL).at_war = true
	var play: PlaySession = _session(war)
	var economy: PlayerEconomy = play.ai.economy_for(OWNER)
	economy.treasury = 20000
	economy.stockpile["lumber"] = 10
	economy.stockpile["fabric"] = 10
	economy.tech_unlocked[ShipEconomy.tech_for("sloop")] = true
	var report: Dictionary = MapPlayObjectivesAi.run(play)
	assert_true(
		((report[OWNER] as Dictionary)["lines"] as Array).any(
			func(line: Variant) -> bool: return String(line).begins_with("navy.build")
		),
		"the court at war prices its yard"
	)
	assert_true(
		(play.ai.objectives_for(OWNER)["funded_ids"] as Array).has("navy.build"),
		"a rich court funds it"
	)
	var cargo: Dictionary = MapPlayCargoAi.run(play, OWNER, economy)
	assert_false((cargo.get("warship", {}) as Dictionary).is_empty(), "the hull is laid down")
	assert_eq(
		String((cargo["warship"] as Dictionary)["type_id"]), "sloop",
		"the cheapest warship its techs open"
	)
	play.ship_layer.free()
	play.civilian_layer.free()


# --- the save round-trip -----------------------------------------------------


func test_a_save_round_trips_the_ledger() -> void:
	var state := AiState.new()
	state.note_objectives(
		OWNER,
		{
			"phase": AiPhasePlanner.PHASE_WAR, "ranked": 4, "funded": 3,
			"lines": ["colonise.new_world u50 hull 0/1 deferred"],
		},
		7
	)
	var restored := AiState.from_dict(state.to_dict())
	var claim: Dictionary = restored.objectives_for(OWNER)

	assert_eq(int(claim["turn"]), 7)
	assert_eq(String(claim["phase"]), AiPhasePlanner.PHASE_WAR)
	assert_eq(int(claim["ranked"]), 4)
	assert_eq(int(claim["funded"]), 3)
	assert_eq(String((claim["lines"] as Array)[0]), "colonise.new_world u50 hull 0/1 deferred")


func test_an_old_save_reads_an_empty_ledger() -> void:
	var restored := AiState.from_dict({"difficulty": Difficulty.DEFAULT})

	assert_true(restored.objectives_for(OWNER).is_empty(), "an old save simply has no ledger")
	assert_eq(int(restored.to_dict().get("objective_claims", {}).size()), 0)
