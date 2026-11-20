extends GdToolsTest
## App flow: title -> setup -> map, in-game menu, save slot, load rebuilds the
## screen (clearing the old game), and back to the title (REQ-P5-01, P5-07).
## One chart is rolled in `before_all` and handed through `Main.preset_world` so
## coverage does not pay `generate_world` on every new-game / load path. Pure
## charge / key-catalogue cases never touch the shell, so they skip a Main boot
## under coverage (docs/testing.md § Speed rules).

const Fixture = preload("res://tests/map_fixture.gd")

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const DIR: String = "user://test_menu_flow"

const FLOW_SEED: int = 777
const FLOW_SIZE: Vector2i = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)

## Backing store for the lazy shell; cases reach it through `main`.
var _main: Node = null
## Non-underscore: gd-tools copies these from `before_all` onto each test instance.
var flow_world: WorldMap = null
var flow_snapshot: Array = []


func before_all() -> void:
	flow_world = MapGenerator.new().generate_world(FLOW_SEED, FLOW_SIZE.x, FLOW_SIZE.y)
	flow_snapshot = Fixture.snapshot(flow_world)


func before_each() -> void:
	_clean_dir()
	Fixture.restore(flow_world, flow_snapshot)


## Flow cases ask for the shell; charge / key-catalogue cases that never ask
## never pay a `Main` instantiate under coverage.
func _ensure_shell() -> Node:
	if is_instance_valid(_main):
		return _main
	_main = MAIN.instantiate()
	_main.auto_start = false
	_main.size_override = FLOW_SIZE
	_main.preset_world = flow_world
	add_child(_main)
	return _main


var main: Node:
	get:
		return _ensure_shell()


func after_each() -> void:
	get_tree().paused = false
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	if is_instance_valid(_main):
		_main.free()
	_main = null
	# The intro cases mount their own charge page; the flow cases do not.
	if is_instance_valid(page):
		page.free()
	page = null
	for holder: SubViewport in _mounted:
		if is_instance_valid(holder):
			holder.free()
	_mounted.clear()
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
	assert_false(menu.has_signal("observer_pressed"), "no debug door on the title menu")
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


