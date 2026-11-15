# gdlint: disable=max-public-methods
extends GdToolsTest
## One boot for the crown's three ledgers: the province ledger, the intelligence
## reading (the crown's eyes) and the muster roll. Each projects its own snapshot
## over a small fixture and then drives its sheet on the one mounted chart —
## seal, key, filters, Visit and back (wiki: world-model § Provinces and Tiles;
## civilian-units § Spy; military-armies § The muster roll).
##
## Merged from test_province_ledger, test_spy_ledger, test_force_ledger_rules and
## test_ledger_rows:
## one Godot boot pays one coverage instrumentation pass instead of three (~11 s
## a suite under coverage), and the three sheets share the one mounted chart.

const Naval = preload("res://tests/naval_fixture.gd")
const Civilians = preload("res://tests/civilian_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so a case starts on a bare
## chart instead of remounting (`Fixture.suite_reset`). A case that visits a
## province leaves its dossier open, and that would answer the next case's back
## when the order is shuffled.
var screen: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	screen = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(screen)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.command_ledger.close()
		screen.hud.towns_ledger.close()
		screen.hud.walls_ledger.close()
		screen.hud.navy_ledger.close()
		screen.hud.province_ledger.close()
		screen.free()
	screen = null
	pristine = {}


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(screen, pristine)
	# The command ledger and the three realm sheets are not dock panels: a case
	# that leaves one open would answer the next case's back press.
	screen.hud.command_ledger.close()
	screen.hud.towns_ledger.close()
	screen.hud.walls_ledger.close()
	screen.hud.navy_ledger.close()
	screen.hud.province_ledger.close()
	# Back's debounce is static (one press per 300 ms per process), so the two
	# back cases in this boot must not swallow each other's press.
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS


## --- the province ledger -----------------------------------------------------


func test_snapshot_lists_every_own_province_in_both_charts() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(ProvinceLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(ProvinceLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's province stays out")
		assert_ne(String(row["name"]), "", "every row names its province")


func test_the_seat_leads_the_reading() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var first: Dictionary = (snapshot["rows"] as Array)[0]
	assert_eq(String(first["name"]), "Cádiz", "the seat is read first")
	assert_true(bool(first["capital"]), "and it is marked as the seat")
	assert_eq(String(first["place"]), "Harbour — Mar Caribe", "its own water is named")


func test_a_cut_off_province_is_flagged_and_counted() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_false(bool(overseas["linked"]), "the overseas province has no road home")
	assert_true((overseas["flags"] as Array).has(ProvinceLedger.FILTER_CUT))
	assert_true(
		String(overseas["state"]).contains("Cut off — 3 road tiles to lay"),
		"the row names the gap it waits on"
	)
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[ProvinceLedger.FILTER_CUT]), 1, "one province is cut off")


func test_a_blockaded_harbour_is_named_not_a_missing_road() -> void:
	var regions: Array[Dictionary] = _regions()
	(regions[0]["links"] as Dictionary)[0] = {
		"linked": false, "distance": -1, "blockaded": true,
	}
	var snapshot: Dictionary = ProvinceLedger.snapshot(regions, 0)
	var home: Dictionary = _province_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_true(String(home["state"]).contains("Harbour blockaded"))


func test_an_ungarrisoned_province_is_flagged_and_a_rival_does_not_hold_it() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var home: Dictionary = _province_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["regiments"]), 2, "the crown's two regiments stand there")
	assert_false((home["flags"] as Array).has(ProvinceLedger.FILTER_UNGARRISONED))
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["regiments"]), 0, "a rival's standard is not a garrison")
	assert_true((overseas["flags"] as Array).has(ProvinceLedger.FILTER_UNGARRISONED))
	assert_true(String(overseas["state"]).contains("Ungarrisoned"))


func test_estates_read_the_ledgers_own_yield_and_works() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var home: Dictionary = _province_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["estates"]), 2, "two estates in the seat")
	assert_eq(int(home["yield"]), 5, "3 + 2, the rows' own output")
	assert_true((home["flags"] as Array).has(ProvinceLedger.FILTER_WORKS))
	assert_true(String(home["line"]).contains("2 estates · 5 a turn"))
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["estates"]), 0)
	assert_true(String(overseas["line"]).contains("No estates"))


func test_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[ProvinceLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[ProvinceLedger.FILTER_UNGARRISONED]), 1)
	assert_eq(int(counts[ProvinceLedger.FILTER_WORKS]), 1)
	var cut: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_ALL, ProvinceLedger.FILTER_CUT
	)
	assert_eq(cut.size(), 1, "only the chart that holds a cut-off province")
	for group: Dictionary in cut:
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)
		assert_eq((group["rows"] as Array).size(), 1)
	assert_eq(
		ProvinceLedger.count(snapshot, LedgerRows.REGION_OLD, ProvinceLedger.FILTER_CUT),
		0,
		"the seat is not cut off"
	)


# --- the sheet --------------------------------------------------------------


func test_the_realm_door_opens_the_ledger_and_its_rows_visit_a_province() -> void:
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	assert_not_null(panel, "the HUD mounts the province ledger")
	var door: Button = _realm_door()
	assert_not_null(door, "the province dossier carries the realm door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the dossier's realm door opens it")
	assert_true(_province_row_widgets(panel) > 0, "the crown's provinces are listed")
	var row: ProvinceLedgerRow = _first_row(panel)
	assert_not_null(row)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_false(panel.is_open(), "a tap on the row visits the province")
	assert_true(screen.play.selected_province >= 0, "and the dossier is open on it")


func test_back_and_the_key_close_the_ledger() -> void:
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.provinces_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.PROVINCE_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## An emptied view prints its notice alone: the rows the last press left must not
## stand under it, or a crown reads a stale province beside "no province answers".
func test_an_emptied_realm_prints_its_notice_alone() -> void:
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.provinces_pressed.emit()
	assert_true(_province_row_widgets(panel) > 0, "the sheet opens on the crown's holdings")
	panel._snapshot = {}
	panel._apply_filter()
	assert_true(panel._empty.visible, "an empty realm prints the empty line")
	assert_true(panel._empty.text.contains("No province answers this view"))
	assert_eq(_province_row_widgets(panel), 0, "and the rows it stood over are cleared")
	panel.close()


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: the crown holds Cádiz at home and a
## renamed province abroad, with one rival province on each chart.
func _regions() -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	var armies: Array = [
		ArmyState.muster(1, 0, 0, true, ["pikemen", "arquebusiers"]),
		ArmyState.muster(2, 1, 0, false, ["pikemen"]),
	]
	var estates: Dictionary = {
		"groups": [
			{
				"id": 0,
				"name": "Cádiz",
				"count": 2,
				"rows": [
					{"output": 3, "working": true},
					{"output": 2, "working": false},
				],
			},
		],
	}
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"armies": armies,
			"estates": estates,
			"links": {0: {"linked": true, "distance": 0, "blockaded": false}},
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"armies": [] as Array,
			"estates": {},
			"links": {0: {"linked": false, "distance": 3, "blockaded": false}},
		},
	]


func _province_row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


func _first_row(panel: ProvinceLedgerPanel) -> ProvinceLedgerRow:
	for child: Node in panel._rows.get_children():
		if child is ProvinceLedgerRow:
			return child
	return null


## The province dossier's realm door, found by its word so the suite reads the
## button the player presses.
func _realm_door() -> Button:
	for node: Node in screen.hud._panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Realm":
			return button
	return null


func _province_row_widgets(panel: ProvinceLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ProvinceLedgerRow:
			total += 1
	return total


## --- the crown's eyes --------------------------------------------------------


func test_snapshot_reads_every_duty_the_crown_holds() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_spy_world(), _units(), 0)
	assert_eq(int(snapshot["spies"]), 3, "the rival's spy stays out")
	assert_eq(int(snapshot["shadowed"]), 1, "one spy stands on a rival's land")
	assert_eq(int(snapshot["idle"]), 1, "one waits at home with no order")
	assert_true(bool(snapshot["screened"]), "one holds the counter-espionage screen")
	var first: Dictionary = (snapshot["rows"] as Array)[0]
	assert_eq(String(first["duty"]), SpyLedger.DUTY_SHADOW, "the shadow leads the reading")
	assert_eq(String(first["host_name"]), "England", "the host court is named")
	assert_true(
		String(first["duty_text"]).contains("Shadowing England"),
		"the row says what the shadow is worth"
	)


func test_a_shadowed_court_is_named_and_an_open_one_stays_listed() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_spy_world(), _units(), 0)
	var courts: Array = snapshot["courts"]
	assert_eq(courts.size(), FactionCatalog.great_power_ids().size() - 1, "every rival crown")
	assert_eq(int(snapshot["unobserved"]), courts.size() - 1, "only England is shadowed")
	for raw: Variant in courts:
		var court: Dictionary = raw
		assert_ne(String(court["name"]), "Spain", "the reader's own crown is not a target")
		if String(court["name"]) == "England":
			assert_true(bool(court["shadowed"]))
			assert_eq(String(court["province_name"]), "Coro", "the shadow names its province")
			assert_true(String(court["line"]).contains("Shadowed in Coro"))
		else:
			assert_false(bool(court["shadowed"]), "%s is open" % String(court["name"]))
			assert_true(String(court["line"]).contains("Unobserved"))


func test_a_spy_on_a_minor_land_only_watches_it() -> void:
	var model: MapModel = Civilians.build_minor()
	var units: Array = [CivilianState.create(1, 0, "spy", Vector2i(2, 0))]
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, units)
	var world := WorldMap.new()
	world.add_region(model)
	var snapshot: Dictionary = SpyLedger.snapshot(world, table, 0)
	var row: Dictionary = (snapshot["rows"] as Array)[0]
	assert_eq(String(row["duty"]), SpyLedger.DUTY_WATCH, "a Minor's land watches, it shadows not")
	assert_eq(int(snapshot["shadowed"]), 0, "no Great Power is shadowed by it")
	assert_true(String(row["duty_text"]).contains("Genoa"))
	assert_true(String(row["duty_text"]).contains("visible"), "the reveal is named")


func test_the_screen_names_where_it_stands() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_spy_world(), _units(), 0)
	assert_eq(String(snapshot["screen"].get("province_name", "")), "Cádiz")
	assert_true(String(SpyLedger.screen_text(snapshot)).contains("Screen up at Cádiz"))
	var open: Dictionary = SpyLedger.snapshot(_spy_world(), _idle_only(), 0)
	assert_false(bool(open["screened"]))
	assert_true(
		String(SpyLedger.screen_text(open)).contains("No counter-espionage screen"),
		"a crown with no screen is told how to raise it"
	)


func test_the_summary_names_the_gap_not_only_the_gain() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_spy_world(), _units(), 0)
	var summary: String = SpyLedger.summary(snapshot)
	assert_true(summary.contains("3 spies"))
	assert_true(summary.contains("shadowing 1 court"))
	assert_true(summary.contains("screen up"))
	assert_true(summary.contains("1 idle"))
	var note: String = SpyLedger.courts_note(snapshot)
	assert_true(note.contains("1 of %d Great Powers shadowed" % snapshot["courts"].size()))
	assert_true(SpyLedger.boost_note().contains("%d%%" % SpyNetworks.BOOST_PERCENT))


# --- projection edges -------------------------------------------------------


func test_an_empty_world_and_a_foreign_roster_read_nothing() -> void:
	var empty: Dictionary = SpyLedger.snapshot(null, null, 0)
	assert_eq(int(empty["spies"]), 0, "no chart, no network")
	assert_true((empty["courts"] as Array).is_empty(), "and no court to read")
	assert_true(
		SpyLedger.summary(empty).contains("No spy answers the crown"),
		"the empty head names the gap"
	)
	assert_true(
		SpyLedger.courts_note(empty).contains("No rival Great Power"),
		"an empty court list says so"
	)
	# A rival's spy and a Builder are not the crown's eyes.
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [
		CivilianState.create(1, 1, "spy", Vector2i(0, 0)),
		CivilianState.create(2, 0, "builder", Vector2i(0, 0)),
		null,
	])
	table.set_region(FactionCatalog.NEW_WORLD, [] as Array)
	var snapshot: Dictionary = SpyLedger.snapshot(_spy_world(), table, 0)
	assert_eq(int(snapshot["spies"]), 0, "only the crown's spies are counted")


func test_every_great_power_shadowed_reads_as_a_closed_gap() -> void:
	# The note is a pure string read over the court list, so a closed gap is
	# proven without a chart that seats every rival.
	var closed: Dictionary = {
		"courts": [{"shadowed": true}, {"shadowed": true}],
		"unobserved": 0,
	}
	assert_true(
		SpyLedger.courts_note(closed).contains("Every Great Power is shadowed"),
		"and the note says the gap is closed"
	)
	var open: Dictionary = {
		"courts": [{"shadowed": false}, {"shadowed": false}],
		"unobserved": 2,
	}
	assert_true(
		SpyLedger.courts_note(open).contains("0 of 2 Great Powers shadowed"),
		"an open gap is counted"
	)


func test_a_spy_aboard_or_on_a_bare_tile_names_its_own_duty() -> void:
	var model: MapModel = Naval.build()
	var aboard := CivilianState.create(1, 0, "spy", Vector2i(0, 0))
	aboard.embark_on(7)
	assert_eq(SpyLedger.duty_of(model, aboard), SpyLedger.DUTY_ABOARD, "a passenger sails")
	assert_true(
		SpyLedger.duty_text(SpyLedger.DUTY_ABOARD, 0, "").contains("Aboard a squadron")
	)
	assert_eq(SpyLedger.duty_of(model, null), SpyLedger.DUTY_IDLE, "no unit, no duty")
	# A tile no crown holds is neither shadow nor watch.
	var open := CivilianState.create(2, 0, "spy", Vector2i(3, 0))
	assert_eq(SpyLedger.duty_of(model, open), SpyLedger.DUTY_IDLE, "neutral ground is idle")
	assert_true(
		SpyLedger.duty_text(SpyLedger.DUTY_IDLE, 0, "").contains("Idle — no order")
	)
	assert_true(
		SpyLedger.duty_text(SpyLedger.DUTY_SCREEN, 0, "Cádiz").contains("Counter-espionage")
	)


func test_every_duty_has_its_one_word_and_an_unknown_reads_idle() -> void:
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_SHADOW), "SHADOW")
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_SCREEN), "SCREEN")
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_WATCH), "WATCH")
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_ABOARD), "ABOARD")
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_IDLE), "IDLE")
	assert_eq(SpyLedger.duty_word("no_such_duty"), "IDLE", "an unknown duty idles")


