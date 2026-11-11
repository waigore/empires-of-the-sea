extends GdToolsTest
## The crown's charge: the campaign's opening gate (wiki: dialogue-content-and-
## yarn § Kinds, `game_start_intro`; dialogue-management § Kinds). One dismissal
## before the first turn, printed from the rules and reachable on every platform.

const INTRO: PackedScene = preload("res://scenes/intro.tscn")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
## The chart's province targets clamp from 40x32 up, so this floor seats the same
## crowns while the flow paints fewer tiles per mount (the chart and the map
## share one world). This case reads the seat, not the roster.
const FLOW_SIZE: Vector2i = Vector2i(40, 32)

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


func after_each() -> void:
	if is_instance_valid(page):
		page.free()
	page = null
	for holder: SubViewport in _mounted:
		if is_instance_valid(holder):
			holder.free()
	_mounted.clear()


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
	var main: Node = MAIN.instantiate()
	main.auto_start = false
	main.size_override = FLOW_SIZE
	add_child(main)
	var menu: MainMenu = main.current_page
	menu.new_game_button.emit_signal("pressed")
	var setup: GameSetupScreen = main.current_page
	setup.nation_option.select(0)
	setup.size_option.select(0)
	setup.seed_field.text = "1500"
	setup.start_button.emit_signal("pressed")
	var chart: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	assert_not_null(chart, "the chart opens before turn 1")
	if chart == null:
		main.free()
		return
	await get_tree().process_frame
	chart.confirm_button.emit_signal("pressed")

	var charge: IntroScreen = main.current_page as IntroScreen
	assert_not_null(charge, "the crown's charge follows the chart")
	assert_null(main.current_screen, "no campaign runs behind the charge")
	if charge == null:
		main.free()
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
