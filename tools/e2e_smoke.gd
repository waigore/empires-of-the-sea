extends SceneTree
## Headless e2e smoke: boot main.tscn, exercise a short map-screen flow, quit.
## Keep fast — aim ≤2 minutes wall time. Extend asserts for new player paths;
## leave deep rules to tests/. Run:
##   godot --headless --path . --script res://tools/e2e_smoke.gd

const BOOT_FRAMES: int = 12

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

	_check(screen.civilian_layer != null, "civilian layer present")
	_check(
		screen.civilian_layer.units.size() == MapScreen.STARTING_CIVILIANS.size(),
		"civilians muster at the capital"
	)

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
		screen._on_tapped(world)
		await process_frame
		_check(screen.selected_province == province_id, "province selection sticks")
		_check(screen.hud.is_panel_open(), "province panel opens")

	var civilian: CivilianState = screen.civilian_layer.units[0]
	var marker_world: Vector2 = screen.model.tile_center(
		civilian.tile.x, civilian.tile.y, MapScreen.TILE_SIZE
	)
	screen._on_tapped(marker_world)
	await process_frame
	_check(screen.civilian_layer.selected_unit == civilian, "civilian selection sticks")
	_check(screen.hud.is_civilian_panel_open(), "civilian dossier opens")

	var work_tile: Vector2i = _owned_resource_tile(screen)
	var builder: CivilianState = screen.civilian_layer.units[1]
	if work_tile.x >= 0:
		builder.tile = work_tile
		screen.civilian_layer.select(builder)
		screen._on_civilian_action("build_improvement")
		_check(builder.is_working(), "civilian work order starts")

	var turn_before: int = screen.turn
	var treasury_before: int = screen.treasury
	screen._on_end_turn()
	await process_frame
	_check(screen.turn == turn_before + 1, "end turn advances calendar")
	_check(
		screen.treasury == treasury_before + screen.income,
		"end turn applies income"
	)
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
	for province: Dictionary in screen.model.provinces:
		if int(province["owner"]) != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province["tiles"]:
			if screen.model.resource_at(tile.x, tile.y) >= 0:
				return tile
	return Vector2i(-1, -1)


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
