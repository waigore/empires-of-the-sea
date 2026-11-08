extends GdToolsTest
## Application shell: title screen by default, direct map boot when asked.


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