func test_a_spy_row_wears_its_chip_and_visits_on_a_tap() -> void:
	var row := SpyLedgerRow.new()
	row.compact = true
	row.setup({
		"unit_id": 4,
		"region": FactionCatalog.OLD_WORLD,
		"region_label": "the Old World",
		"province_name": "Cádiz",
		"duty": SpyLedger.DUTY_SHADOW,
		"duty_text": SpyLedger.duty_text(SpyLedger.DUTY_SHADOW, 1, "Cádiz"),
	})
	assert_eq(row._name.text, "Spy — Cádiz")
	assert_eq(row._chip.text, "SHADOW", "the chip names the duty")
	assert_true(row._detail.text.contains("Shadowing"), "the row prints what it buys")
	var visited: Array = []
	row.visit_pressed.connect(func(region: int, unit_id: int) -> void:
		visited.append([region, unit_id])
	)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_eq(visited, [[FactionCatalog.OLD_WORLD, 4]], "the whole row is the Visit door")
	row.free()


func test_the_reading_orders_shadows_screens_watches_idle_and_passengers() -> void:
	# Two charts: the Old World holds a rival Great Power (Coro, England) and the
	# New World a Minor (Genoa), so one reading carries every duty but the screen.
	var old: MapModel = Naval.build()
	var new: MapModel = Civilians.build_minor()
	new.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	var aboard := CivilianState.create(5, 0, "spy", Vector2i(0, 0))
	aboard.embark_on(7)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [
		aboard,
		CivilianState.create(4, 0, "spy", Vector2i(0, 0)),
		_screening(2, Vector2i(0, 0)),
		CivilianState.create(1, 0, "spy", Vector2i(5, 0)),
	])
	table.set_region(FactionCatalog.NEW_WORLD, [
		CivilianState.create(3, 0, "spy", Vector2i(2, 0)),
	])
	var snapshot: Dictionary = SpyLedger.snapshot(world, table, 0)
	var duties: Array[String] = []
	for raw: Variant in snapshot["rows"]:
		duties.append(String((raw as Dictionary)["duty"]))
	assert_eq(
		duties,
		[SpyLedger.DUTY_SHADOW, SpyLedger.DUTY_SCREEN, SpyLedger.DUTY_WATCH,
			SpyLedger.DUTY_IDLE, SpyLedger.DUTY_ABOARD],
		"the network reads gains first, passengers last"
	)
	assert_eq(int(snapshot["watched"]), 1, "the Minor's land is a watch, not a shadow")
	assert_eq(int(snapshot["aboard"]), 1, "the passenger is counted apart")


# --- the sheet --------------------------------------------------------------


func test_the_courts_eyes_door_opens_the_sheet_it_reads() -> void:
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	assert_not_null(panel, "the HUD mounts the crown's eyes")
	var door: Button = _eyes_door()
	assert_not_null(door, "the court ledger carries the EYES door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the court's door opens the sheet")
	assert_true(_spy_row_widgets(panel) > 0, "the reading is painted")
	assert_true(panel._subtitle.text.length() > 0, "the head states the network")


func test_the_sheet_paints_a_network_and_a_visit() -> void:
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	panel.open()
	assert_true(
		panel._subtitle.text.begins_with("No spy"), "an empty network says so"
	)
	var model: MapModel = play.model
	var home: ProvinceState = model.provinces[0]
	var foreign: ProvinceState = model.provinces[Fixture.foreign_province(model)]
	var shadow := CivilianState.create(91, play.player_faction, "spy", foreign.tiles[0])
	var screen_spy := _screening(92, home.tiles[0])
	screen_spy.owner = play.player_faction
	var roster: Array[CivilianState] = [shadow, screen_spy]
	play.civilian_layer.units = roster
	play.civilian_layer.regions.set_region(play.region_index, roster)
	panel.refresh()
	assert_true(panel._subtitle.text.contains("2 spies"), "the head counts the network")
	assert_true(_spy_row_widgets(panel) > 2, "the network and the courts are painted")
	# Every row wears the chip its own duty names.
	for raw: Variant in panel._snapshot.get("rows", []):
		var duty: String = String((raw as Dictionary)["duty"])
		assert_true(
			_has_duty_word(panel, SpyLedger.duty_word(duty)),
			"a %s row wears its chip" % duty
		)
	var visit: Button = _first_visit(panel)
	assert_not_null(visit, "a spy row carries its Visit")
	visit.pressed.emit()
	assert_false(panel.is_open(), "Visit opens the spy and sets the sheet aside")
	_clear_spies(play)


## The compact and narrow profiles repaint the sheet without losing its rows,
## and every duty has its own one-word chip.
func test_the_phone_profile_repaints_the_reading() -> void:
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	screen.hud.spy_ledger_pressed.emit()
	assert_true(panel.is_open())
	var before: int = _spy_row_widgets(panel)
	panel._apply_profile(true, true)
	panel._on_profile_changed()
	assert_eq(_spy_row_widgets(panel), before, "the phone profile keeps every row")
	panel._apply_profile(false, false)
	panel._on_profile_changed()
	assert_eq(_spy_row_widgets(panel), before, "and the atlas profile restores it")
	for duty: String in [
		SpyLedger.DUTY_SHADOW, SpyLedger.DUTY_SCREEN, SpyLedger.DUTY_WATCH,
		SpyLedger.DUTY_IDLE, SpyLedger.DUTY_ABOARD,
	]:
		assert_ne(SpyLedger.duty_word(duty), "", "every duty has a chip word")
	assert_eq(SpyLedger.duty_word(SpyLedger.DUTY_WATCH), "WATCH")
	panel.close()


func test_back_and_the_key_close_the_sheet() -> void:
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	screen.hud.spy_ledger_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the sheet aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.SPY_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: Spain holds Cádiz at home, England Coro.
func _spy_world() -> WorldMap:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world


## Three of the crown's spies — shadowing, screening, idle — and one of
## England's, which the reading never counts.
func _units() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old: Array = [
		CivilianState.create(1, 0, "spy", Vector2i(5, 0)),
		_screening(2, Vector2i(0, 0)),
		CivilianState.create(3, FactionCatalog.great_power_ids()[1], "spy", Vector2i(0, 0)),
	]
	table.set_region(FactionCatalog.OLD_WORLD, old)
	var abroad: Array = [CivilianState.create(4, 0, "spy", Vector2i(0, 0))]
	table.set_region(FactionCatalog.NEW_WORLD, abroad)
	return table


func _idle_only() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [CivilianState.create(1, 0, "spy", Vector2i(0, 0))])
	table.set_region(FactionCatalog.NEW_WORLD, [] as Array)
	return table


## A spy on `counter_spy` at home: the same order `SpyRules.screened_owners`
## counts, which is what raises the empire-wide screen.
func _screening(id: int, tile: Vector2i) -> CivilianState:
	var spy := CivilianState.create(id, 0, "spy", tile)
	spy.start_work(SpyRules.WORK_COUNTER, tile, 1)
	return spy


## The court ledger's EYES door, found by its word so the suite presses the
## button the player presses.
func _eyes_door() -> Button:
	for node: Node in screen.hud._diplomacy_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("EYES"):
			return button
	return null


func _spy_row_widgets(panel: SpyLedgerPanel) -> int:
	return panel._rows.get_child_count()


## The first spy row's Visit door, found by its word.
func _first_visit(panel: SpyLedgerPanel) -> Button:
	for node: Node in panel._rows.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Visit":
			return button
	return null


## Whether a row's duty chip prints the word, found by text so the suite reads
## what the player reads.
func _has_duty_word(panel: SpyLedgerPanel, word: String) -> bool:
	for node: Node in panel._rows.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text == word:
			return true
	return false


## The mounted session's own roster, emptied so a case reads only its spies.
func _clear_spies(play: PlaySession) -> void:
	play.civilian_layer.units.clear()
	for region: int in play.world.region_count():
		play.civilian_layer.regions.set_region(region, [] as Array)


## --- the muster roll ---------------------------------------------------------


func test_snapshot_lists_every_own_force_in_both_regions() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	assert_eq(int(snapshot["total"]), 5, "three armies and two squadrons of the crown")
	assert_eq(int(snapshot["by_kind"][ForceLedger.KIND_ARMY]), 3, "the rival colours stay out")
	assert_eq(int(snapshot["by_kind"][ForceLedger.KIND_SQUADRON]), 2, "the rival hulls stay out")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_OLD), 3)
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_NEW), 2)
	var counts: Dictionary = ForceLedger.kind_counts(snapshot, LedgerRows.REGION_OLD)
	assert_eq(int(counts[ForceLedger.KIND_ARMY]), 2)
	assert_eq(int(counts[ForceLedger.KIND_SQUADRON]), 1)


func test_region_and_kind_filters_narrow_the_ledger() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_OLD, ForceLedger.KIND_ARMY), 2)
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_OLD, ForceLedger.KIND_SQUADRON), 1)
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_NEW, ForceLedger.KIND_ARMY), 1)
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_NEW, ForceLedger.KIND_SQUADRON), 1)
	for group: Dictionary in ForceLedger.groups(snapshot, LedgerRows.REGION_NEW):
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)
		for raw: Variant in group["rows"]:
			assert_ne(String((raw as Dictionary)["kind"]), "", "every row names its kind")


func test_army_row_reads_standing_composition_and_strength() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	var home: Dictionary = _force_row(snapshot, ForceLedger.KIND_ARMY, 1)
	assert_eq(String(home["title"]), "Home Army")
	assert_eq(String(home["place"]), "Cádiz")
	assert_eq(int(home["region"]), FactionCatalog.OLD_WORLD)
	assert_true(String(home["line"]).contains("2 regiments"))
	var army: ArmyState = _army_of(_armies(), 1)
	var one: Array[ArmyState] = [army]
	assert_almost_eq(float(home["strength"]), ArmyForce.side_strength(one), 0.001)
	assert_true(String(home["state"]).contains("seat"), "the Home Army never marches")
	assert_true(String(home["line"]).contains("%.1f strength" % float(home["strength"])))


func test_embarked_army_reads_aboard_its_squadron() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	var embarked: Dictionary = _force_row(snapshot, ForceLedger.KIND_ARMY, 2)
	assert_true(String(embarked["place"]).contains("Aboard a squadron"))
	assert_true(String(embarked["place"]).contains("Cádiz"), "the carrying squadron's station")
	assert_true(String(embarked["state"]).contains("Embarked"))


func test_squadron_row_reads_port_sea_station_and_cargo() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	var in_port: Dictionary = _force_row(snapshot, ForceLedger.KIND_SQUADRON, 7)
	assert_true(String(in_port["title"]).begins_with("Squadron"))
	assert_eq(String(in_port["place"]), "In port at Cádiz")
	assert_true(String(in_port["line"]).contains("2 hulls"))
	assert_true(String(in_port["line"]).contains("6 holds"), "two carracks carry three apiece")
	assert_true(String(in_port["state"]).contains("carrying an army"))
	var afloat: Dictionary = _force_row(snapshot, ForceLedger.KIND_SQUADRON, 9)
	assert_eq(String(afloat["place"]), "At sea — Mar Caribe")
	assert_true(String(afloat["state"]).contains("Patrol"))
	assert_eq(int(afloat["region"]), FactionCatalog.NEW_WORLD)


func test_kind_labels_and_flagship_title() -> void:
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_ARMY), "army")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_ARMY, true), "armies")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_SQUADRON), "squadron")
	assert_eq(ForceLedger.kind_label(ForceLedger.KIND_SQUADRON, true), "squadrons")
	var fleets: MapRegionTable = _fleets()
	var fleet: FleetState = (fleets.value(FactionCatalog.OLD_WORLD, []) as Array)[0]
	fleet.hull_names = {"ship_1": "Trinidad"}
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), fleets, 0)
	assert_eq(
		String(_force_row(snapshot, ForceLedger.KIND_SQUADRON, 7)["title"]),
		"Squadron — Trinidad",
		"a squadron reads by the flagship it flies"
	)


func test_empty_or_missing_rosters_project_an_empty_ledger() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(null, null, null, 0)
	assert_eq(int(snapshot["total"]), 0)
	assert_true((snapshot["groups"] as Array).is_empty())
	assert_eq(ForceLedger.count(snapshot, LedgerRows.REGION_ALL), 0)
	var empty_world: WorldMap = WorldMap.new()
	assert_eq(int(ForceLedger.snapshot(empty_world, null, null, 0)["total"]), 0)


# --- the panel on the live map ----------------------------------------------


func test_muster_seal_key_and_keyboard_action_open_the_ledger() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUSTER_ROLL))
	assert_ne(InputActions.MUSTER_ROLL, InputActions.CIVILIAN_ROSTER)
	assert_not_null(_seal_with_caption(screen.hud, "MUSTER"), "the cartouche carries the seal")
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	assert_not_null(panel)
	screen.hud.muster_roll_pressed.emit()
	assert_true(panel.is_open())
	assert_true(int(panel._snapshot.get("total", 0)) > 0, "the crown holds forces on the chart")
	screen.hud.muster_roll_pressed.emit()
	assert_false(panel.is_open())


func test_ledger_kind_filter_and_visit_open_the_chosen_force() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	panel._on_filter(ForceLedger.KIND_ARMY, false)
	assert_eq(panel._reading, ForceLedger.KIND_ARMY)
	var shown: int = ForceLedger.count(
		panel._snapshot, LedgerRows.REGION_ALL, ForceLedger.KIND_ARMY
	)
	assert_true(
		String(panel._subtitle.text).begins_with("Showing %d of" % shown),
		"the subtitle counts the narrowed view"
	)
	var rows: Array[Dictionary] = _rows_of_kind(panel._snapshot, ForceLedger.KIND_ARMY)
	assert_true(rows.size() > 0)
	assert_true(_force_row_widgets(panel) > 0, "the ledger printed rows")
	var first: Dictionary = rows[0]
	panel._visit(int(first["region"]), String(first["kind"]), int(first["id"]))
	assert_false(panel.is_open(), "Visit sets the ledger aside")
	assert_true(_selected_force(screen.play), "the force under the camera is the crown's own")


func test_region_filter_with_no_force_says_so() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	panel._on_filter(LedgerRows.REGION_OLD, true)
	panel._on_filter(ForceLedger.KIND_SQUADRON, false)
	panel._apply_filter()
	var shown: int = ForceLedger.count(panel._snapshot, panel._region, panel._reading)
	assert_eq(panel._empty.visible, shown == 0)
	if shown == 0:
		assert_true(String(panel._empty.text).contains("No force"))


func test_visit_a_squadron_selects_her_and_missing_ids_do_not() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var rows: Array[Dictionary] = _rows_of_kind(panel._snapshot, ForceLedger.KIND_SQUADRON)
	assert_true(rows.size() > 0, "the crown keeps a squadron afloat")
	var fleet: Dictionary = rows[0]
	assert_true(
		MapPlayForceLedger.focus(
			screen.play, int(fleet["region"]), ForceLedger.KIND_SQUADRON, int(fleet["id"])
		),
		"a squadron can be visited"
	)
	assert_not_null(screen.play.ship_layer.selected())
	assert_false(MapPlayForceLedger.focus(screen.play, 0, ForceLedger.KIND_ARMY, -999))
	assert_false(MapPlayForceLedger.focus(screen.play, 0, ForceLedger.KIND_SQUADRON, -999))
	assert_false(MapPlayForceLedger.focus(null, 0, ForceLedger.KIND_ARMY, 0))


