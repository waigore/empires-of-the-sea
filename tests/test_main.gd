extends GdToolsTest
## Smoke test for the application shell.

const Fixture = preload("res://tests/map_fixture.gd")


func test_main_shell_loads_the_map_screen() -> void:
	var main: Node = preload("res://scenes/main.gd").new()
	main.map_width = Fixture.WORLD_WIDTH
	main.map_height = Fixture.WORLD_HEIGHT
	add_child(main)
	assert_eq(main.get_child_count(), 1)
	assert_true(main.get_child(0) is MapScreen)
	main.free()
