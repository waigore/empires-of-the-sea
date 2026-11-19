extends RefCounted
## Second step of the e2e smoke: the map the chart handed over — its provinces,
## sea zones, spawned hulls, canvas, HUD, leaders, court charts and both regions —
## then the pause menu's save through its own browser (docs/testing.md § E2E
## smoke). Nothing here places an order; the turn is still the launch's turn 1.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeRun = preload("res://tools/smoke/smoke_run.gd")
const SmokeLaunch = preload("res://tools/smoke/smoke_launch.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	for region_index in screen.world.region_count():
		var region: MapModel = screen.world.region(region_index)
		for zone: SeaZoneState in region.sea_zones:
			run.check(
				MapNaming.sea_presets(region.region_id).has(String(zone.name).split(" (")[0]),
				"sea zone %d reads %s" % [zone.id, zone.name]
			)
	run.check(screen.ship_layer != null, "ship layer present")
	run.check(
		screen.ship_layer.ships.size() == MapScreen.SHIP_COUNT,
		"ships spawned (%d)" % MapScreen.SHIP_COUNT
	)
	run.check(screen.capital_province >= 0, "capital province chosen")
	run.check(screen.canvas != null and screen.canvas.model == screen.model, "map canvas wired")
	run.check(screen.hud != null, "HUD present")
	# The sea reading raises from the bar's one seal and reads the chart's own
	# squadrons (DR-20261115-17), not only the court's lists.
	run.check(screen.play.sea_lens != null, "the sea reading is mounted")
	MapPlayInput.select_lens(screen.play, LensLegend.KIND_SEA)
	run.check(screen.play.sea_lens.active, "the sea reading raises")
	run.check(screen.hud.lens_legend.kind == LensLegend.KIND_SEA, "the key names the sea")
	MapPlayInput.select_lens(screen.play, "")
	run.check(screen.world != null and screen.world.region_count() == 2, "world has two regions")
	run.check(
		screen.overlay._country_borders.size() >= 4,
		"country borders built for every nation"
	)
	run.check(
		screen.play.map_seed == SmokeLaunch.SETUP_SEED.to_int(),
		"setup seed reaches the world"
	)
	var leaders: Dictionary = screen.play.leaders
	run.check(
		leaders.size() == FactionCatalog.great_power_ids().size(),
		"every Great Power fields a leader"
	)
	run.check(
		String(leaders.get(screen.player_faction, ""))
		== LeaderCatalog.default_key(screen.player_faction),
		"the human crown fields its configured leader"
	)
	run.check(screen.play.court_charts != null, "every rival court holds a chart")
	run.check(
		screen.play.court_charts.model_for(screen.player_faction, screen.region_index)
		== screen.visibility,
		"the human grid is the one the charts route to"
	)
	run.check(
		screen.play.court_charts.known_zones(
			FactionCatalog.great_power_ids()[1], FactionCatalog.NEW_WORLD
		).is_empty(),
		"no rival has charted the New World on turn one"
	)
	run.check(screen.game_menu != null, "in-game menu present")
	screen.game_menu.open()
	run.check(screen.game_menu.is_open(), "in-game menu opens")
	run.check(run.tree.paused, "in-game menu pauses the tree")
	# The chart's controls are readable from the pause, never hover-only
	# (REQ-P5-03).
	screen.game_menu.open_keys()
	run.check(screen.game_menu._keys_page.visible, "the pause reads the chart's keys")
	screen.game_menu.handle_back()
	# English-only: no mid-campaign tongue page.
	screen.game_menu.open_save()
	run.check(screen.game_menu.browser.visible, "save browser opens")
	screen.game_menu.browser.slot_chosen.emit(SmokeRun.SAVE_SLOT)
	run.check(
		SaveStore.has_slot(SmokeRun.SAVE_SLOT, SmokeRun.SAVE_DIR),
		"in-game save writes the slot"
	)
	run.check(screen.game_menu._status.text.contains("Saved"), "save is acknowledged")
	screen.game_menu.close()
	run.check(not run.tree.paused, "in-game menu resumes the tree")

	screen._cycle_region()
	await run.tree.process_frame
	run.check(screen.region_index == 1, "region switch reaches the New World")
	run.check(
		screen.model.region_id == FactionCatalog.NEW_WORLD and screen.canvas.model == screen.model,
		"New World map is drawn"
	)
	run.check(
		screen.ship_layer.ships.is_empty(),
		"no Great Power capital in the New World, so no opening squadron"
	)
	screen._cycle_region()
	await run.tree.process_frame
	run.check(screen.region_index == 0, "region switch returns to the Old World")

	run.check(screen.civilian_layer != null, "civilian layer present")
	run.check(
		screen.civilian_layer.units.size() == MapScreen.STARTING_CIVILIANS.size(),
		"civilians muster at the capital"
	)
	run.check(screen.improvements != null, "estates ledger present")
