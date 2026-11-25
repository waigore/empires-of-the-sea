extends GdToolsTest
## Turn-to-calendar mapping (wiki: turn-time-mapping).


func test_turn_one_is_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(1), 1500)


func test_two_years_per_turn_before_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(2), 1502)
	assert_eq(TurnTime.year_for_turn(51), 1600)


func test_cutoff_turn_is_1700() -> void:
	assert_eq(TurnTime.TURNS_BEFORE_CUTOFF, 100)
	assert_eq(TurnTime.year_for_turn(101), 1700)


func test_one_year_per_turn_after_cutoff() -> void:
	assert_eq(TurnTime.year_for_turn(102), 1701)
	assert_eq(TurnTime.year_for_turn(201), 1800)


func test_turn_zero_clamps_to_start_year() -> void:
	assert_eq(TurnTime.year_for_turn(0), 1500)
	assert_eq(TurnTime.year_for_turn(-4), 1500)


func test_label_formats_turn_and_year() -> void:
	assert_eq(TurnTime.label_for_turn(1), "Turn 1  ·  1500")
	assert_eq(TurnTime.label_for_turn(201), "Turn 201  ·  1800")