func test_an_embarked_army_visits_the_squadron_that_carries_it() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var marker: Ship = null
	for ship: Ship in screen.play.ship_layer.ships:
		if ship.faction == screen.play.player_faction:
			marker = ship
			break
	assert_not_null(marker, "the crown has a squadron in this region")
	var army: ArmyState = null
	for candidate: ArmyState in screen.play.army_layer.armies:
		if candidate.owner == screen.play.player_faction:
			army = candidate
			break
	assert_not_null(army, "the crown has an army in this region")
	army.embarked_fleet = marker.fleet_id
	assert_true(
		MapPlayForceLedger.focus(
			screen.play, screen.play.region_index, ForceLedger.KIND_ARMY, army.id
		),
		"an embarked standard is reached through its hulls"
	)
	assert_eq(screen.play.ship_layer.selected(), marker, "the carrying squadron is selected")
	army.embarked_fleet = MapModel.NO_ID


func test_back_closes_the_muster_roll_before_the_dossiers() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	var escaped := InputEventAction.new()
	escaped.action = InputActions.CANCEL
	escaped.pressed = true
	screen.hud.muster_roll_pressed.emit()
	panel._input(escaped)
	assert_false(panel.is_open(), "Escape closes the ledger")


func test_the_rows_own_tap_visits_its_force() -> void:
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.muster_roll_pressed.emit()
	var row: ForceLedgerRow = null
	for child: Node in panel._rows.get_children():
		if child is ForceLedgerRow:
			row = child
			break
	assert_not_null(row)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	row._gui_input(tap)
	assert_false(panel.is_open(), "a tap on the row visits the force")


func test_the_keyboard_action_toggles_from_the_map() -> void:
	InputActions.ensure_actions()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	var toggle := InputEventAction.new()
	toggle.action = InputActions.MUSTER_ROLL
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open())
	panel._unhandled_input(toggle)
	assert_false(panel.is_open())


# --- the shared ledger dress --------------------------------------------------


func test_the_filter_bar_states_the_chart_once_and_reports_the_press() -> void:
	assert_eq(LedgerFilterBar.chart_word(LedgerRows.REGION_OLD), "Old World")
	assert_eq(LedgerFilterBar.chart_word(LedgerRows.REGION_NEW), "New World")
	assert_eq(LedgerFilterBar.chart_word(LedgerRows.REGION_ALL), "Both charts")
	assert_eq(LedgerFilterBar.chart_word("unknown"), "Both charts", "an unknown key filters nothing")
	# A bar that was never filled paints nothing: a ledger may refresh first.
	LedgerFilterBar.new().render(LedgerRows.REGION_ALL, ProvinceLedger.FILTER_ALL)

	var bar := LedgerFilterBar.new()
	add_child(bar)
	bar.fill(
		"Chart", "Reading", LedgerRows.REGION_FILTERS, ProvinceLedger.FILTERS,
		ProvinceLedger.filter_label
	)
	var chart_row := bar.get_child(0) as HBoxContainer
	var reading_row := bar.get_child(1) as HBoxContainer
	assert_eq(_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(
		_chip_captions(reading_row),
		["All provinces", "Cut off", "Ungarrisoned", "Works"],
		"the reading chips are the family's own words"
	)

	var presses: Array = []
	bar.chosen.connect(func(key: String, region_row: bool) -> void:
		presses.append([key, region_row])
	)
	_chip(reading_row, "Cut off").pressed.emit()
	assert_eq(presses.size(), 1, "one press, one report")
	assert_eq(String((presses[0] as Array)[0]), ProvinceLedger.FILTER_CUT)
	assert_false(bool((presses[0] as Array)[1]), "a reading chip is not the chart row")

	bar.render(LedgerRows.REGION_OLD, ProvinceLedger.FILTER_CUT)
	var lit: Color = _chip(chart_row, "Old World").get_theme_color("font_color")
	var plain: Color = _chip(chart_row, "Both charts").get_theme_color("font_color")
	assert_eq(lit, Palette.GOLD_PALE, "the chosen chart reads gold")
	assert_ne(plain, lit, "the rest stay plain")


func test_the_grouped_list_keeps_its_empty_notice_and_prints_headings() -> void:
	var list := VBoxContainer.new()
	add_child(list)
	var empty := Label.new()
	list.add_child(empty)
	var groups: Array[Dictionary] = [
		{"region_label": "Old World", "rows": [{"id": 1}, {"id": 2}]},
		{"region_label": "New World", "rows": [{"id": 3}]},
	]
	var heading := func(group: Dictionary, count: int) -> Control:
		return LedgerList.heading("%s · %d" % [String(group["region_label"]).to_upper(), count])
	var minted: Array = []
	var mint := func(raw: Variant, compact: bool) -> Control:
		var row := Label.new()
		row.text = str(int((raw as Dictionary)["id"]))
		minted.append([row.text, compact])
		return row

	LedgerList.fill(list, empty, groups, heading, mint)
	assert_eq(list.get_child_count(), 6, "one empty notice, two headings, three rows")
	assert_true(list.get_child(0) == empty, "the empty notice keeps its place")
	assert_eq((list.get_child(1) as Label).text, "OLD WORLD · 2")
	assert_eq((list.get_child(4) as Label).text, "NEW WORLD · 1")
	assert_eq(minted.size(), 3)
	assert_eq(
		bool((minted[0] as Array)[1]), LedgerList.is_compact(list),
		"every row is built for the chart's own profile"
	)

	# A repaint clears the last reading and keeps the notice it repaints into.
	LedgerList.fill(list, empty, groups, heading, mint)
	assert_eq(list.get_child_count(), 6)
	assert_true(list.get_child(0) == empty)


func test_the_flat_list_prints_rows_without_headings() -> void:
	var list := VBoxContainer.new()
	add_child(list)
	var empty := Label.new()
	list.add_child(empty)
	var rows: Array = [1, 2, 3]
	var mint := func(raw: Variant, _compact: bool) -> Control:
		var row := Label.new()
		row.text = "row %d" % int(raw)
		return row

	LedgerList.flat(list, empty, rows, mint)
	assert_eq(list.get_child_count(), 4, "three rows and the empty notice")
	assert_true(list.get_child(0) == empty, "a flat list keeps the notice too")
	for index in [1, 2, 3]:
		assert_true((list.get_child(index) as Label).text.begins_with("row "))

	LedgerList.flat(list, empty, [] as Array, mint)
	assert_eq(list.get_child_count(), 1, "an empty reading leaves only its notice")


## --- the force plaques -------------------------------------------------------


## Collects the lines a plaque press raises, so an empty press is read without a
## mounted chart (issue #670).
class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)


## The plaques read "Where are my pieces?" with no region qualifier, so a press
## walks every chart and comes back to the one it started on (issue #670).
func test_the_ships_plaque_cycles_every_squadron_across_charts() -> void:
	_boot_both_charts()
	var play: PlaySession = screen.play
	var total: int = _own_fleet_ids(play, FactionCatalog.OLD_WORLD).size() \
		+ _own_fleet_ids(play, FactionCatalog.NEW_WORLD).size()
	assert_gt(total, 1, "the crown floats squadrons on both charts")
	var visited: Array[String] = []
	var charts: Array[int] = []
	for press: int in total:
		screen.hud.fleet_status_pressed.emit()
		var ship: Ship = play.ship_layer.selected()
		assert_not_null(ship, "every press selects a squadron")
		assert_eq(ship.faction, play.player_faction, "only the crown's own hulls")
		visited.append(_piece_key(play.region_index, ship.fleet_id))
		charts.append(play.region_index)
	assert_eq(visited.size(), total, "one press per squadron")
	assert_eq(_unique(visited).size(), total, "no squadron is visited twice")
	assert_true(charts.has(FactionCatalog.NEW_WORLD), "the cycle crosses to the other chart")
	screen.hud.fleet_status_pressed.emit()
	assert_eq(play.region_index, FactionCatalog.OLD_WORLD, "the cycle wraps onto the first chart")
	assert_eq(
		_piece_key(play.region_index, play.ship_layer.selected().fleet_id),
		visited[0],
		"and onto the first squadron"
	)


func test_the_troops_plaque_cycles_every_army_across_charts() -> void:
	_boot_both_charts()
	var play: PlaySession = screen.play
	_raise_army_on_the_far_chart(play)
	var total: int = _own_army_ids(play, FactionCatalog.OLD_WORLD).size() \
		+ _own_army_ids(play, FactionCatalog.NEW_WORLD).size()
	assert_gt(total, 1, "the crown keeps a standard on both charts")
	var visited: Array[String] = []
	var charts: Array[int] = []
	for press: int in total:
		screen.hud.army_status_pressed.emit()
		var army: ArmyState = play.army_layer.selected_army
		assert_not_null(army, "every press selects an army")
		assert_eq(army.owner, play.player_faction, "only the crown's own standards")
		visited.append(_piece_key(play.region_index, army.id))
		charts.append(play.region_index)
	assert_eq(_unique(visited).size(), total, "no army is visited twice")
	assert_true(charts.has(FactionCatalog.NEW_WORLD), "the cycle crosses to the other chart")
	screen.hud.army_status_pressed.emit()
	assert_eq(play.region_index, FactionCatalog.OLD_WORLD, "the cycle wraps onto the first chart")
	assert_eq(
		_piece_key(play.region_index, play.army_layer.selected_army.id),
		visited[0],
		"and onto the first standard"
	)


## The bug's own signature: a chart with no pieces must not answer "none here"
## while the crown's pieces stand on the other chart (issue #670).
func test_a_press_reaches_squadrons_that_stand_on_the_other_chart() -> void:
	_boot_both_charts()
	var play: PlaySession = screen.play
	_strip_own_fleets(play, FactionCatalog.OLD_WORLD)
	screen.hud.fleet_status_pressed.emit()
	assert_eq(play.region_index, FactionCatalog.NEW_WORLD, "the press crosses to where the hulls are")
	var ship: Ship = play.ship_layer.selected()
	assert_not_null(ship, "and selects the squadron it found")
	assert_eq(ship.faction, play.player_faction)


## An empty press names the whole crown, not the chart on screen (issue #670).
func test_an_empty_press_names_a_crown_with_no_pieces_anywhere() -> void:
	var play := PlaySession.new()
	var hud := StubHud.new()
	var ships := ShipLayer.new()
	var armies := ArmyLayer.new()
	add_child(hud)
	add_child(ships)
	add_child(armies)
	play.hud = hud
	play.ship_layer = ships
	play.army_layer = armies
	MapPlayFocus.focus_next(play, MapPlayFocus.KIND_FLEET)
	assert_eq(hud.toasts.size(), 1, "a bare crown is told once")
	assert_true(hud.toasts[0].contains("crown's service"), hud.toasts[0])
	MapPlayFocus.focus_next(play, MapPlayFocus.KIND_ARMY)
	assert_eq(hud.toasts.size(), 2, "and the troops plaque answers the same way")
	assert_true(hud.toasts[1].contains("crown's service"), hud.toasts[1])


# --- fixtures ---------------------------------------------------------------


func _force_world() -> WorldMap:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	var world := WorldMap.new()
	world.add_region(old)
	world.add_region(new)
	return world


func _armies() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old: Array[ArmyState] = []
	old.append(ArmyState.muster(1, 0, 0, true, ["pikemen", "arquebusiers"]))
	var embarked: ArmyState = ArmyState.muster(2, 0, MapModel.NO_ID, false, ["pikemen"])
	embarked.embarked_fleet = 7
	old.append(embarked)
	old.append(ArmyState.muster(3, 1, 0, false, ["pikemen"]))
	table.set_region(FactionCatalog.OLD_WORLD, old)
	var new: Array[ArmyState] = []
	new.append(ArmyState.muster(4, 0, 0, false, ["arquebusiers", "pikemen"]))
	table.set_region(FactionCatalog.NEW_WORLD, new)
	return table


func _fleets() -> MapRegionTable:
	var table := MapRegionTable.new()
	var old: Array[FleetState] = []
	var moored: FleetState = FleetState.in_port(7, 0, 0)
	moored.set_hulls(["ship_1", "ship_2"])
	moored.embarked_army = 2
	old.append(moored)
	var rival: FleetState = FleetState.in_port(8, 1, 1)
	rival.set_hulls(["ship_3"])
	old.append(rival)
	table.set_region(FactionCatalog.OLD_WORLD, old)
	var new: Array[FleetState] = []
	var patrol: FleetState = FleetState.at_sea(9, 0, 0)
	patrol.set_hulls(["ship_4"])
	patrol.mission = FleetState.Mission.PATROL
	new.append(patrol)
	table.set_region(FactionCatalog.NEW_WORLD, new)
	return table


## Boots the far chart once so both region tables hold the crown's rosters, then
## returns the view to the Old World with nothing selected. The shared world has
## no crown seat on the far chart, so a case hands it one (the fixture restores
## ownership before the next case) — otherwise there is nothing to cross for.
func _boot_both_charts() -> void:
	var play: PlaySession = screen.play
	var far: int = FactionCatalog.NEW_WORLD
	var seat: ProvinceState = play.world.region(far).provinces[0]
	seat.owner = play.player_faction
	seat.capital = true
	screen.load_region(far)
	screen.load_region(FactionCatalog.OLD_WORLD)
	play.ship_layer.deselect()
	play.army_layer.deselect()


func _own_fleet_ids(play: PlaySession, region: int) -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in play.ship_layer.regions.value(region, []):
		var fleet := raw as FleetState
		if fleet != null and fleet.owner == play.player_faction:
			ids.append(fleet.id)
	return ids


func _own_army_ids(play: PlaySession, region: int) -> Array[int]:
	var ids: Array[int] = []
	for raw: Variant in play.army_layer.regions.value(region, []):
		var army := raw as ArmyState
		if army != null and army.owner == play.player_faction and not army.is_embarked():
			ids.append(army.id)
	return ids


## A field army on the far chart, so the troops plaque has a piece to cross for.
## Home Armies muster only for a region's own crowns, and no Great Power is one
## there, so the case raises its own standard (the fixture restores the rosters).
func _raise_army_on_the_far_chart(play: PlaySession) -> void:
	var far: int = FactionCatalog.NEW_WORLD
	var province: int = MapModel.NO_ID
	for row: ProvinceState in play.world.region(far).provinces:
		if row.owner == play.player_faction:
			province = row.id
			break
	assert_true(province >= 0, "the crown holds ground on the far chart")
	var muster := ArmyMuster.new()
	muster.next_army = play.army_layer.next_army
	muster.next_regiment = play.army_layer.next_regiment
	var army: ArmyState = muster.mint(play.player_faction, province, false, ["peasant_levies"])
	play.army_layer.next_army = muster.next_army
	play.army_layer.next_regiment = muster.next_regiment
	var stored: Array = play.army_layer.regions.value(far, [])
	stored.append(army)
	play.army_layer.regions.set_region(far, stored)


