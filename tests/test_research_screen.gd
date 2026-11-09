extends GdToolsTest
## Integration: the research ledger drives the real economy (REQ-P2-03).

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_the_screen_owns_three_research_slots() -> void:
	var state: ResearchState = _screen.economy.economy.research
	assert_not_null(state)
	assert_eq(state.slots.size(), ResearchState.DEFAULT_SLOTS)
	assert_gt(state.researchable().size(), 0)


func test_the_research_ledger_opens_and_closes() -> void:
	assert_false(_screen.hud.panels.is_research_open())
	_screen.hud.research_pressed.emit()
	assert_true(_screen.hud.panels.is_research_open())
	var panel: ResearchPanel = _screen.hud.panels.research_panel
	assert_not_null(panel)
	assert_gt(panel.get_combined_minimum_size().y, 200.0)
	_screen.hud.panels.hide_research()
	assert_false(_screen.hud.panels.is_research_open())


func test_assigning_through_the_controller_holds_the_slot() -> void:
	var state: ResearchState = _screen.economy.economy.research
	_screen.economy.open_research()
	_screen.economy._on_research_assign("land_enclosure")
	assert_eq(state.tech_at(0), "land_enclosure")
	assert_eq(state.funding_at(0), ResearchFunding.DEFAULT)
	_screen.economy._on_research_cancel(0)
	assert_eq(state.tech_at(0), ResearchState.EMPTY_TECH)


func test_ending_the_turn_pays_for_research() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	assert_true(bool(economy.research.assign("crop_rotation", "low")["ok"]))
	Fixture.end_turn(_screen.play)
	assert_eq(economy.research.progress_of("crop_rotation"), 100)


func test_researched_techs_lift_the_estate_caps() -> void:
	assert_eq(int(_screen.play.tech_caps().get("timber", 1)), 1)
	_screen.economy.economy.research.unlock("saw_mill")
	assert_eq(int(_screen.play.tech_caps().get("timber", 1)), 2)
	assert_eq(int(_screen.economy.tech_caps().get("timber", 1)), 2)


func test_the_projection_includes_research_gold() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	assert_true(bool(economy.research.assign("crop_rotation", "low")["ok"]))
	var preview: Dictionary = _screen.economy.projected()
	var research: Dictionary = preview["research"]
	assert_eq(int(research["spent"]), ResearchFunding.gold("low"))
