extends GdToolsTest
## Integration: the research ledger drives the real economy (REQ-P2-03).

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so the cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
var _screen: MapScreen = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_screen = mounted


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	_screen = null
	pristine = {}


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
	_screen.economy.orders.assign_research("land_enclosure")
	assert_eq(state.tech_at(0), "land_enclosure")
	assert_eq(state.funding_at(0), ResearchFunding.DEFAULT)
	_screen.economy.orders.cancel_research(0)
	assert_eq(state.tech_at(0), ResearchState.EMPTY_TECH)


func test_ending_the_turn_pays_for_research() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	assert_true(bool(economy.research.assign("crop_rotation", "low")["ok"]))
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(economy.research.progress_of("crop_rotation"), 100)


func test_researched_techs_lift_the_estate_caps() -> void:
	assert_eq(int(_screen.play.tech_caps().get("timber", 1)), 1)
	_screen.economy.economy.research.unlock("saw_mill")
	assert_eq(int(_screen.play.tech_caps().get("timber", 1)), 2)
	assert_eq(int(_screen.economy.readings.tech_caps().get("timber", 1)), 2)


func test_the_projection_includes_research_gold() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	assert_true(bool(economy.research.assign("crop_rotation", "low")["ok"]))
	var preview: Dictionary = _screen.economy.readings.projected()
	var research: Dictionary = preview["research"]
	assert_eq(int(research["spent"]), ResearchFunding.gold("low"))


## Changing a slot's priority used to repaint the whole dialog. The row the
## player pressed must survive and its spend line and gauge must follow at once
## (REQ-P1-05).
func test_a_priority_change_repaints_the_slot_at_once_without_reloading() -> void:
	_screen.economy.open_research()
	_screen.economy.orders.assign_research("land_enclosure")
	var panel: ResearchPanel = _screen.hud.panels.research_panel
	var row: ResearchSlotRow = panel._slots_body.get_child(0)
	assert_eq(row.bar().next_gain(), 300, "Medium buys 300 points")
	_screen.economy.orders.cycle_research_funding(0)
	assert_is(row, panel._slots_body.get_child(0), "the slot is repainted, not rebuilt")
	assert_true(_screen.hud.panels.is_research_open())
	assert_eq(row.bar().next_gain(), 800, "High buys 800 points")
	assert_eq(row.gold_next(), 400)


func test_cancelling_a_study_keeps_the_ledger_and_its_rows() -> void:
	_screen.economy.open_research()
	_screen.economy.orders.assign_research("land_enclosure")
	var panel: ResearchPanel = _screen.hud.panels.research_panel
	var row: ResearchSlotRow = panel._slots_body.get_child(0)
	_screen.economy.orders.cancel_research(0)
	assert_is(row, panel._slots_body.get_child(0), "no button rebuilds the slot")
	assert_true(_screen.hud.panels.is_research_open())
	assert_eq(row.bar().next_gain(), 0, "an idle slot buys nothing")


## The sheet fades in once. A repaint while it is open must not restart the
## fade, which is what read as the dialog reloading.
func test_repainting_the_open_ledger_does_not_fade_it_back_in() -> void:
	_screen.economy.open_research()
	var wrap: Control = _screen.hud._research_wrap
	for _frame in 120:
		if wrap.modulate.a >= 0.999:
			break
		await get_tree().process_frame
	wrap.modulate.a = 0.5
	_screen.economy.open_research()
	await get_tree().process_frame
	assert_true(wrap.modulate.a > 0.3, "a repaint must not restart the reveal fade")
