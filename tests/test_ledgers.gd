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
	# Back's debounce is static (one press per 300 ms per process), so the two
	# back cases in this boot must not swallow each other's press.
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS


## --- the province ledger -----------------------------------------------------


func test_snapshot_lists_every_own_province_in_both_charts() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(ProvinceLedger.count(snapshot, ProvinceLedger.REGION_OLD), 1)
	assert_eq(ProvinceLedger.count(snapshot, ProvinceLedger.REGION_NEW), 1)
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
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, ProvinceLedger.REGION_ALL)
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
	var counts: Dictionary = ProvinceLedger.filter_counts(snapshot, ProvinceLedger.REGION_ALL)
	assert_eq(int(counts[ProvinceLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[ProvinceLedger.FILTER_UNGARRISONED]), 1)
	assert_eq(int(counts[ProvinceLedger.FILTER_WORKS]), 1)
	var cut: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, ProvinceLedger.REGION_ALL, ProvinceLedger.FILTER_CUT
	)
	assert_eq(cut.size(), 1, "only the chart that holds a cut-off province")
	for group: Dictionary in cut:
		assert_eq(int(group["region"]), FactionCatalog.NEW_WORLD)
		assert_eq((group["rows"] as Array).size(), 1)
	assert_eq(
		ProvinceLedger.count(snapshot, ProvinceLedger.REGION_OLD, ProvinceLedger.FILTER_CUT),
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
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD), 3)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW), 2)
	var counts: Dictionary = ForceLedger.kind_counts(snapshot, ForceLedger.REGION_OLD)
	assert_eq(int(counts[ForceLedger.KIND_ARMY]), 2)
	assert_eq(int(counts[ForceLedger.KIND_SQUADRON]), 1)


func test_region_and_kind_filters_narrow_the_ledger() -> void:
	var snapshot: Dictionary = ForceLedger.snapshot(_force_world(), _armies(), _fleets(), 0)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD, ForceLedger.KIND_ARMY), 2)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_OLD, ForceLedger.KIND_SQUADRON), 1)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW, ForceLedger.KIND_ARMY), 1)
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_NEW, ForceLedger.KIND_SQUADRON), 1)
	for group: Dictionary in ForceLedger.groups(snapshot, ForceLedger.REGION_NEW):
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
	assert_eq(ForceLedger.count(snapshot, ForceLedger.REGION_ALL), 0)
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
		panel._snapshot, ForceLedger.REGION_ALL, ForceLedger.KIND_ARMY
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
	panel._on_filter(ForceLedger.REGION_OLD, true)
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