func _strip_own_fleets(play: PlaySession, region: int) -> void:
	var kept: Array = []
	for raw: Variant in play.ship_layer.regions.value(region, []):
		var fleet := raw as FleetState
		if fleet != null and fleet.owner != play.player_faction:
			kept.append(fleet)
	play.ship_layer.regions.set_region(region, kept)


## A piece's place in the cycle: fleet and army ids restart on each chart, so the
## region has to travel with the id (issue #670).
func _piece_key(region: int, id: int) -> String:
	return "%d:%d" % [region, id]


func _unique(keys: Array[String]) -> Array[String]:
	var seen: Array[String] = []
	for key: String in keys:
		if not seen.has(key):
			seen.append(key)
	return seen


func _army_of(table: MapRegionTable, id: int) -> ArmyState:
	for raw: Variant in table.value(FactionCatalog.OLD_WORLD, []):
		var army := raw as ArmyState
		if army != null and army.id == id:
			return army
	return null


func _force_row(snapshot: Dictionary, kind: String, id: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["kind"]) == kind and int(row["id"]) == id:
			return row
	return {}


## One chip of a filter row by the word it carries.
func _chip(row: HBoxContainer, caption: String) -> Button:
	for child: Node in row.get_children():
		var button := child as Button
		if button != null and button.text == caption:
			return button
	return null


func _chip_captions(row: HBoxContainer) -> Array[String]:
	var captions: Array[String] = []
	for child: Node in row.get_children():
		var button := child as Button
		if button != null:
			captions.append(button.text)
	return captions


func _rows_of_kind(snapshot: Dictionary, kind: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if String(row["kind"]) == kind:
			rows.append(row)
	return rows


func _force_row_widgets(panel: ForceLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ForceLedgerRow:
			total += 1
	return total


func _seal_with_caption(node: Node, caption: String) -> Button:
	var button := node as Button
	if button != null and _labels_carry(button, caption):
		return button
	for child: Node in node.get_children():
		var found: Button = _seal_with_caption(child, caption)
		if found != null:
			return found
	return null


func _labels_carry(node: Node, caption: String) -> bool:
	var label := node as Label
	if label != null:
		return label.text == caption
	for child: Node in node.get_children():
		if _labels_carry(child, caption):
			return true
	return false


func _selected_force(play: PlaySession) -> bool:
	if play.army_layer != null and play.army_layer.selected_army != null:
		return true
	return play.ship_layer != null and play.ship_layer.selected() != null


# --- the command ledger -----------------------------------------------------
## The pool of generals read as a ledger — who each commander is, what his
## medals buy in the field and which study raises the cap next (wiki:
## military-generals § Generals, § Count and tech-gated cap, § Medals;
## DR-20261115-11). Merged from test_command_ledger: the projection cases read a
## small roster and the drive presses the sheet on the one mounted chart.


func test_the_pool_reads_every_commander_with_his_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {})
	roster.award(0, "general_1")
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {}, "isabella")
	assert_eq(int(data["held"]), 1, "the opening cap is one commander")
	assert_eq(int(data["cap"]), 1)
	assert_false(bool(data["above_cap"]))
	var row: Dictionary = (data["rows"] as Array)[0]
	assert_eq(String(row["id"]), "general_1")
	assert_ne(String(row["name"]), "", "every commander is christened")
	assert_eq(int(row["medals"]), 1, "the medal he won is read")
	assert_false(bool(row["full"]), "one medal is not the ceiling")


func test_the_command_cap_follows_the_studied_rungs() -> void:
	var roster := GeneralRoster.new()
	assert_eq(roster.sync(0, {}), 1, "the opening cap")
	assert_eq(roster.sync(0, {"organised_regiments": true}), 2)
	assert_eq(
		roster.sync(0, {"organised_regiments": true, "national_bureaucracy": true}), 3
	)
	assert_eq(
		roster.sync(
			0,
			{
				"organised_regiments": true,
				"national_bureaucracy": true,
				"improved_infantry_tactics": true,
			},
		),
		3,
		"the two cap-3 rungs do not stack"
	)
	assert_eq(roster.sync(0, {"nationalism": true}), 4, "nationalism alone reaches four")
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {"nationalism": true}, "")
	assert_eq(int(data["cap"]), 4)
	assert_eq(int(data["held"]), 4, "the pool always holds the cap")


func test_the_command_road_names_the_next_study() -> void:
	var opening: Dictionary = CommandLedger.snapshot(GeneralRoster.new(), 0, {}, "")
	var next: Dictionary = opening["next"]
	assert_eq(String(next["tech"]), "organised_regiments", "the first rung is named")
	assert_eq(int(next["cap"]), 2)
	assert_eq(String(next["name"]), TechCatalog.display_name("organised_regiments"))
	assert_true(
		CommandLedger.summary(opening).contains("next: "),
		"the count line names the road"
	)
	var studied: Dictionary = CommandLedger.snapshot(
		GeneralRoster.new(), 0, {"organised_regiments": true}, ""
	)
	assert_eq(String((studied["next"] as Dictionary)["tech"]), "national_bureaucracy")
	var ceiling: Dictionary = CommandLedger.snapshot(
		GeneralRoster.new(), 0, {"nationalism": true}, ""
	)
	assert_true((ceiling["next"] as Dictionary).is_empty(), "four is the ceiling")
	assert_true(CommandLedger.summary(ceiling).contains("ceiling is 4"))


func test_the_command_road_reads_every_rung_and_which_are_studied() -> void:
	var road: Array[Dictionary] = CommandLedger.road({"nationalism": true})
	assert_eq(road.size(), CommandLedger.ROAD.size(), "every published rung is read")
	var studied: int = 0
	for rung: Dictionary in road:
		if bool(rung["unlocked"]):
			studied += 1
	assert_eq(studied, 1, "only the rung the crown studied reads taken")
	assert_eq(CommandLedger.ceiling(), 4)


func test_an_above_cap_command_roster_is_read_not_trimmed() -> void:
	var roster := GeneralRoster.new()
	roster.sync(0, {"nationalism": true})
	var data: Dictionary = CommandLedger.snapshot(roster, 0, {}, "")
	assert_eq(int(data["held"]), 4, "the roster keeps every commander it spawned")
	assert_eq(int(data["cap"]), 1, "the cap is the studies' own")
	assert_true(bool(data["above_cap"]), "an above-cap roster is tolerated, not trimmed")
	assert_true(
		CommandLedger.summary(data).begins_with("4 commanders (cap 1)"),
		"the count line reads the roster against the studies' own cap"
	)


func test_a_command_medal_buys_the_combat_modules_own_figures() -> void:
	var one: Dictionary = CommandLedger.effects(1)
	assert_eq(int(one["line"]), 1, "one more regiment in the line")
	assert_eq(int(one["morale_pct"]), 5, "the aura's own step")
	assert_eq(int(one["initiative"]), 10, "the medal weight")
	var four: Dictionary = CommandLedger.effects(4)
	assert_eq(int(four["line"]), 4)
	assert_eq(int(four["morale_pct"]), 20, "the aura caps at a fifth")
	assert_eq(int(four["initiative"]), 40)
	var clamped: Dictionary = CommandLedger.effects(9)
	assert_eq(int(clamped["line"]), 4, "no commander earns a fifth medal")
	assert_true(CommandLedger.medal_line().contains("+1 regiment in the line"))


func test_the_command_fallback_reads_the_leaders_own_medals() -> void:
	var napoleon: Dictionary = CommandLedger.fallback("napoleon")
	assert_eq(int(napoleon["attack"]), 4, "a 1.25 leader fights as four medals")
	assert_eq(int(napoleon["defend"]), 4)
	var gustavus: Dictionary = CommandLedger.fallback("gustavus")
	assert_eq(int(gustavus["attack"]), 2, "his bonus is published attacking only")
	assert_eq(int(gustavus["defend"]), 0)
	var neutral: Dictionary = CommandLedger.fallback(LeaderCatalog.DEFAULT_KEY)
	assert_eq(int(neutral["attack"]), 0, "a crown with no leader falls back to none")
	var data: Dictionary = CommandLedger.snapshot(GeneralRoster.new(), 0, {}, "napoleon")
	assert_true(CommandLedger.fallback_line(data).contains("4 medals"))


func test_a_command_row_prints_the_medals_and_what_they_buy() -> void:
	var row := CommandLedgerRow.new()
	row.setup({
		"name": "Don Álvaro",
		"medals": 2,
		"effects": CommandLedger.effects(2),
		"full": false,
	})
	assert_eq(row._name.text, "Don Álvaro")
	assert_eq(row._medals.text, "×2")
	assert_true(row._detail.text.contains("Line +2"), "the line a medal adds")
	assert_true(row._detail.text.contains("morale +10%"))
	assert_true(row._detail.text.contains("initiative +20"))
	row.free()


func test_a_command_row_reads_a_commander_with_no_medals_and_one_at_the_ceiling() -> void:
	var bare := CommandLedgerRow.new()
	bare.compact = true
	bare.setup({"name": "A new commander", "medals": 0, "effects": CommandLedger.effects(0)})
	assert_eq(bare._medals.text, "—", "no decoration reads as none")
	assert_true(bare._detail.text.contains("No medals yet"))
	bare.free()
	var full := CommandLedgerRow.new()
	full.setup({
		"name": "A veteran",
		"medals": GeneralRoster.MAX_MEDALS,
		"effects": CommandLedger.effects(GeneralRoster.MAX_MEDALS),
		"full": true,
	})
	assert_eq(full._medals.text, "×4")
	assert_true(full._detail.text.contains("every medal he can earn"))
	full.free()


func test_a_session_with_no_army_layer_reads_an_empty_command_pool() -> void:
	var data: Dictionary = MapPlayCommand.snapshot(null)
	assert_eq(int(data["held"]), 0, "no layer, no commanders")
	assert_true((data["rows"] as Array).is_empty())
	assert_eq(int(data["cap"]), GeneralRoster.BASE_CAP, "the cap is still the rules'")


## The campaign opens with its commander on the roll. Nothing else syncs a pool
## before the first turn tick, so a sheet that opens on turn 0 read "0 of 1
## commander" with no row while the wiki says the faction always holds its cap
## (wiki: military-generals § Count and tech-gated cap).
func test_a_fresh_campaign_opens_with_its_commander() -> void:
	var play: PlaySession = screen.play
	var data: Dictionary = MapPlayCommand.snapshot(play)

	assert_eq(int(data["cap"]), GeneralRoster.BASE_CAP, "the opening cap")
	assert_eq(int(data["held"]), 1, "the crown holds its opening commander")
	assert_false((data["rows"] as Array).is_empty(), "and the roll names him")

	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.command_pressed.emit()
	assert_true(
		panel._subtitle.text.contains("1 of 1 commander"),
		"the count line reads the pool the rows print"
	)
	assert_true(not panel._empty.visible, "no empty-state note on the opening sheet")


func test_the_command_door_opens_the_ledger_and_lists_the_pool() -> void:
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	assert_not_null(panel, "the HUD mounts the command ledger")
	var play: PlaySession = screen.play
	play.army_layer.sync_generals(play.player_faction, play.tech_unlocked())
	var door: Button = _command_door()
	assert_not_null(door, "the army dossier carries the command door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the dossier's command door opens it")
	assert_true(_command_row_widgets(panel) > 0, "the crown's commanders are listed")
	assert_true(
		panel._subtitle.text.contains("commander"),
		"the count line names the pool"
	)
	assert_true(panel._medal.text.contains("Each medal"), "the medal note is printed")


func test_back_and_the_key_close_the_command_ledger() -> void:
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.command_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.COMMAND_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## --- the shared row skeleton -------------------------------------------------


## The heading is one line (issue #669): a name that autowraps inside the
## heading's HBox reports no minimum width, so the box hands it a single glyph
## and the chip lands on the letter stack. Every sheet that prints a LedgerRow
## is read at a desktop and a phone width.
func test_every_ledger_row_keeps_its_name_on_one_line_beside_its_chip() -> void:
	var cases: Array = [
		[ProvinceLedgerRow, {"name": "Nueva Cádiz"}],
		[SpyLedgerRow, {"province_name": "Nueva Cádiz"}],
		[ForceLedgerRow, {"title": "The Old Guard"}],
		[CommandLedgerRow, {"name": "Don Álvaro"}],
		[NavalLedgerRow, {"name": "Santa Ana"}],
		[CivilianRosterRow, {"role": "Explorer"}],
	]
	for width: float in [640.0, 411.0]:
		for entry: Array in cases:
			var row: LedgerRow = (entry[0] as GDScript).new()
			row.compact = width < 500.0
			add_child(row)
			row.setup(entry[1])
			row.size = Vector2(width, 0.0)
			await get_tree().process_frame
			var name: Label = row._name
			var font: Font = name.get_theme_font("font")
			var size: int = name.get_theme_font_size("font_size")
			var one_line: float = font.get_string_size(
				name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size
			).x
			assert_eq(name.get_line_count(), 1, "%s at %s" % [name.text, width])
			assert_true(
				name.size.x + 0.5 >= one_line,
				"%s reads across, not down: %s of %s" % [name.text, name.size.x, one_line]
			)
			if row._chip != null:
				assert_true(
					row._chip.get_global_rect().position.x + 0.5
					>= name.get_global_rect().end.x,
					"the chip sits beside %s, not on it" % name.text
				)
			row.free()


## Every sheet the HUD mounts is read at a desktop and a phone width (issue
## #693). The courts print a court's line beside a fixed name column, and an
## autowrapped label reports a one-pixel minimum, so a row that does not hand it
## the remaining width prints one glyph per line down the margin (the same
## failure as #669, one drawer further down). The guard here is the whole sheet:
## every visible autowrapped label must be at least as wide as its widest word.
func test_every_sheet_reads_its_prose_across_at_desktop_and_phone_widths() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(914, 411)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var chart: MapScreen = Fixture.attach_screen(viewport)
		chart.hud._relayout()
		await get_tree().process_frame
		await get_tree().process_frame
		for sheet: SheetFrame in _hud_sheets(chart.hud):
			sheet.open()
			await get_tree().process_frame
			await get_tree().process_frame
			var caption: String = (sheet.get_script() as Script).resource_path.get_file()
			_assert_prose_reads_across(sheet, caption, size)
			if sheet is SpyLedgerPanel:
				_assert_the_courts_read_across(sheet as SpyLedgerPanel, size)
			sheet.close()
			await get_tree().process_frame
		chart.free()
		viewport.free()


## The ten sheets the HUD mounts on its modal layers.
func _hud_sheets(hud: GameHud) -> Array[SheetFrame]:
	var sheets: Array[SheetFrame] = []
	for sheet: SheetFrame in [
		hud.spy_ledger, hud.province_ledger, hud.muster_roll, hud.command_ledger,
		hud.towns_ledger, hud.walls_ledger, hud.navy_ledger, hud.civilian_roster,
		hud.tech_tree, hud.dossier_screen,
	]:
		if sheet != null:
			sheets.append(sheet)
	assert_eq(sheets.size(), 10, "every sheet the HUD mounts is read")
	return sheets


