extends RefCounted
## First step of the e2e smoke: the real title -> setup -> capital chart ->
## crown's charge -> map flow, ending on the campaign the rest of the drive
## plays (wiki: capital-choice-phase § Player choice; docs/testing.md § E2E
## smoke). Each page is a named assert, so a flow change stops the drive where
## the player would and names the page that moved.
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const BOOT_FRAMES: int = 8
## The smoke drives the real title -> setup -> map flow. Small keeps it fast.
const SETUP_SIZE_INDEX: int = 0
const SETUP_SEED: String = "1500"

const SmokeRun = preload("res://tools/smoke/smoke_run.gd")


## True when a MapScreen is up with its own seat checked; false stops the drive.
static func step(run) -> bool:
	print("e2e_smoke: loading main scene")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	run.check(packed != null, "main.tscn loads")
	if packed == null:
		return false

	run.clean_save_dir()
	var main: Node = packed.instantiate()
	run.main = main
	run.tree.root.add_child(main)
	for _frame in BOOT_FRAMES:
		await run.tree.process_frame

	run.check(GameVersion.as_string() != "", "GameVersion.as_string non-empty")
	run.check(
		GameVersion.is_compatible_with(GameVersion.MAJOR), "GameVersion major compatible"
	)

	var menu: MainMenu = main.current_page as MainMenu
	run.check(menu != null, "main menu boots first")
	run.check(main.current_screen == null, "no map runs behind the title screen")
	if menu == null:
		return false
	# English-only: the tongue settings door is gone.
	menu.new_game_button.emit_signal("pressed")
	await run.tree.process_frame

	var setup: GameSetupScreen = main.current_page as GameSetupScreen
	run.check(setup != null, "new game opens the setup screen")
	if setup == null:
		return false
	setup.seed_field.text = SETUP_SEED
	setup.size_option.select(SETUP_SIZE_INDEX)
	run.check(setup.leader_option.item_count > 0, "leader choices offered at setup")
	run.check(
		setup.advanced_option != null and setup.advanced_option.item_count == 3,
		"setup offers the advanced-start openings"
	)
	# The difficulty row names the bar the chosen level sets, so the choice is
	# never blind (wiki: victory § Military victory; DR-20261111-28).
	run.check(
		run.has_text(setup, "hold %d Old World provinces" % VictoryRules.MILITARY_THRESHOLD),
		"setup states the crown's win bar"
	)
	setup.start_button.emit_signal("pressed")
	await run.tree.process_frame

	# Capital-choice phase: the chart is generated on the next idle frame, then
	# the crown's seat is confirmed (wiki: capital-choice-phase § Player choice).
	var chart: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	run.check(chart != null, "new game opens the capital chart")
	if chart == null:
		return false
	var waited: int = 0
	while chart.model == null and waited < 120:
		await run.tree.process_frame
		waited += 1
	run.check(chart.model != null, "the capital chart is generated")
	run.check(chart.selected_province >= 0, "the crown's recommended seat is marked")
	var seat: int = chart.selected_province
	var seat_tile: Vector2i = chart.selected_tile
	chart.confirm_button.emit_signal("pressed")
	await run.tree.process_frame

	# The crown's charge is the gate before the first turn (wiki: dialogue-management
	# § Kinds, `game_start_intro`): no campaign runs behind it, and one press opens
	# the age.
	var charge: IntroScreen = main.current_page as IntroScreen
	run.check(charge != null, "the crown's charge follows the capital chart")
	run.check(main.current_screen == null, "no campaign runs behind the charge")
	if charge == null:
		return false
	run.check(
		run.has_text(charge, FactionCatalog.name_of(0))
		or run.has_text(charge, "THE CROWN'S CHARGE"),
		"the charge names the crown and its title"
	)
	run.check(
		run.has_text(charge, str(VictoryRules.MILITARY_THRESHOLD)),
		"the charge publishes the win condition"
	)
	charge.begin_button.emit_signal("pressed")
	await run.tree.process_frame

	var screen: MapScreen = main.current_screen
	run.check(screen != null, "main hosts MapScreen")
	if screen == null:
		return false
	run.screen = screen
	screen.save_dir = SmokeRun.SAVE_DIR

	run.check(screen.model != null, "map model built")
	run.check(screen.model.province_count() > 0, "provinces generated")
	run.check(screen.capital_province == seat, "the chart's seat starts the campaign")
	run.check(screen.capital_tile == seat_tile, "the chart's tile is the seat")
	return true
