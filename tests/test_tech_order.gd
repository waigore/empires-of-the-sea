extends GdToolsTest
## Goal-first ordering of the research queue (wiki: tech-tree § Research Model —
## the goal slot sorts the display only).


func test_the_goal_sits_at_depth_zero() -> void:
	assert_eq(TechOrder.chain_depth("bayonet", "bayonet"), 0)


func test_direct_prerequisites_sit_one_step_back() -> void:
	assert_eq(TechOrder.chain_depth("improved_iron_weapons", "bayonet"), 1)
	assert_eq(TechOrder.chain_depth("crucible_process", "bayonet"), 1)


func test_deeper_ancestors_count_their_steps() -> void:
	assert_eq(TechOrder.chain_depth("organised_regiments", "bayonet"), 2)
	assert_eq(TechOrder.chain_depth("iron_mining", "bayonet"), 2)


func test_a_tech_off_the_path_has_no_depth() -> void:
	assert_eq(TechOrder.chain_depth("crop_rotation", "bayonet"), -1)


func test_an_empty_or_unknown_goal_leaves_every_tech_off_path() -> void:
	assert_eq(TechOrder.chain_depth("bayonet", ""), -1)
	assert_eq(TechOrder.chain_depth("bayonet", "no_such_tech"), -1)
	assert_eq(TechOrder.chain_depth("no_such_tech", "bayonet"), -1)


func test_the_queue_puts_the_goal_path_first() -> void:
	var queue: Array[String] = ["crop_rotation", "iron_mining", "bayonet", "crucible_process"]
	var ordered: Array[String] = TechOrder.sorted(queue, "bayonet")
	assert_eq(ordered[0], "bayonet", "the goal leads")
	assert_eq(ordered[1], "crucible_process", "its prerequisite comes next")
	assert_eq(ordered[2], "iron_mining", "then the deeper ancestor")
	assert_eq(ordered[3], "crop_rotation", "off-path techs trail")


func test_techs_at_one_depth_keep_catalog_order() -> void:
	var queue: Array[String] = ["crucible_process", "improved_iron_weapons"]
	assert_eq(TechOrder.sorted(queue, "bayonet"), ["improved_iron_weapons", "crucible_process"])


func test_without_a_goal_the_queue_keeps_catalog_order() -> void:
	var queue: Array[String] = ["superior_hull_design", "crop_rotation", "printing_press"]
	assert_eq(
		TechOrder.sorted(queue), ["crop_rotation", "printing_press", "superior_hull_design"]
	)


func test_catalog_order_runs_category_then_era_then_name() -> void:
	assert_true(TechOrder.before("saw_mill", "wind_saw_mill"), "era 1 before era 2 in gathering")
	assert_true(TechOrder.before("crop_rotation", "saw_mill"), "same era sorts by name")
	assert_true(TechOrder.before("crop_rotation", "printing_press"), "gathering before labour")
	assert_false(TechOrder.before("printing_press", "crop_rotation"))