func _assert_prose_reads_across(sheet: Control, caption: String, width: Vector2i) -> void:
	for node: Node in sheet.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.is_visible_in_tree():
			continue
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		var text: String = label.text.strip_edges()
		if text.is_empty():
			continue
		var holder := label.get_parent() as Control
		var room: float = holder.size.x if holder != null else label.size.x
		var needed: float = minf(_widest_word(label), room)
		assert_true(
			label.size.x + 0.5 >= needed,
			"%s @%s: '%s' reads across, not down (%.1f of %.1f)"
			% [caption, width, text.substr(0, 40), label.size.x, needed]
		)


## The courts' rows: each line takes the width its name column leaves, so the
## sentence wraps at the sheet's width instead of one glyph per line.
func _assert_the_courts_read_across(sheet: SpyLedgerPanel, width: Vector2i) -> void:
	var courts: int = 0
	for node: Node in sheet._rows.get_children():
		var row := node as HBoxContainer
		if row == null or row.get_child_count() != 2:
			continue
		var name_label := row.get_child(0) as Label
		var line := row.get_child(1) as Label
		if name_label == null or line == null:
			continue
		if line.autowrap_mode == TextServer.AUTOWRAP_OFF:
			continue
		courts += 1
		var room: float = (
			row.size.x - name_label.size.x - row.get_theme_constant("separation")
		)
		assert_true(
			line.size.x + 0.5 >= room,
			"%s @%s: the line takes the row's width (%.1f of %.1f)"
			% [name_label.text, width, line.size.x, room]
		)
		assert_true(
			line.get_line_count() <= 3,
			"%s @%s: the line wraps in a few rows, not %d"
			% [name_label.text, width, line.get_line_count()]
		)
	assert_eq(courts, 5, "every Great Power but the crown's own is read")


## The widest word in pixels: a wrapped label narrower than this breaks words
## mid-glyph, which is what the letter stack looks like.
func _widest_word(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var widest: float = 0.0
	for word: String in label.text.split(" ", false):
		widest = maxf(
			widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		)
	return widest


## The army dossier's command door, found by its word so the suite reads the
## button the player presses.
func _command_door() -> Button:
	for node: Node in screen.hud._army_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Commanders":
			return button
	return null


func _command_row_widgets(panel: CommandLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is CommandLedgerRow:
			total += 1
	return total

# --- ledger rows --------------------------------------------------------------
## The plumbing every crown ledger reads (REQ-P3-01, REQ-P3-02): which chart a
## row sits on, the rows a chart-and-reading filter leaves, the tally each chip
## carries and the one heading per chart. Merged here so the narrowing is read
## in the boot the sheets already pay (docs/testing.md).

func test_region_keys_read_the_chart_a_row_sits_on() -> void:
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_OLD))
	assert_false(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_OLD))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_NEW))
	assert_false(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_NEW))


func test_all_and_an_unknown_key_keep_every_chart() -> void:
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, LedgerRows.REGION_ALL))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, LedgerRows.REGION_ALL))
	assert_true(LedgerRows.region_matches(FactionCatalog.NEW_WORLD, ""))
	assert_true(LedgerRows.region_matches(FactionCatalog.OLD_WORLD, "a_chart_no_sheet_names"))


func test_the_chart_keys_are_one_list_every_sheet_reads() -> void:
	assert_eq(",".join(LedgerRows.REGION_FILTERS), "all,old_world,new_world")


