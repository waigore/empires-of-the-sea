extends GdToolsTest
## The plumbing the crown's ledgers share (REQ-P3-01, REQ-P3-02): which chart a
## row sits on, the rows a chart-and-reading filter leaves, the tally each chip
## carries and the one heading per chart. The five sheets read it through this
## module, so its own suite proves the narrowing on a small fixture instead of
## leaning on a map screen (docs/testing.md).


func test_region_keys_read_the_chart_a_row_sits_on() -> void:
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_OLD))
	assert_false(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_OLD))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_NEW))
	assert_false(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_NEW))


func test_all_and_an_unknown_key_keep_every_chart() -> void:
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_ALL))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_ALL))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, ""))
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, "a_chart_no_sheet_names"))


func test_the_chart_keys_are_one_list_every_sheet_reads() -> void:
	assert_eq(",".join(LedgerRows.REGION_FILTERS), "all,old_world,new_world")


func test_groups_keep_one_chart_and_drop_the_group_it_emptied() -> void:
	var data: Dictionary = _fixture()
	var old: Array[Dictionary] = LedgerRows.groups(data, LedgerRows.REGION_OLD, _always)
	assert_eq(old.size(), 1, "one heading for the chart that still has rows")
	assert_eq(int(old[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((old[0]["rows"] as Array).size(), 2)


func test_groups_narrow_by_the_sheets_own_reading() -> void:
	var data: Dictionary = _fixture()
	var ships: Array[Dictionary] = LedgerRows.groups(
		data, LedgerRows.REGION_ALL, LedgerRows.field_matches.bind("kind", "squadron")
	)
	assert_eq(ships.size(), 1, "a chart keeps its heading only while a row survives")
	assert_eq(int(ships[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((ships[0]["rows"] as Array).size(), 1, "the armies drop out of the muster")


func test_groups_never_edit_the_snapshot_they_read() -> void:
	var data: Dictionary = _fixture()
	LedgerRows.groups(data, LedgerRows.REGION_NEW, _always)
	var groups: Array = data["groups"]
	assert_eq((groups[0]["rows"] as Array).size(), 2, "the source keeps every row")
	assert_eq((groups[1]["rows"] as Array).size(), 1)


func test_count_is_the_rows_the_narrowed_view_prints() -> void:
	var data: Dictionary = _fixture()
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_ALL, _always), 3)
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_OLD, _always), 2)
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_NEW, _always), 1)
	assert_eq(
		LedgerRows.count(
			data, LedgerRows.REGION_ALL, LedgerRows.field_matches.bind("kind", "army")
		),
		2,
		"the reading narrows before the count"
	)


func test_counts_tally_every_reading_against_one_chart() -> void:
	var data: Dictionary = _fixture()
	var counts: Dictionary = LedgerRows.counts(
		data, LedgerRows.REGION_OLD, ["all", "army", "squadron"], _kind
	)
	assert_eq(int(counts["all"]), 2, "all is the chart's own total")
	assert_eq(int(counts["army"]), 1)
	assert_eq(int(counts["squadron"]), 1)


func test_group_nests_rows_under_the_chart_that_holds_them() -> void:
	var rows: Array[Dictionary] = [
		_row(0, "first"),
		_row(0, "second"),
		_row(1, "third"),
	]
	var groups: Array[Dictionary] = LedgerRows.group(rows)
	assert_eq(groups.size(), 2, "one heading per chart in reading order")
	assert_eq(int(groups[0]["region"]), 0)
	assert_eq(String(groups[0]["region_label"]), FactionCatalog.region_label(0))
	assert_eq((groups[0]["rows"] as Array).size(), 2)
	assert_eq((groups[1]["rows"] as Array).size(), 1)


func test_a_row_reads_by_its_own_word_or_by_a_flag() -> void:
	var row: Dictionary = {"kind": "army", "flags": ["cut_off"]}
	assert_true(LedgerRows.field_matches(row, "kind", "army"))
	assert_false(LedgerRows.field_matches(row, "kind", "squadron"))
	assert_true(LedgerRows.field_matches(row, "kind", "all"), "all keeps every row")
	assert_true(LedgerRows.field_matches(row, "kind", ""), "an empty key keeps every row")
	assert_false(LedgerRows.field_matches(row, "missing", "army"), "an absent word matches nothing")
	assert_true(LedgerRows.flags_match(row, "cut_off"))
	assert_false(LedgerRows.flags_match(row, "works"))
	assert_true(LedgerRows.flags_match(row, "all"))


func test_one_region_reads_as_a_roster_and_answers_empty_when_it_cannot() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, 2, 3])
	assert_eq(LedgerRows.stored_rows(table, 0).size(), 3)
	assert_eq(LedgerRows.stored_rows(table, 1), [], "a chart never visited is empty")
	assert_eq(LedgerRows.stored_rows(null, 0), [], "a missing table reads empty, not an error")
	table.set_region(2, {"not": "a roster"})
	assert_eq(LedgerRows.stored_rows(table, 2), [], "a works table is not a roster")


# --- fixtures ---------------------------------------------------------------


## Two charts: the Old World holds an army and a squadron, the New World one army.
func _fixture() -> Dictionary:
	var old_rows: Array[Dictionary] = [_row(0, "army"), _row(0, "squadron")]
	var new_rows: Array[Dictionary] = [_row(1, "army")]
	return {
		"rows": old_rows + new_rows,
		"groups": [
			{"region": 0, "region_label": FactionCatalog.region_label(0), "rows": old_rows},
			{"region": 1, "region_label": FactionCatalog.region_label(1), "rows": new_rows},
		],
	}


func _row(region: int, kind: String) -> Dictionary:
	return {
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"kind": kind,
		"flags": [kind],
	}


static func _always(_row: Dictionary) -> bool:
	return true


static func _kind(row: Dictionary, key: String) -> bool:
	return LedgerRows.field_matches(row, "kind", key)
