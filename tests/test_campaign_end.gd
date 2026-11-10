# gdlint: disable=max-public-methods
extends GdToolsTest
## Campaign calendar cap, endless mode and the campaign-complete plate (wiki:
## turn-time-mapping § Campaign calendar cap, victory § Calendar campaign end).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const CAP: int = 201
const SAVE_DIR: String = "user://test_campaign_end"

var screen: MapScreen = null
## Ownership as the shared world was generated: `_seat_crowns` rewrites owners,
## so each case starts from the same pristine world instead of a new one.
var saved: Array = []


## Snapshotted before any case touches the fixture, so the base is a clean world.
func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	Fixture.restore(Fixture.world(), saved)


## The chart is only built for the cases that read it: the calendar and config
## rules here assert on constants, and a screen attach paints the whole map.
func _attach() -> MapScreen:
	if screen == null:
		screen = Fixture.attach_screen(self)
	return screen


func after_each() -> void:
	Fixture.restore(Fixture.world(), saved)
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


# --- the standing reads the order of battle ----------------------------------


func test_the_strongest_order_of_battle_is_declared() -> void:
	_attach()
	var crowns: Array[int] = _seat_crowns()
	var model: MapModel = screen.play.world.region(screen.play.region_index)
	var province: int = int(model.provinces[0].id)
	var many_weak := ArmyState.muster(
		9001, crowns[0], province, false,
		["peasant_levies", "peasant_levies", "peasant_levies"]
	)
	var few_strong := ArmyState.muster(
		9002, crowns[1], province, false, ["knights", "knights"]
	)
	var armies: Array[ArmyState] = [many_weak, few_strong]
	screen.play.army_layer.armies.assign(armies)

	assert_eq(
		MapPlayCampaign.declared_leader(screen.play),
		crowns[1],
		"3 peasant levies (strength 9) fall short of 2 knights (strength 12)"
	)


func test_a_crown_is_scored_on_its_whole_order_of_battle() -> void:
	_attach()
	var crowns: Array[int] = _seat_crowns()
	var model: MapModel = screen.play.world.region(screen.play.region_index)
	var province: int = int(model.provinces[0].id)
	var here: Array[ArmyState] = [
		ArmyState.muster(
			9101, crowns[1], province, false, ["knights", "knights", "knights"]
		)
	]
	screen.play.army_layer.armies.assign(here)
	var elsewhere: int = (
		WorldMap.OLD_WORLD
		if screen.play.region_index == WorldMap.NEW_WORLD
		else WorldMap.NEW_WORLD
	)
	var far: Array[ArmyState] = [
		ArmyState.muster(
			9102, crowns[0], province, false,
			["grenadiers", "grenadiers", "grenadiers", "grenadiers"]
		)
	]
	screen.play.army_layer.regions.set_region(elsewhere, far)

	assert_eq(
		MapPlayCampaign.declared_leader(screen.play),
		crowns[0],
		"four grenadiers across the ocean outrank three knights on screen"
	)


## Splits every province of both regions evenly between the first two crowns and
## clears every fleet, so the standing depends only on the land forces a test
## gives them.
func _seat_crowns() -> Array[int]:
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var world: WorldMap = screen.play.world
	for index in world.region_count():
		var model: MapModel = world.region(index)
		var seat: int = 0
		for province: ProvinceState in model.provinces:
			province.owner = MapModel.NO_ID
		for province: ProvinceState in model.provinces:
			if seat < 20:
				province.owner = crowns[seat % 2]
			seat += 1
	var no_ships: Array[Ship] = []
	screen.play.ship_layer.ships.assign(no_ships)
	for index in screen.play.ship_layer.regions.region_ids():
		var no_fleets: Array[FleetState] = []
		screen.play.ship_layer.regions.set_region(index, no_fleets)
	return crowns


# --- end of turn -------------------------------------------------------------