## Every rival's temperament is chosen on the new-game screen, fixed for the run
## and carried into the session and the save (wiki: ai-profile-overrides
## § Design intent; ai-parameter-registry § Seed profiles — "a small blessed set
## … for new-game AI slot overrides").
func test_setup_binds_a_temperament_to_each_rival() -> void:
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page as GameSetupScreen
	assert_not_null(setup, "setup opens")
	if setup == null:
		return
	# One chooser per rival; the player's own crown is no AI slot.
	var rivals: int = FactionCatalog.great_power_ids().size() - 1
	assert_eq(setup._rival_options.size(), rivals, "one chooser per rival")
	var human: int = int(setup.nation_option.get_item_id(setup.nation_option.selected))
	assert_false(setup._rival_options.has(human), "the crown's own seat carries no temperament")
	# The rows follow the crown: taking another seat makes it no AI slot, and the
	# seat it leaves becomes one again.
	setup.nation_option.select(2)
	setup.nation_option.item_selected.emit(2)
	assert_false(setup._rival_options.has(2), "the new crown's seat carries no temperament")
	assert_true(setup._rival_options.has(human), "the seat it left is a rival again")
	setup.nation_option.select(0)
	setup.nation_option.item_selected.emit(0)
	# Bind France the aggressive temperament through its own chooser.
	var option: OptionButton = setup._rival_options.get(2, null)
	assert_not_null(option, "France has a chooser")
	if option == null:
		return
	var ids: Array[String] = AiProfile.ids()
	var aggressive: int = ids.find(AiProfile.AGGRESSIVE)
	option.select(aggressive)
	option.item_selected.emit(aggressive)
	# The row prints what the temperament shifts, and the summary names it.
	var note: Label = setup._rival_notes.get(2, null)
	assert_not_null(note, "the row keeps its note")
	if note != null:
		assert_eq(note.text, AiProfile.hint(AiProfile.AGGRESSIVE), "the effect is printed, not hovered")
	assert_true(setup._summary.text.contains("France Aggressive"), "SET SAIL names the binding")
	# A second pick joins the summary, and one put back on the neutral profile
	# prints no line at all.
	var england: OptionButton = setup._rival_options.get(1, null)
	assert_not_null(england, "England has a chooser")
	if england != null:
		var economic: int = ids.find(AiProfile.ECONOMIC)
		england.select(economic)
		england.item_selected.emit(economic)
		assert_eq(
			String(setup._rival_notes[1].text), AiProfile.hint(AiProfile.ECONOMIC),
			"the second pick prints its own effect"
		)
		assert_true(
			setup._summary.text.contains("England Economic")
			and setup._summary.text.contains("France Aggressive"),
			"every non-neutral pick is named before SET SAIL"
		)
		var normal: int = ids.find(AiProfile.NORMAL)
		england.select(normal)
		england.item_selected.emit(normal)
		assert_eq(String(setup._rival_notes[1].text), "", "the neutral profile prints nothing")
	setup.size_option.select(0)
	setup.seed_field.text = str(FLOW_SEED)
	setup.start_button.emit_signal("pressed")
	var page: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	assert_not_null(page, "the capital-choice phase opens")
	if page == null:
		return
	await get_tree().process_frame
	page.confirm_button.emit_signal("pressed")
	_pass_the_charge()
	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "the map screen starts")
	if screen == null:
		return
	var play: PlaySession = screen.play
	assert_eq(String(play.ensure_ai().profiles.get(2, "")), AiProfile.AGGRESSIVE, "France plans aggressive")
	assert_eq(String(play.ensure_ai().profiles.get(1, "")), AiProfile.NORMAL, "an untouched rival plans neutral")
	assert_eq(
		String(play.ensure_ai().profiles.get(play.player_faction, "")), AiProfile.NORMAL,
		"the crown's own seat plans neutral"
	)
	assert_eq(
		AiProfile.for_court(2, play.map_seed, play.ensure_ai().profiles).profile,
		AiProfile.AGGRESSIVE,
		"the court's config reads the binding"
	)
	# The campaign carries it: the AI bookkeeping holds the binding, and a load
	# resumes the same rivals.
	var save: Dictionary = SaveCodec.capture(play)
	var ai_saved: Dictionary = (save.get("session", {}) as Dictionary).get("ai", {})
	assert_eq(
		String((ai_saved.get("profiles", {}) as Dictionary).get(2, "")),
		AiProfile.AGGRESSIVE,
		"the save carries the temperament"
	)
	assert_true(SaveCodec.restore(play, save, flow_world), "the save restores")
	assert_eq(String(play.ensure_ai().profiles.get(2, "")), AiProfile.AGGRESSIVE, "a load resumes it")


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
	if is_instance_valid(_main):
		_main.free()
	_main = null


## The shell `before_each` mounted is the title screen: read it in place instead
## of paying a second `Main` boot for the same assertion.
func test_main_shell_boots_the_title_screen() -> void:
	assert_true(main.current_page is MainMenu, "title screen is the entry point")
	assert_null(main.current_screen)
	assert_not_null(main.audio, "the shell mounts one audio director")
	assert_not_null(main.soundtrack, "the shell mounts the launch score")


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


## Debug door: the desktop `--ai-observer` switch boots a fully-AI campaign with
## no human court, and the title screen never appears (docs/ai-observer.md).
func test_observer_launch_starts_an_all_ai_campaign() -> void:
	_drop_flow_shell()
	var chart: WorldMap = Fixture.world()
	var snap: Array = Fixture.snapshot(chart)
	var shell: Node = MAIN.instantiate()
	shell.observer_start = true
	shell.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	shell.preset_world = chart
	add_child(shell)
	assert_false(shell.current_page is MainMenu, "the switch skips the title screen")
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


## The switch is read from the user args after `--`, and only as its own arg: a
## value after `=` or a neighbouring switch never opens the observer.
func test_the_observer_switch_is_read_from_the_user_args() -> void:
	var script: Script = load("res://scenes/main.gd")
	assert_true(script.has_observer_flag(PackedStringArray(["--ai-observer"])))
	assert_true(script.has_observer_flag(PackedStringArray(
		["--agent-debug=8765", " --ai-observer "]
	)))
	assert_false(script.has_observer_flag(PackedStringArray(["--ai-observer=1"])))
	assert_false(script.has_observer_flag(PackedStringArray(["--ai-observe"])))
	assert_false(script.has_observer_flag(PackedStringArray([])))

# --- the crown's charge (campaign intro) ---

