extends GdToolsTest
## The court's power standing: the published Great Power power score, the
## relative band the court reads and the line it draws under each crown's name
## (wiki: diplomacy § Great Power power score, § Acceptance criteria).

const AiFixture = preload("res://tests/ai_fixture.gd")

var state: DiplomacyState
var panel: DiplomacyPanel
## 0 = the reader (Spain), 1 = a stronger England, 2 = a weaker France,
## 6 = Genoa, a Minor Nation that never carries a band.
var power: Dictionary = {0: 100, 1: 140, 2: 60, 6: 90}


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)
	panel = DiplomacyPanel.new()
	add_child(panel)


func after_each() -> void:
	if is_instance_valid(panel):
		panel.free()
	panel = null


# --- the published score -----------------------------------------------------


func test_the_power_score_reads_provinces_strength_and_hulls() -> void:
	var world: WorldMap = AiFixture.world([3, 3, 1])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 3.0}, {3: 2})
	assert_eq(int(scores[3]), 33, "2 provinces × 10 + 3 strength + 2 hulls × 5")
	assert_eq(int(scores[1]), 10, "a crown with no field forces scores on land alone")
	assert_eq(int(scores[4]), 0, "a crown holding nothing scores nothing")


func test_the_score_rounds_a_fractional_order_of_battle() -> void:
	var world: WorldMap = AiFixture.world([3, 3])
	var scores: Dictionary = DiplomacyPower.public_power(world, {3: 2.6}, {})
	assert_eq(int(scores[3]), 23, "20 land + round(2.6) strength")


func test_no_world_answers_no_scores() -> void:
	assert_true(DiplomacyPower.public_power(null, {0: 3.0}, {0: 1}).is_empty())


func test_the_ratio_and_its_signed_share() -> void:
	assert_almost_eq(DiplomacyPower.power_ratio(100, 140), 1.4, 0.0001)
	assert_eq(DiplomacyPower.power_percent(100, 140), 40)
	assert_eq(DiplomacyPower.power_percent(100, 80), -20)
	assert_eq(DiplomacyPower.power_percent(100, 100), 0, "an even court carries no sign")
	assert_almost_eq(DiplomacyPower.power_ratio(0, 50), 50.0, 0.0001)
	assert_eq(DiplomacyPower.power_percent(0, 50), 4900, "a crown with nothing is measured against 1")


# --- the line under each crown's name ----------------------------------------


func test_a_stronger_crown_reads_red_with_its_share() -> void:
	_refresh()
	var mark: Label = _find_label(panel._list, "STRONGER")
	assert_not_null(mark, "the band is named on the row")
	assert_true(String(mark.text).contains("+40%"), "and carries its signed share")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_WAR, "a stronger crown reads red")


func test_a_weaker_crown_reads_green_with_its_share() -> void:
	_refresh()
	var mark: Label = _find_label(panel._list, "FRAIL")
	assert_not_null(mark, "a crown at 0.6 of the reader is frail")
	assert_true(String(mark.text).contains("−40%"), "the share is signed down")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)


func test_an_even_crown_reads_green() -> void:
	power = {0: 100, 1: 100}
	_refresh()
	var mark: Label = _find_label(panel._list, "EVEN")
	assert_not_null(mark)
	assert_true(String(mark.text).contains("0%"), "an even court carries no sign")
	assert_eq(mark.get_theme_color("font_color"), Palette.DIPLO_FRIENDLY)


func test_a_far_stronger_crown_is_overwhelming() -> void:
	power = {0: 100, 1: 160}
	_refresh()
	var mark: Label = _find_label(panel._list, "OVERWHELMING")
	assert_not_null(mark, "a crown half again the reader's size is named so")
	assert_true(String(mark.text).contains("+60%"))


func test_a_minor_nation_carries_no_power_line() -> void:
	_refresh()
	var row: VBoxContainer = _row_for("Genoa")
	assert_not_null(row, "the minor's row is in the list")
	assert_eq(row.get_child_count(), 1, "name and stand only: no score for a minor")


func test_a_court_without_scores_shows_no_line() -> void:
	power = {}
	_refresh()
	var row: VBoxContainer = _row_for("England")
	assert_not_null(row)
	assert_eq(row.get_child_count(), 1, "a fixture without orders draws nothing")


func test_the_detail_names_the_figures_behind_the_band() -> void:
	_refresh()
	panel.select_faction(1)
	assert_true(_has_text(panel._detail, "Power 140"), "the rival's own score")
	assert_true(_has_text(panel._detail, "yours 100"), "beside the reader's")
	assert_true(_has_text(panel._detail, "Stronger"), "and the band in words")


func _refresh() -> void:
	panel.refresh(state, null, 0, 2500, {}, {}, power)


func _row_for(name: String) -> VBoxContainer:
	for child: Node in panel._list.get_children():
		if not child is VBoxContainer:
			continue
		var row := child as VBoxContainer
		if row.get_child_count() > 0 and _has_text(row.get_child(0), name):
			return row
	return null


func _find_label(node: Node, needle: String) -> Label:
	if node is Label and String((node as Label).text).contains(needle):
		return node as Label
	for child: Node in node.get_children():
		var found: Label = _find_label(child, needle)
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
