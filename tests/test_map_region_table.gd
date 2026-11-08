extends GdToolsTest
## Region tables: one table row per map region, plus the encode/decode walk the
## save codec uses instead of layer privates (REQ-P3-02 narrow APIs).


func test_missing_region_falls_back_without_creating_a_row() -> void:
	var table := MapRegionTable.new()

	assert_false(table.has_region(3))
	assert_eq(table.value(3, []), [])
	assert_false(table.has_region(3))


func test_rows_are_addressed_by_region_and_clear_together() -> void:
	var table := MapRegionTable.new()
	var roster: Array[int] = [1, 2]
	table.set_region(5, roster)
	table.set_region(2, [9])

	assert_true(table.has_region(5))
	assert_eq(table.value(5, []), [1, 2])
	assert_eq(table.region_ids(), [2, 5])
	assert_eq(table.values().size(), 2)

	table.clear()
	assert_false(table.has_region(5))
	assert_eq(table.values(), [])


func test_encode_walks_rosters_and_single_values() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, 2])
	table.set_region(1, 7)
	table.set_region(2, [])

	var encoded: Dictionary = table.encode(
		func(item: Variant) -> Dictionary: return {"n": int(item)}
	)

	assert_eq(encoded[0], [{"n": 1}, {"n": 2}])
	assert_eq(encoded[1], {"n": 7})
	assert_eq(encoded[2], [])


func test_encode_drops_null_entries_and_null_rows() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, null, 2])
	table.set_region(1, null)

	var encoded: Dictionary = table.encode(func(item: Variant) -> int: return int(item))

	assert_eq(encoded[0], [1, 2])
	assert_false(encoded.has(1))


func test_decode_replaces_rows_and_skips_null_results() -> void:
	var table := MapRegionTable.new()
	table.set_region(9, 99)

	table.decode({0: 4, 1: 5, 2: 6}, func(raw: Variant) -> Variant:
		return null if int(raw) == 5 else int(raw)
	)

	assert_eq(table.value(0, -1), 4)
	assert_eq(table.value(2, -1), 6)
	assert_false(table.has_region(1))
	assert_false(table.has_region(9))
