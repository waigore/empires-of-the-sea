extends GdToolsTest
## The crown's eyes: the intelligence reading projects every spy the crown
## holds, the courts they shadow and the counter-espionage screen (wiki:
## civilian-units § Spy; DR-20261115-10), and the sheet drives it — the court's
## door, the key and back. One Godot boot: the projection suite reads small
## fixtures, the drive mounts the shared map screen (docs/testing.md).

const Naval = preload("res://tests/naval_fixture.gd")
const Civilians = preload("res://tests/civilian_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

var screen: MapScreen = null


func before_all() -> void:
	screen = Fixture.attach_screen(self)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.spy_ledger.close()
		screen.free()
	screen = null


func before_each() -> void:
	if screen == null or not is_instance_valid(screen):
		screen = Fixture.attach_screen(self)
		return
	screen.hud.spy_ledger.close()


# --- projection -------------------------------------------------------------


func test_snapshot_reads_every_duty_the_crown_holds() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_world(), _units(), 0)
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
	var snapshot: Dictionary = SpyLedger.snapshot(_world(), _units(), 0)
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
	var snapshot: Dictionary = SpyLedger.snapshot(_world(), _units(), 0)
	assert_eq(String(snapshot["screen"].get("province_name", "")), "Cádiz")
	assert_true(String(SpyLedger.screen_text(snapshot)).contains("Screen up at Cádiz"))
	var open: Dictionary = SpyLedger.snapshot(_world(), _idle_only(), 0)
	assert_false(bool(open["screened"]))
	assert_true(
		String(SpyLedger.screen_text(open)).contains("No counter-espionage screen"),
		"a crown with no screen is told how to raise it"
	)


func test_the_summary_names_the_gap_not_only_the_gain() -> void:
	var snapshot: Dictionary = SpyLedger.snapshot(_world(), _units(), 0)
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
	var snapshot: Dictionary = SpyLedger.snapshot(_world(), table, 0)
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
	assert_true(_row_widgets(panel) > 0, "the reading is painted")
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
	assert_true(_row_widgets(panel) > 2, "the network and the courts are painted")
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
	var before: int = _row_widgets(panel)
	panel._apply_profile(true, true)
	panel._on_profile_changed()
	assert_eq(_row_widgets(panel), before, "the phone profile keeps every row")
	panel._apply_profile(false, false)
	panel._on_profile_changed()
	assert_eq(_row_widgets(panel), before, "and the atlas profile restores it")
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
func _world() -> WorldMap:
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


func _row_widgets(panel: SpyLedgerPanel) -> int:
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