func test_groups_keep_one_chart_and_drop_the_group_it_emptied() -> void:
	var data: Dictionary = _rows_fixture()
	var old: Array[Dictionary] = LedgerRows.groups(data, LedgerRows.REGION_OLD, _rows_always)
	assert_eq(old.size(), 1, "one heading for the chart that still has rows")
	assert_eq(int(old[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((old[0]["rows"] as Array).size(), 2)


func test_groups_narrow_by_the_sheets_own_reading() -> void:
	var data: Dictionary = _rows_fixture()
	var ships: Array[Dictionary] = LedgerRows.groups(
		data, LedgerRows.REGION_ALL, LedgerRows.field_matches.bind("kind", "squadron")
	)
	assert_eq(ships.size(), 1, "a chart keeps its heading only while a row survives")
	assert_eq(int(ships[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((ships[0]["rows"] as Array).size(), 1, "the armies drop out of the muster")


func test_groups_never_edit_the_snapshot_they_read() -> void:
	var data: Dictionary = _rows_fixture()
	LedgerRows.groups(data, LedgerRows.REGION_NEW, _rows_always)
	var groups: Array = data["groups"]
	assert_eq((groups[0]["rows"] as Array).size(), 2, "the source keeps every row")
	assert_eq((groups[1]["rows"] as Array).size(), 1)


func test_count_is_the_rows_the_narrowed_view_prints() -> void:
	var data: Dictionary = _rows_fixture()
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_ALL, _rows_always), 3)
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_OLD, _rows_always), 2)
	assert_eq(LedgerRows.count(data, LedgerRows.REGION_NEW, _rows_always), 1)
	assert_eq(
		LedgerRows.count(
			data, LedgerRows.REGION_ALL, LedgerRows.field_matches.bind("kind", "army")
		),
		2,
		"the reading narrows before the count"
	)


func test_counts_tally_every_reading_against_one_chart() -> void:
	var data: Dictionary = _rows_fixture()
	var counts: Dictionary = LedgerRows.counts(
		data, LedgerRows.REGION_OLD, ["all", "army", "squadron"], _rows_kind
	)
	assert_eq(int(counts["all"]), 2, "all is the chart's own total")
	assert_eq(int(counts["army"]), 1)
	assert_eq(int(counts["squadron"]), 1)


func test_group_nests_rows_under_the_chart_that_holds_them() -> void:
	var rows: Array[Dictionary] = [
		_rows_row(0, "first"),
		_rows_row(0, "second"),
		_rows_row(1, "third"),
	]
	var groups: Array[Dictionary] = LedgerRows.group(rows)
	assert_eq(groups.size(), 2, "one heading per chart in reading order")
	assert_eq(int(groups[0]["region"]), 0)
	assert_eq(String(groups[0]["region_label"]), FactionCatalog.region_label(0))
	assert_eq((groups[0]["rows"] as Array).size(), 2)
	assert_eq((groups[1]["rows"] as Array).size(), 1)


## A sheet that sorts by its own key before the chart (a town's level, a spy's
## duty) still prints one heading per chart: the chart's rows gather under the
## heading its first row raised, in the order they arrived.
func test_group_keeps_one_heading_per_chart_when_the_reading_interleaves() -> void:
	var rows: Array[Dictionary] = [
		_rows_row(0, "first"),
		_rows_row(1, "second"),
		_rows_row(0, "third"),
	]
	var groups: Array[Dictionary] = LedgerRows.group(rows)
	assert_eq(groups.size(), 2, "one heading per chart, not one per run of rows")
	assert_eq(int(groups[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((groups[0]["rows"] as Array).size(), 2, "both home rows under one heading")
	assert_eq(
		String((groups[0]["rows"] as Array)[1]["kind"]), "third", "in the order they arrived"
	)
	assert_eq(int(groups[1]["region"]), FactionCatalog.NEW_WORLD)
	assert_eq((groups[1]["rows"] as Array).size(), 1)


func test_a_row_reads_by_its_own_word_or_by_a_flag() -> void:
	var row: Dictionary = {"kind": "army", "flags": ["cut_off"]}
	assert_true(LedgerRows.field_matches(row, "kind", "army"))
	assert_false(LedgerRows.field_matches(row, "kind", "squadron"))
	assert_true(LedgerRows.field_matches(row, "kind", "all"), "all keeps every row")
	assert_true(LedgerRows.field_matches(row, "kind", ""), "an empty key keeps every row")
	assert_false(LedgerRows.field_matches(row, "missing", "army"), "an absent word matches nothing")
	assert_true(LedgerRows.flags_match(row, "cut_off"))
	assert_false(LedgerRows.flags_match(row, "works"))
	assert_true(LedgerRows.flags_match(row, "all"))


func test_one_region_reads_as_a_roster_and_answers_empty_when_it_cannot() -> void:
	var table := MapRegionTable.new()
	table.set_region(0, [1, 2, 3])
	assert_eq(LedgerRows.stored_rows(table, 0).size(), 3)
	assert_eq(LedgerRows.stored_rows(table, 1), [], "a chart never visited is empty")
	assert_eq(LedgerRows.stored_rows(null, 0), [], "a missing table reads empty, not an error")
	table.set_region(2, {"not": "a roster"})
	assert_eq(LedgerRows.stored_rows(table, 2), [], "a works table is not a roster")


func test_the_chart_scope_is_one_wording_every_count_line_reads() -> void:
	assert_eq(LedgerRows.scope_text(LedgerRows.REGION_OLD), "in the Old World")
	assert_eq(LedgerRows.scope_text(LedgerRows.REGION_NEW), "in the New World")
	assert_eq(LedgerRows.scope_text(LedgerRows.REGION_ALL), "in both charts")
	assert_eq(
		LedgerRows.scope_text("a_chart_no_sheet_names"),
		"in both charts",
		"an unknown key keeps every chart, as the narrowing does"
	)


func test_the_crowns_fleets_are_walked_once_for_both_ledgers() -> void:
	var table := MapRegionTable.new()
	var mine := FleetState.new()
	mine.owner = 4
	var theirs := FleetState.new()
	theirs.owner = 7
	table.set_region(0, [mine, theirs])
	var fleets: Array[FleetState] = LedgerRows.stored_fleets(table, 0, 4)
	assert_eq(fleets.size(), 1, "a rival's squadron drops out")
	assert_eq(fleets[0], mine)
	assert_eq(LedgerRows.stored_fleets(table, 1, 4), [], "a chart never visited is empty")
	assert_eq(LedgerRows.stored_fleets(null, 0, 4), [], "a missing table reads empty, not an error")


# --- fixtures ---------------------------------------------------------------


## Two charts: the Old World holds an army and a squadron, the New World one army.
func _rows_fixture() -> Dictionary:
	var old_rows: Array[Dictionary] = [_rows_row(0, "army"), _rows_row(0, "squadron")]
	var new_rows: Array[Dictionary] = [_rows_row(1, "army")]
	return {
		"rows": old_rows + new_rows,
		"groups": [
			{"region": 0, "region_label": FactionCatalog.region_label(0), "rows": old_rows},
			{"region": 1, "region_label": FactionCatalog.region_label(1), "rows": new_rows},
		],
	}


func _rows_row(region: int, kind: String) -> Dictionary:
	return {
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"kind": kind,
		"flags": [kind],
	}


static func _rows_always(_row: Dictionary) -> bool:
	return true


static func _rows_kind(row: Dictionary, key: String) -> bool:
	return LedgerRows.field_matches(row, "kind", key)

# --- the crown's towns ---

## The crown's towns: the whole-empire town ledger reads every town the crown holds, the
## level it stands at and the step the Builder would take next (wiki:
## extraction-and-improvements § Town manufacturing bonus; DR-20261115-12) and the sheet
## drives it — the realm's door, the Raise press, back and the key. One Godot boot: the
## projection suite reads small fixtures, the drive mounts the shared map screen
## (docs/testing.md).

const TOWN_TILE: Vector2i = Vector2i(1, 0)



# --- towns: projection ---


func test_snapshot_lists_every_town_the_crown_holds_in_both_charts() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown town per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's town stays out")


## A crown town on each chart at different levels: the sheet prints one heading
## per chart, and the batch walk still leads with the weakest step whichever
## chart it stands on (DR-20261116-03).
func test_the_towns_sheet_prints_one_heading_per_chart_whatever_the_levels() -> void:
	var regions: Array[Dictionary] = _town_regions(_builders())
	var home: MapModel = regions[0]["model"] as MapModel
	home.provinces[1].owner = 0
	home.provinces[1].town_development = 2
	var abroad: MapModel = regions[1]["model"] as MapModel
	abroad.provinces[0].town_development = 1
	var snapshot: Dictionary = TownLedger.snapshot(regions, 0)
	assert_eq(int(snapshot["total"]), 3, "two towns at home, one abroad")
	var groups: Array[Dictionary] = TownLedger.groups(snapshot, LedgerRows.REGION_ALL)
	assert_eq(groups.size(), 2, "one heading per chart, not one per level")
	assert_eq(int(groups[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((groups[0]["rows"] as Array).size(), 2, "both home towns under one heading")
	assert_eq((groups[1]["rows"] as Array).size(), 1, "the colony under its own")
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 3, "every ready town is a target")
	assert_eq(int(targets[0]["region"]), FactionCatalog.OLD_WORLD, "a level-1 town leads")
	assert_eq(int(targets[1]["region"]), FactionCatalog.NEW_WORLD, "then the level-1 colony")
	assert_eq(int(targets[2]["region"]), FactionCatalog.OLD_WORLD, "the level-2 town last")


func test_a_ready_town_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_READY, "a crew is free and the study is known")
	assert_eq(String(home["level_text"]), "I", "the level reads as a numeral")
	assert_eq(int(home["next_level"]), 2)
	assert_eq(String(home["cost_text"]), "4 lumber + 4 cast iron", "the table's own price")
	assert_eq(int(home["turns"]), 2, "the target level is the wait")
	assert_eq(
		String(home["note"]),
		"Next: II · 4 lumber + 4 cast iron · 2 turns",
		"the row names the level, the price and the wait"
	)


func test_a_town_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders(), {}), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_LOCKED)
	assert_true(
		String(home["note"]).contains("National Bureaucracy"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[TownLedger.FILTER_READY]),
		0,
		"a locked town is not counted as ready"
	)


## The third gate the order charges is the purse: a crown with no stores was
## offered a Raise the work order refused (wiki: civilian-units § Builder,
## extraction-and-improvements § Town manufacturing bonus; DR-20261115-12 —
## "a row that cannot be raised carries no press").
func test_a_town_the_stores_cannot_pay_for_is_locked_and_names_the_shortfall() -> void:
	var tech: Dictionary = {"national_bureaucracy": true}
	var regions: Array[Dictionary] = _town_regions(_builders(), tech, {})
	var snapshot: Dictionary = TownLedger.snapshot(regions, 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_LOCKED, "the order would refuse the level")
	assert_eq(
		String(home["note"]),
		CivilianWorkPlan.town_upgrade_refusal(
			(regions[0]["model"] as MapModel).provinces[0], tech, {}
		),
		"the row speaks the order's own refusal"
	)
	assert_true(
		String(home["note"]).contains("4 lumber + 4 cast iron"),
		"the note names what the crown is short of: %s" % home["note"]
	)
	assert_eq(
		int(TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[TownLedger.FILTER_READY]),
		0,
		"a town the stores cannot pay for is not counted as ready"
	)
	var paid: Dictionary = TownLedger.snapshot(
		_town_regions(_builders(), tech, {"lumber": 4, "castIron": 4}), 0
	)
	assert_eq(
		String(_row(paid, FactionCatalog.OLD_WORLD)["state"]), TownLedger.STATE_READY,
		"the materials, and nothing else, open the row"
	)


func test_a_town_with_no_idle_crew_waits_on_a_builder() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions([] as Array), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_NO_BUILDER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Builder"), "the row names the wait")


## The town tile is shared with the wall and the ward, and the crew rule keeps
## one Builder, Engineer or Merchant a tile: a Raise offered while an Engineer
## already works the town would be refused, so the row names the busy tile
## instead (wiki: civilian-units § Per-player tile exclusivity; DR-20261115-12 —
## "a row that cannot be raised carries no press").
func test_a_crew_already_on_the_town_tile_closes_the_press() -> void:
	var engineer: CivilianState = CivilianState.create(2, 0, "engineer", TOWN_TILE)
	engineer.start_work("build_fort", TOWN_TILE, 1, TOWN_TILE, {"fort_level": 1})
	var builder: CivilianState = CivilianState.create(1, 0, "builder", Vector2i(0, 0))
	var units: Array[CivilianState] = [builder, engineer]
	var regions: Array[Dictionary] = _town_regions(units)
	var home: Dictionary = _row(TownLedger.snapshot(regions, 0), FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_LOCKED, "the order would refuse the tile")
	# The row speaks the order's own words, so the promise and the refusal match.
	var order: Dictionary = ImprovementOrders.upgrade_town(
		regions[0]["model"] as MapModel, units, LandWorks.new(),
		{"lumber": 9, "castIron": 9}, VisibilityModel.new(), 0, TOWN_TILE,
		{"national_bureaucracy": true}
	)
	assert_false(bool(order.get("ok", true)), "the order refuses the busy tile")
	assert_eq(String(home["note"]), String(order.get("message", "")), "one wording")
	assert_eq(
		int(TownLedger.filter_counts(
			TownLedger.snapshot(regions, 0), LedgerRows.REGION_ALL
		)[TownLedger.FILTER_READY]),
		0,
		"a busy town is never counted as ready"
	)


func test_a_crew_already_at_work_is_read_from_its_own_record() -> void:
	var builder: CivilianState = CivilianState.create(1, 0, "builder", TOWN_TILE)
	builder.start_work("upgrade_town", TOWN_TILE, 2, TOWN_TILE, {"town_level": 2})
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions([builder]), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), TownLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises it to II"), "the target level is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_developed_town_reads_finished() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["level"]), 4)
	assert_eq(String(overseas["state"]), TownLedger.STATE_DEVELOPED)
	assert_true(String(overseas["note"]).contains("Fully developed"))


func test_town_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var counts: Dictionary = TownLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[TownLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[TownLedger.FILTER_READY]), 1)
	assert_eq(int(counts[TownLedger.FILTER_DEVELOPED]), 1)
	assert_eq(int(counts[TownLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = TownLedger.groups(
		snapshot, LedgerRows.REGION_ALL, TownLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready town")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(TownLedger.count(snapshot, LedgerRows.REGION_NEW, TownLedger.FILTER_READY), 0)


func test_the_reading_leads_with_what_can_be_raised_now() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var rows: Array = snapshot["rows"]
	assert_eq(String((rows[0] as Dictionary)["state"]), TownLedger.STATE_READY)
	assert_eq(String((rows[1] as Dictionary)["state"]), TownLedger.STATE_DEVELOPED)


func test_the_bonus_note_states_where_the_bonus_sits() -> void:
	var note: String = TownLedger.bonus_note()
	assert_true(note.contains("levels 2 and 4"), "the rule a crown pays by is printed")


# --- the shared raise spine -------------------------------------------------


## The spine under both raise sheets: a tally per state, the reading order and
## the state words each sheet passes in (DR-20261115-12, DR-20261116-01).
func test_the_spine_counts_every_state_a_row_can_carry() -> void:
	var counts: Dictionary = RaiseLedger.empty_counts(TownLedger.STATES)
	assert_eq(counts.size(), TownLedger.STATES.size(), "one tally per state")
	for state: String in TownLedger.STATES:
		assert_eq(int(counts[state]), 0, "a zero stays legible")


func test_the_spine_orders_a_ready_step_before_a_finished_one() -> void:
	var rows: Array[Dictionary] = [
		{"state": TownLedger.STATE_DEVELOPED, "level": 1, "region": 0, "id": 1},
		{"state": TownLedger.STATE_READY, "level": 3, "region": 1, "id": 2},
		{"state": TownLedger.STATE_READY, "level": 1, "region": 0, "id": 3},
	]
	RaiseLedger.sort_rows(rows, TownLedger.STATE_ORDER)
	assert_eq(int(rows[0]["id"]), 3, "the weakest ready step leads")
	assert_eq(int(rows[1]["id"]), 2, "then the stronger ready step")
	assert_eq(int(rows[2]["id"]), 1, "the finished work reads last")


func test_the_spine_reads_the_finished_and_no_crew_words_the_sheet_passes() -> void:
	assert_eq(
		RaiseLedger.state_for(
			4, 4, null, "", false, TownLedger.STATE_DEVELOPED, TownLedger.STATE_NO_BUILDER
		),
		TownLedger.STATE_DEVELOPED,
		"a finished work is the sheet's own word"
	)
	assert_eq(
		RaiseLedger.state_for(
			1, 4, null, "", false, TownLedger.STATE_DEVELOPED, TownLedger.STATE_NO_BUILDER
		),
		TownLedger.STATE_NO_BUILDER,
		"a missing crew is the sheet's own word"
	)


# --- the batch press ---------------------------------------------------------


## The press files exactly what the view prints: the ready rows, in the sheet's
## own order, and nothing a filter has hidden (REQ-P5-04; DR-20261116-03).
func test_the_batch_press_reads_only_the_ready_rows_the_view_prints() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 1, "one ready town, one target")
	assert_eq(int(targets[0]["region"]), FactionCatalog.OLD_WORLD, "the chart it stands on")
	assert_eq(
		RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_NEW).size(),
		0,
		"a chart with nothing ready offers no target"
	)
	assert_eq(
		RaiseLedger.ready_targets(
			snapshot, LedgerRows.REGION_ALL, TownLedger.FILTER_DEVELOPED
		).size(),
		0,
		"a finished reading offers no press"
	)


## The walk stops at the first refusal — the rules' own answer — so a press never
## claims a step the order refused (REQ-P2-03, REQ-P5-05; DR-20261116-03).
func test_the_batch_walk_stops_at_the_first_refusal() -> void:
	_filed.clear()
	var targets: Array[Dictionary] = [
		{"region": 0, "id": 1},
		{"region": 0, "id": 2},
		{"region": 0, "id": 3},
	]
	var result: Dictionary = RaiseLedger.file_batch(targets, _refuse_second)
	assert_eq(_filed.size(), 2, "the walk stops at the refusal")
	assert_eq(_filed[0], 1, "the first target was filed")
	assert_eq(_filed[1], 2, "the refusing target was asked, and the walk stopped")
	assert_eq(int(result["raised"]), 1, "one order was filed")
	assert_eq(int(result["total"]), 3, "the view held three")
	assert_eq(String(result["refusal"]), "No idle Builder musters.", "the refusal is kept")


func test_the_receipt_names_what_the_press_left() -> void:
	assert_eq(
		RaiseLedger.batch_receipt({"raised": 3, "total": 3, "refusal": ""}, "towns"),
		"Raised 3 towns — every ready step in this view is ordered."
	)
	assert_eq(
		RaiseLedger.batch_receipt(
			{"raised": 1, "total": 3, "refusal": "No idle Builder musters."}, "towns"
		),
		"Raised 1 of 3 towns. The next waits: No idle Builder musters."
	)


# --- towns: the sheet ---


func test_the_realm_door_opens_the_towns_ledger() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	assert_not_null(panel, "the HUD mounts the towns ledger")
	var door: Button = _towns_door()
	assert_not_null(door, "the realm ledger carries the towns door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the realm's towns door opens it")
	assert_true(_row_widgets(panel) > 0, "the crown's towns are listed")


func test_raise_files_the_builders_order_on_the_provinces_chart() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	var province: ProvinceState = _crown_town()
	assert_not_null(province, "the campaign seats the crown in a town")
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["castIron"] = 40
	var town: Vector2i = province.town_tile
	var builder: CivilianState = CivilianState.create(90, screen.play.player_faction, "builder", town)
	screen.play.civilian_layer.units.append(builder)
	panel.open()
	var row: TownLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	row.press_raise()
	assert_true(builder.is_working(), "the press files the order")
	assert_eq(builder.work_action(), "upgrade_town", "the Builder raises the town")
	assert_eq(builder.work_tile(), town, "on the province's own town tile")
	assert_eq(int(stock["lumber"]), 36, "the price is the table's own")
	assert_true(_state_of(_row_for(panel, province.id)) == "at_work", "and the row reads it")


## A hand-built chart predates town assignment: the seat stands, the town tile
## was never written. The row, its press and the Builder's order all read the
## one site rule (`ProvinceState.town_site`), so the press files on the seat
## instead of being refused for a town the chart never assigned
## (REQ-P2-03, REQ-P5-05).
func test_the_town_press_files_on_the_seat_a_hand_built_chart_never_assigned() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	var province: ProvinceState = _crown_town()
	assert_not_null(province, "the campaign seats the crown in a town")
	_cancel_works()
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["castIron"] = 40
	var seat: Vector2i = province.town_tile
	province.town_tile = Vector2i(-1, -1)
	province.capital = true
	province.capital_tile = seat
	assert_eq(province.town_site(), seat, "the seat is the province's town site")
	var builder: CivilianState = CivilianState.create(
		91, screen.play.player_faction, "builder", seat
	)
	screen.play.civilian_layer.units.append(builder)
	panel.open()
	var row: TownLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the seat still carries a town row")
	assert_eq(String(row.data.get("state", "")), TownLedger.STATE_READY, "and offers the step")
	assert_true(row._raise.visible, "with the press on it")
	row.press_raise()
	assert_eq(builder.work_action(), "upgrade_town", "the press files the Builder's order")
	assert_eq(builder.work_tile(), seat, "on the seat the chart does carry")


## The purse is the third gate on the sheet itself: with every store at zero the
## row reads LOCKED and carries no press, and the materials arriving open it —
## no press the order would refuse (wiki: civilian-units § Builder;
## DR-20261115-12, REQ-P2-03, REQ-P5-05).
func test_a_short_purse_leaves_the_town_raise_press_off_the_sheet() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	_cancel_works()
	var province: ProvinceState = _crown_town()
	assert_not_null(province, "the campaign seats the crown in a town")
	var stock: Dictionary = screen.play.stockpile()
	for key: Variant in stock.keys():
		stock[key] = 0
	panel.open()
	var row: TownLedgerRow = _row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), TownLedger.STATE_LOCKED, "the order would refuse")
	assert_false(row._raise.visible, "a row that cannot be raised carries no press")
	assert_true(
		String(row.data.get("note", "")).contains("Stores are short of"),
		String(row.data.get("note", ""))
	)
	## The materials arrive: the same row opens without the sheet reopening.
	var price: Dictionary = CivilianWork.cost_for(
		"upgrade_town", CivilianWorkPlan.town_upgrade_level(screen.play.model, province.town_tile)
	)
	for key: Variant in price.keys():
		stock[key] = int(price[key])
	panel.refresh()
	var paid: TownLedgerRow = _row_for(panel, province.id)
	assert_eq(String(paid.data.get("state", "")), TownLedger.STATE_READY, "paid, the step opens")
	assert_true(paid._raise.visible, "and the press returns")


## The map hooks answer a missing session and an unreadable province without
## folding: a sheet that opens before the campaign seats reads an empty roll.
func test_the_map_hooks_guard_a_missing_session() -> void:
	assert_eq(int(MapPlayTowns.snapshot(null).get("total", -1)), 0, "no session, no towns")
	MapPlayTowns.raise(null, FactionCatalog.OLD_WORLD, 0)
	MapPlayTowns.raise(screen.play, FactionCatalog.OLD_WORLD, -1)
	MapPlayTowns.raise(screen.play, 99, 0)
	assert_eq(int(MapPlayTowns.snapshot(screen.play).get("total", 0)), _crown_towns())


func test_back_and_the_key_close_the_towns_ledger() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.hud.towns_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.TOWNS_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## One arm, one confirm, and every ready town the view prints takes a Builder —
## the receipt is the one line the court reads (REQ-P5-04, REQ-P5-05;
## DR-20261116-03).
func test_the_batch_press_files_every_ready_town_in_one_confirmed_press() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	screen.play.tech_unlocked()["national_bureaucracy"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 400
	stock["castIron"] = 400
	panel.open()
	panel._on_filter(LedgerRows.REGION_OLD, true)
	var targets: Array[Dictionary] = panel._ready_targets()
	assert_true(
		targets.size() >= 2,
		"the campaign seats two towns the crown can raise: %d" % targets.size()
	)
	for index in targets.size():
		var province: ProvinceState = screen.play.model.province_data(int(targets[index]["id"]))
		screen.play.civilian_layer.units.append(
			CivilianState.create(
				300 + index, screen.play.player_faction, "builder", province.town_tile
			)
		)
	panel.refresh()
	var press: RaiseBatchPress = panel._batch
	assert_not_null(press, "the sheet carries the batch press")
	assert_true(press.visible, "the press stands when the view holds a ready step")
	assert_eq(press.text, "Raise all ready (%d)" % targets.size(), "the press names the count")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(
		press.text, "Confirm — raise %d towns" % targets.size(), "the second tap is named"
	)
	press.pressed.emit()
	assert_false(press.is_armed(), "the press forgets the arm once it files")
	assert_eq(_working_town_builders(), targets.size(), "every ready town took a Builder")
	assert_eq(panel._ready_targets().size(), 0, "the view holds no ready step after the press")
	assert_false(press.visible, "and the press stands down")


func test_the_batch_press_stands_down_when_the_view_holds_nothing_ready() -> void:
	var panel: TownLedgerPanel = screen.hud.towns_ledger
	panel.open()
	panel._on_filter(TownLedger.FILTER_DEVELOPED, false)
	assert_false(panel._batch.visible, "a reading with nothing ready carries no press")


# --- towns: fixtures ---


## Two charts of the naval fixture: the crown holds Cádiz at home (a level-1
## town) and Veracruz abroad (a finished town), and the rival's Coro carries a
## town of its own that must never reach the reading.
func _town_regions(
	units: Array, tech: Dictionary = {"national_bureaucracy": true}, stockpile: Variant = null
) -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = TOWN_TILE
	new.provinces[0].town_development = 4
	old.provinces[0].town_tile = TOWN_TILE
	old.provinces[0].town_development = 1
	old.provinces[1].town_tile = Vector2i(5, 1)
	old.provinces[1].town_development = 2
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
	]


