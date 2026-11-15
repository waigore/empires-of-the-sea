extends GdToolsTest
## App flow: title -> setup -> map, in-game menu, save slot, load rebuilds the
## screen (clearing the old game), and back to the title (REQ-P5-01, P5-07).
## One chart is rolled in `before_all` and handed through `Main.preset_world` so
## coverage does not pay `generate_world` on every new-game / load path.

const Fixture = preload("res://tests/map_fixture.gd")

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const DIR: String = "user://test_menu_flow"

const FLOW_SEED: int = 777
const FLOW_SIZE: Vector2i = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)

var main: Node = null
## Non-underscore: gd-tools copies these from `before_all` onto each test instance.
var flow_world: WorldMap = null
var flow_snapshot: Array = []


func before_all() -> void:
	flow_world = MapGenerator.new().generate_world(FLOW_SEED, FLOW_SIZE.x, FLOW_SIZE.y)
	flow_snapshot = Fixture.snapshot(flow_world)


func before_each() -> void:
	_clean_dir()
	Fixture.restore(flow_world, flow_snapshot)
	main = MAIN.instantiate()
	main.auto_start = false
	main.size_override = FLOW_SIZE
	main.preset_world = flow_world
	add_child(main)


func after_each() -> void:
	get_tree().paused = false
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	if is_instance_valid(main):
		main.free()
	main = null
	Fixture.restore(flow_world, flow_snapshot)
	_clean_dir()


## Android back from the setup page belongs to the title screen, not to the OS:
## the swap is deferred so the freshly built title page does not receive the
## same back request and quit the app (REQ-P5-01, REQ-P5-07).
func test_back_from_setup_returns_to_the_title() -> void:
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	assert_true(main.current_page is GameSetupScreen, "setup opens")
	main.current_page.back_pressed.emit()
	assert_true(
		main.current_page is GameSetupScreen,
		"the swap waits for the next idle frame"
	)
	await get_tree().process_frame
	assert_true(main.current_page is MainMenu, "back lands on the title screen")
	assert_null(main.current_screen, "no map was started")


func test_title_screen_offers_new_and_load() -> void:
	assert_true(main.current_page is MainMenu, "title screen boots first")
	var menu: MainMenu = main.current_page
	assert_true(menu.new_game_button != null)
	assert_true(menu.load_game_button != null)
	assert_true(menu.quit_button != null)
	assert_eq(DialogueLocale.locale(), DialogueLocale.SOURCE_LOCALE, "English only")


func test_new_game_setup_starts_the_chosen_world() -> void:
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	assert_true(main.current_page is GameSetupScreen, "setup opens")

	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(2)
	setup.size_option.select(0)
	setup.seed_field.text = str(FLOW_SEED)
	setup.start_button.emit_signal("pressed")

	var page: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	assert_not_null(page, "the capital-choice phase opens before turn 1")
	if page == null:
		return
	assert_null(main.current_screen, "no campaign runs behind the chart")
	await get_tree().process_frame
	assert_not_null(page.model, "the chart is generated")
	assert_true(page.world == flow_world, "the shell reused the cached chart")
	assert_eq(page.model.province_owner(page.selected_province), 2, "the seat is French")
	assert_false(page.confirm_button.disabled, "the recommended seat can be confirmed")
	page.confirm_button.emit_signal("pressed")
	_pass_the_charge()

	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "confirming the seat starts the map screen")
	if screen == null:
		return
	assert_eq(screen.player_faction, 2, "France is the human crown")
	assert_eq(screen.play.player_faction, 2)
	assert_eq(screen.play.map_seed, FLOW_SEED)
	assert_eq(screen.map_width, FLOW_SIZE.x)
	assert_eq(screen.map_height, FLOW_SIZE.y)
	assert_eq(screen.model.province_owner(screen.capital_province), 2, "seat is French")
	assert_eq(screen.capital_province, page.selected_province, "the chart's seat starts")
	assert_eq(screen.capital_tile, page.selected_tile, "the chart's tile starts")
	assert_eq(screen.hud._nation_label.text, "FRANCE")
	assert_eq(screen.visibility.player_id, 2, "fog belongs to France")
	assert_eq(screen.economy.player_faction, 2, "economy belongs to France")
	var french_fleets: int = 0
	for fleet: FleetState in screen.ship_layer.fleets:
		if fleet.owner == 2:
			french_fleets += 1
	assert_eq(french_fleets, FleetMuster.PLAYER_FLEETS, "player squadrons fly French colours")
	var home: ArmyState = null
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == 2 and army.is_home_army():
			home = army
	assert_not_null(home, "French Home Army musters")
	if home != null:
		assert_eq(home.province, screen.capital_province, "Home Army holds the seat")


