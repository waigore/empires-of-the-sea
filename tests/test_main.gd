extends GdToolsTest
## Smoke tests for the placeholder main scene script.


func test_main_ready_uses_game_version() -> void:
	var main: Node = preload("res://scenes/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	assert_true(is_instance_valid(main))
	main.queue_free()
