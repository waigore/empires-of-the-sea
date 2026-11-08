extends SceneTree
## Headless e2e smoke: boot main.tscn, exercise a short map-screen flow, quit.
## Budget: ≤2 minutes wall time (CI job timeout 2). Extend asserts for new
## player paths; leave deep rules to tests/. Run:
##   godot --headless --path . --script res://tools/e2e_smoke.gd

const BOOT_FRAMES: int = 8
## Smaller than the playable default so smoke stays well under the 2 min budget.
const SMOKE_WIDTH: int = 64
const SMOKE_HEIGHT: int = 42

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("e2e_smoke: loading main scene")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	if packed == null:
		_finish()
		return

	var main: Node = packed.instantiate()
	main.map_width = SMOKE_WIDTH
	main.map_height = SMOKE_HEIGHT
	root.add_child(main)
	for _frame in BOOT_FRAMES:
		await process_frame

	_check(GameVersion.as_string() != "", "GameVersion.as_string non-empty")
	_check(GameVersion.is_compatible_with(GameVersion.MAJOR), "GameVersion major compatible")

	var screen: MapScreen = _map_screen(main)
	_check(screen != null, "main hosts MapScreen")
	if screen == null:
		_finish()
		return

	_check(screen.model != null, "map model built")
	_check(screen.model.province_count() > 0, "provinces generated")
	_check(screen.ship_layer != null, "ship layer present")
	_check(
		screen.ship_layer.ships.size() == MapScreen.SHIP_COUNT,
		"ships spawned (%d)" % MapScreen.SHIP_COUNT
	)
	_check(screen.capital_province >= 0, "capital province chosen")
	_check(screen.canvas != null and screen.canvas.model == screen.model, "map canvas wired")
	_check(screen.hud != null, "HUD present")
	_check(screen.world != null and screen.world.region_count() == 2, "world has two regions")
	_check(
		screen.overlay._country_borders.size() >= 4,
		"country borders built for every nation"
	)

	screen._cycle_region()
	await process_frame
	_check(screen.region_index == 1, "region switch reaches the New World")
	_check(
		screen.model.region_id == FactionCatalog.NEW_WORLD and screen.canvas.model == screen.model,
		"New World map is drawn"
	)
	_check(
		screen.ship_layer.ships.size() == MapScreen.SHIP_COUNT,
		"New World fleets spawned"
	)
	screen._cycle_region()
	await process_frame
	_check(screen.region_index == 0, "region switch returns to the Old World")

	_check(screen.civilian_layer != null, "civilian layer present")
	_check(
		screen.civilian_layer.units.size() == MapScreen.STARTING_CIVILIANS.size(),
		"civilians muster at the capital"
	)
	_check(screen.improvements != null, "estates ledger present")

	var estates_toggle: Button = screen.improvements._toggle
	_check(estates_toggle != null, "estates toggle present")
	screen.improvements.open()
	await process_frame
	_check(screen.improvements.is_open(), "estates ledger opens")
	_check(
		screen.improvements._data.has("counts"),
		"estates ledger builds a snapshot"
	)
	screen.improvements.close()

	var cues_before: int = 0
	var audio: AudioDirector = screen.get_node_or_null("Audio") as AudioDirector
	var controls: AudioControls = screen.hud.get_node_or_null("AudioControls") as AudioControls
	_check(audio != null, "audio director present")
	_check(controls != null, "sound seal present")
	if audio != null:
		_check(audio.current_track_id() == MusicPlaylist.AGE_OF_DISCOVERY, "opening bed playing")
		_check(audio._ambience.playing, "sea ambience playing")
		cues_before = audio.sfx_played
		_check(audio.play_event(AudioEvents.UI_CLICK), "ui cue fires")
		_check(audio.sfx_played == cues_before + 1, "ui cue counted")
		audio.set_muted(true)
		_check(audio._active_player().volume_db == AudioDirector.SILENT_DB, "mute silences music")
		audio.set_muted(false)

	var province_id: int = _inland_province(screen)
	_check(province_id >= 0, "inland province available")
	if province_id >= 0:
		var world: Vector2 = screen.model.province_center(province_id) * MapScreen.TILE_SIZE
		MapPlayInput.on_tapped(screen.play, world)
		await process_frame
		_check(screen.selected_province == province_id, "province selection sticks")
		_check(screen.hud.is_panel_open(), "province panel opens")

	var civilian: CivilianState = screen.civilian_layer.units[0]
	var marker_world: Vector2 = MapGeo.tile_center(
		civilian.tile.x, civilian.tile.y, MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(screen.play, marker_world)
	await process_frame
	_check(screen.civilian_layer.selected_unit == civilian, "civilian selection sticks")
	_check(screen.hud.is_civilian_panel_open(), "civilian dossier opens")

	var work_tile: Vector2i = _owned_resource_tile(screen)
	var builder: CivilianState = screen.civilian_layer.units[1]
	if work_tile.x >= 0:
		builder.tile = work_tile
		var resource: int = screen.model.resource_at(work_tile.x, work_tile.y)
		if ImprovementCatalog.needs_prospecting(resource):
			screen.land_works.set_prospected(
				MapScreen.PLAYER_FACTION, screen.model, work_tile
			)
		screen.civilian_layer.select(builder)
		MapPlayCivilians.on_action(screen.play, "build_improvement")
		_check(builder.is_working(), "civilian work order starts")

	var turn_before: int = screen.turn
	MapPlayTurn.end_turn(screen.play)
	await process_frame
	_check(screen.turn == turn_before + 1, "end turn advances calendar")
	_check(screen.economy != null, "economy wired")
	_check(
		screen.treasury == screen.economy.economy.treasury,
		"treasury reads from the economy ledger"
	)
	_check(screen.economy.economy.total_units() > 0, "stockpile holds goods")
	_check(
		screen.economy.extraction().size() > 0,
		"owned provinces yield commodities"
	)
	screen.economy.open_panel()
	await process_frame
	_check(screen.hud.is_economy_open(), "ledger opens")
	screen.economy._on_production("lumber", 1)
	_check(
		screen.economy.economy.assignment_units("lumber") == 1,
		"production assignment sticks"
	)
	screen.hud.hide_economy()
	_check(not screen.hud.is_economy_open(), "ledger closes")
	_check(
		TurnTime.year_for_turn(screen.turn) == TurnTime.START_YEAR + 2,
		"turn maps to expected year"
	)
	if work_tile.x >= 0:
		_check(
			screen.land_works.improvement_at(screen.model, work_tile) == 1,
			"civilian work completes on end turn"
		)
	if audio != null:
		_check(audio.sfx_played >= cues_before + 3, "turn cues fired")
		# A contested zone resolves on turn one, which legitimately hands the
		# score to the battle bed; either bed is fine, silence is not.
		var bed: String = audio.current_track_id()
		_check(
			bed == MusicPlaylist.AGE_OF_DISCOVERY or bed == MusicPlaylist.BROADSIDES,
			"music keeps a bed after the turn (%s)" % bed
		)

	_finish()


func _map_screen(main: Node) -> MapScreen:
	for child in main.get_children():
		if child is MapScreen:
			return child as MapScreen
	return null


func _inland_province(screen: MapScreen) -> int:
	for province: Dictionary in screen.model.provinces:
		if not bool(province["coastal"]) and int(province["area"]) > 30:
			return int(province["id"])
	if screen.model.provinces.is_empty():
		return -1
	return int(screen.model.provinces[0]["id"])


func _owned_resource_tile(screen: MapScreen) -> Vector2i:
	var fallback: Vector2i = Vector2i(-1, -1)
	for province: Dictionary in screen.model.provinces:
		if int(province["owner"]) != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province["tiles"]:
			var resource: int = screen.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if not ImprovementCatalog.needs_prospecting(resource):
				return tile
			if fallback.x < 0:
				fallback = tile
	return fallback


func _check(ok: bool, label: String) -> void:
	if ok:
		print("e2e_smoke: PASS %s" % label)
	else:
		printerr("e2e_smoke: FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("e2e_smoke: all asserts passed")
		quit(0)
	else:
		printerr(
			"e2e_smoke: %d assert(s) failed: %s"
			% [_failures.size(), ", ".join(_failures)]
		)
		quit(1)