## The chart's pick is the campaign's seat: home fleet, Home Army and fog all
## muster on the province the player chose, not the auto-choice one.
func test_a_chosen_seat_reaches_the_campaign() -> void:
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(0)
	setup.size_option.select(0)
	setup.seed_field.text = str(FLOW_SEED)
	setup.start_button.emit_signal("pressed")
	var page: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	assert_not_null(page, "the capital-choice phase opens")
	if page == null:
		return
	await get_tree().process_frame
	var model: MapModel = page.model
	var faction: int = page.config.player_faction
	var target: int = _other_coast(model, page.selected_province, faction)
	assert_gte(target, 0, "the crown holds a second seaboard province")
	if target < 0:
		return
	var tile: Vector2i = model.province_tiles(target)[0]
	assert_true(page.pick_province(target))
	assert_true(page.pick_tile(tile))
	page.confirm_button.emit_signal("pressed")
	_pass_the_charge()

	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "the campaign starts")
	if screen == null:
		return
	assert_eq(screen.capital_province, target, "the chosen province is the seat")
	assert_eq(screen.capital_tile, tile, "the chosen tile is the seat")
	var home: ArmyState = null
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == faction and army.is_home_army():
			home = army
	assert_not_null(home, "the Home Army musters")
	if home != null:
		assert_eq(home.province, target, "the Home Army holds the chosen seat")


## Pause menu shows the live map seed; COPY confirms (clipboard is unsupported
## under the headless display server used by gd-tools).
func test_pause_menu_shows_and_copies_map_seed() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	if screen == null:
		return
	screen.game_menu.open()
	assert_eq(
		screen.game_menu.seed_label.text, str(FLOW_SEED), "pause menu shows the live seed"
	)
	assert_false(screen.game_menu.copy_seed_button.disabled, "copy is available")
	screen.game_menu.copy_seed_button.emit_signal("pressed")
	assert_eq(screen.game_menu._status.text, "Seed copied.", "copy confirms")
	screen.game_menu.close()


## Back from the save browser returns to the pause rows; back again closes
## (REQ-P5-07). Covers the browser-visible branch of handle_back.
func test_back_from_the_save_browser_returns_to_pause() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	if screen == null:
		return
	screen.game_menu.open()
	screen.game_menu.open_save()
	assert_true(screen.game_menu.browser.visible, "save browser opens")
	assert_true(screen.game_menu.handle_back(), "back is handled")
	assert_false(screen.game_menu.browser.visible, "browser steps aside")
	assert_true(screen.game_menu.is_open(), "pause menu stays open")
	assert_true(get_tree().paused, "tree stays paused")
	assert_true(screen.game_menu.handle_back(), "back closes the pause menu")
	assert_false(screen.game_menu.is_open(), "pause menu closed")
	assert_false(get_tree().paused, "tree resumes")
	assert_false(screen.game_menu.handle_back(), "back is a no-op when closed")


## The chart's controls read on one page from the pause (REQ-P5-03, REQ-P5-07):
## every action the map registers is named, each row prints the key the InputMap
## actually holds, and back returns to the pause rows.
func test_the_pause_page_reads_the_charts_keys() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	if screen == null:
		return
	InputActions.ensure_actions()
	screen.game_menu.open()
	screen.game_menu.keys_button.emit_signal("pressed")
	assert_true(screen.game_menu.is_open(), "the pause stays open")
	assert_true(screen.game_menu._keys_page.visible, "the keys page is up")
	assert_false(screen.game_menu._pause_page.visible, "the pause rows step aside")
	var rows: Array[Control] = _key_rows(screen.game_menu._keys_page)
	var listed: int = 0
	for group: Dictionary in KeyReference.groups():
		listed += (group["rows"] as Array).size()
	assert_eq(rows.size(), listed, "one row per control on the page")
	for row: Control in rows:
		assert_ne(_key_chip(row), KeyReference.NO_KEY, "every row prints a key")
	# A named control reads its own binding, so a rebind moves the page.
	assert_eq(
		_key_chip(_row_for(rows, "Muster roll")),
		KeyReference.primary(InputActions.MUSTER_ROLL),
		"the muster row prints the key the InputMap holds (O on a QWERTY cap)"
	)
	assert_true(
		_key_chip(_row_for(rows, "Pan")).contains(" "), "the four pan keys read as a cluster"
	)
	assert_true(screen.game_menu.handle_back(), "back is handled")
	assert_false(screen.game_menu._keys_page.visible, "the keys page steps aside")
	assert_true(screen.game_menu._pause_page.visible, "the pause rows come back")
	assert_true(screen.game_menu.is_open(), "the pause menu stays open")
	screen.game_menu.close()


