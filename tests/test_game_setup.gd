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
	assert_true(setup.leader_option.get_item_text(0).contains("+15%"))
	setup.nation_option.select(2)
	setup.nation_option.emit_signal("item_selected", 2)
	assert_eq(setup.leader_option.item_count, LeaderCatalog.keys_for(2).size())
	assert_true(setup.leader_option.get_item_text(0).contains("Napoleon"))
	assert_true(setup.leader_option.get_item_text(0).contains("+25%"))


## The reported defect: the new-game screen printed "no land-combat bonus" for
## every crown but France, because five leaders had no entry in the bonus table
## (wiki: leader-bonuses § Bonus Table; DR-20261111-24). Every nation row must
## name its leader's real bonus.
func test_every_nation_row_names_a_land_bonus() -> void:
	for index: int in setup.nation_option.item_count:
		setup.nation_option.select(index)
		setup.nation_option.emit_signal("item_selected", index)
		assert_gt(setup.leader_option.item_count, 0, "nation %d fields a leader" % index)
		var text: String = setup.leader_option.get_item_text(0)
		assert_false(
			text.contains("no land-combat bonus"),
			"nation %d reads its leader's bonus: %s" % [index, text]
		)
		assert_true(text.contains("%"), "nation %d names a percentage: %s" % [index, text])


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


func test_difficulty_starts_on_normal_and_states_its_effect() -> void:
	assert_eq(setup.difficulty_option.item_count, Difficulty.IDS.size())
	assert_eq(setup.difficulty_option.selected, Difficulty.index_of(Difficulty.DEFAULT))
	assert_eq(setup.difficulty_option.get_item_text(0), "Introductory")
	assert_true(setup._difficulty_hint.text.contains("alike"), "Normal reads as the published rules")


func test_start_carries_the_chosen_difficulty_into_the_config() -> void:
	setup.difficulty_option.select(Difficulty.index_of("hard"))
	setup.difficulty_option.emit_signal("item_selected", Difficulty.index_of("hard"))
	assert_true(setup._difficulty_hint.text.contains("140%"))
	setup.start_button.emit_signal("pressed")
	assert_not_null(started)
	if started != null:
		assert_eq(started.difficulty, "hard")
		assert_eq(started.to_dict()["difficulty"], "hard")


func test_config_round_trips_the_difficulty_layer() -> void:
	var config: GameConfig = GameConfig.make(99, 1, 1, "", false, "", "impossible")
	var restored: GameConfig = GameConfig.from_dict(config.to_dict())
	assert_eq(restored.difficulty, "impossible")
	assert_eq(GameConfig.make(99, 1, 1).difficulty, Difficulty.DEFAULT)


## The extra row must not push SET SAIL off a landscape phone; the row itself
## rides the page's scroll like every later field (REQ-P1-05, REQ-P1-07;
## geometry measured like tests/test_mobile_layout.gd).
func test_phone_setup_keeps_the_difficulty_row_reachable() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(914, 411)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var page: GameSetupScreen = SETUP.instantiate()
	viewport.add_child(page)
	await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(viewport.size))
	assert_true(page.difficulty_option.is_visible_in_tree(), "the row is mounted")
	assert_true(_contains(screen, page.start_button.get_global_rect()), "SET SAIL stays on screen")
	assert_gt(page.start_button.size.y, 39.5, "SET SAIL is thumb-sized")
	assert_gt(page.difficulty_option.size.y, 39.5, "the Difficulty row is thumb-sized")
	var scroll: ScrollContainer = _page_scroll(page)
	assert_not_null(scroll, "the setup page scrolls its fields")
	if scroll != null:
		assert_true(scroll.scroll_vertical == 0, "the page opens at its top")
		assert_gt(
			scroll.get_v_scroll_bar().max_value,
			0.0,
			"the fields below the fold stay reachable by scrolling"
		)
		assert_true(
			scroll.find_children("*", "", true, false).has(page.difficulty_option),
			"the Difficulty row rides that scroll"
		)
	viewport.free()


func _page_scroll(page: Control) -> ScrollContainer:
	for node: Node in page.find_children("*", "ScrollContainer", true, false):
		return node as ScrollContainer
	return null


func _contains(outer: Rect2, inner: Rect2) -> bool:
	var pad: float = 0.5
	return (
		inner.position.x >= outer.position.x - pad
		and inner.position.y >= outer.position.y - pad
		and inner.end.x <= outer.end.x + pad
		and inner.end.y <= outer.end.y + pad
	)