## The crown's charge: the campaign's opening gate (wiki: dialogue-content-and- yarn §
## Kinds, `game_start_intro`; dialogue-management § Kinds). One dismissal before the first
## turn, printed from the rules and reachable on every platform.


const INTRO: PackedScene = preload("res://scenes/intro.tscn")
## Shared fixture size: the flow reuses `Fixture.world()` via `Main.preset_world`
## so this case does not roll a chart under coverage.

var page: IntroScreen = null
var _mounted: Array[SubViewport] = []


## Only the cases that read the page pay for building it; the rest assert the
## rules the charge is composed from, so a mounted broadside would be wasted
## paint under coverage.
func _page() -> IntroScreen:
	if page == null:
		page = INTRO.instantiate()
		page.show_address(CampaignIntro.address(
			"Spain", "Isabella I", "Madrid", 1, false, CampaignIntro.salt(1500, 0)
		))
		add_child(page)
		await get_tree().process_frame
	return page


## The charge names the crown, the leader and the seat the chart just confirmed,
## and opens in the campaign's own year (wiki: advanced-starts).
func test_the_charge_names_the_crown_the_leader_and_the_seat() -> void:
	var charge: Dictionary = CampaignIntro.address(
		"Spain", "Isabella I", "Madrid", 1, false, 3
	)
	assert_eq(String(charge["kicker"]), CampaignIntro.KICKER)
	assert_eq(String(charge["title"]), CampaignIntro.TITLE)
	assert_eq(String(charge["begin"]), CampaignIntro.BEGIN)
	var body: String = String(charge["body"])
	assert_true(body.contains("Isabella I"), "the leader is addressed by name")
	assert_false(body.contains("{leader}"), "no placeholder reaches the page")
	assert_false(body.contains("{crown}"), "the crown name is filled in")
	assert_true(String(charge["stamp"]).contains("1500"), "the stamp names the year")
	assert_true(String(charge["stamp"]).contains("Madrid"), "the stamp names the seat")


## An advanced start opens in its own year, not in 1500: the campaign's calendar
## is the one the charge prints (wiki: advanced-starts).
func test_an_advanced_start_opens_in_its_own_year() -> void:
	var charge: Dictionary = CampaignIntro.address("Spain", "Isabella I", "Madrid", 50, false, 1)
	assert_true(
		String(charge["stamp"]).contains(str(TurnTime.year_for_turn(50))),
		"the stamp follows the preset's turn"
	)


## The same seed and crown always open with the same words, so a replay and a
## reload speak alike; a different crown may be addressed differently.
func test_the_same_campaign_opens_with_the_same_words() -> void:
	var salt: int = CampaignIntro.salt(1500, 0)
	var first: Dictionary = CampaignIntro.address("Spain", "Isabella I", "Madrid", 1, false, salt)
	var again: Dictionary = CampaignIntro.address("Spain", "Isabella I", "Madrid", 1, false, salt)
	assert_eq(String(first["body"]), String(again["body"]), "the same campaign speaks alike")
	var seen: Dictionary = {}
	for seed_value: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		seen[CampaignIntro.address(
			"Spain", "Isabella I", "Madrid", 1, false, CampaignIntro.salt(seed_value, 0)
		)["body"]] = true
	assert_true(seen.size() > 1, "different campaigns can be addressed differently")


## The charge publishes the win condition and the calendar the player chose, so
## the opening never hides an outcome (wiki: victory § Military victory).
func test_the_charge_publishes_the_win_condition_and_the_calendar() -> void:
	var historical: Array[String] = CampaignIntro.charges(false)
	var joined: String = "\n".join(historical)
	assert_true(joined.contains(str(VictoryRules.MILITARY_THRESHOLD)), "the win bar is printed")
	assert_true(joined.contains(str(TurnTime.STOP_YEAR)), "the stop year is printed")
	assert_true(joined.contains(str(TurnTime.cap_turn())), "the cap turn is printed")
	var endless: String = "\n".join(CampaignIntro.charges(true))
	assert_false(endless.contains(str(TurnTime.STOP_YEAR)), "an endless age names no cap")
	assert_true(endless.contains("No calendar"), "an endless age says so")