## No control ships unread: every action `InputActions` registers has a row on
## the page (REQ-P5-03). The guard is the catalogue's own constant map, so a new
## key cannot land without the sheet naming it.
func test_every_registered_action_is_on_the_keys_page() -> void:
	InputActions.ensure_actions()
	var named: Array[String] = KeyReference.actions()
	var table: Dictionary = load("res://scripts/input_actions.gd").get_script_constant_map()
	var missing: Array[String] = []
	for constant: Variant in table.keys():
		var action: String = String(table[constant])
		if action.is_empty() or named.has(action):
			continue
		# The page prints the actions the chart answers to; a constant that is
		# not an InputMap action is not a key.
		if InputMap.has_action(action):
			missing.append(action)
	assert_eq(missing, [] as Array[String], "every registered action is named")


func test_menu_save_load_and_return_flow() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	screen.game_menu.open()
	assert_true(screen.game_menu.is_open(), "menu opens")
	assert_true(get_tree().paused, "tree pauses behind the menu")
	screen.game_menu.open_save()
	screen.game_menu.browser.slot_chosen.emit(2)
	assert_true(SaveStore.has_slot(2, DIR), "slot 2 written")
	assert_true(screen.game_menu._status.text.contains("Saved"))
	screen.game_menu.close()
	assert_false(get_tree().paused, "tree resumes")

	screen.play.turn = 9
	screen.play.economy.economy.treasury = 999_999
	screen.game_menu.load_chosen.emit(2)

	var loaded: MapScreen = main.current_screen
	assert_not_null(loaded, "a new screen is installed")
	if loaded == null:
		return
	assert_true(loaded != screen, "the old screen is replaced")
	assert_null(screen.get_parent(), "the old screen left the tree")
	assert_eq(loaded.play.turn, 1, "saved turn restored")
	assert_eq(
		loaded.play.economy.economy.treasury,
		PlayerEconomy.START_TREASURY,
		"saved treasury restored"
	)
	assert_eq(loaded.save_dir, DIR, "load keeps the slot directory")
	assert_eq(loaded.player_faction, 2, "saved human crown restored")
	assert_eq(loaded.play.economy.player_faction, 2, "economy follows the crown")
	assert_eq(loaded.play.visibility.player_id, 2, "fog follows the crown")
	assert_eq(loaded.hud._nation_label.text, "FRANCE")

	loaded.game_menu.main_menu_chosen.emit()
	assert_true(main.current_page is MainMenu, "title screen returns")
	assert_null(main.current_screen, "no map survives the return")


func test_title_screen_mounts_a_living_backdrop() -> void:
	var menu: MainMenu = main.current_page
	assert_not_null(menu.backdrop, "title screen owns a living backdrop")
	assert_eq(menu.backdrop.get_index(), 0, "backdrop paints behind every menu control")
	assert_not_null(menu.backdrop.plate, "painted plate is the far plane")
	assert_not_null(menu.backdrop.life, "gulls and embers layer exists")
	assert_eq(menu.backdrop.ships.size(), 2, "two carracks ride the bay")


func test_backdrop_covers_phone_desktop_and_short_windows() -> void:
	var menu: MainMenu = main.current_page
	var backdrop: MenuBackdrop = menu.backdrop
	for view: Vector2 in [Vector2(1280, 720), Vector2(720, 1280), Vector2(2560, 1080)]:
		backdrop.fit(view)
		var rect: Rect2 = backdrop.stage_rect()
		assert_true(rect.position.x <= 0.05, "stage is flush with the left edge")
		assert_true(rect.position.y <= 0.05, "stage is flush with the top edge")
		assert_true(rect.size.x >= view.x, "stage covers the full width")
		assert_true(rect.size.y >= view.y, "stage covers the full height")


