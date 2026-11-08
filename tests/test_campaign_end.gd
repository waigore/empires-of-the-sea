# gdlint: disable=max-public-methods
extends GdToolsTest
## Campaign calendar cap, endless mode and the campaign-complete plate (wiki:
## turn-time-mapping § Campaign calendar cap, victory § Calendar campaign end).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const CAP: int = 201
const SAVE_DIR: String = "user://test_campaign_end"

var screen: MapScreen = null


func before_each() -> void:
	screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(screen):
		screen.free()
	screen = null
	get_tree().paused = false


# --- calendar rules ----------------------------------------------------------


func test_the_cap_lands_on_the_turn_that_starts_1800() -> void:
	assert_eq(TurnTime.turn_for_year(1800), CAP)
	assert_eq(TurnTime.year_for_turn(CAP), 1800)
	assert_eq(TurnTime.cap_turn(), CAP)
	assert_true(TurnTime.is_cap_turn(CAP))


func test_a_skipped_year_starts_no_turn() -> void:
	assert_eq(TurnTime.turn_for_year(1699), -1)
	assert_eq(TurnTime.turn_for_year(1499), -1)
	assert_eq(TurnTime.turn_for_year(1601), -1)
	assert_eq(TurnTime.turn_for_year(1600), 51)
	assert_eq(TurnTime.turn_for_year(1701), 102)


func test_the_cap_only_closes_a_historical_campaign() -> void:
	assert_false(VictoryRules.calendar_halt(CAP - 1, false))
	assert_true(VictoryRules.calendar_halt(CAP, false))
	assert_false(VictoryRules.calendar_halt(CAP, true))


func test_the_strongest_crown_is_declared_when_the_calendar_closes() -> void:
	var model: MapModel = Fixture.region()
	var saved: Array[int] = []
	for province: ProvinceState in model.provinces:
		saved.append(province.owner)
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var world := WorldMap.new()
	world.add_region(model)
	var half: int = model.provinces.size() / 2
	for index in model.provinces.size():
		if index < half * 2:
			model.provinces[index].owner = crowns[0] if index < half else crowns[1]
		else:
			model.provinces[index].owner = MapModel.NO_ID
	var tie: int = VictoryRules.declared_leader(world)
	model.provinces[half].owner = crowns[0]
	var strict: int = VictoryRules.declared_leader(world)
	for index in saved.size():
		model.provinces[index].owner = saved[index]

	assert_eq(tie, MapModel.NO_ID, "an even split declares no-one")
	assert_eq(strict, crowns[0], "one province ahead is enough to lead the age")


# --- end of turn -------------------------------------------------------------


func test_the_calendar_closes_an_undecided_campaign_on_its_last_turn() -> void:
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)

	assert_true(screen.play.campaign_halted)
	assert_null(screen.play.victory)
	assert_eq(screen.turn, CAP, "the turn number stays on the last full turn")
	assert_true(screen.hud.is_victory_shown())
	assert_eq(screen.hud.victory_overlay._title.text, "CAMPAIGN COMPLETE")
	assert_true(screen.hud.victory_overlay._detail.text.contains("No military victory"))
	assert_true(screen.hud._end_turn_button.disabled)
	assert_eq(screen.hud._end_turn_button.text, "CAMPAIGN ENDED")


func test_a_closed_calendar_takes_no_more_turns() -> void:
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	var turn_before: int = screen.turn

	MapPlayTurn.end_turn(screen.play)

	assert_eq(screen.turn, turn_before)
	assert_true(screen.play.campaign_halted)


func test_a_closed_calendar_takes_no_orders() -> void:
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)

	MapPlayCivilians.on_action(screen.play, "move")
	MapPlayFleets.try_order(screen.play, Vector2i(0, 0))
	MapPlayDiplomacy.on_order(screen.play, "war", 1, "")

	assert_true(screen.play.campaign_over())
	assert_false(screen.hud.panels.is_panel_open())


func test_an_endless_campaign_sails_past_the_cap() -> void:
	screen.play.infinite_mode = true
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)

	assert_false(screen.play.campaign_halted)
	assert_false(screen.hud.is_victory_shown())
	assert_eq(screen.turn, CAP + 1)
	assert_eq(TurnTime.year_for_turn(screen.turn), 1801)
	assert_false(screen.hud._end_turn_button.disabled)


# --- persistence -------------------------------------------------------------


func test_a_calendar_closed_slot_reopens_on_the_complete_plate() -> void:
	screen.save_dir = SAVE_DIR
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	assert_true(screen.play.campaign_halted)
	var save: Dictionary = SaveCodec.capture(screen.play)
	assert_true(SaveCodec.is_valid(save))
	screen.free()
	screen = null

	var reopened: MapScreen = _load(save)

	assert_true(reopened.play.campaign_halted, "the closed calendar survives the save")
	assert_null(reopened.play.victory)
	assert_eq(reopened.turn, CAP)
	assert_true(reopened.hud.is_victory_shown(), "the plate returns on load")
	assert_eq(reopened.hud.victory_overlay._title.text, "CAMPAIGN COMPLETE")
	assert_true(reopened.hud._end_turn_button.disabled)
	var turn_before: int = reopened.turn
	MapPlayTurn.end_turn(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")


func test_an_endless_choice_survives_the_save() -> void:
	screen.save_dir = SAVE_DIR
	screen.play.infinite_mode = true
	var save: Dictionary = SaveCodec.capture(screen.play)
	screen.free()
	screen = null

	var reopened: MapScreen = _load(save)

	assert_true(reopened.play.infinite_mode, "endless campaigns stay endless")


func _load(data: Dictionary) -> MapScreen:
	var node: MapScreen = SCREEN.instantiate()
	node.save_dir = SAVE_DIR
	node.pending_save = data
	add_child(node)
	return node