## A level that moves the crown's bar is named in the charge, so the opening
## never hides the price the level asks (wiki: victory § Military victory;
## DR-20261111-28). `normal` stays the published sentence.
func test_the_charge_prints_the_bar_the_level_sets() -> void:
	var hard: String = "\n".join(CampaignIntro.charges(false, "hard"))
	assert_true(hard.contains("hold 36 Old World provinces"), "the crown's own bar")
	assert_true(hard.contains("a rival needs 31"), "and the bar every rival keeps")
	var eased: String = "\n".join(CampaignIntro.charges(false, "introductory"))
	assert_true(eased.contains("hold 26 Old World provinces"))
	var published: String = "\n".join(CampaignIntro.charges(false))
	assert_false(published.contains("a rival needs"), "the published age prints one bar")
	var page: Dictionary = CampaignIntro.address(
		"Spain", "Isabella I", "Madrid", 1, false, 0, "impossible"
	)
	assert_true(
		"\n".join(page["charges"] as Array).contains("hold 40 Old World provinces"),
		"the page carries the level it was opened with"
	)


## One press opens the age: the gate is dismiss-only and never silent
## (REQ-P5-02, REQ-P5-05).
func test_one_press_begins_the_age() -> void:
	var shown: IntroScreen = await _page()
	var begun: Array[bool] = []
	shown.begin_pressed.connect(func() -> void: begun.append(true))
	assert_not_null(shown.begin_button, "the page offers its one action")
	shown.begin_button.emit_signal("pressed")
	assert_eq(begun.size(), 1, "BEGIN reports to the router")


## Android back is the same one dismissal: a gate with a single option must not
## quit the app from under the player (REQ-P5-07).
func test_back_is_the_same_one_dismissal() -> void:
	var shown: IntroScreen = await _page()
	var begun: Array[bool] = []
	shown.begin_pressed.connect(func() -> void: begun.append(true))
	shown.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(begun.size(), 1, "back begins the age")
	assert_true(shown.paper.visible, "the broadside is still the page")


## The letter is printed on paper, with the ink colours the printed plates use,
## so it reads as a period broadside rather than another dossier (REQ-P1-02).
func test_the_charge_prints_on_paper() -> void:
	var shown: IntroScreen = await _page()
	assert_not_null(shown.paper, "the broadside panel exists")
	assert_true(shown.paper.get_child_count() > 0, "the panel carries the letter")
	var texts: Array[String] = _texts(shown)
	assert_true(texts.size() > 3, "kicker, title, stamp, body and charges print")
	assert_true("\n".join(texts).contains("Isabella I"), "the letter is on the page")


## Phone, tablet and desktop share the one page: it never outgrows the window and
## its single action stays on screen (REQ-P1-05, REQ-P5-07). Geometry runs in a
## SubViewport at the point size the device reports, because the page reads the
## viewport it is mounted in.
func test_the_page_fits_a_phone_a_tablet_and_a_desktop() -> void:
	for view: Vector2i in [Vector2i(914, 411), Vector2i(800, 360), Vector2i(1180, 820), Vector2i(1280, 720)]:
		var shown: IntroScreen = await _mount_at(view)
		assert_true(shown.begin_button.is_visible_in_tree(), "BEGIN is reachable at %s" % view)
		var rect: Rect2 = shown.begin_button.get_global_rect()
		assert_true(rect.position.y >= 0.0, "the action starts inside the window at %s" % view)
		assert_true(
			rect.position.y + rect.size.y <= float(view.y) + 1.0,
			"the action ends inside the window at %s" % view
		)
		assert_true(
			shown.paper.get_global_rect().size.x <= float(view.x),
			"the broadside fits the width at %s" % view
		)


## A phone held landscape builds the compact page: no crest, a tighter column and
## the short action height (REQ-P5-01).
func test_a_phone_builds_the_compact_page() -> void:
	var phone: IntroScreen = await _mount_at(Vector2i(914, 411))
	assert_true(MenuFrame.is_short(phone), "the phone is a short window")
	assert_eq(
		phone.begin_button.custom_minimum_size.y, MenuFrame.BUTTON_HEIGHT_SHORT,
		"the action keeps its thumb height"
	)
	var desktop: IntroScreen = await _mount_at(Vector2i(1280, 720))
	assert_false(MenuFrame.is_short(desktop), "a desktop window is not short")
	assert_eq(
		desktop.begin_button.custom_minimum_size.y, MenuFrame.BUTTON_HEIGHT,
		"the action keeps its full height"
	)


