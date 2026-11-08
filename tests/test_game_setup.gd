extends GdToolsTest
## New-game setup: nation, seed and map-size choices resolve into one config.

const SETUP: PackedScene = preload("res://scenes/game_setup.tscn")

var setup: GameSetupScreen = null
var started: GameConfig = null
var back_presses: int = 0


func before_each() -> void:
	started = null
	back_presses = 0
	setup = SETUP.instantiate()
	setup.start_requested.connect(func(config: GameConfig) -> void: started = config)
	setup.back_pressed.connect(func() -> void: back_presses += 1)
	add_child(setup)


func after_each() -> void:
	if is_instance_valid(setup):
		setup.free()
	setup = null


func test_offers_every_great_power_and_size_preset() -> void:
	assert_eq(setup.nation_option.item_count, FactionCatalog.great_power_ids().size())
	assert_eq(setup.nation_option.get_item_text(0), "Spain")
	assert_eq(setup.nation_option.get_item_id(1), 1, "England keeps its faction id")
	assert_eq(setup.size_option.item_count, GameConfig.SIZES.size())
	assert_eq(setup.size_option.selected, GameConfig.DEFAULT_SIZE_INDEX)
	assert_true(setup.seed_field.placeholder_text.contains("random"))


func test_leader_choices_follow_the_chosen_crown() -> void:
	assert_eq(setup.leader_option.item_count, LeaderCatalog.keys_for(0).size())
	assert_true(setup.leader_option.get_item_text(0).contains("Isabella I"))
	assert_true(setup.leader_option.get_item_text(0).contains("no land-combat bonus"))
	setup.nation_option.select(2)
	setup.nation_option.emit_signal("item_selected", 2)
	assert_eq(setup.leader_option.item_count, LeaderCatalog.keys_for(2).size())
	assert_true(setup.leader_option.get_item_text(0).contains("Napoleon"))
	assert_true(setup.leader_option.get_item_text(0).contains("+25%"))


func test_start_carries_the_chosen_leader_into_the_config() -> void:
	setup.nation_option.select(2)
	setup.nation_option.emit_signal("item_selected", 2)
	setup.seed_field.text = "42"
	setup.start_button.emit_signal("pressed")
	assert_not_null(started)
	if started != null:
		assert_eq(started.player_faction, 2)
		assert_eq(started.player_leader, "napoleon")


func test_start_resolves_nation_seed_and_size() -> void:
	setup.nation_option.select(1)
	setup.size_option.select(2)
	setup.seed_field.text = "777"
	setup.start_button.emit_signal("pressed")
	assert_not_null(started, "start emits a config")
	if started == null:
		return
	assert_eq(started.player_faction, 1, "England is the human slot")
	assert_eq(started.map_seed, 777)
	assert_eq(started.map_width, int(GameConfig.SIZES[2]["width"]))
	assert_eq(started.map_height, int(GameConfig.SIZES[2]["height"]))


func test_invalid_seed_keeps_the_player_on_setup() -> void:
	setup.seed_field.text = "not-a-number"
	setup.start_button.emit_signal("pressed")
	assert_null(started, "no config on an invalid seed")
	assert_true(setup._error.visible, "the error is shown")


func test_blank_seed_rolls_a_non_zero_seed() -> void:
	setup.seed_field.text = ""
	setup.start_button.emit_signal("pressed")
	assert_not_null(started)
	if started != null:
		assert_gt(started.map_seed, 0, "blank seed becomes random")


func test_back_emits_once() -> void:
	setup.back_button.emit_signal("pressed")
	assert_eq(back_presses, 1)


func test_config_round_trips_through_plain_data() -> void:
	var config: GameConfig = GameConfig.make(1234, 0, 3, "henry")
	var restored: GameConfig = GameConfig.from_dict(config.to_dict())
	assert_eq(restored.map_seed, 1234)
	assert_eq(restored.map_width, int(GameConfig.SIZES[0]["width"]))
	assert_eq(restored.map_height, int(GameConfig.SIZES[0]["height"]))
	assert_eq(restored.player_faction, 3)
	assert_eq(restored.player_leader, "henry")


func test_config_refuses_a_leader_the_crown_does_not_field() -> void:
	var config: GameConfig = GameConfig.make(1234, 0, 0, "napoleon")
	assert_eq(config.player_leader, "isabella", "Spain keeps its configured leader")
