extends GdToolsTest
## Local slot storage: paths, metadata rows, overwrite and deletion.
## Uses a scratch directory so the player's saves are never touched.

const DIR: String = "user://test_save_store"


func before_each() -> void:
	_clean_dir()


func after_each() -> void:
	_clean_dir()


func test_slots_report_existing_saves_and_empty_slots() -> void:
	var rows: Array[Dictionary] = SaveStore.slots(DIR)
	assert_eq(rows.size(), SaveStore.SLOT_COUNT)
	assert_false(bool(rows[0]["exists"]), "fresh slot is empty")

	assert_true(SaveStore.save_slot(3, _data(7), DIR), "slot 3 saves")
	assert_true(SaveStore.has_slot(3, DIR), "slot 3 exists")
	assert_false(SaveStore.has_slot(2, DIR), "slot 2 stays empty")
	rows = SaveStore.slots(DIR)
	assert_true(bool(rows[2]["exists"]), "row reports the save")
	assert_eq(int(rows[2]["turn"]), 7, "row carries the turn")
	assert_eq(String(rows[2]["nation"]), "Spain", "row carries the nation")
	assert_eq(String(rows[2]["region"]), "Old World", "row carries the region")
	assert_eq(int(rows[2]["seed"]), 4242, "row carries the seed")
	assert_false(String(rows[2]["saved_at"]).is_empty(), "row carries a timestamp")


func test_overwrite_replaces_the_slot_and_delete_clears_it() -> void:
	assert_true(SaveStore.save_slot(1, _data(2), DIR))
	assert_true(SaveStore.save_slot(1, _data(11), DIR), "slot overwrites")
	assert_eq(int(SaveStore.slots(DIR)[0]["turn"]), 11, "newer save wins")
	assert_true(SaveStore.delete_slot(1, DIR), "slot deletes")
	assert_false(SaveStore.has_slot(1, DIR), "deleted slot is gone")
	assert_false(SaveStore.delete_slot(1, DIR), "deleting twice is a no-op")


func test_slot_numbers_are_clamped_and_bad_data_is_refused() -> void:
	assert_eq(SaveStore.path_for(0, DIR), SaveStore.path_for(1, DIR))
	assert_eq(SaveStore.path_for(99, DIR), SaveStore.path_for(SaveStore.SLOT_COUNT, DIR))
	assert_false(SaveStore.save_slot(1, {}, DIR), "empty data is refused")
	assert_false(SaveStore.save_slot(1, {"version": 999}, DIR), "bad version refused")


func _data(turn: int) -> Dictionary:
	return {
		"version": SaveCodec.VERSION,
		"saved_at": "2026-11-08 12:00:00",
		"session": {
			"map_seed": 4242,
			"map_width": 64,
			"map_height": 42,
			"player_faction": 0,
			"region_index": 0,
			"turn": turn,
		},
		"regions": [{}],
	}


func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