## The page always has something to print: mounted without an address it opens
## on the catalogue's own charge (REQ-P5-05, never a blank gate).
func test_a_page_without_an_address_prints_the_default_charge() -> void:
	var bare: IntroScreen = INTRO.instantiate()
	add_child(bare)
	await get_tree().process_frame
	var texts: String = "\n".join(_texts(bare))
	assert_true(texts.contains(CampaignIntro.TITLE), "the default charge prints")
	assert_true(texts.contains("Anno Domini"), "the default charge still names the year")
	assert_false(texts.contains("  ·  \n"), "a page with no seat prints no dangling stamp")
	bare.free()


## A reprint replaces the charges rather than stacking them, so a page reused by
## a test or a tool never prints two ages at once.
func test_a_reprint_replaces_the_charge() -> void:
	var shown: IntroScreen = await _page()
	shown.show_address(CampaignIntro.address("France", "Napoleon", "Paris", 1, true, 1))
	var texts: String = "\n".join(_texts(shown))
	assert_true(texts.contains("Napoleon"), "the new address prints")
	assert_false(texts.contains("Isabella I"), "the old address is gone")
	assert_true(texts.contains("No calendar"), "the new terms print")


## Escape is the same one dismissal on a keyboard, and the press is consumed so
## nothing behind the gate hears it (REQ-P5-07).
func test_escape_is_the_same_one_dismissal() -> void:
	var shown: IntroScreen = await _page()
	var begun: Array[bool] = []
	shown.begin_pressed.connect(func() -> void: begun.append(true))
	var event := InputEventAction.new()
	event.action = InputActions.CANCEL
	event.pressed = true
	shown._unhandled_input(event)
	assert_eq(begun.size(), 1, "escape begins the age")


## The shell raises the charge between the chart and the first turn: no map runs
## behind it, and one press installs the campaign (wiki: dialogue-management).
func test_the_flow_opens_the_charge_before_the_first_turn() -> void:
	var chart_world: WorldMap = Fixture.world()
	var snap: Array = Fixture.snapshot(chart_world)
	var main: Node = MAIN.instantiate()
	main.auto_start = false
	main.size_override = FLOW_SIZE
	main.preset_world = chart_world
	add_child(main)
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(0)
	setup.size_option.select(0)
	setup.seed_field.text = str(Fixture.SEED)
	setup.start_button.emit_signal("pressed")
	var chart: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	assert_not_null(chart, "the chart opens before turn 1")
	if chart == null:
		main.free()
		Fixture.restore(chart_world, snap)
		return
	await get_tree().process_frame
	assert_true(chart.world == chart_world, "the shell reused the cached chart")
	chart.confirm_button.emit_signal("pressed")

	var charge: IntroScreen = main.current_page as IntroScreen
	assert_not_null(charge, "the crown's charge follows the chart")
	assert_null(main.current_screen, "no campaign runs behind the charge")
	if charge == null:
		main.free()
		Fixture.restore(chart_world, snap)
		return
	assert_true(
		"\n".join(_texts(charge)).contains(FactionCatalog.name_of(0)),
		"the charge names the crown the player chose"
	)
	charge.begin_button.emit_signal("pressed")
	var screen: MapScreen = main.current_screen
	assert_not_null(screen, "one press opens the age")
	if screen != null:
		assert_eq(screen.turn, 1, "the charge is the gate before turn one")
		assert_eq(
			screen.capital_province, chart.selected_province,
			"the seat the charge named is the seat the campaign starts on"
		)
	main.free()
	Fixture.restore(chart_world, snap)


func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is Label:
		found.append(String((node as Label).text))
	if node is Button:
		found.append(String((node as Button).text))
	for child: Node in node.get_children():
		found.append_array(_texts(child))
	return found


## A window of the given size, so the page lays itself out as it would on that
## device (REQ-P1-05). The root viewport is fixed under gd-tools, so the page is
## mounted in a SubViewport at the point size the device would report.
func _mount_at(view: Vector2i) -> IntroScreen:
	var holder := SubViewport.new()
	holder.size = view
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(holder)
	var shown: IntroScreen = INTRO.instantiate()
	shown.show_address(CampaignIntro.address(
		"Spain", "Isabella I", "Madrid", 1, false, CampaignIntro.salt(1500, 0)
	))
	holder.add_child(shown)
	await get_tree().process_frame
	_mounted.append(holder)
	return shown
