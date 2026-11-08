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

	var province_id: int = _inland_province(screen)
	_check(province_id >= 0, "inland province available")
	if province_id >= 0:
		var world: Vector2 = screen.model.province_center(province_id) * MapScreen.TILE_SIZE
		screen._on_tapped(world)
		await process_frame
		_check(screen.selected_province == province_id, "province selection sticks")
		_check(screen.hud.is_panel_open(), "province panel opens")

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
