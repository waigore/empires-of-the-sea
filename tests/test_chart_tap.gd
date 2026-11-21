extends GdToolsTest
## The chart's tap law (REQ-P3-04): one press slot per input stream, a release
## close to its press is a tap, and the same tap seen twice in one frame is
## answered once. Pure — no viewport, no nodes.

const START := Vector2(400.0, 300.0)


func test_a_touch_press_answers_nothing() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.touch(true, 0, START), Vector2.INF, "a press is not a tap")


func test_a_touch_release_close_to_its_press_is_a_tap() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, START)
	assert_eq(taps.touch(false, 0, START + Vector2(1.0, 1.0)), START + Vector2(1.0, 1.0))


func test_a_drag_is_not_a_tap() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, START)
	var far: Vector2 = START + Vector2(ChartTap.SLOP + 1.0, 0.0)
	assert_eq(taps.touch(false, 0, far), Vector2.INF, "a pan belongs to the camera")


func test_a_release_without_its_own_press_answers_nothing() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.touch(false, 0, START), Vector2.INF, "no press, no tap")
	taps.touch(true, 0, START)
	assert_eq(taps.touch(false, 1, START), Vector2.INF, "another finger's release")


func test_a_mouse_click_is_a_tap() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.mouse(true, START), Vector2.INF)
	assert_eq(taps.mouse(false, START), START)


func test_a_touch_and_its_emulated_click_keep_their_own_presses() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, START)
	taps.mouse(true, START)
	assert_eq(taps.touch(false, 0, START), START, "the touch release answers")
	assert_eq(taps.mouse(false, START), START, "the emulated release answers too")


func test_the_same_tap_in_one_frame_is_a_repeat() -> void:
	var taps := ChartTap.new()
	assert_false(taps.is_repeat(7, START), "the first answer is not a repeat")
	taps.mark_answered(7, START)
	assert_true(taps.is_repeat(7, START + Vector2(0.1, 0.0)), "the second path is silent")
	assert_false(taps.is_repeat(8, START), "the next frame is a new tap")
	assert_false(
		taps.is_repeat(7, START + Vector2(ChartTap.MERGE_DISTANCE + 1.0, 0.0)),
		"a tap elsewhere is its own answer"
	)
