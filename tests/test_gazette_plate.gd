extends GdToolsTest
## The soft Gazette plate: the turn-start sheet, the archive and the watchlist
## editor on one surface, dismissible with one press (wiki: the-gazette § When
## it appears, § History screen; DR-20261110-14). Presentation only — the lines
## are what [Gazette] built (REQ-P2-03, REQ-P5-06).

const VIEWER: int = 0
const ENGLAND: int = 1

var plate: GazettePlate = null


func before_each() -> void:
	plate = GazettePlate.new()
	add_child(plate)


func after_each() -> void:
	if is_instance_valid(plate):
		plate.free()
	plate = null


func test_the_sheet_prints_its_stamp_and_each_class_heading() -> void:
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	assert_true(plate.is_shown())
	assert_true(_has_text(plate, "THE GAZETTE"))
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	assert_true(_has_text(plate, "THE WORLD"))
	assert_true(_has_text(plate, "OUR COURT"))
	assert_true(_has_text(plate, "The gauntlet passes between them."))


func test_one_press_sets_the_sheet_aside() -> void:
	var dismissed: Array[bool] = []
	plate.dismissed.connect(func() -> void: dismissed.append(true))
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	plate.dismiss()
	assert_false(plate.is_shown())
	assert_false(plate.visible)
	assert_eq(dismissed.size(), 1)


## The plate is soft: the map under and around it keeps its pointer.
func test_only_the_plate_takes_the_pointer() -> void:
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	assert_eq(plate.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the map stays usable")
	assert_eq(plate._panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the sheet is readable")


func test_a_turn_that_printed_nothing_says_so() -> void:
	plate.open_sheet({"turn": 4, "items": []}, GazetteState.new(), null, VIEWER)
	assert_true(_has_text(plate, GazettePlate.EMPTY_LINE))


## The plate stands as tall as its news and only the news scrolls, so a quiet
## sheet never leaves a reef of blank paper under it.
func test_the_plate_takes_the_height_of_its_news() -> void:
	plate.size = Vector2(1280, 800)
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	plate._fit()
	assert_eq(plate._panel.offset_bottom, plate._panel.offset_top, "height follows content")
	assert_true(plate._scroll.custom_minimum_size.y >= 120.0, "the sheet keeps a readable body")
	assert_true(plate._scroll.custom_minimum_size.y <= 600.0, "a long sheet scrolls")


## The sheet's foot states the race for the age; the archive, a past sheet, does
## not (wiki: victory § Victory Check; DR-20261112-05).
func test_the_live_sheet_states_the_race_for_the_age() -> void:
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER, age)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the standing column is printed")
	assert_true(_has_text(plate, "you hold 12 of 31"), age)
	var state := GazetteState.new()
	state.append(_sheet(3))
	plate.open_archive(state, null, VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"), "a past sheet carries no standing")


func test_a_sheet_without_a_reading_prints_no_standing_column() -> void:
	plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"))


## The seal opens the history screen; its sheet tab is the live sheet, so the
## race stays readable on a turn that printed no news, and it is the newest
## sheet rather than whatever was on screen last (wiki: the-gazette § History
## screen — the Gazette and every prior turn's sheet are readable there).
func test_the_history_screen_keeps_the_live_sheet_and_its_standing() -> void:
	var state := GazetteState.new()
	state.append(_sheet(2))
	state.append(_sheet(3))
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_archive(state, null, VIEWER, age)
	plate._go(GazettePlate.Mode.SHEET)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the live sheet keeps its standing")
	assert_true(_has_text(plate, age), age)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)), "the newest sheet is read")
	assert_false(_has_text(plate, GazettePlate.EMPTY_LINE), "a filed sheet is not empty news")


func test_the_archive_opens_on_the_newest_sheet_and_walks_back() -> void:
	var state := GazetteState.new()
	state.append(_sheet(2))
	state.append(_sheet(3))
	plate.open_archive(state, null, VIEWER)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	plate._step(1)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(2)))
	assert_true(plate._older.disabled, "the oldest sheet has no older neighbour")
	plate._step(-1)
	assert_true(plate._newer.disabled, "the newest sheet leads")


func test_an_archive_without_sheets_says_the_presses_have_not_run() -> void:
	plate.open_archive(GazetteState.new(), null, VIEWER)
	assert_true(_has_text(plate, GazettePlate.NO_HISTORY))


func test_the_watchlist_lists_met_courts_and_toggles_the_list() -> void:
	var state := GazetteState.new()
	var diplomacy := DiplomacyState.new()
	diplomacy.initialize(1)
	plate.open_watchlist(state, diplomacy, VIEWER)
	var box: CheckBox = _check_for(plate, "England")
	assert_not_null(box, "a met court is offered")
	assert_false(box.button_pressed)
	box.button_pressed = true
	assert_true(state.is_watched(ENGLAND), "ticking follows the court")
	box.button_pressed = false
	assert_false(state.is_watched(ENGLAND))
	assert_true(state.removed.has(ENGLAND), "and the removal is remembered")


func test_the_plate_narrows_to_a_phone_viewport() -> void:
	plate.size = Vector2(480, 800)
	plate._fit()
	var width: float = plate._panel.offset_right - plate._panel.offset_left
	assert_true(width <= 480.0, "the sheet never outgrows the screen")
	assert_true(width >= GazettePlate.MIN_WIDTH)


## Toasts stay readable: while the sheet is up they are pushed to the lane under
## it, and the moment it goes they return to the top (REQ-P5-05). A phone's
## resting lane is not the atlas 84, so the plate gives back the lane's own top.
func test_the_sheet_moves_the_toast_lane_below_itself() -> void:
	var host := ToastHost.new()
	host.size = Vector2(1280, 800)
	add_child(host)
	var lane := HudDespatches.new()
	host.add_child(lane)
	# A compact bar (56) + 6 is well above the atlas 84 the old plate assumed.
	lane.fit(true, 56.0, 382.0)
	var resting: float = lane.resting_top()
	assert_eq(resting, 62.0)

	var sheet_plate := GazettePlate.new()
	sheet_plate.despatches = lane
	host.add_child(sheet_plate)
	sheet_plate.open_sheet(_sheet(3), GazetteState.new(), null, VIEWER)
	# The lane follows the laid-out sheet, so let one layout pass settle.
	await get_tree().process_frame
	sheet_plate._fit()
	assert_true(lane.lane_top() > resting, "the lane drops below the sheet")
	sheet_plate.dismiss()
	assert_eq(lane.lane_top(), resting, "the lane comes back to its own top")
	host.free()


## A stand-in for the HUD: the plate only needs the despatch lane.
class ToastHost:
	extends Control


# --- helpers -----------------------------------------------------------------


func _sheet(turn: int) -> Dictionary:
	return {
		"turn": turn,
		"items": [
			{
				"class": Gazette.Class.WORLD,
				"kind": "warDeclared",
				"text": "The gauntlet passes between them.",
			},
			{
				"class": Gazette.Class.COURT,
				"kind": "techFinished",
				"text": "Our scholars have finished the Crop Rotation.",
			},
		],
	}


func _check_for(node: Node, needle: String) -> CheckBox:
	if node is CheckBox and String((node as CheckBox).text).contains(needle):
		return node as CheckBox
	for child: Node in node.get_children():
		var found: CheckBox = _check_for(child, needle)
		if found != null:
			return found
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false