func test_carrack_bobs_wraps_and_fades_at_the_lane_edge() -> void:
	var menu: MainMenu = main.current_page
	var ship: MenuShip = menu.backdrop.ships[1]
	var start_y: float = ship.position.y
	ship.advance(0.7)
	assert_true(absf(ship.position.y - start_y) > 0.0, "hull rides the swell")
	ship.bounds = Vector2(0.0, 1000.0)
	ship.place_at(995.0)
	assert_true(ship.modulate.a < 0.2, "hull dissolves before the lane edge")
	ship.place_at(1001.0)
	ship.advance(0.0)
	assert_eq(ship.position.x, 0.0, "hull re-enters from the far edge")


func test_ambient_life_keeps_gulls_and_embers() -> void:
	var menu: MainMenu = main.current_page
	var life: MenuLife = menu.backdrop.life
	assert_eq(life._birds.size(), MenuLife.BIRD_COUNT)
	assert_eq(life._embers.size(), MenuLife.EMBER_COUNT)
	life._process(0.5)
	assert_true(life._time > 0.0)


## A slot that cannot be read is refused in place: the browser names it, the
## router keeps the running campaign, and the notice lands on the pause menu
## (wiki: campaign-persistence § Load and resume — announced, never silent).
func test_an_unreadable_slot_never_replaces_the_running_campaign() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	if screen == null:
		return
	var path: String = SaveStore.path_for(4, DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "the unreadable fixture opens")
	if file == null:
		return
	file.store_string("not a save at all")
	file.close()
	var turn: int = screen.play.turn
	screen.game_menu.open()
	screen.game_menu.open_load()
	var row: Button = screen.game_menu.browser.slot_buttons[3]
	assert_false(row.disabled, "the slot is not offered as empty")
	assert_true(row.text.contains("Unreadable"), "the row says it cannot be read")
	row.emit_signal("pressed")
	assert_eq(screen.game_menu.browser._status.text, SaveBrowser.UNREADABLE)
	assert_true(screen.game_menu.browser.visible, "the browser stays open")
	# Even a caller that bypasses the browser cannot replace the campaign.
	screen.game_menu.load_chosen.emit(4)
	assert_true(main.current_screen == screen, "the campaign is not replaced")
	assert_true(main.current_page == screen, "no title screen is installed")
	assert_eq(screen.play.turn, turn, "the turn is untouched")
	assert_eq(
		screen.game_menu._status.text, SaveBrowser.UNREADABLE, "the pause menu shows the notice"
	)
	assert_true(screen.game_menu.is_open(), "the player is back on the pause menu")
	# Saving over a file the build cannot read asks the confirming press first.
	screen.game_menu.open_save()
	screen.game_menu.browser.slot_buttons[3].emit_signal("pressed")
	assert_true(
		screen.game_menu.browser._status.text.contains("again"), "a used slot asks twice"
	)
	assert_false(
		SaveCodec.is_valid(SaveStore.read(path)), "one press leaves the file alone"
	)


## The campaign length is fixed at creation, so the row that offers a load names
## it and loading an Endless save keeps its open calendar (wiki:
## campaign-persistence § Load and resume, DR-20261111-08).
func test_a_slot_row_names_its_campaign_length() -> void:
	await _start_game()
	var screen: MapScreen = main.current_screen
	if screen == null:
		return
	screen.game_menu.open()
	screen.game_menu.open_save()
	screen.game_menu.browser.slot_chosen.emit(1)
	var label: String = screen.game_menu.browser.slot_buttons[0].text
	assert_true(label.contains("Historical"), "a historical row names it: %s" % label)

	screen.play.infinite_mode = true
	screen.game_menu.browser.slot_chosen.emit(2)
	label = screen.game_menu.browser.slot_buttons[1].text
	assert_true(label.contains("Endless"), "an endless row names it: %s" % label)

	screen.game_menu.load_chosen.emit(2)
	var loaded: MapScreen = main.current_screen
	assert_not_null(loaded, "the endless save loads")
	if loaded == null:
		return
	assert_true(loaded.play.infinite_mode, "an endless campaign loads endless")


func _start_game() -> void:
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(2)
	setup.size_option.select(0)
	setup.seed_field.text = str(FLOW_SEED)
	setup.start_button.emit_signal("pressed")
	# The capital-choice chart binds the cached world on ready; confirming the
	# recommended seat is the default setup path (wiki: capital-choice-phase).
	var page: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	if page != null:
		await get_tree().process_frame
		page.confirm_button.emit_signal("pressed")
		_pass_the_charge()
	assert_not_null(main.current_screen, "game started")
	if main.current_screen != null:
		main.current_screen.save_dir = DIR


