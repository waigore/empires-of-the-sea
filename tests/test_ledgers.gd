# gdlint: disable=max-public-methods
extends GdToolsTest
## One boot for the crown's three ledgers: the province ledger, the intelligence
## reading (the crown's eyes) and the muster roll. Each projects its own snapshot
## over a small fixture and then drives its sheet on the one mounted chart —
## seal, key, filters, Visit and back (wiki: world-model § Provinces and Tiles;
## civilian-units § Spy; military-armies § The muster roll).
##
## Merged from test_province_ledger, test_spy_ledger and test_force_ledger_rules:
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
		screen.free()
	screen = null
	pristine = {}


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(screen, pristine)
	# The command ledger is not a dock panel: a case that leaves it open would
	# answer the next case's back press.
	screen.hud.command_ledger.close()
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
	assert_eq(panel._kind, ForceLedger.KIND_ARMY)
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
	var shown: int = ForceLedger.count(panel._snapshot, panel._region, panel._kind)
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
