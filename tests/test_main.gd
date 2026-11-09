extends GdToolsTest
## Application shell: title screen by default, direct map boot when asked.

const Fixture = preload("res://tests/map_fixture.gd")


func test_main_shell_boots_the_title_screen() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	assert_eq(main.get_child_count(), 1)
	assert_true(main.current_page is MainMenu, "title screen is the entry point")
	assert_null(main.current_screen)
	main.free()


func test_auto_start_boots_the_map_screen() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.auto_start = true
	main.map_width = 48
	main.map_height = 32
	add_child(main)
	assert_eq(main.get_child_count(), 1)
	assert_true(main.current_screen is MapScreen, "auto-start goes straight to play")
	main.free()


## Debug door: the title screen starts a fully-AI campaign with no human court.
func test_observer_entry_starts_an_all_ai_campaign() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	add_child(main)
	var menu: MainMenu = main.current_page as MainMenu
	assert_not_null(menu, "the title screen offers the door")
	if menu == null:
		main.free()
		return
	menu.observer_pressed.emit()
	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "the observer builds a map screen")
	if screen == null:
		main.free()
		return
	assert_true(screen.observer_mode, "the screen runs the full-AI observer")
	assert_true(screen.play.observer_mode, "the session runs the full-AI observer")
	assert_true(screen.play.infinite_mode, "an observer may outlast the calendar cap")
	assert_eq(screen.play.diplomacy.human_faction, MapModel.NO_ID, "no human court")
	assert_false(screen.hud.visible, "the human chrome stays hidden")
	assert_true(screen.game_menu.save_button.disabled, "an observer session is not saved")
	assert_not_null(screen.get_node_or_null("AiObserver"), "the dashboard mounts")
	main.free()
