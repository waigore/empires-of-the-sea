extends GdToolsTest
## Military victory (wiki: victory § Current scope: military victory only).
## Pure rules: synthetic worlds only, so the threshold and tie-break are pinned
## without a generated map (REQ-P2-04).


func test_thirty_old_world_provinces_are_not_enough() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 30})
	assert_null(VictoryRules.evaluate(world, 4))


func test_thirty_one_old_world_provinces_win() -> void:
	var world: WorldMap = _world({FactionCatalog.PLAYER_FACTION: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 7)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, FactionCatalog.PLAYER_FACTION)
	assert_eq(victory.type, VictoryState.Type.MILITARY)
	assert_eq(victory.turn_number, 7)
	assert_eq(victory.type_label(), "Military victory")
	assert_true(victory.won_by(FactionCatalog.PLAYER_FACTION))
	assert_eq(
		victory.summary(),
		"Spain — Military victory, turn 7",
		"the record names winner, type and turn"
	)


func test_only_great_powers_are_eligible() -> void:
	var world: WorldMap = _world({6: 40})
	assert_null(VictoryRules.evaluate(world, 3), "a Minor Nation never wins")


func test_shared_threshold_resolves_by_the_smallest_player_id() -> void:
	# Two qualified crowns: the smallest player id wins even though the other
	# holds more provinces (wiki: victory § Tie-breaking).
	var world: WorldMap = _world({4: 40, 2: 31})
	var victory: VictoryState = VictoryRules.evaluate(world, 3)
	assert_not_null(victory)
	assert_eq(victory.winner_player_id, 2)


func test_new_world_provinces_do_not_count() -> void:
	var world: WorldMap = _old_and_new(
		{FactionCatalog.PLAYER_FACTION: 10}, {FactionCatalog.PLAYER_FACTION: 30}
	)
	assert_null(VictoryRules.evaluate(world, 3))


func test_an_existing_victory_is_never_overwritten() -> void:
	var first: VictoryState = VictoryRules.evaluate(_world({1: 31}), 3)
	var later: WorldMap = _world({2: 40})
	assert_eq(VictoryRules.resolve(first, later, 9), first)


func test_qualified_crowns_are_ordered_and_filtered() -> void:
	var world: WorldMap = _world({4: 31, 1: 31, 3: 30})
	var ids: Array[int] = VictoryRules.qualified(world)
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], 1)
	assert_eq(ids[1], 4)


func _world(counts: Dictionary) -> WorldMap:
	return _old_and_new(counts, {})


func _old_and_new(old_world: Dictionary, new_world: Dictionary) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(_model(old_world, FactionCatalog.OLD_WORLD))
	world.add_region(_model(new_world, FactionCatalog.NEW_WORLD))
	return world


func _model(counts: Dictionary, region_id: int) -> MapModel:
	var model := MapModel.new()
	model.setup(1, 1)
	model.region_id = region_id
	model.faction_ids = FactionCatalog.ids_in_region(region_id)
	var next_id: int = 0
	for faction_id: int in counts.keys():
		for _index in int(counts[faction_id]):
			var tiles: Array[Vector2i] = []
			model.provinces.append(
				ProvinceState.create(
					next_id, "Province %d" % next_id, tiles, Vector2.ZERO, 1, faction_id
				)
			)
			next_id += 1
	return model
