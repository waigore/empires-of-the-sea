extends GdToolsTest
## App flow: title -> setup -> map, in-game menu, save slot, load rebuilds the
## screen (clearing the old game), and back to the title (REQ-P5-01, P5-07).

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const DIR: String = "user://test_menu_flow"
const FLOW_SIZE: Vector2i = Vector2i(48, 32)

var main: Node = null


func before_each() -> void:
	_clean_dir()
	main = MAIN.instantiate()
	main.auto_start = false
	add_child(main)


func after_each() -> void:
	get_tree().paused = false
	if is_instance_valid(main):
		main.free()
	main = null
	_clean_dir()


func test_title_screen_offers_new_load_and_a_dimmed_settings_door() -> void:
	assert_true(main.current_page is MainMenu, "title screen boots first")
	var menu: MainMenu = main.current_page
	assert_true(menu.new_game_button != null)
	assert_true(menu.load_game_button != null)
	assert_true(menu.settings_button.disabled, "settings is dimmed")
	assert_true(menu.quit_button != null)


func test_new_game_setup_starts_the_chosen_world() -> void:
	main.size_override = FLOW_SIZE
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	assert_true(main.current_page is GameSetupScreen, "setup opens")

	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(2)
	setup.size_option.select(0)
	setup.seed_field.text = "777"
	setup.start_button.emit_signal("pressed")

	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "setup starts the map screen")
	if screen == null:
		return
	assert_eq(screen.player_faction, 2, "France is the human crown")
	assert_eq(screen.play.player_faction, 2)
	assert_eq(screen.play.map_seed, 777)
	assert_eq(screen.map_width, FLOW_SIZE.x)
	assert_eq(screen.map_height, FLOW_SIZE.y)
	assert_eq(screen.model.province_owner(screen.capital_province), 2, "seat is French")
	assert_eq(screen.hud._nation_label.text, "FRANCE")
	assert_eq(screen.visibility.player_id, 2, "fog belongs to France")
	assert_eq(screen.economy.player_faction, 2, "economy belongs to France")
	var french_fleets: int = 0
	for fleet: FleetState in screen.ship_layer.fleets:
		if fleet.owner == 2:
			french_fleets += 1
	assert_eq(french_fleets, FleetMuster.PLAYER_FLEETS, "player squadrons fly French colours")
	var home: ArmyState = null
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == 2 and army.is_home_army():
			home = army
	assert_not_null(home, "French Home Army musters")
	if home != null:
		assert_eq(home.province, screen.capital_province, "Home Army holds the seat")


func test_menu_save_load_and_return_flow() -> void:
	_start_game()
	var screen: MapScreen = main.current_screen
	screen.game_menu.open()
	assert_true(screen.game_menu.is_open(), "menu opens")
	assert_true(get_tree().paused, "tree pauses behind the menu")
	assert_true(screen.game_menu.settings_button.disabled, "settings is dimmed")
	screen.game_menu.open_save()
	screen.game_menu.browser.slot_chosen.emit(2)
	assert_true(SaveStore.has_slot(2, DIR), "slot 2 written")
	assert_true(screen.game_menu._status.text.contains("Saved"))
	screen.game_menu.close()
	assert_false(get_tree().paused, "tree resumes")

	screen.play.turn = 9
	screen.play.economy.economy.treasury = 999_999
	screen.play.prestige = 99
	screen.game_menu.load_chosen.emit(2)

	var loaded: MapScreen = main.current_screen
	assert_not_null(loaded, "a new screen is installed")
	if loaded == null:
		return
	assert_true(loaded != screen, "the old screen is replaced")
	assert_null(screen.get_parent(), "the old screen left the tree")
	assert_eq(loaded.play.turn, 1, "saved turn restored")
	assert_eq(loaded.play.prestige, 38, "saved prestige restored")
	assert_eq(loaded.play.economy.economy.treasury, 2500, "saved treasury restored")
	assert_eq(loaded.save_dir, DIR, "load keeps the slot directory")
	assert_eq(loaded.player_faction, 2, "saved human crown restored")
	assert_eq(loaded.play.economy.player_faction, 2, "economy follows the crown")
	assert_eq(loaded.play.visibility.player_id, 2, "fog follows the crown")
	assert_eq(loaded.hud._nation_label.text, "FRANCE")

	loaded.game_menu.main_menu_chosen.emit()
	assert_true(main.current_page is MainMenu, "title screen returns")
	assert_null(main.current_screen, "no map survives the return")


func test_title_screen_mounts_a_living_backdrop() -> void:
	var menu: MainMenu = main.current_page
	assert_not_null(menu.backdrop, "title screen owns a living backdrop")
	assert_eq(menu.backdrop.get_index(), 0, "backdrop paints behind every menu control")
	assert_not_null(menu.backdrop.plate, "painted plate is the far plane")
	assert_not_null(menu.backdrop.life, "gulls and embers layer exists")
	assert_eq(menu.backdrop.ships.size(), 2, "two carracks ride the bay")


func test_backdrop_covers_phone_desktop_and_short_windows() -> void:
	var menu: MainMenu = main.current_page
	var backdrop: MenuBackdrop = menu.backdrop
	for view: Vector2 in [Vector2(1280, 720), Vector2(720, 1280), Vector2(2560, 1080)]:
		backdrop.fit(view)
		var rect: Rect2 = backdrop.stage_rect()
		assert_true(rect.position.x <= 0.05, "stage is flush with the left edge")
		assert_true(rect.position.y <= 0.05, "stage is flush with the top edge")
		assert_true(rect.size.x >= view.x, "stage covers the full width")
		assert_true(rect.size.y >= view.y, "stage covers the full height")


func test_carrack_bobs_wraps_and_fades_at_the_lane_edge() -> void:
	var menu: MainMenu = main.current_page
	var ship: MenuShip = menu.backdrop.ships[1]
	var start_y: float = ship.position.y
	ship.advance(0.7)
	assert_true(absf(ship.position.y - start_y) > 0.0, "hull rides the swell")
	ship.bounds = Vector2(0.0, 1000.0)
	ship.place_at(995.0)
	assert_true(ship.modulate.a < 0.2, "hull dissolves before the lane edge")
	ship.place_at(1001.0)
	ship.advance(0.0)
	assert_eq(ship.position.x, 0.0, "hull re-enters from the far edge")


func test_ambient_life_keeps_gulls_and_embers() -> void:
	var menu: MainMenu = main.current_page
	var life: MenuLife = menu.backdrop.life
	assert_eq(life._birds.size(), MenuLife.BIRD_COUNT)
	assert_eq(life._embers.size(), MenuLife.EMBER_COUNT)
	life._process(0.5)
	assert_true(life._time > 0.0)


func _start_game() -> void:
	main.size_override = FLOW_SIZE
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(2)
	setup.size_option.select(0)
	setup.seed_field.text = "777"
	setup.start_button.emit_signal("pressed")
	assert_not_null(main.current_screen, "game started")
	if main.current_screen != null:
		main.current_screen.save_dir = DIR


func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
