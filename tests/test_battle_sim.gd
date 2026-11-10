extends GdToolsTest
## The Battle Simulator's rules glue (`BattleScenario`) and its scene. The
## sandbox must run the live Quick Battle resolver, not a parallel model
## (REQ-P2-03); the screen must paint the record it gets back.

const SIM_SCENE: PackedScene = preload("res://scenes/battle_sim.tscn")


func test_the_scenario_builds_the_requested_battle() -> void:
	var spec: Dictionary = {
		"attacker": ["musketeers", "musketeers", "musketeers", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": 2, "terrain": "woods", "seed": 3,
	}
	var result: Dictionary = BattleScenario.fight(spec)
	var report: Dictionary = result["report"]
	var quick: Dictionary = report["quick"]

	assert_eq(int(report["fort_level"]), 2)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(String(quick["terrain"]), "woods")
	assert_eq(String(quick["terrain_label"]), "Woods")
	assert_eq(int(quick["guns_start"]), 2, "a stone fort fields two emplaced guns")
	assert_eq(int(quick["lanes"]["wall"]), 3)
	assert_eq(int(quick["lanes"]["behind"]), 1)
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_eq(int(quick["attacker_start"]), 4)
	assert_eq(int(quick["defender_start"]), 4)


func test_the_scenario_runs_the_live_resolver() -> void:
	var spec: Dictionary = {
		"attacker": ["guards", "guards", "guards", "guards", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers"], "fort": 1, "terrain": "town",
		"attacker_plan": "aggressive", "defender_plan": "balanced", "seed": 11,
	}
	var first: Dictionary = BattleScenario.fight(spec)
	var scene: Dictionary = BattleScenario.build(spec)
	var direct: Dictionary = QuickBattle.resolve_exchange(
		scene["model"], scene["armies"], scene["province"], scene["defender"],
		scene["attacker"], false, scene["context"]
	)
	var sandbox: Dictionary = first["report"]

	assert_eq(int(sandbox["outcome"]), int(direct["outcome"]))
	assert_eq(
		(sandbox["defender_lost"] as Array).size(),
		(direct["defender_lost"] as Array).size()
	)
	assert_eq(
		(sandbox["attacker_lost"] as Array).size(),
		(direct["attacker_lost"] as Array).size()
	)
	assert_eq(String(sandbox["quick"]["defender_plan"]), "balanced")


func test_the_scenario_normalises_unknown_types() -> void:
	var scene: Dictionary = BattleScenario.build({
		"attacker": ["not_a_regiment"], "defender": ["pikemen"], "terrain": "open",
	})
	var armies: Array[ArmyState] = scene["armies"]
	assert_eq(armies[1].count(), 1)
	assert_eq(armies[1].type_of(armies[1].regiments[0]), RegimentCatalog.DEFAULT_TYPE)


func test_a_field_scenario_has_no_wall() -> void:
	var result: Dictionary = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers"], "defender": ["pikemen", "pikemen"],
		"fort": 0, "terrain": "hill",
	})
	var quick: Dictionary = result["report"]["quick"]
	assert_eq(String(result["report"]["battle_mode"]), "field")
	assert_true((quick["gates"] as Dictionary).is_empty(), "no fort, no gates")
	assert_eq(String(quick["terrain"]), "hill")


func test_every_ground_paints() -> void:
	var field := QuickBattleField.new()
	field.custom_minimum_size = Vector2(480, 320)
	field.size = Vector2(480, 320)
	add_child(field)
	for terrain: String in ["open", "hill", "woods", "town", "swamp"]:
		field.terrain = terrain
		field.fort_level = 3 if terrain == "town" else 0
		field.gates_broken = 2
		field.attacker_count = 4
		field.defender_count = 4
		field.attacker_health = []
		field.defender_health = []
		field.queue_redraw()
		await get_tree().process_frame
	assert_eq(field.terrain, "swamp")
	field.free()


func test_the_simulator_scene_fights_and_steps() -> void:
	var screen: BattleSimScreen = SIM_SCENE.instantiate()
	add_child(screen)
	await get_tree().process_frame

	screen._fight()
	assert_false(screen._result.is_empty(), "Fight resolves the current setup")
	assert_true(screen._log.text.contains("ROUND"), "the despatch is printed")
	assert_true(screen._log.text.contains("OUTCOME"))
	assert_true(screen._field.fort_level >= 0)

	screen._step()
	assert_true(screen._status.text.contains("Round") or screen._status.text.contains("No rounds"))
	screen._reset()
	assert_true(screen._result.is_empty())
	assert_eq(screen._field.attacker_count, 0)

	screen.free()