## One idle Builder on the crown's own land, so a ready town has a crew free.
func _builders() -> Array:
	return [CivilianState.create(1, 0, "builder", TOWN_TILE)]


func _row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that carries a town and has
## not been finished yet.
func _crown_town() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if not province.has_town() or province.town_tile.x < 0:
			continue
		if province.town_level() < CivilianWorkPlan.MAX_TOWN:
			return province
	return null


## The realm ledger's towns door, found by its word so the suite reads the
## button the player presses.
func _towns_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Towns ›":
			return button
	return null


## Frees every crew this suite put to work, so a case that reads a row does not
## inherit the order an earlier case filed.
func _cancel_works() -> void:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit != null and unit.owner == screen.play.player_faction and unit.is_working():
			unit.cancel_work()


func _row_for(panel: TownLedgerPanel, province_id: int) -> TownLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as TownLedgerRow
		if row != null and int(row.data.get("id", -1)) == province_id:
			return row
	return null


func _state_of(row: TownLedgerRow) -> String:
	if row == null:
		return ""
	return String(row.data.get("state", ""))


## How many towns the mounted campaign's crown holds in both charts, so the
## sheet's own total is checked against the chart rather than a hand count.
func _crown_towns() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if province.has_town():
				total += 1
	return total


func _row_widgets(panel: TownLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is TownLedgerRow:
			total += 1
	return total

## Every target the batch walk asked for, in the order it asked: the pure walk's
## own record, so a refusal's cost is read (DR-20261116-03).
var _filed: Array[int] = []


## An order hook that files the first two targets and refuses the third the way a
## sheet with no free Builder would.
func _refuse_second(_region: int, province_id: int) -> Dictionary:
	_filed.append(province_id)
	if province_id == 2:
		return {"ok": false, "message": "No idle Builder musters."}
	return {"ok": true, "message": ""}


## How many of the crown's Builders in the mounted chart are raising a town now.
func _working_town_builders() -> int:
	var working: int = 0
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit == null or unit.owner != screen.play.player_faction:
			continue
		if unit.work_action() == "upgrade_town":
			working += 1
	return working


# --- the crown's walls ---

## The crown's walls: the whole-empire wall ledger reads every province the crown holds
## that can carry a fort, the wall it stands behind and the step the Engineer would take
## next (wiki: siege-mechanics § Fort Levels, § Wall Protection; DR-20261116-01) and the
## sheet drives it — the realm's door, the Raise press, back and the key. One Godot boot:
## the projection suite reads small fixtures, the drive mounts the shared map screen
## (docs/testing.md).




# --- walls: projection ---


func test_snapshot_lists_every_wall_the_crown_can_raise_in_both_charts() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions(_engineers()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's shore stays out")


## A wall on each chart at different levels: one heading per chart, however the
## level order interleaves the charts (DR-20261116-01).
func test_the_walls_sheet_prints_one_heading_per_chart_whatever_the_levels() -> void:
	var regions: Array[Dictionary] = _wall_regions(_engineers())
	var home: MapModel = regions[0]["model"] as MapModel
	home.provinces[1].owner = 0
	home.provinces[1].fort_level = 1
	var abroad: MapModel = regions[1]["model"] as MapModel
	abroad.provinces[0].fort_level = 0
	var snapshot: Dictionary = WallLedger.snapshot(regions, 0)
	assert_eq(int(snapshot["total"]), 3, "two shores at home, one abroad")
	var groups: Array[Dictionary] = WallLedger.groups(snapshot, LedgerRows.REGION_ALL)
	assert_eq(groups.size(), 2, "one heading per chart, not one per level")
	assert_eq(int(groups[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((groups[0]["rows"] as Array).size(), 2, "both home shores under one heading")
	assert_eq((groups[1]["rows"] as Array).size(), 1, "the colony under its own")


func test_a_bare_shore_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions(_engineers()), 0)
	var home: Dictionary = _wall_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_READY, "a crew is free and no study is owed")
	assert_eq(String(home["level_text"]), "—", "an open shore is a dash, not a zero")
	assert_eq(String(home["line"]), "No fort")
	assert_eq(int(home["next_level"]), 1)
	assert_eq(String(home["cost_text"]), "3 lumber + 3 bronze", "the fort table's own price")
	assert_eq(int(home["turns"]), 1, "a wood wall is one turn")
	assert_eq(
		String(home["note"]),
		"Next: wood fort · 3 lumber + 3 bronze · 1 turn",
		"the row names the wall, the price and the wait"
	)


func test_a_wall_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(
		_wall_regions(_engineers(), {"mine_engineering": false}), 0
	)
	var overseas: Dictionary = _wall_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(String(overseas["state"]), WallLedger.STATE_LOCKED, "a wood wall is up; stone is gated")
	assert_true(
		String(overseas["note"]).contains("Mine Engineering"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[WallLedger.FILTER_READY]),
		1,
		"a locked wall is not counted as ready"
	)


## The third gate the order charges is the purse: a crown with no stores was
## offered a Raise the work order refused (wiki: siege-mechanics § Fort Levels —
## "a row that cannot be raised carries no press"; DR-20261116-01).
func test_a_shore_the_stores_cannot_pay_for_is_locked_and_names_the_shortfall() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions(_engineers(), {}, {}), 0)
	var home: Dictionary = _wall_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_LOCKED, "the order would refuse the wall")
	assert_eq(
		String(home["note"]),
		CivilianWorkPlan.fort_refusal(0, {"mine_engineering": true}, {}),
		"the row speaks the order's own refusal"
	)
	assert_true(
		String(home["note"]).contains("3 lumber + 3 bronze"),
		"the note names what the crown is short of"
	)
	assert_eq(
		int(WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[WallLedger.FILTER_READY]),
		0,
		"a wall the stores cannot pay for is not counted as ready"
	)
	var paid: Dictionary = WallLedger.snapshot(
		_wall_regions(_engineers(), {}, {"lumber": 3, "bronze": 3}), 0
	)
	assert_eq(
		String(_wall_row(paid, FactionCatalog.OLD_WORLD)["state"]), WallLedger.STATE_READY,
		"the materials, and nothing else, open the row"
	)


func test_a_shore_with_no_idle_crew_waits_on_an_engineer() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions([] as Array), 0)
	var home: Dictionary = _wall_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_NO_ENGINEER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Engineer"), "the row names the wait")


func test_an_engineer_already_at_work_is_read_from_its_own_record() -> void:
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", TOWN_TILE)
	engineer.start_work("build_fort", TOWN_TILE, 2, TOWN_TILE, {"fort_level": 2})
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions([engineer]), 0)
	var home: Dictionary = _wall_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), WallLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises the stone fort"), "the target wall is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_modern_wall_reads_finished() -> void:
	var raised: Dictionary = _raised()
	assert_eq(int(raised["level"]), FortRules.MAX_LEVEL)
	assert_eq(String(raised["state"]), WallLedger.STATE_RAISED, "a citadel owes nothing")
	assert_eq(String(raised["note"]), "Fully walled — 3 guns, 30 wall hp.")
	assert_eq(String(raised["level_text"]), "III")


func test_wall_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(
		_wall_regions(_engineers(), {"mine_engineering": false}), 0
	)
	var counts: Dictionary = WallLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[WallLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[WallLedger.FILTER_READY]), 1)
	assert_eq(int(counts[WallLedger.FILTER_RAISED]), 0)
	assert_eq(int(counts[WallLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = WallLedger.groups(
		snapshot, LedgerRows.REGION_ALL, WallLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready wall")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(WallLedger.count(snapshot, LedgerRows.REGION_NEW, WallLedger.FILTER_READY), 0)


func test_wall_the_reading_leads_with_what_can_be_raised_now() -> void:
	var rows: Array = _raised_snapshot()["rows"]
	assert_eq(String((rows[0] as Dictionary)["state"]), WallLedger.STATE_READY, "the open shore leads")
	assert_eq(String((rows[1] as Dictionary)["state"]), WallLedger.STATE_RAISED, "the citadel follows")


func test_the_summary_names_where_nothing_stands() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions(_engineers(), _wide_tech()), 0)
	var reading: Dictionary = WallLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["total"]), 2)
	assert_eq(int(reading["bare"]), 1, "one open shore")
	assert_eq(int(reading["walled"]), 1, "one wood or stone wall")
	assert_eq(int(reading["citadel"]), 0)
	var built: Dictionary = WallLedger.summary(_raised_snapshot(), LedgerRows.REGION_ALL)
	assert_eq(int(built["citadel"]), 1, "a modern wall is a citadel")


func test_the_rule_note_states_what_a_wall_buys() -> void:
	var note: String = WallLedger.rule_note()
	assert_true(note.contains("10 / 20 / 30 wall hp"), "the wall's soak is printed")
	assert_true(note.contains("emplaced guns"), "the battery is printed")


# --- walls: the sheet ---


func test_the_realm_door_opens_the_walls_ledger() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	assert_not_null(panel, "the HUD mounts the walls ledger")
	var door: Button = _walls_door()
	assert_not_null(door, "the realm ledger carries the walls door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the realm's walls door opens it")
	assert_true(_wall_row_widgets(panel) > 0, "the crown's walls are listed")


func test_raise_files_the_engineers_order_on_the_provinces_chart() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	var province: ProvinceState = _crown_wall()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a wall")
	screen.play.tech_unlocked()["mine_engineering"] = true
	screen.play.tech_unlocked()["modern_forts"] = true
	var stock: Dictionary = screen.play.stockpile()
	stock["lumber"] = 40
	stock["bronze"] = 40
	stock["steel"] = 40
	var site: Vector2i = FortRules.site_tile(screen.play.model, province.id)
	var price: Dictionary = FortRules.cost(FortRules.next_level(province.fort_level))
	var lumber: int = int(stock["lumber"])
	panel.open()
	var row: WallLedgerRow = _wall_row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), WallLedger.STATE_READY, "the row offers the press")
	row.press_raise()
	var crew: CivilianState = _wall_crew(site)
	assert_not_null(crew, "the press sends an Engineer")
	assert_eq(crew.work_action(), "build_fort", "and files the wall order")
	assert_eq(crew.work_tile(), site, "on the province's own town tile")
	assert_eq(
		int(stock["lumber"]), lumber - int(price.get("lumber", 0)),
		"the price is the fort table's own"
	)
	assert_eq(_wall_state_of(_wall_row_for(panel, province.id)), "at_work", "and the row reads it")


## The purse is the third gate on the sheet itself: with every store at zero the
## row reads LOCKED and carries no press, and the materials arriving open it —
## no press the order would refuse (wiki: siege-mechanics § Fort Levels;
## DR-20261116-01, REQ-P2-03, REQ-P5-05).
func test_a_short_purse_leaves_the_wall_raise_press_off_the_sheet() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	screen.play.tech_unlocked()["mine_engineering"] = true
	screen.play.tech_unlocked()["modern_forts"] = true
	_cancel_works()
	var province: ProvinceState = _crown_wall()
	assert_not_null(province, "the campaign seats the crown on ground that can carry a wall")
	var stock: Dictionary = screen.play.stockpile()
	for key: Variant in stock.keys():
		stock[key] = 0
	panel.open()
	var row: WallLedgerRow = _wall_row_for(panel, province.id)
	assert_not_null(row, "the province is on the sheet")
	assert_eq(String(row.data.get("state", "")), WallLedger.STATE_LOCKED, "the order would refuse")
	assert_false(row._raise.visible, "a row that cannot be raised carries no press")
	assert_true(String(row.data.get("note", "")).contains("Stores are short of"), row.data.get("note", ""))
	## The materials arrive: the same row opens without the sheet reopening.
	var price: Dictionary = FortRules.cost(FortRules.next_level(province.fort_level))
	for key: Variant in price.keys():
		stock[key] = int(price[key])
	panel.refresh()
	var paid: WallLedgerRow = _wall_row_for(panel, province.id)
	assert_eq(String(paid.data.get("state", "")), WallLedger.STATE_READY, "paid, the step opens")
	assert_true(paid._raise.visible, "and the press returns")


## The map hooks answer a missing session and an unreadable province without
## folding: a sheet that opens before the campaign seats reads an empty roll.
func test_wall_the_map_hooks_guard_a_missing_session() -> void:
	assert_eq(int(MapPlayWalls.snapshot(null).get("total", -1)), 0, "no session, no walls")
	MapPlayWalls.raise(null, FactionCatalog.OLD_WORLD, 0)
	MapPlayWalls.raise(screen.play, FactionCatalog.OLD_WORLD, -1)
	MapPlayWalls.raise(screen.play, 99, 0)
	assert_eq(int(MapPlayWalls.snapshot(screen.play).get("total", 0)), _crown_walls())


func test_back_and_the_key_close_the_walls_ledger() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	screen.hud.walls_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.WALLS_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## The walls sheet is the towns sheet's sibling, so it carries the same one-press
## batch under its chips (DR-20261116-03).
func test_the_walls_sheet_carries_the_batch_press() -> void:
	var panel: WallLedgerPanel = screen.hud.walls_ledger
	panel.open()
	assert_not_null(panel._batch, "the sheet carries the batch press")
	assert_true(panel._batch is RaiseBatchPress, "and it is the shared press")


# --- walls: fixtures ---


## Two charts of the naval fixture: the crown holds Cádiz at home (a bare town)
## and Veracruz abroad (a wood wall), and the rival's Coro carries a town of its
## own that must never reach the reading.
func _wall_regions(
	units: Array, tech: Dictionary = {"mine_engineering": true}, stockpile: Variant = null
) -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = TOWN_TILE
	new.provinces[0].fort_level = 1
	old.provinces[0].town_tile = TOWN_TILE
	old.provinces[1].town_tile = Vector2i(5, 1)
	return [
		{
			"region": FactionCatalog.OLD_WORLD,
			"model": old,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"units": units,
			"tech_unlocked": tech,
			"stockpile": stockpile,
		},
	]


## The gates a citadel owes: Mine Engineering for stone, Modern Forts for the
## third level, so a raised wall is a finished wall.
func _wide_tech() -> Dictionary:
	return {"mine_engineering": true, "modern_forts": true}


## One idle Engineer on the crown's own ground, so a ready shore has a crew free.
func _engineers() -> Array:
	return [CivilianState.create(1, 0, "engineer", TOWN_TILE)]


## The crown's province at home, walled to the third level, so the finished
## reading has a row of its own.
func _raised_snapshot() -> Dictionary:
	var regions: Array[Dictionary] = _wall_regions(_engineers(), _wide_tech())
	(regions[0]["model"] as MapModel).provinces[0].fort_level = FortRules.MAX_LEVEL
	return WallLedger.snapshot(regions, 0)


func _raised() -> Dictionary:
	return _wall_row(_raised_snapshot(), FactionCatalog.OLD_WORLD)


func _wall_row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that can carry a wall and
## has not been finished yet.
func _crown_wall() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if province.fort_level >= FortRules.MAX_LEVEL:
			continue
		if FortRules.site_tile(screen.play.model, province.id).x >= 0:
			return province
	return null