## The crown's charge sits between the chart and the first turn: one press opens
## the age (wiki: dialogue-management § Kinds, `game_start_intro`).
func _pass_the_charge() -> void:
	var page: IntroScreen = main.current_page as IntroScreen
	if page != null:
		page.begin_button.emit_signal("pressed")


## Another sea-bound province of the given crown (for the seat-choice cases).
func _other_coast(model: MapModel, first: int, faction: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != faction or province.id == first:
			continue
		if CapitalChoice.is_sea_bound(model, province.id):
			return province.id
	return -1


func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)


## The keys page's rows, in reading order: one `KeyRow` per control. Godot gives
## duplicate sibling names an internal spelling, so the cases read the rows by
## shape (an HBox row beside the group captions and rules) rather than by name.
func _key_rows(page: Control) -> Array[Control]:
	var out: Array[Control] = []
	for node: Node in page.get_children():
		var row := node as HBoxContainer
		if row != null:
			out.append(row)
	return out


## The key a row prints, read off its own cap; "" when the row has none.
func _key_chip(row: Control) -> String:
	if row == null:
		return ""
	for node: Node in row.find_children("KeyChip", "", true, false):
		var plate := node as PanelContainer
		if plate == null or plate.get_child_count() == 0:
			continue
		var label := plate.get_child(0) as Label
		if label != null:
			return label.text
	return ""


## The row whose words open with this control's name.
func _row_for(rows: Array[Control], label: String) -> Control:
	for row: Control in rows:
		for raw: Variant in row.get_children():
			var text := raw as Label
			if text != null and text.text.begins_with(label):
				return row
	return null


# --- application shell -------------------------------------------------------
## The shell's own boot (merged from test_main): the title is the entry point,
## an auto-start goes straight to the chart, and the debug door seats an all-AI
## observer. Each case drops the flow's shell first, so only one campaign is
## ever mounted in the tree.


func _drop_flow_shell() -> void:
	if is_instance_valid(main):
		main.free()
	main = null


func test_main_shell_boots_the_title_screen() -> void:
	_drop_flow_shell()
	var shell: Node = MAIN.instantiate()
	add_child(shell)
	assert_true(shell.current_page is MainMenu, "title screen is the entry point")
	assert_null(shell.current_screen)
	assert_not_null(shell.audio, "the shell mounts one audio director")
	assert_not_null(shell.soundtrack, "the shell mounts the launch score")
	shell.free()


func test_auto_start_boots_the_map_screen() -> void:
	_drop_flow_shell()
	var chart: WorldMap = Fixture.world()
	var snap: Array = Fixture.snapshot(chart)
	var shell: Node = MAIN.instantiate()
	shell.auto_start = true
	shell.map_width = Fixture.WORLD_WIDTH
	shell.map_height = Fixture.WORLD_HEIGHT
	shell.preset_world = chart
	add_child(shell)
	assert_true(shell.current_screen is MapScreen, "auto-start goes straight to play")
	assert_true(shell.current_screen.play.world == chart, "auto-start reused the cached chart")
	shell.free()
	Fixture.restore(chart, snap)


## Debug door: the title screen starts a fully-AI campaign with no human court.
func test_observer_entry_starts_an_all_ai_campaign() -> void:
	_drop_flow_shell()
	var chart: WorldMap = Fixture.world()
	var snap: Array = Fixture.snapshot(chart)
	var shell: Node = MAIN.instantiate()
	shell.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	shell.preset_world = chart
	add_child(shell)
	var menu: MainMenu = shell.current_page as MainMenu
	assert_not_null(menu, "the title screen offers the door")
	if menu == null:
		shell.free()
		Fixture.restore(chart, snap)
		return
	menu.observer_pressed.emit()
	var screen: MapScreen = shell.current_screen
	assert_not_null(screen, "the observer builds a map screen")
	if screen == null:
		shell.free()
		Fixture.restore(chart, snap)
		return
	assert_true(screen.play.world == chart, "the observer reused the cached chart")
	assert_true(screen.observer_mode, "the screen runs the full-AI observer")
	assert_true(screen.play.observer_mode, "the session runs the full-AI observer")
	assert_true(screen.play.infinite_mode, "an observer may outlast the calendar cap")
	assert_eq(screen.play.diplomacy.human_faction, MapModel.NO_ID, "no human court")
	assert_false(screen.hud.visible, "the human chrome stays hidden")
	assert_true(screen.game_menu.save_button.disabled, "an observer session is not saved")
	assert_not_null(screen.get_node_or_null("AiObserver"), "the dashboard mounts")
	shell.free()
	Fixture.restore(chart, snap)
