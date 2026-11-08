extends GdToolsTest
## Cue table contract: every gameplay cue resolves to a shipped file and keeps a
## sane trim so the mix never clips (REQ-P1-06).


func test_every_cue_points_at_a_shipped_file() -> void:
	var names: Array[String] = AudioEvents.names()
	assert_gt(names.size(), 8)
	for event_name: String in names:
		var path: String = AudioEvents.path_for(event_name)
		assert_true(path.begins_with(AudioEvents.ROOT), event_name)
		assert_true(FileAccess.file_exists(path), path)


func test_unknown_events_have_no_cue() -> void:
	assert_false(AudioEvents.has("cannon_fire_9000"))
	assert_true(AudioEvents.cue("cannon_fire_9000").is_empty())
	assert_eq(AudioEvents.path_for("cannon_fire_9000"), "")


func test_trims_stay_inside_a_safe_mix_window() -> void:
	for event_name: String in AudioEvents.names():
		var cue: Dictionary = AudioEvents.cue(event_name)
		assert_between(float(cue.get("volume_db", 0.0)), -26.0, 0.0, event_name)
		assert_between(float(cue.get("pitch", 0.0)), 0.0, 0.1, event_name)


func test_names_are_sorted_and_unique() -> void:
	var names: Array[String] = AudioEvents.names()
	var sorted_copy: Array[String] = names.duplicate()
	sorted_copy.sort()
	assert_eq(names, sorted_copy)
	for event_name: String in names:
		assert_eq(names.count(event_name), 1, event_name)