func test_the_calendar_closes_an_undecided_campaign_on_its_last_turn() -> void:
	_attach()
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_true(screen.play.campaign_halted)
	assert_null(screen.play.victory)
	assert_eq(screen.turn, CAP, "the turn number stays on the last full turn")
	assert_true(screen.hud.is_victory_shown())
	assert_eq(screen.hud.victory_overlay._title.text, "CAMPAIGN COMPLETE")
	assert_eq(
		screen.hud.victory_overlay._detail.text,
		"1800  ·  Turn 201",
		"the plate reads year then turn (wiki: victory § Victory Screen)"
	)
	assert_true(screen.hud._end_turn_button.disabled)
	assert_eq(screen.hud._end_turn_button.text, "CAMPAIGN ENDED")


func test_a_closed_calendar_takes_no_more_turns() -> void:
	_attach()
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	var turn_before: int = screen.turn

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_eq(screen.turn, turn_before)
	assert_true(screen.play.campaign_halted)


func test_a_closed_calendar_takes_no_orders() -> void:
	_attach()
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	MapPlayCivilians.on_action(screen.play, "move")
	MapPlayFleets.try_order(screen.play, Vector2i(0, 0))
	MapPlayDiplomacy.on_order(screen.play, "war", 1, "")

	assert_true(screen.play.campaign_over())
	assert_false(screen.hud.panels.is_panel_open())


func test_the_complete_plate_speaks_the_wikis_calendar_copy() -> void:
	_attach()
	var overlay: VictoryOverlay = screen.hud.victory_overlay
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = crowns[1] if crowns[1] != player else crowns[0]

	overlay.show_campaign_complete(rival, CAP, player)
	assert_eq(overlay._detail.text, "1800  ·  Turn 201", "year then turn")
	assert_true(
		overlay._tagline.text.ends_with("holds the age."),
		"a rival's standing reads '<Name> holds the age.'"
	)

	overlay.show_campaign_complete(player, CAP, player)
	assert_eq(overlay._tagline.text, "The age belongs to your crown.")

	overlay.show_campaign_complete(MapModel.NO_ID, CAP, player)
	assert_eq(overlay._tagline.text, "The age is divided — no crown is declared.")


func test_an_endless_campaign_sails_past_the_cap() -> void:
	_attach()
	screen.play.infinite_mode = true
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_false(screen.play.campaign_halted)
	assert_false(screen.hud.is_victory_shown())
	assert_eq(screen.turn, CAP + 1)
	assert_eq(TurnTime.year_for_turn(screen.turn), 1801)
	assert_false(screen.hud._end_turn_button.disabled)


# --- setup -------------------------------------------------------------------


func test_setup_carries_the_campaign_choice_into_the_config() -> void:
	var setup: GameSetupScreen = load("res://scenes/game_setup.tscn").instantiate()
	add_child(setup)
	var started: Array[GameConfig] = []
	setup.start_requested.connect(func(config: GameConfig) -> void:
		started.append(config)
	)
	setup.campaign_option.select(1)

	setup._on_start()

	assert_eq(started.size(), 1)
	assert_true(started[0].infinite_mode, "endless setup flags the config")
	assert_eq(setup.campaign_option.item_count, 2, "historical and endless on offer")


func test_the_config_round_trips_the_campaign_choice() -> void:
	var config: GameConfig = GameConfig.make(7, 0, 1, "", true)

	var restored: GameConfig = GameConfig.from_dict(config.to_dict())

	assert_true(restored.infinite_mode)
	assert_eq(restored.map_seed, 7)


# --- persistence -------------------------------------------------------------


func test_a_calendar_closed_slot_reopens_on_the_complete_plate() -> void:
	_attach()
	screen.save_dir = SAVE_DIR
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
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
	Fixture.settle(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")


func test_an_endless_choice_survives_the_save() -> void:
	_attach()
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
	# The save came from the shared world: hand it back so the load applies the
	# save over that map instead of regenerating and repainting a fresh one.
	node.map_width = Fixture.WORLD_WIDTH
	node.map_height = Fixture.WORLD_HEIGHT
	node.preset_world = Fixture.world()
	node.pending_save = data
	add_child(node)
	return node
