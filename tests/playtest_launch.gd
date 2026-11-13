extends RefCounted
## Shared launch path for the hand-run playtest drives (docs/testing.md § Free
## playtest drives): title -> setup -> capital chart -> map. The chart is a real
## phase before turn 1 (wiki: capital-choice-phase § Player choice), so every
## drive must confirm it; a driver that stops at the setup screen never reaches
## a MapScreen and silently reports "map screen missing".
##
## No `class_name`: the drives preload this file, so a fresh clone, a manual run
## and the gd-tools cache all resolve it the same way.
##
## A failure here is a flow change, not a game defect: the drives are manual
## tools, so the message says which page was expected.

const MAX_CHART_FRAMES: int = 300


## `advanced` picks an advanced-start preset (see AdvancedStart); empty keeps the
## turn-0 campaign, so every existing drive is unchanged. `faction` picks the
## crown at setup (default Spain, the catalog's player slot); a drive that walks
## court state must be able to play a crown that is not faction 0.
static func open_map(
	tree: SceneTree,
	seed_text: String,
	size_index: int = 0,
	advanced: String = "",
	faction: int = -1
) -> MapScreen:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("playtest: main.tscn did not load")
		return null
	var main: Node = packed.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var menu: MainMenu = main.current_page as MainMenu
	if menu == null:
		push_error("playtest: the title screen did not open — update tests/playtest_launch.gd")
		return null
	menu.new_game_button.emit_signal("pressed")
	await tree.process_frame
	var setup: GameSetupScreen = main.current_page as GameSetupScreen
	if setup == null:
		push_error("playtest: the setup screen did not open — update tests/playtest_launch.gd")
		return null
	setup.seed_field.text = seed_text
	setup.size_option.select(size_index)
	if faction >= 0 and setup.nation_option != null:
		for index in setup.nation_option.item_count:
			if setup.nation_option.get_item_id(index) == faction:
				setup.nation_option.select(index)
				setup.nation_option.item_selected.emit(index)
				break
	if not advanced.is_empty() and setup.advanced_option != null:
		var preset: String = AdvancedStart.normalize(advanced)
		var index: int = AdvancedStart.IDS.find(preset)
		if index >= 0:
			setup.advanced_option.select(index)
			setup.advanced_option.item_selected.emit(index)
	setup.start_button.emit_signal("pressed")
	await tree.process_frame
	# The capital chart generates its world on the next idle frame, then the
	# crown's seat is confirmed (wiki: capital-choice-phase § Player choice).
	var chart: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	if chart == null:
		push_error("playtest: the capital chart did not open — update tests/playtest_launch.gd")
		return null
	var waited: int = 0
	while chart.model == null and waited < MAX_CHART_FRAMES:
		await tree.process_frame
		waited += 1
	if chart.model == null:
		push_error("playtest: the capital chart never generated a world")
		return null
	chart.confirm_button.emit_signal("pressed")
	await tree.process_frame
	# The crown's charge sits between the chart and the first turn.
	var charge: IntroScreen = main.current_page as IntroScreen
	if charge != null:
		charge.begin_button.emit_signal("pressed")
		await tree.process_frame
	var screen: MapScreen = main.current_screen
	if screen == null:
		push_error("playtest: the map screen did not open after the charge")
	return screen
