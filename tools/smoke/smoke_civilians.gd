extends RefCounted
## Sixth step of the e2e smoke: the player civilian path — select, march, one
## work order per type, a cancel, and a hire queued for Build/work. The tiles
## that must resolve on end turn are left on `run.works` for the turn step.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeFind = preload("res://tools/smoke/smoke_find.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	run.works = {
		"improvement": Vector2i(-1, -1),
		"road": Vector2i(-1, -1),
		"prospect": Vector2i(-1, -1),
	}
	var works: Dictionary = run.works
	var explorer: CivilianState = SmokeFind.civilian_of(screen, "explorer")
	var builder: CivilianState = SmokeFind.civilian_of(screen, "builder")
	var engineer: CivilianState = SmokeFind.civilian_of(screen, "engineer")
	run.check(explorer != null and builder != null and engineer != null, "starting civilians present")
	if explorer == null or builder == null or engineer == null:
		return

	MapPlayInput.on_tapped(
		screen.play, MapGeo.tile_center(explorer.tile.x, explorer.tile.y, MapScreen.TILE_SIZE)
	)
	await run.tree.process_frame
	run.check(screen.civilian_layer.selected_unit == explorer, "explorer selection sticks")
	run.check(screen.hud.panels.is_civilian_panel_open(), "civilian dossier opens")

	var march_tiles: Array[Vector2i] = CivilianMovement.valid_tiles(screen.model, explorer)
	run.check(not march_tiles.is_empty(), "explorer has a march tile")
	if not march_tiles.is_empty():
		var dest: Vector2i = march_tiles[0]
		var from: Vector2i = explorer.tile
		run.check(
			MapPlayCivilians.try_move(
				screen.play, MapGeo.tile_center(dest.x, dest.y, MapScreen.TILE_SIZE)
			),
			"explorer marches"
		)
		run.check(explorer.tile == dest and explorer.tile != from, "explorer tile advances")

	var explore_tile: Vector2i = SmokeFind.uncharted_land_tile(screen)
	run.check(explore_tile.x >= 0, "uncharted land available")
	if explore_tile.x >= 0:
		explorer.tile = explore_tile
		explorer.moved = false
		screen.civilian_layer.select(explorer)
		MapPlayCivilians.on_action(screen.play, "explore")
		run.check(
			explorer.is_working() and explorer.work_action() == "explore", "explore order starts"
		)
		MapPlayCivilians.on_cancel(screen.play)
		run.check(explorer.is_idle(), "explore order cancels")

	var mineral: Vector2i = SmokeFind.mineral_tile(screen)
	run.check(mineral.x >= 0, "survey ground available")
	if mineral.x >= 0:
		explorer.tile = mineral
		screen.civilian_layer.select(explorer)
		run.check(
			screen.overlay.survey_tiles.has(mineral),
			"explorer marks the survey ground"
		)
		MapPlayCivilians.on_action(screen.play, "prospect")
		run.check(
			explorer.is_working() and explorer.work_action() == "prospect",
			"prospect order starts"
		)
		works["prospect"] = mineral

	var work_tile: Vector2i = SmokeFind.owned_resource_tile(screen, mineral)
	run.check(work_tile.x >= 0, "owned resource tile for builder")
	if work_tile.x >= 0:
		builder.tile = work_tile
		var resource: int = screen.model.resource_at(work_tile.x, work_tile.y)
		if ImprovementCatalog.needs_prospecting(resource):
			screen.land_works.set_prospected(
				MapScreen.PLAYER_FACTION, screen.model, work_tile
			)
		screen.civilian_layer.select(builder)
		MapPlayCivilians.on_action(screen.play, "build_improvement")
		run.check(builder.is_working(), "builder improvement starts")
		works["improvement"] = work_tile

	var road_tile: Vector2i = SmokeFind.owned_roadable_tile(screen, [work_tile, mineral])
	run.check(road_tile.x >= 0, "owned roadable tile for engineer")
	if road_tile.x >= 0:
		engineer.tile = road_tile
		screen.civilian_layer.select(engineer)
		var options: Array[Dictionary] = CivilianWork.options(
			screen.model, engineer, screen.land_works, screen.civilian_layer.units,
			screen.stockpile, screen.visibility
		)
		run.check(SmokeFind.options_has(options, "build_road"), "engineer offers build_road")
		run.check(SmokeFind.options_has(options, "build_port"), "engineer offers build_port")
		run.check(SmokeFind.options_has(options, "build_fort"), "engineer offers build_fort")
		MapPlayCivilians.on_action(screen.play, "build_road")
		run.check(
			engineer.is_working() and engineer.work_action() == "build_road", "road order starts"
		)
		works["road"] = road_tile

	var units_before: int = screen.civilian_layer.units.size()
	var capital_world: Vector2 = (
		screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	)
	MapPlayInput.select_province(screen.play, screen.capital_province, capital_world)
	await run.tree.process_frame
	MapPlayInput.on_panel_action(screen.play, "train_explorer")
	run.check(
		screen.play.economy.economy.recruits.pending(RecruitQueue.KIND_CIVILIAN, "explorer") == 1,
		"capital queues an explorer for Build/work"
	)
	run.check(
		screen.civilian_layer.units.size() == units_before,
		"the hire waits for the turn to close"
	)
	works["hire"] = units_before
	# The dossier's rail block is a reading of the crown's roads: with no road to
	# upgrade it offers no press (DR-20261117-10).
	run.check(
		screen.hud.panels.panel._rail.rows().is_empty(),
		"no rail block without a road to upgrade"
	)
