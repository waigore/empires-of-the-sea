extends GdToolsTest
## Score catalogue: era beds follow the campaign calendar and every track exists
## on disk (REQ-P1-06, period-fitting music).


func test_every_track_points_at_a_shipped_file() -> void:
	var ids: Array[String] = MusicPlaylist.ids()
	assert_gte(ids.size(), 6)
	for track_id: String in ids:
		var path: String = MusicPlaylist.path_for(track_id)
		assert_true(path.begins_with(MusicPlaylist.ROOT), track_id)
		assert_true(FileAccess.file_exists(path), path)
	assert_true(FileAccess.file_exists(MusicPlaylist.AMBIENCE))


func test_unknown_track_has_no_path() -> void:
	assert_true(MusicPlaylist.track("sea_shanty_404").is_empty())
	assert_eq(MusicPlaylist.path_for("sea_shanty_404"), "")


func test_eras_open_on_the_consort_and_close_on_the_minuet() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1500), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1549), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_id_for_year(1550), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1699), MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_id_for_year(1700), MusicPlaylist.GILDED_MINUET)
	assert_eq(MusicPlaylist.bed_id_for_year(1800), MusicPlaylist.GILDED_MINUET)


func test_years_before_the_start_fall_back_to_the_first_bed() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(1400), MusicPlaylist.AGE_OF_DISCOVERY)


func test_beds_follow_the_turn_calendar() -> void:
	assert_eq(MusicPlaylist.bed_id_for_year(TurnTime.year_for_turn(1)),
		MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(MusicPlaylist.bed_for_turn(1)["id"], MusicPlaylist.AGE_OF_DISCOVERY)
	# 1500 + 2 years per turn: turn 30 is 1558, turn 101 is 1700.
	assert_eq(MusicPlaylist.bed_for_turn(30)["id"], MusicPlaylist.SPANISH_MAIN)
	assert_eq(MusicPlaylist.bed_for_turn(101)["id"], MusicPlaylist.GILDED_MINUET)


func test_beds_carry_period_metadata() -> void:
	for bed: Dictionary in MusicPlaylist.ERA_BEDS:
		assert_true(bed.has("title"), "title")
		assert_true(bed.has("era"), "era")
		assert_gt(int(bed["from_year"]), 0)


func test_only_stingers_are_one_shots() -> void:
	assert_true(MusicPlaylist.loops(MusicPlaylist.SPANISH_MAIN))
	assert_true(MusicPlaylist.loops(MusicPlaylist.BROADSIDES))
	assert_false(MusicPlaylist.loops(MusicPlaylist.VICTORY))
	assert_false(MusicPlaylist.loops(MusicPlaylist.DEFEAT))