## The realm ledger's walls door, found by its word so the suite reads the
## button the player presses.
func _walls_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Walls ›":
			return button
	return null


## The Engineer the sheet sent: the crown's crew with a wall order on this site.
func _wall_crew(site: Vector2i) -> CivilianState:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit.owner != screen.play.player_faction or not unit.is_working():
			continue
		if unit.work_action() == "build_fort" and unit.work_tile() == site:
			return unit
	return null


func _wall_row_for(panel: WallLedgerPanel, province_id: int) -> WallLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as WallLedgerRow
		if row != null and int(row.data.get("id", -1)) == province_id:
			return row
	return null


func _wall_state_of(row: WallLedgerRow) -> String:
	if row == null:
		return ""
	return String(row.data.get("state", ""))


## How many provinces the mounted campaign's crown holds that can carry a wall,
## so the sheet's own total is checked against the chart rather than a hand
## count.
func _crown_walls() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if FortRules.site_tile(model, province.id).x >= 0:
				total += 1
	return total


func _wall_row_widgets(panel: WallLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is WallLedgerRow:
			total += 1
	return total

# --- the crown's navy, hull by hull ---

## The crown's navy, hull by hull (wiki: ships-and-naval § Ship combat and cargo stats, §
## Ship instances; DR-20261115-14): the projection reads every hull the crown floats in
## both charts, squadron by squadron, and the sheet drives it — the fleet dossier's door,
## the readings, back and the key. One Godot boot: the projection cases read a tiny
## two-chart fixture, the sheet cases mount the shared map screen (docs/testing.md).


const OWNER: int = 0
const RIVAL: int = 1



# --- navy: projection ---


func test_the_ledger_reads_every_hull_of_both_charts() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	assert_eq(int(data["total"]), 3, "one row per hull the crown floats")
	assert_eq((data["groups"] as Array).size(), 2, "one heading per squadron")
	assert_eq(NavalLedger.count(data, LedgerRows.REGION_OLD), 2)
	assert_eq(NavalLedger.count(data, LedgerRows.REGION_NEW), 1)
	assert_eq(NavalLedger.squadron_count(data, LedgerRows.REGION_ALL), 2)
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["hull"]), "ship_9", "the rival's hull stays out")


func test_a_hull_row_reads_her_class_guns_and_holds() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var frigate: Dictionary = _row_of(data, "ship_2")
	assert_eq(String(frigate["class"]), "Frigate")
	assert_eq(String(frigate["role"]), NavalLedger.READING_WARSHIP)
	assert_eq(String(frigate["role_label"]), "WARSHIP")
	assert_eq(String(frigate["line"]), NavalStrength.hull_line("frigate"), "the catalogue's own line")
	assert_eq(int(frigate["holds"]), 0, "a warship carries none")
	assert_eq(String(frigate["state"]), "No holds — she fights in the line")
	var carrack: Dictionary = _row_of(data, "ship_1")
	assert_eq(String(carrack["role"]), NavalLedger.READING_MERCHANT)
	assert_eq(String(carrack["state"]), "3 holds for the world market")
	assert_eq(int(carrack["holds"]), 3)


func test_the_line_leads_every_squadron() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var rows: Array = data["rows"]
	var first: Dictionary = rows[0]
	assert_eq(String(first["role"]), NavalLedger.READING_WARSHIP, "the man-of-war leads her squadron")
	assert_eq(String(first["region_label"]), FactionCatalog.region_label(FactionCatalog.OLD_WORLD))


func test_the_squadron_heading_reads_where_she_sails_and_her_station() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var groups: Array[Dictionary] = NavalLedger.groups(data, LedgerRows.REGION_ALL)
	var home: Dictionary = groups[0]
	assert_true(String(home["heading"]).contains("SQUADRON — "), "the heading names the flagship")
	assert_eq(String(home["place"]), "In port at Cádiz")
	assert_eq(String(home["station"]), "Patrol", "the station is the rules' own word")
	assert_eq(int(home["holds"]), TradeCargo.fleet_holds(_home_fleet()), "her holds, not the ship's")
	assert_almost_eq(float(home["strength"]), NavalStrength.strength(_home_fleet()), 0.001)
	var abroad: Dictionary = groups[1]
	assert_eq(String(abroad["place"]), "At sea — Mar Caribe")
	assert_eq(String(abroad["station"]), "Awaiting orders")


func test_the_readings_narrow_the_ledger_and_keep_their_tallies() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var counts: Dictionary = NavalLedger.filter_counts(data, LedgerRows.REGION_ALL)
	assert_eq(int(counts[NavalLedger.READING_ALL]), 3)
	assert_eq(int(counts[NavalLedger.READING_WARSHIP]), 1)
	assert_eq(int(counts[NavalLedger.READING_MERCHANT]), 2)
	assert_eq(NavalLedger.count(data, LedgerRows.REGION_NEW, NavalLedger.READING_WARSHIP), 0)
	var warships: Array[Dictionary] = NavalLedger.groups(
		data, LedgerRows.REGION_ALL, NavalLedger.READING_WARSHIP
	)
	assert_eq(warships.size(), 1, "only the squadron that still has a standing hull")
	for row: Dictionary in warships[0]["rows"]:
		assert_eq(String(row["role"]), NavalLedger.READING_WARSHIP)


func test_the_count_line_and_the_note_print_the_rules_own_figures() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var line: String = NavalLedger.summary(data, LedgerRows.REGION_ALL)
	assert_true(line.contains("3 of 3 hulls in 2 squadrons"))
	assert_true(line.contains("1 warships, 2 merchant hulls"))
	assert_true(line.contains("8 holds"), "the merchant hulls' own cargo")
	assert_true(line.contains("strength"))
	var narrowed: String = NavalLedger.summary(
		data, LedgerRows.REGION_OLD, NavalLedger.READING_MERCHANT
	)
	assert_true(narrowed.contains("1 of 2 hulls in the Old World"), "the chart is the denominator")
	assert_true(narrowed.contains("merchant hulls only"))
	assert_true(NavalLedger.note().contains("holds cap"), "the rule a crown buys by is printed")


func test_a_chart_with_no_squadron_reads_empty_and_a_slip_reads_no_hull() -> void:
	assert_eq(int(NavalLedger.snapshot(null, _navy_regions(), OWNER).get("total", -1)), 0)
	assert_eq(int(NavalLedger.snapshot(_world(), null, OWNER).get("total", -1)), 0)
	var slip := FleetState.empty_in_port(7, OWNER, 0)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [slip])
	var data: Dictionary = NavalLedger.snapshot(_world(), table, OWNER)
	assert_eq(int(data["total"]), 0, "a slip has no hull to read")
	assert_eq(NavalLedger.squadron_count(data, LedgerRows.REGION_ALL), 1, "the yard is still counted")
	assert_eq((data["groups"] as Array).size(), 0, "an empty squadron prints no heading")
	assert_true(NavalLedger.summary(data, LedgerRows.REGION_ALL).contains("0 hulls"))


# --- navy: the row ---


func test_a_row_prints_her_name_chip_and_her_own_line() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.setup(_row_of(data, "ship_2"))
	assert_ne(row._name.text, "", "every hull flies a name")
	assert_eq(row._chip.text, "WARSHIP")
	assert_true(row._detail.text.contains("In port at Cádiz"))
	assert_true(row._standing.text.contains("FRP"), "the catalogue's own line")
	assert_true(row._reading.text.contains("No holds"))
	row.free()


func test_a_compact_row_folds_her_class_into_the_detail_line() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.compact = true
	row.setup(_row_of(data, "ship_3"))
	assert_true(row._detail.text.contains("Trader"), "a phone row names the class")
	assert_true(row._detail.text.contains("At sea — Mar Caribe"))
	row.free()


func test_a_visit_asks_for_her_squadrons_chart() -> void:
	var data: Dictionary = NavalLedger.snapshot(_world(), _navy_regions(), OWNER)
	var row := NavalLedgerRow.new()
	row.setup(_row_of(data, "ship_3"))
	var seen: Array = []
	row.visit_pressed.connect(func(region: int, fleet_id: int) -> void:
		seen.append([region, fleet_id])
	)
	row._on_visit()
	assert_eq(seen.size(), 1)
	assert_eq(int((seen[0] as Array)[0]), FactionCatalog.NEW_WORLD)
	assert_eq(int((seen[0] as Array)[1]), 2, "her squadron, not the hull")
	row.free()


# --- navy: the sheet ---


func test_the_muster_rolls_door_opens_the_ledger() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	assert_not_null(panel, "the HUD mounts the navy ledger")
	screen.hud.muster_roll_pressed.emit()
	var door: Button = _navy_door()
	assert_not_null(door, "the muster roll carries the navy door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the muster roll's navy door opens it")
	assert_true(_navy_row_widgets(panel) > 0, "the crown's hulls are listed")
	assert_true(panel._subtitle.text.contains("hulls"), "the count line names the fleet")
	assert_true(_has_text(panel._rows, "holds"), "a squadron heading prints her holds")
	screen.hud.muster_roll.close()


func test_the_readings_narrow_the_sheet() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.navy_pressed.emit()
	assert_true(panel.is_open())
	panel._on_filter(NavalLedger.READING_WARSHIP, false)
	assert_eq(panel._reading, NavalLedger.READING_WARSHIP)
	assert_true(panel._subtitle.text.contains("warships only"))
	for child: Node in panel._rows.get_children():
		var row := child as NavalLedgerRow
		if row != null:
			assert_eq(String(row.data["role"]), NavalLedger.READING_WARSHIP)
	panel._on_filter(LedgerRows.REGION_OLD, true)
	assert_eq(panel._region, LedgerRows.REGION_OLD)
	panel._on_filter(LedgerRows.REGION_ALL, true)
	panel._on_filter(NavalLedger.READING_ALL, false)


## The explanation a filter that empties the sheet earns: the crown may hold no
## hull yet, the filter may be hiding them, or the chart may hold none at all
## (REQ-P5-05).
func test_the_empty_view_names_why_no_hull_answers() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.bind(screen.play)
	screen.hud.navy_pressed.emit()
	assert_true(_navy_row_widgets(panel) > 0, "the sheet opens on the crown's hulls")
	# A chart the crown floats nothing in: the whole navy answers, this chart does not.
	panel._snapshot = NavalLedger.snapshot(_world(), _old_only(), OWNER)
	panel._region = LedgerRows.REGION_NEW
	panel._apply_filter()
	assert_true(panel._empty.visible, "an empty chart prints the empty line")
	assert_eq(_navy_row_widgets(panel), 0, "and the rows the last press left are cleared")
	assert_true(panel._empty.text.contains("No hull answers this view"))
	assert_true(panel._subtitle.text.contains("0 of 0 hulls"), "the count line stays honest")
	# Nothing afloat but a yard slip: the sheet names the yard rather than a gap.
	var slip := FleetState.empty_in_port(7, OWNER, 0)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [slip])
	panel._snapshot = NavalLedger.snapshot(_world(), table, OWNER)
	panel._region = LedgerRows.REGION_ALL
	panel._apply_filter()
	assert_true(panel._empty.text.contains("the yard launches the first"))
	# No squadron at all: clearing a filter is the way back.
	panel._snapshot = NavalLedger.snapshot(_world(), MapRegionTable.new(), OWNER)
	panel._apply_filter()
	assert_true(panel._empty.text.contains("Clear a filter"))
	panel._snapshot = {}
	panel._region = LedgerRows.REGION_ALL
	panel._reading = NavalLedger.READING_ALL


func test_every_chip_names_its_own_reading() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	var chart_row := panel._bar.get_child(0) as HBoxContainer
	var reading_row := panel._bar.get_child(1) as HBoxContainer
	assert_eq(_navy_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(_navy_chip_captions(reading_row), ["All hulls", "Warships", "Merchant hulls"])


func test_navy_back_and_the_key_close_the_ledger() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.navy_pressed.emit()
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	InputActions.ensure_actions()
	var toggle := InputEventAction.new()
	toggle.action = InputActions.NAVY_LEDGER
	toggle.pressed = true
	panel._unhandled_input(toggle)
	assert_true(panel.is_open(), "the key opens it from the map")
	panel._unhandled_input(toggle)
	assert_false(panel.is_open(), "and closes it again")


## A hull has no marker of her own: Visit frames the squadron that flies her and
## leaves the sheet, so the map a tap would have shown is the one under it.
func test_a_visit_frames_her_squadron_and_sets_the_sheet_aside() -> void:
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.open()
	assert_true(panel.is_open())
	var row: NavalLedgerRow = _navy_first_row(panel)
	assert_not_null(row, "the campaign floats a hull")
	if row == null:
		return
	row._on_visit()
	assert_false(panel.is_open(), "the sheet sets itself aside")
	assert_not_null(screen.play.ship_layer.selected(), "her squadron is the selection")


# --- navy: fixtures ---


## Two charts of the naval fixture. The crown keeps a patrolling home squadron
## (frigate + carrack) in Cádiz and a lone trader at sea in the New World; the
## rival's squadron must never reach the reading.
func _world() -> WorldMap:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	var map := WorldMap.new()
	map.add_region(old)
	map.add_region(new)
	return map


func _navy_regions() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [_home_fleet(), _rival_fleet()])
	table.set_region(FactionCatalog.NEW_WORLD, [_trader_fleet()])
	return table


## The home chart alone: the New World holds no hull, so a one-chart view has an
## empty page and the whole navy still answers.
func _old_only() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [_home_fleet()])
	return table


func _home_fleet() -> FleetState:
	var fleet := FleetState.in_port(1, OWNER, 0, ["ship_1", "ship_2"], {
		"ship_1": "carrack", "ship_2": "frigate",
	})
	fleet.mission = FleetState.Mission.PATROL
	return fleet


func _trader_fleet() -> FleetState:
	return FleetState.at_sea(2, OWNER, 0, ["ship_3"], {"ship_3": "trader"})


func _rival_fleet() -> FleetState:
	return FleetState.in_port(9, RIVAL, 1, ["ship_9"], {"ship_9": "frigate"})


func _row_of(data: Dictionary, hull_id: String) -> Dictionary:
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		if String(row["hull"]) == hull_id:
			return row
	return {}


## The muster roll's navy door, found by its word so the suite reads the button
## the player presses.
func _navy_door() -> Button:
	for node: Node in screen.hud.muster_roll.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("The crown's navy"):
			return button
	return null


func _navy_first_row(panel: NavalLedgerPanel) -> NavalLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as NavalLedgerRow
		if row != null:
			return row
	return null


func _navy_row_widgets(panel: NavalLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is NavalLedgerRow:
			total += 1
	return total


func _navy_chip_captions(row: HBoxContainer) -> Array[String]:
	var captions: Array[String] = []
	for child: Node in row.get_children():
		var chip := child as Button
		if chip != null:
			captions.append(chip.text)
	return captions


func _has_text(root: Node, needle: String) -> bool:
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.contains(needle):
			return true
	return false
