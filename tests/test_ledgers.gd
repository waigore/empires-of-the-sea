# gdlint: disable=max-public-methods
extends GdToolsTest
## One boot for the crown's three ledgers: the province ledger, the intelligence
## reading (the crown's eyes) and the muster roll. Each projects its own snapshot
## over a small fixture and then drives its sheet on the one mounted chart —
## seal, key, filters, Visit and back (wiki: world-model § Provinces and Tiles;
## civilian-units § Spy; military-armies § The muster roll).
##
## Merged from test_province_ledger, test_spy_ledger, test_force_ledger_rules,
## test_ledger_rows and the hospital train ledger:
## one Godot boot pays one coverage instrumentation pass instead of three (~11 s
## a suite under coverage), and the three sheets share the one mounted chart.

const Naval = preload("res://tests/naval_fixture.gd")
const Civilians = preload("res://tests/civilian_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

## Shared world snapshot; non-underscore so before_all copies it onto each case.
var pristine_map: Array = []
## Chart mounts lazily: under coverage a mount costs ~0.5 s and a re-seat ~0.15 s.
## ~189 projection cases never call `_attach()`, so they never pay a MapScreen
## (same pattern as research / audio; docs/testing.md § Speed rules). Static
## because gd-tools clones each case. The hospitals sheet rides this same chart.
static var _host: Node = null
static var screen: MapScreen = null
static var pristine: Dictionary = {}
## The crown holding a seat on both charts, captured on the first cycle case:
## re-seat from it instead of swapping both charts again (~2.5 s under coverage).
static var both_charts: Dictionary = {}
static var both_charts_map: Array = []
## The orders a hand-built batch walk filed, read by the raise-spine cases.
var _filed: Array = []


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	_host = self


func before_each() -> void:
	# Projection cases never mount; after the chart exists, park so idle HUD/fog
	# work does not run under coverage between sheet cases.
	Fixture.park_screen(screen)


func after_all() -> void:
	if is_instance_valid(screen):
		screen.hud.command_ledger.close()
		screen.hud.navy_ledger.close()
		screen.hud.army_ledger.close()
		screen.hud.province_ledger.close()
		screen.free()
	screen = null
	pristine = {}
	both_charts = {}
	both_charts_map = []
	_host = null


## A sheet/drive case starts on a pristine chart. First call mounts once; later
## calls re-seat. Projection cases that never ask never pay the mount.
func _attach() -> MapScreen:
	Fixture.restore(Fixture.world(), pristine_map)
	if not is_instance_valid(screen):
		screen = Fixture.attach_screen(_host)
		pristine = Fixture.suite_capture(screen)
	else:
		Fixture.suite_reset(screen, pristine, Fixture.world())
	# Realm sheets are not dock panels: a case that leaves one open would answer
	# the next case's back press.
	screen.hud.command_ledger.close()
	screen.hud.navy_ledger.close()
	screen.hud.army_ledger.close()
	screen.hud.province_ledger.close()
	# Back's debounce is static (one press per 300 ms per process), so the two
	# back cases in this boot must not swallow each other's press.
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
	return screen


## Builds the both-charts capture once: far-chart seat + load_region round trip.
## Cycle cases ask; every other case skips the ~2.5 s boot under coverage.
func _ensure_both_charts() -> void:
	if not both_charts.is_empty() and is_instance_valid(screen):
		return
	_attach()
	_boot_both_charts()
	both_charts = Fixture.suite_capture(screen)
	both_charts_map = Fixture.snapshot(Fixture.world())


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
	assert_true((overseas["flags"] as Array).has("cut_off"))
	assert_true(
		String(overseas["state"]).contains("Cut off — 3 road tiles to lay"),
		"the row names the gap it waits on"
	)
	var counts: Dictionary = snapshot["counts"]
	assert_eq(int(counts["cut_off"]), 1, "one province is cut off")


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
	assert_false((home["flags"] as Array).has("ungarrisoned"))
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["regiments"]), 0, "a rival's standard is not a garrison")
	assert_true((overseas["flags"] as Array).has("ungarrisoned"))
	assert_true(String(overseas["state"]).contains("Ungarrisoned"))


func test_estates_read_the_ledgers_own_yield_and_works() -> void:
	var snapshot: Dictionary = ProvinceLedger.snapshot(_regions(), 0)
	var home: Dictionary = _province_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["estates"]), 2, "two estates in the seat")
	assert_eq(int(home["yield"]), 5, "3 + 2, the rows' own output")
	assert_eq(int((home["economy"] as Dictionary)["output"]), 5, "the economy view sums them")
	assert_true((home["flags"] as Array).has("works"))
	assert_true(String(home["line"]).contains("2 estates"))
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(int(overseas["estates"]), 0)
	assert_true(String(overseas["line"]).contains("No estates"))


func test_the_realm_reads_three_views_over_one_holding() -> void:
	var snapshot: Dictionary = _snapshot()
	var home: Dictionary = _province_row(snapshot, FactionCatalog.OLD_WORLD)
	var economy: Dictionary = home["economy"]
	assert_eq(int(economy["estates"]), 2, "two estates in the seat")
	assert_eq(int(economy["developed"]), 1, "one of them is raised")
	assert_eq(int(economy["headroom"]), 2, "both still have room")
	assert_eq(int(economy["value"]), 5 * CommodityCatalog.base_price("timber"), "priced at the sell")
	var defence: Dictionary = home["defence"]
	assert_eq(
		int(defence["figure"]),
		roundi(float(home["strength"]) * float(defence["multiplier"]) + float(defence["emplaced"])),
		"the figure is the garrison at the ground's own multiplier plus the battery"
	)
	assert_true(float(home["strength"]) > 0.0, "the crown's men are counted")
	assert_eq(String(defence["terrain_name"]), "Plains", "the ground is the battle's own pick")
	assert_eq(int(defence["fort"]), 0, "an open province")
	var link: Dictionary = home["connectivity"]
	assert_true(bool(link["linked"]), "the seat roads to itself")
	assert_eq(int(link["hops"]), 0, "the seat is nought hops")
	assert_true(bool(link["seat"]), "and knows it is the seat")


func test_a_cut_off_overseas_province_reads_no_road_and_no_hops() -> void:
	var snapshot: Dictionary = _snapshot()
	var overseas: Dictionary = _province_row(snapshot, FactionCatalog.NEW_WORLD)
	var link: Dictionary = overseas["connectivity"]
	assert_false(bool(link["linked"]), "no crown road home")
	assert_eq(int(link["hops"]), -1, "no owned-land road to the seat")
	assert_false(bool(link["same_chart"]), "it lies on the other chart")
	assert_eq(int((overseas["economy"] as Dictionary)["value"]), 0, "no estates, no value")


func test_the_economy_view_orders_by_value_and_by_kind() -> void:
	var snapshot: Dictionary = _snapshot()
	var by_value: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_ALL, ProvinceLedger.VIEW_ECONOMY, ProvinceLedger.SORT_VALUE
	)
	assert_eq(String((by_value[0]["rows"] as Array)[0]["name"]), "Cádiz", "the rich seat leads")
	var by_kind: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_ALL, ProvinceLedger.VIEW_ECONOMY, "tree"
	)
	assert_eq((by_kind[0]["rows"] as Array).size(), 1, "only the chart holding timber")
	var defence: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_ALL, ProvinceLedger.VIEW_DEFENCE, ProvinceLedger.SORT_DEFENCE
	)
	assert_eq(String((defence[0]["rows"] as Array)[0]["name"]), "Cádiz", "the garrisoned seat leads")


## The sheet's order survives the grouping: two provinces on one chart, the poor
## one holding the lower id, so a value sort must paint the other first.
func test_the_painted_rows_keep_the_chosen_order() -> void:
	var poor: Dictionary = _plain_row(1, "Poor", 1.0, -1.0)
	var rich: Dictionary = _plain_row(2, "Rich", 9.0, -2.0)
	var rows: Array[Dictionary] = [poor, rich]
	var snapshot: Dictionary = {
		"rows": rows, "groups": LedgerRows.group(rows), "counts": {}, "total": 2,
	}
	var painted: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_OLD, ProvinceLedger.VIEW_ECONOMY, ProvinceLedger.SORT_VALUE
	)
	assert_eq(painted.size(), 1, "one heading for the chart")
	assert_eq(String((painted[0]["rows"] as Array)[0]["name"]), "Rich", "the richer row leads")
	var by_defence: Array[Dictionary] = ProvinceLedger.groups(
		snapshot, LedgerRows.REGION_OLD, ProvinceLedger.VIEW_DEFENCE, ProvinceLedger.SORT_DEFENCE
	)
	assert_eq(
		String((by_defence[0]["rows"] as Array)[0]["name"]), "Poor",
		"the defence figure orders the same rows its own way"
	)


## One bare row the order cases can sort: no chart label beyond the old one and
## one figure on each view.
func _plain_row(id: int, name: String, value: float, figure: float) -> Dictionary:
	return {
		"id": id, "region": FactionCatalog.OLD_WORLD, "region_label": "Old World",
		"name": name, "capital": false,
		"economy": {"value": int(value), "by_kind": {}},
		"defence": {"figure": int(figure)},
		"connectivity": {"hops": 0},
	}


func test_connectivity_orders_near_first_and_unreached_last() -> void:
	var rows: Array[Dictionary] = []
	for raw: Variant in (_snapshot()["rows"] as Array):
		rows.append(raw)
	ProvinceLedger._sort_rows(rows, ProvinceLedger.VIEW_CONNECTIVITY, ProvinceLedger.SORT_HOPS)
	assert_eq(String(rows[0]["name"]), "Cádiz", "the seat leads its own reading")
	assert_eq(String(rows[rows.size() - 1]["name"]), "Veracruz", "the unroaded shore reads last")


# --- the sheet --------------------------------------------------------------


## Every view names itself and its own order, and a view the sheet does not know
## falls back to the economy reading rather than to nothing.
func test_each_view_names_itself_and_the_figure_it_opens_on() -> void:
	assert_eq(ProvinceLedger.view_label(ProvinceLedger.VIEW_ECONOMY), "Economy")
	assert_eq(ProvinceLedger.view_label(ProvinceLedger.VIEW_DEFENCE), "Defence")
	assert_eq(ProvinceLedger.view_label(ProvinceLedger.VIEW_CONNECTIVITY), "Connectivity")
	assert_eq(ProvinceLedger.view_label("no-such-view"), "Economy", "an unknown key reads economy")
	assert_eq(
		ProvinceLedger.sort_keys(ProvinceLedger.VIEW_ECONOMY),
		[ProvinceLedger.SORT_VALUE, "tree", "ore", "coin", "wheat"],
		"the economy view orders by total and by each kind"
	)
	assert_eq(
		ProvinceLedger.sort_keys(ProvinceLedger.VIEW_DEFENCE), [ProvinceLedger.SORT_DEFENCE]
	)
	assert_eq(
		ProvinceLedger.sort_keys(ProvinceLedger.VIEW_CONNECTIVITY), [ProvinceLedger.SORT_HOPS]
	)
	assert_eq(ProvinceLedger.sort_default(ProvinceLedger.VIEW_DEFENCE), ProvinceLedger.SORT_DEFENCE)
	assert_eq(
		ProvinceLedger.sort_default(ProvinceLedger.VIEW_CONNECTIVITY), ProvinceLedger.SORT_HOPS
	)
	assert_eq(ProvinceLedger.sort_default(ProvinceLedger.VIEW_ECONOMY), ProvinceLedger.SORT_VALUE)
	assert_eq(ProvinceLedger.sort_label(ProvinceLedger.SORT_VALUE), "Total")
	assert_eq(ProvinceLedger.sort_label(ProvinceLedger.SORT_DEFENCE), "Figure")
	assert_eq(ProvinceLedger.sort_label(ProvinceLedger.SORT_HOPS), "Hops")
	assert_eq(
		ProvinceLedger.sort_label("wheat"), "Farm",
		"a kind reads the survey's own name for it"
	)


## A chart the crown holds no seat on has no hop reading at all: the walk is
## skipped rather than answered with a made-up distance.
func test_a_chart_with_no_seat_reaches_no_hop_reading() -> void:
	assert_true(ProvinceLedger._hops(Naval.build(), 0, -1).is_empty())
	var snapshot: Dictionary = _snapshot()
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) != FactionCatalog.NEW_WORLD:
			continue
		assert_eq(int((row["connectivity"] as Dictionary)["hops"]), -1, "no seat, no hops")
		assert_false(bool((row["connectivity"] as Dictionary)["same_chart"]), "another chart")


## The painted sheet answers each view in its own words: the economy prices, the
## defence prints one figure with its terms, the connectivity names the hops and
## the seat; a press on an order chip reorders without leaving the view.
func test_the_realm_paints_each_view_in_its_own_words() -> void:
	_attach()
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	assert_true(panel.is_open(), "the realm opens")
	panel._on_filter(ProvinceLedger.VIEW_ECONOMY, false)
	assert_true(_texts(panel).contains("ducats"), "the economy view prices the harvest")
	panel._on_filter(ProvinceLedger.VIEW_DEFENCE, false)
	var defence_text: String = _texts(panel)
	assert_true(defence_text.contains("Defence "), defence_text)
	assert_true(defence_text.contains("Town "), "the defence line names the town")
	panel._on_filter(ProvinceLedger.VIEW_CONNECTIVITY, false)
	var link_text: String = _texts(panel)
	assert_true(link_text.contains("hop") or link_text.contains("seat"), link_text)
	# The order row is rebuilt for the view, so a kind chip the defence view does
	# not offer can never stay chosen behind it.
	panel._on_filter(ProvinceLedger.VIEW_ECONOMY, false)
	panel._on_sort("wheat")
	assert_eq(panel._sort, "wheat", "the order chip reorders the view")
	panel._on_filter(ProvinceLedger.VIEW_DEFENCE, false)
	assert_eq(panel._sort, ProvinceLedger.SORT_DEFENCE, "a view falls back to its own figure")
	var before: int = _province_row_widgets(panel)
	panel._on_sort(ProvinceLedger.SORT_DEFENCE)
	assert_eq(_province_row_widgets(panel), before, "a reorder keeps every row")
	panel.close()


## Every word the painted rows carry, joined: one string a case can search.
func _texts(panel: ProvinceLedgerPanel) -> String:
	var parts: PackedStringArray = []
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row == null:
			continue
		parts.append(row._name.text)
		parts.append(row._chip.text)
		parts.append(row._detail.text)
		if row._standing != null:
			parts.append(row._standing.text)
		if row._reading != null:
			parts.append(row._reading.text)
	return " · ".join(parts)


## Every word the spy sheet's rows carry, joined: one string a case can search.
func _spy_texts(panel: SpyLedgerPanel) -> String:
	var parts: PackedStringArray = []
	_collect_labels(panel._rows, parts)
	return " · ".join(parts)


func _collect_labels(node: Node, parts: PackedStringArray) -> void:
	var label := node as Label
	if label != null:
		parts.append(label.text)
	for child: Node in node.get_children():
		_collect_labels(child, parts)


func test_the_realm_door_opens_the_ledger_and_its_rows_visit_a_province() -> void:
	_attach()
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	assert_not_null(panel, "the HUD mounts the province ledger")
	var door: Button = _realm_door()
	assert_not_null(door, "the province dossier carries the realm door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the dossier's realm door opens it")
	assert_true(_province_row_widgets(panel) > 0, "the crown's provinces are listed")
	var row: ProvinceLedgerRow = _first_row(panel)
	assert_not_null(row)
	var wanted: int = int(row.data.get("id", -1))
	_assert_visit_seal(row._visit, "Open ", "the realm row's Visit")
	row._visit.pressed.emit()
	assert_false(panel.is_open(), "the Visit seal sets the sheet aside")
	assert_eq(
		screen.play.selected_province, wanted, "and the dossier is open on that province"
	)


## The row body is a reading, not a door: a real pointer tap on the name visits
## nothing. It used to visit on the press and set the sheet aside, so the release
## fell through to the chart and selected whatever tile then sat under the
## pointer — a province other than the row's (issue #1195).
func test_a_pointer_tap_on_the_realm_row_body_visits_nothing() -> void:
	_attach()
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	assert_true(panel.is_open(), "the realm opens")
	var row: ProvinceLedgerRow = _first_row(panel)
	assert_not_null(row)
	var body: Vector2 = row._name.get_global_rect().get_center()
	assert_true(
		get_viewport().get_visible_rect().has_point(body), "the row is on the mounted chart"
	)
	var before: int = screen.play.selected_province
	await _click(body)
	assert_eq(screen.play.selected_province, before, "a body tap selects no province")
	assert_true(panel.is_open(), "and leaves the sheet standing")


func test_back_and_the_key_close_the_ledger() -> void:
	_attach()
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
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
	_attach()
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
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
					{
						"output": 3, "working": true, "level": 1, "resource": 0,
						"commodity": "timber", "terrain_cap": 3, "tech_cap": 3,
					},
					{
						"output": 2, "working": false, "level": 0, "resource": 0,
						"commodity": "timber", "terrain_cap": 3, "tech_cap": 3,
					},
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
			"seat": 0,
		},
		{
			"region": FactionCatalog.NEW_WORLD,
			"model": new,
			"armies": [] as Array,
			"estates": {},
			"links": {0: {"linked": false, "distance": 3, "blockaded": false}},
			"seat": -1,
		},
	]


## The realm read with a priced market, so the economy column has a sell price
## the ledger can quote (the live sheet reads the session's own book).
func _snapshot(regions: Array[Dictionary] = []) -> Dictionary:
	return ProvinceLedger.snapshot(
		regions if not regions.is_empty() else _regions(),
		0, WorldMarket.with_default_prices()
	)


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


## The Visit seal's one dress on every LedgerRow sheet: an icon-only control at
## the close seal's touch floor, its words in a tooltip (issue #1195).
func _assert_visit_seal(button: Button, tip_prefix: String, message: String) -> void:
	assert_not_null(button, message + ": the row carries a Visit seal")
	if button == null:
		return
	assert_eq(button.text, "", message + ": no caption on the seal")
	assert_not_null(button.icon, message + ": one medallion glyph")
	assert_eq(button.custom_minimum_size, CloseSeal.SIZE, message + ": a thumb floor")
	assert_true(
		String(button.tooltip_text).begins_with(tip_prefix),
		"%s: the tooltip names the place (%s)" % [message, String(button.tooltip_text)]
	)


## One pointer click through the mounted chart: press and release in the
## viewport's own coordinates, then a frame for the sheet to answer.
func _click(point: Vector2) -> void:
	var viewport: Viewport = get_viewport()
	viewport.push_input(_mouse(true, point), true)
	viewport.push_input(_mouse(false, point), true)
	await get_tree().process_frame


func _mouse(pressed: bool, point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	return event


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


## The headings count in plain words and name the screen's state, never a table
## plural ("spys") or a bare "down" (issue #1303).
func test_the_headings_count_spies_and_name_the_screen() -> void:
	assert_eq(SpyLedger.count_text(0), "no spies", "an empty network heads itself")
	assert_eq(SpyLedger.count_text(1), "1 spy", "one spy is singular")
	assert_eq(SpyLedger.count_text(3), "3 spies", "three spies pluralise")
	assert_eq(SpyLedger.count_text(-1), "no spies", "no negative count is printed")
	var up: Dictionary = SpyLedger.snapshot(_spy_world(), _units(), 0)
	assert_eq(SpyLedger.screen_word(up), "up at Cádiz", "the screen names its seat")
	assert_eq(SpyLedger.screen_word(up, false), "screen up", "a digest sheds the seat")
	assert_eq(SpyLedger.screen_word({}), "no screen", "a bare down is never printed")
	assert_eq(
		SpyLedger.screen_word({"screened": true}), "screen up",
		"a screen with no seat named still reads"
	)
	var open: Dictionary = SpyLedger.snapshot(_spy_world(), _idle_only(), 0)
	assert_eq(SpyLedger.screen_word(open), "no screen", "an open crown says no screen")


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


func test_a_spy_row_wears_its_chip_and_visits_from_its_seal() -> void:
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
	_assert_visit_seal(row._visit, "Open ", "the spy row's Visit")
	row._visit.pressed.emit()
	assert_eq(visited, [[FactionCatalog.OLD_WORLD, 4]], "the seal visits the spy")
	row.free()


func test_the_reading_orders_shadows_screens_watches_idle_and_passengers() -> void:
	# Two charts: the Old World holds a rival Great Power (Coro, England) and the
	# New World a Minor (Genoa), so one reading carries every duty but the screen.
	_attach()
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
	_attach()
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	assert_not_null(panel, "the HUD mounts the crown's eyes")
	var door: Button = _eyes_door()
	assert_not_null(door, "the court ledger carries the EYES door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the court's door opens the sheet")
	assert_true(_spy_row_widgets(panel) > 0, "the reading is painted")
	assert_true(panel._subtitle.text.length() > 0, "the head states the network")


func test_the_sheet_paints_a_network_and_a_visit() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	panel.open()
	assert_true(
		panel._subtitle.text.begins_with("No spy"), "an empty network says so"
	)
	assert_true(
		_spy_texts(panel).contains("2,000 ducats and 4 paper"),
		"the empty network prices the hire in ducats (issue #1305)"
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


## The sheet's own headings print the words: no spies, one spy, no screen — and
## the screen's seat by name when it stands (issue #1303).
func test_the_sheet_headings_read_no_spies_and_name_the_screen() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	panel.open()
	var painted: String = _spy_texts(panel)
	assert_true(painted.contains("no spies"), "an empty network's tally reads")
	assert_false(painted.contains("spys"), "a heading never wears a table plural")
	assert_true(painted.contains("no screen"), "the screen block reads its state")
	var seat: Vector2i = play.capital_tile
	var screen_spy := _screening(95, seat)
	screen_spy.owner = play.player_faction
	var roster: Array[CivilianState] = [screen_spy]
	play.civilian_layer.units = roster
	play.civilian_layer.regions.set_region(play.region_index, roster)
	panel.refresh()
	painted = _spy_texts(panel)
	assert_true(painted.contains("1 spy"), "one spy heads the network")
	var seat_name: String = play.model.province_name(
		play.model.province_at(seat.x, seat.y)
	)
	assert_true(painted.contains("up at %s" % seat_name), painted)
	_clear_spies(play)


## The compact and narrow profiles repaint the sheet without losing its rows,
## and every duty has its own one-word chip.
func test_the_phone_profile_repaints_the_reading() -> void:
	_attach()
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.EYES)
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


## The reading is worded off the spies the pass books, in the sheet's own row
## order, and capped so a busy network stays one line (REQ-P5-07;
## DR-20261121-11).
func test_the_eyes_pick_words_the_spies_the_pass_would_book() -> void:
	assert_true(MapPlaySpyPick.of([]).is_empty(), "a crown with no spy names nothing")
	var spies: Array[Dictionary] = [
		{"region": 0, "unit_id": 2, "kind": MapPlaySpyPick.KIND_WALK, "place": "Genoa"},
		{"region": 0, "unit_id": 1, "kind": MapPlaySpyPick.KIND_KEEP, "place": "Sevilla"},
	]
	var pick: Dictionary = MapPlaySpyPick.of(spies, {})
	assert_eq(
		String(pick["line"]),
		"the court would walk its Spy toward Genoa and keep its Spy at Sevilla"
	)
	# The marks ride the same pick: the spy the pass would walk is keyed, the spy
	# it keeps on watch is not (DR-20261122-18).
	assert_eq(pick.get("keys", {}), {"0:2": true}, "one order, one key")
	assert_eq(
		MapPlaySpyPick.keys_of(spies).keys(), ["0:2"], "the keeper wears no mark"
	)
	assert_eq(
		MapPlayPickProse.sentence(String(pick["line"])),
		"The court would walk its Spy toward Genoa and keep its Spy at Sevilla."
	)
	# The sheet's own rows come first, so the line reads down the page.
	var snapshot: Dictionary = {
		"rows": [{"region": 0, "unit_id": 1}, {"region": 0, "unit_id": 2}],
	}
	assert_eq(
		String(MapPlaySpyPick.of(spies, snapshot)["line"]),
		"the court would keep its Spy at Sevilla and walk its Spy toward Genoa"
	)
	var screening: Array[Dictionary] = [
		{"region": 0, "unit_id": 1, "kind": MapPlaySpyPick.KIND_SCREEN, "place": "Madrid"},
	]
	assert_eq(
		String(MapPlaySpyPick.of(screening, {})["line"]),
		"the court would set its Spy at Madrid to counter-espionage"
	)
	# Beyond three the line counts the spies it cannot name.
	var many: Array[Dictionary] = []
	for index: int in 5:
		many.append({
			"region": 0,
			"unit_id": index,
			"kind": MapPlaySpyPick.KIND_KEEP,
			"place": "P%d" % index,
		})
	assert_eq(
		String(MapPlaySpyPick.of(many, {})["line"]),
		"the court would keep its Spy at P0, keep its Spy at P1, keep its Spy at P2 and 2 more"
	)
	# One spy, three spies and none: the line's own joins and its empty gate.
	assert_eq(MapPlaySpyPick.pick_line([]), "", "no spy, no clause")
	assert_eq(
		String(MapPlaySpyPick.of([
			{"region": 0, "unit_id": 1, "kind": MapPlaySpyPick.KIND_KEEP, "place": "Cádiz"},
		], {})["line"]),
		"the court would keep its Spy at Cádiz"
	)
	assert_eq(
		String(MapPlaySpyPick.of([
			{"region": 0, "unit_id": 1, "kind": MapPlaySpyPick.KIND_KEEP, "place": "Cádiz"},
			{"region": 0, "unit_id": 2, "kind": MapPlaySpyPick.KIND_KEEP, "place": "Sevilla"},
			{"region": 0, "unit_id": 3, "kind": MapPlaySpyPick.KIND_WALK, "place": "Genoa"},
		], {})["line"]),
		"the court would keep its Spy at Cádiz, keep its Spy at Sevilla and walk its Spy toward Genoa"
	)
	assert_eq(MapPlaySpyPick.line(null), "", "a session that is not there names nothing")


## The reading is the pass's own: a crown spy with no order is named with what
## the published planner would have it do, the sheet prints it, and the spy is
## neither moved nor ordered (REQ-P2-03, REQ-P5-06; DR-20261121-11).
func test_the_eyes_print_the_spies_the_crowns_pass_would_book() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	var home: ProvinceState = play.model.provinces[0]
	var spy := CivilianState.create(93, play.player_faction, "spy", home.tiles[0])
	var roster: Array[CivilianState] = [spy]
	play.civilian_layer.units = roster
	play.civilian_layer.regions.set_region(play.region_index, roster)
	panel.open()
	var pick: Dictionary = MapPlaySpyPick.pick(play, panel._snapshot)
	assert_eq((pick.get("spies", []) as Array).size(), 1, "one clause per spy")
	assert_true(
		panel.counsel_text().begins_with("The court would "), panel.counsel_text()
	)
	assert_true(panel.counsel_text().contains("its Spy"), panel.counsel_text())
	assert_true(panel._counsel.visible, "the sheet prints the reading")
	assert_true(spy.work_action().is_empty(), "a reading, not an order")
	assert_eq(spy.tile, home.tiles[0], "and the spy does not move")
	# The three clauses the pass's own verbs give: the screen, the march and the
	# pick read on another chart's roster id (never this spy's).
	var screening: Dictionary = MapPlaySpyPick._spy(
		play.model, spy, play.region_index,
		{"action": MapPlaySpyPick.ACTION_SCREEN, "tile": spy.tile}
	)
	assert_eq(String(screening["kind"]), MapPlaySpyPick.KIND_SCREEN, "the screen is the pass's")
	var walking: Dictionary = MapPlaySpyPick._spy(
		play.model, spy, play.region_index,
		{"action": "make_move", "tile": spy.tile}
	)
	assert_eq(String(walking["kind"]), MapPlaySpyPick.KIND_WALK, "the march is the pass's")
	assert_eq(
		String(MapPlaySpyPick._spy(play.model, spy, play.region_index, {}).get("kind", "")),
		MapPlaySpyPick.KIND_KEEP, "a spy with no order keeps its watch"
	)
	# A session that runs no planner, or one watching another crown, names nothing.
	play.observer_mode = true
	assert_true(MapPlaySpyPick.pick(play, {}).is_empty(), "an observer names nothing")
	play.observer_mode = false
	_clear_spies(play)
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "a crown with no spy names nothing")

## A spy aboard a squadron is off the map: the eyes sheet already prints its
## `aboard` row, and the court's line names no watch it cannot keep (wiki:
## civilian-units § Overseas deployment; DR-20261121-11).
func test_the_eyes_name_no_spy_aboard_a_squadron() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	var home: ProvinceState = play.model.provinces[0]
	var passenger := CivilianState.create(94, play.player_faction, "spy", home.tiles[0])
	passenger.embark_on(5)
	var roster: Array[CivilianState] = [passenger]
	play.civilian_layer.units = roster
	play.civilian_layer.regions.set_region(play.region_index, roster)
	panel.open()
	assert_true(MapPlaySpyPick.pick(play, panel._snapshot).is_empty(), "a spy at sea is no pick")
	assert_eq(panel.counsel_text(), "", "and the sheet prints no line")
	assert_false(panel._counsel.visible, "the gold line stands down")
	# The sheet still lists the spy, under its own `aboard` duty.
	assert_eq(SpyLedger.duty_of(play.model, passenger), SpyLedger.DUTY_ABOARD)
	_clear_spies(play)
	panel.refresh()


## The sheet prints the reading it is handed and hides it when the reading is
## empty, so a session with no planner carries no gold line (REQ-P5-06).
func test_the_eyes_print_and_hide_the_counsel_they_are_handed() -> void:
	_attach()
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	panel.counsel_source = (
		func(_data: Dictionary) -> String: return "The court would keep its Spy at Cádiz."
	)
	panel.open()
	assert_eq(panel.counsel_text(), "The court would keep its Spy at Cádiz.")
	assert_true(panel._counsel.visible, "the sheet prints the line")
	assert_true(panel._court.is_empty(), "a plain line marks no row")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	panel.close()


## The network's rows mark the spies the reading orders, and leave the spies it
## keeps on watch unmarked, off the one pick the gold line is worded from
## (DR-20261122-18; RUB-P5-03).
func test_the_eyes_mark_the_spies_the_court_would_order() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	_clear_spies(play)
	var home: ProvinceState = play.model.provinces[0]
	var walking := CivilianState.create(95, play.player_faction, "spy", home.tiles[0])
	var keeping := CivilianState.create(
		96, play.player_faction, "spy", home.tiles[mini(1, home.tiles.size() - 1)]
	)
	var roster: Array[CivilianState] = [walking, keeping]
	play.civilian_layer.units = roster
	play.civilian_layer.regions.set_region(play.region_index, roster)
	var mark: String = MapPlayPickProse.row_key(
		{"region": play.region_index, "unit_id": walking.id}, "unit_id"
	)
	var order: Dictionary = {
		"kind": MapPlaySpyPick.KIND_WALK,
		"keys": {mark: true},
		"line": "the court would walk its Spy toward Genoa",
	}
	panel.counsel_source = func(_data: Dictionary) -> Dictionary: return order
	panel.open()
	var walked: SpyLedgerRow = _spy_row(panel, walking.id)
	var kept: SpyLedgerRow = _spy_row(panel, keeping.id)
	assert_not_null(walked, "the walking spy is printed")
	assert_not_null(kept, "the keeping spy is printed")
	assert_true(
		walked._name.text.begins_with(SpyLedgerRow.COURT_MARK),
		"the spy the court would walk leads with the mark"
	)
	assert_false(
		kept._name.text.begins_with(SpyLedgerRow.COURT_MARK),
		"the spy the court keeps on watch carries none"
	)
	assert_true(
		walked._name.text.contains("Spy —"), "the row keeps its own name"
	)
	# The mark is a reading: the spy has no order and has not moved.
	assert_true(walking.work_action().is_empty(), "a mark sets no order")
	assert_eq(walking.tile, home.tiles[0], "and the spy does not move")
	_clear_spies(play)
	panel.counsel_source = Callable()
	panel.refresh()
	panel.close()


# --- the crown's people ------------------------------------------------------


## The people's own reading (DR-20261121-12): the work the published civilian
## pass would give the crown's crews, worded down the sheet's own rows and capped
## so a busy roster stays one line of chrome (REQ-P5-06, REQ-P5-07).
func test_the_people_pick_words_the_work_the_pass_would_give() -> void:
	assert_true(MapPlayPeoplePick.of([]).is_empty(), "an unread roster names nothing")
	var crews: Array[Dictionary] = [
		{
			"region": 0,
			"unit_id": 2,
			"role": "Explorer",
			"action": "explore",
			"place": "",
			"short": "survey the Mar Caribe",
		},
		{
			"region": 0,
			"unit_id": 1,
			"role": "Builder",
			"action": "build_improvement",
			"place": "Cádiz",
			"short": "raise the lumber camp",
		},
	]
	var pick: Dictionary = MapPlayPeoplePick.of(crews, {})
	assert_eq(
		String(pick["line"]),
		"the court would put its Explorer to survey the Mar Caribe and its Builder"
		+ " to raise the lumber camp at Cádiz this turn"
	)
	assert_eq(
		MapPlayPickProse.sentence(String(pick["line"])),
		"The court would put its Explorer to survey the Mar Caribe and its Builder"
		+ " to raise the lumber camp at Cádiz this turn."
	)
	# The sheet's own rows come first, so the line reads down the page it answers.
	var snapshot: Dictionary = {
		"rows": [{"region": 0, "unit_id": 1}, {"region": 0, "unit_id": 2}],
	}
	assert_eq(
		String(MapPlayPeoplePick.of(crews, snapshot)["line"]),
		"the court would put its Builder to raise the lumber camp at Cádiz and its"
		+ " Explorer to survey the Mar Caribe this turn"
	)
	# Beyond three the line counts the crews it cannot name.
	var many: Array[Dictionary] = []
	for index: int in 5:
		many.append({
			"region": 0,
			"unit_id": index,
			"role": "Builder",
			"action": "build_road",
			"place": "P%d" % index,
			"short": "build a road",
		})
	assert_eq(
		String(MapPlayPeoplePick.of(many, {})["line"]),
		"the court would put its Builder to build a road at P0, its Builder to"
		+ " build a road at P1, its Builder to build a road at P2 and 2 more this turn"
	)
	assert_eq(MapPlayPeoplePick.pick_line([]), "", "no crew, no clause")
	assert_eq(MapPlayPeoplePick.line(null), "", "a session that is not there names nothing")


## A roster with several crews on one order never repeats its clause: a prospect
## names the tile it would uncover, so the crews read apart, and an order two
## crews share is named once with every crew behind it counted (issue #1304).
func test_the_people_pick_names_the_ground_and_never_repeats_a_clause() -> void:
	var prospectors: Array[Dictionary] = [
		{
			"region": 0,
			"unit_id": 1,
			"role": "Explorer",
			"action": "prospect",
			"tile": Vector2i(12, 34),
			"place": "Madrid",
			"short": "prospect this tile",
		},
		{
			"region": 0,
			"unit_id": 2,
			"role": "Explorer",
			"action": "prospect",
			"tile": Vector2i(13, 34),
			"place": "Madrid",
			"short": "prospect this tile",
		},
		{
			"region": 0,
			"unit_id": 3,
			"role": "Explorer",
			"action": "prospect",
			"tile": Vector2i(12, 35),
			"place": "Madrid",
			"short": "prospect this tile",
		},
	]
	assert_eq(
		MapPlayPeoplePick.pick_line(prospectors),
		"the court would put its Explorer to prospect the ground at Madrid (12, 34),"
		+ " its Explorer to prospect the ground at Madrid (13, 34) and its Explorer"
		+ " to prospect the ground at Madrid (12, 35) this turn"
	)
	# The same order booked to several crews is named once, and the tail still
	# counts every crew the one clause stands for.
	var shared: Array[Dictionary] = []
	for index: int in 4:
		shared.append({
			"region": 0,
			"unit_id": index,
			"role": "Engineer",
			"action": "build_road",
			"tile": Vector2i(index, 0),
			"place": "Guimarães",
			"short": "build a road",
		})
	shared.append({
		"region": 0,
		"unit_id": 9,
		"role": "Engineer",
		"action": "build_road",
		"tile": Vector2i(9, 9),
		"place": "Braga",
		"short": "build a road",
	})
	assert_eq(
		MapPlayPeoplePick.pick_line(shared),
		"the court would put its Engineer to build a road at Guimarães, its Engineer"
		+ " to build a road at Braga and 3 more this turn"
	)


## Crews wait and the pass puts none to work: the sheet names that gate rather
## than a clause it cannot print, and a snapshot that has not read the roster
## names nothing at all (REQ-P5-06).
func test_the_people_pick_names_the_gate_when_no_crew_is_put_to_work() -> void:
	assert_true(MapPlayPeoplePick.of([], {}).is_empty(), "an unread roster names no gate")
	var idle: Dictionary = MapPlayPeoplePick.of([], {"idle": 2})
	assert_eq(String(idle["line"]), MapPlayPeoplePick.NO_WORK_LINE)
	assert_true(
		MapPlayPeoplePick.of([], {"idle": 0}).is_empty(),
		"every crew has its order, so the sheet has nothing to say"
	)


## The reading is the pass's own: an idle Builder of the crown on a level-0
## estate is named with the work the published planner would give it, the roster
## prints it, and nothing is ordered (REQ-P2-03, REQ-P5-06; DR-20261121-12).
func test_the_people_print_the_work_the_crowns_pass_would_book() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: CivilianRosterPanel = screen.hud.civilian_roster
	assert_not_null(panel, "the HUD mounts the crown's people")
	assert_true(panel.counsel_source.is_valid(), "the session wires the pass's reading")
	_cancel_works()
	var stock: Dictionary = play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	var estates: ImprovementPanel = screen.improvements
	estates.open()
	var ready: Array[Vector2i] = estates.ready_tiles()
	assert_gte(ready.size(), 1, "the capital holds an estate the crown can raise")
	estates.close()
	var builder: CivilianState = play.civilian_layer.add_unit(
		play.player_faction, "builder", ready[0]
	)
	panel.open()
	var pick: Dictionary = MapPlayPeoplePick.pick(play, panel._snapshot)
	var crews: Array = pick.get("crews", [])
	assert_gte(crews.size(), 1, "the pass puts the Builder to an estate")
	assert_true(
		panel.counsel_text().begins_with("The court would put "), panel.counsel_text()
	)
	assert_true(panel.counsel_text().contains("its Builder"), panel.counsel_text())
	assert_true(panel.counsel_text().ends_with("this turn."), panel.counsel_text())
	assert_true(panel._counsel.visible, "the sheet prints the reading")
	assert_true(builder.work_action().is_empty(), "a reading, not an order")
	# One clause per crew the pass books something for, so the roster cannot name
	# work the pass would not take (REQ-P2-03).
	var booked: Dictionary = MapPlayCivilianPick.picks(play, play.player_faction)
	for raw: Variant in crews:
		var crew: Dictionary = raw
		assert_true(booked.has(int(crew["unit_id"])), "every clause is a pick of the pass")
	# An observer names nothing.
	play.observer_mode = true
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an observer names nothing")
	play.observer_mode = false
	play.civilian_layer.units.erase(builder)
	panel.refresh()


## The people's pick keys the crews it names, so a roster row can wear the
## counsel's mark with one lookup and a crew the pass would leave alone never
## looks busy (DR-20261122-06).
func test_the_people_pick_keys_the_crews_it_names() -> void:
	var crews: Array[Dictionary] = [
		{"region": 0, "unit_id": 3, "role": "Builder", "short": "raise the lumber camp"},
		{"region": 1, "unit_id": 3, "role": "Explorer", "short": "survey the coast"},
	]
	var keys: Dictionary = MapPlayPeoplePick.of(crews, {}).get("keys", {})
	assert_eq(keys.size(), 2, "every crew the line names is keyed")
	assert_true(keys.has("0:3"), "the crew on the old chart")
	assert_true(keys.has("1:3"), "the chart is in the key: ids are minted per chart")
	assert_false(keys.has("0:1"), "a crew the reading never named takes no key")
	assert_eq(MapPlayPeoplePick.keys_of([]), {}, "nothing named, nothing marked")
	# The gate names no crew, so it marks none.
	var gate: Dictionary = MapPlayPeoplePick.of([], {"idle": 2})
	assert_eq(gate.get("keys", {}), {}, "the gate marks no row")


## A roster row wears the counsel's mark before its own craft, so a crown finds
## the crews her staff would put to work among a long page (DR-20261122-06).
func test_a_roster_row_wears_the_courts_mark() -> void:
	var plain := CivilianRosterRow.new()
	plain.setup({"unit_id": 4, "region": 0, "role": "Builder", "working": false})
	assert_eq(plain._name.text, "Builder", "an unmarked crew reads its own craft")
	plain.free()
	var marked := CivilianRosterRow.new()
	marked.court = true
	marked.setup({"unit_id": 4, "region": 0, "role": "Builder", "working": false})
	assert_eq(
		marked._name.text,
		"%s Builder" % CivilianRosterRow.COURT_MARK,
		"the mark leads the craft"
	)
	marked.free()


## The roster marks exactly the crews the court's own reading names, so the
## work is found on the page it answers — and the reading orders nothing
## (REQ-P2-03, REQ-P5-03, REQ-P5-06; DR-20261122-06).
func test_the_roster_marks_the_crews_the_crowns_pass_would_put_to_work() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: CivilianRosterPanel = screen.hud.civilian_roster
	_cancel_works()
	var stock: Dictionary = play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	var estates: ImprovementPanel = screen.improvements
	estates.open()
	var ready: Array[Vector2i] = estates.ready_tiles()
	assert_gte(ready.size(), 1, "the capital holds an estate the crown can raise")
	estates.close()
	var builder: CivilianState = play.civilian_layer.add_unit(
		play.player_faction, "builder", ready[0]
	)
	panel.open()
	var pick: Dictionary = MapPlayPeoplePick.pick(play, panel._snapshot)
	assert_eq(
		panel.counsel_text(),
		MapPlayPickProse.sentence_of(pick),
		"the sheet prints the pass's own line"
	)
	var keys: Dictionary = pick.get("keys", {})
	assert_gte(keys.size(), 1, "the reading keys the crews it names")
	# Every crew the reading names is on the sheet, and only those rows wear the
	# mark — a crew the staff would leave alone never looks busy.
	var shown: Dictionary = {}
	for row: CivilianRosterRow in _roster_rows(panel):
		var key: String = MapPlayPickProse.row_key(row.data, "unit_id")
		shown[key] = true
		assert_eq(row.court, keys.has(key), "a row wears the mark when the court would spend it")
		if row.court:
			assert_true(row._name.text.begins_with(CivilianRosterRow.COURT_MARK), row._name.text)
	for key: String in keys.keys():
		assert_true(shown.has(key), "the crew the court would put to work is on the sheet")
	# A filter press reorders the marks it already read: one read for the roster.
	panel._apply_filter()
	assert_eq(panel._court, keys, "a filter press keeps the reading it was handed")
	assert_true(builder.work_action().is_empty(), "the reading orders nothing")
	panel.close()
	play.civilian_layer.units.erase(builder)


## Every crew row the roster prints, in its own order.
func _roster_rows(panel: CivilianRosterPanel) -> Array[CivilianRosterRow]:
	var rows: Array[CivilianRosterRow] = []
	for child: Node in panel._rows.get_children():
		var row := child as CivilianRosterRow
		if row != null:
			rows.append(row)
	return rows


## The roster prints the reading it is handed and hides it when the reading is
## empty, so a sheet with no planner carries no gold line (REQ-P5-06).
## The people's row reads a crew aboard a squadron as ABOARD: it is off the map,
## has no tile and takes no order (wiki: civilian-units § Overseas deployment).
func test_the_people_row_reads_a_crew_aboard_a_squadron() -> void:
	var row := CivilianRosterRow.new()
	row.compact = false
	add_child(row)
	row.setup({
		"unit_id": 9,
		"region": FactionCatalog.OLD_WORLD,
		"role": "Builder",
		"province_name": "Open country",
		"region_label": "Old World",
		"tile": CivilianState.NO_TILE,
		"working": false,
		"aboard": true,
		"status": "aboard",
		"status_text": "Aboard a squadron — no orders at sea",
		"short_status": "Aboard",
	})
	assert_eq(row._chip.text, "ABOARD", "the chip names the duty")
	assert_true(
		row._detail.text.contains("Aboard a squadron"), row._detail.text
	)
	assert_false(row._detail.text.contains("-1"), row._detail.text)
	assert_eq(row._status.text, "Aboard a squadron — no orders at sea")
	row.compact = true
	row.setup({
		"unit_id": 9,
		"region": FactionCatalog.OLD_WORLD,
		"role": "Builder",
		"region_label": "Old World",
		"tile": CivilianState.NO_TILE,
		"working": false,
		"aboard": true,
		"status": "aboard",
		"status_text": "Aboard a squadron — no orders at sea",
		"short_status": "Aboard",
	})
	assert_true(row._detail.text.contains("Aboard"), row._detail.text)
	row.queue_free()


func test_the_people_print_and_hide_the_counsel_they_are_handed() -> void:
	_attach()
	var panel: CivilianRosterPanel = screen.hud.civilian_roster
	# The sheet is handed the pass's pick, not a sentence: its line and its marks
	# come off the one read (DR-20261122-06).
	panel.counsel_source = (
		func(_data: Dictionary) -> Dictionary:
			return MapPlayPeoplePick.of([
				{"region": 0, "unit_id": 7, "role": "Builder", "short": "work the estate"},
			], {"rows": [{"region": 0, "unit_id": 7}]})
	)
	panel.open()
	assert_eq(
		panel.counsel_text(),
		"The court would put its Builder to work the estate this turn."
	)
	assert_true(panel._counsel.visible, "the sheet prints the line")
	assert_true(panel._court.has("0:7"), "and holds the crew its line names")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	assert_eq(panel._court, {}, "an unwired sheet marks no row")
	panel.close()


func test_back_and_the_key_close_the_sheet() -> void:
	_attach()
	var panel: SpyLedgerPanel = screen.hud.spy_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.EYES)
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


## One spy's own row in the painted network, found by the id its roster minted, so
## a case reads the mark the player reads (DR-20261122-18).
func _spy_row(panel: SpyLedgerPanel, unit_id: int) -> SpyLedgerRow:
	for child: Node in panel._rows.get_children():
		var row := child as SpyLedgerRow
		if row != null and int(row.data.get("unit_id", -1)) == unit_id:
			return row
	return null


## The first spy row's Visit seal, found by the name every ledger row gives it.
func _first_visit(panel: SpyLedgerPanel) -> Button:
	for node: Node in panel._rows.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.name == "Visit":
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


## A standard whose colours have been cited (or laurelled) reads the weight the
## battle pays for it, not the paper sum: a citation is +5% and a laurel +10% in
## the line, so the muster roll, the crown's army and the battle must name one
## figure (wiki: military-armies § The muster roll — "Both strengths are the
## resolver's own aggregation"; combat § Strength; DR-20261113-04).
func test_a_decorated_standard_reads_the_weight_the_battle_pays() -> void:
	var army: ArmyState = ArmyState.muster(
		6, OWNER, 0, false, ["pikemen", "pikemen", "knights"], 601
	)
	army.regiment_history["unit_601"] = {"cited": 3, "fields": []}
	var one: Array[ArmyState] = [army]
	var paper: float = army.strength()
	var paid: float = ArmyModifiers.strength(one, 0, 1.0)
	var laurel: float = ArmyModifiers.rank_of("pikemen", 0, 1.0) * 0.10
	assert_almost_eq(paid, paper + laurel, 0.001, "one laurel in a three-regiment line")
	assert_almost_eq(
		ArmyForce.side_strength(one), paid, 0.001,
		"the side's strength is the resolver's own aggregation"
	)

	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [army])
	var muster: Dictionary = ForceLedger.snapshot(
		_force_world(), table, MapRegionTable.new(), OWNER
	)
	var row: Dictionary = _force_row(muster, ForceLedger.KIND_ARMY, 6)
	assert_almost_eq(
		float(row["strength"]), paid, 0.001, "the muster roll reads the battle's figure"
	)
	assert_true(String(row["line"]).contains("%.1f strength" % paid))

	var ledger: Dictionary = ArmyLedger.snapshot(
		_force_world(), table, MapRegionTable.new(), OWNER
	)
	var standards: Array[Dictionary] = ArmyLedger.groups(ledger, LedgerRows.REGION_OLD)
	assert_eq(standards.size(), 1, "one standard in the home chart")
	assert_almost_eq(
		float(standards[0]["strength"]), paid, 0.001,
		"the crown's army heading reads it too"
	)


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
	_attach()
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUSTER_ROLL))
	assert_ne(InputActions.MUSTER_ROLL, InputActions.CIVILIAN_ROSTER)
	assert_not_null(_seal_with_caption(screen.hud, "MUSTER"), "the cartouche carries the seal")
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	assert_not_null(panel)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	assert_true(panel.is_open())
	assert_true(int(panel._snapshot.get("total", 0)) > 0, "the crown holds forces on the chart")
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	assert_false(panel.is_open())


func test_ledger_kind_filter_and_visit_open_the_chosen_force() -> void:
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
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
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	panel._on_filter(LedgerRows.REGION_OLD, true)
	panel._on_filter(ForceLedger.KIND_SQUADRON, false)
	panel._apply_filter()
	var shown: int = ForceLedger.count(panel._snapshot, panel._region, panel._reading)
	assert_eq(panel._empty.visible, shown == 0)
	if shown == 0:
		assert_true(String(panel._empty.text).contains("No force"))


func test_visit_a_squadron_selects_her_and_missing_ids_do_not() -> void:
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
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


## The roll's own reading (DR-20261121-17): the two force sheets' clauses merged
## into one sentence, in the order the roll prints its rows, capped so a busy
## muster stays one line of chrome, and the gate when forces wait and neither
## pass gives an order (REQ-P5-06, REQ-P5-07).
func test_the_muster_counsel_words_the_orders_of_every_force() -> void:
	var forces: Array[Dictionary] = [
		{
			"region": 0,
			"kind": ForceLedger.KIND_SQUADRON,
			"id": 2,
			"line": "the Leopard into the Mar Caribe",
		},
		{
			"region": 0,
			"kind": ForceLedger.KIND_ARMY,
			"id": 3,
			"line": "the field army at Tucapel to storm Cádiz",
		},
		{
			"region": 0,
			"kind": ForceLedger.KIND_ARMY,
			"id": 1,
			"line": "the Home Army to take the field with 4 regiments",
		},
		{
			"region": 0,
			"kind": ForceLedger.KIND_SQUADRON,
			"id": 4,
			"line": "the Swallow home to Cádiz",
		},
	]
	var snapshot: Dictionary = {
		"rows": [
			{"region": 0, "kind": ForceLedger.KIND_ARMY, "id": 3},
			{"region": 0, "kind": ForceLedger.KIND_ARMY, "id": 1},
			{"region": 0, "kind": ForceLedger.KIND_SQUADRON, "id": 4},
			{"region": 0, "kind": ForceLedger.KIND_SQUADRON, "id": 2},
		],
	}
	# The roll's own row order, not the passes' order, and the fourth counted.
	assert_eq(
		String(MapPlayForceCounsel.of(forces, snapshot)["line"]),
		"the court would send the field army at Tucapel to storm Cádiz, the Home"
		+ " Army to take the field with 4 regiments, the Swallow home to Cádiz"
		+ " and 1 more this turn"
	)
	# No snapshot: the passes' own order, read as prose reads a pair.
	var pair: Array[Dictionary] = [forces[0], forces[1]]
	assert_eq(
		String(MapPlayForceCounsel.of(pair, {})["line"]),
		"the court would send the Leopard into the Mar Caribe and the field army"
		+ " at Tucapel to storm Cádiz this turn"
	)
	# A clause this module cannot say takes no place on the line.
	var silent: Array[Dictionary] = pair.duplicate()
	silent.append({"region": 0, "kind": ForceLedger.KIND_ARMY, "id": 9, "line": ""})
	assert_eq(
		String(MapPlayForceCounsel.of(silent, {})["line"]),
		String(MapPlayForceCounsel.of(pair, {})["line"]),
		"an empty clause is no force named"
	)
	assert_eq(
		MapPlayPickProse.sentence("the court would send the Leopard into the Mar Caribe"),
		"The court would send the Leopard into the Mar Caribe."
	)
	# The gate: a force waited and neither pass gave an order, or silence.
	assert_eq(
		String(MapPlayForceCounsel.gate(true)["line"]), MapPlayForceCounsel.NO_ORDER_LINE
	)
	assert_true(MapPlayForceCounsel.gate(false).is_empty(), "nothing waited, nothing to say")
	assert_true(MapPlayForceCounsel.of([], snapshot).is_empty())
	assert_eq(MapPlayForceCounsel.pick(null), {})
	assert_eq(
		MapPlayForceCounsel.line(null), "", "a session that is not there names nothing"
	)


## The roll prints the reading it reads and hides it when the staff names no
## force, so a muster already under way carries no gold line (REQ-P5-06).
func test_the_muster_roll_prints_its_reading_and_stands_it_down_when_closed() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	panel.open()
	assert_eq(
		panel.counsel_text(),
		MapPlayPickProse.sentence_of(MapPlayForceCounsel.pick(play, panel._snapshot)),
		"the sheet prints the passes' own reading"
	)
	assert_eq(
		panel._counsel.visible, not panel.counsel_text().is_empty(), "the line stands with it"
	)
	# A closed sheet asks the planner nothing: the plan is no one's to read.
	panel.close()
	panel.refresh()
	assert_eq(panel._counsel.pick, {}, "a closed roll carries no reading")
	assert_eq(panel.counsel_text(), "", "a closed sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	assert_eq(panel._counsel.keys(), {}, "and no row wears the mark while it is shut")


## The reading is the passes' own: THE CROWN'S MUSTER names the orders the land
## and naval policies would give every force, in the roll's own row order, and
## moves nothing (REQ-P2-03, REQ-P5-06; DR-20261121-17).
func test_the_muster_roll_names_the_orders_the_crowns_pass_would_give() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	var before: Array = _force_moved_flags(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	var counsel: String = panel.counsel_text()
	var pick: Dictionary = MapPlayForceCounsel.pick(play, panel._snapshot)
	assert_eq(counsel, MapPlayPickProse.sentence(String(pick.get("line", ""))))
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(), "the line stands with its reading"
	)
	if not pick.is_empty() and not (pick.get("forces", []) as Array).is_empty():
		assert_true(counsel.begins_with("The court would send "), counsel)
	panel.close()


## Every force the muster's reading names is keyed by its chart, kind and id, so
## the roll can mark the rows its line answers — including a force whose clause
## the module cannot word, which the court would still order (DR-20261122-03).
func test_the_muster_pick_keys_every_force_it_names() -> void:
	var forces: Array[Dictionary] = [
		{
			"region": 0,
			"kind": ForceLedger.KIND_ARMY,
			"id": 2,
			"line": "the Home Army to take the field with 4 regiments",
		},
		{"region": 1, "kind": ForceLedger.KIND_ARMY, "id": 2, "line": ""},
		{
			"region": 1,
			"kind": ForceLedger.KIND_SQUADRON,
			"id": 5,
			"line": "the Leopard into the Mar Caribe",
		},
	]
	var keys: Dictionary = MapPlayForceCounsel.of(forces, {}).get("keys", {})
	assert_eq(keys.size(), 3, "every force is keyed, even one with no clause")
	assert_true(keys.has("0:army:2"), "the army on the old chart")
	assert_true(keys.has("1:army:2"), "the chart is in the key: ids are minted per chart")
	assert_true(keys.has("1:squadron:5"), "the squadron names her hulls' kind")
	assert_false(keys.has("0:army:5"), "a row the reading never named takes no key")
	assert_eq(MapPlayForceCounsel.force_key(forces[1]), "1:army:2")
	assert_eq(MapPlayForceCounsel.keys_of([]), {}, "nothing named, nothing marked")
	# The gate names no force, so it marks none.
	assert_eq(MapPlayForceCounsel.gate(true).get("keys", {}), {})


## A muster row wears the counsel's mark before its own name, so a crown finds
## the forces her staff would send among a long roll (DR-20261122-03).
func test_a_muster_row_wears_the_courts_mark() -> void:
	var plain := ForceLedgerRow.new()
	plain.setup({
		"region": 0, "kind": ForceLedger.KIND_ARMY, "id": 3, "title": "Home Army",
	})
	assert_eq(plain._name.text, "Home Army", "an unmarked force reads its own name")
	plain.free()
	var marked := ForceLedgerRow.new()
	marked.court = true
	marked.setup({
		"region": 0, "kind": ForceLedger.KIND_ARMY, "id": 3, "title": "Home Army",
	})
	assert_eq(
		marked._name.text,
		"%s Home Army" % ForceLedgerRow.COURT_MARK,
		"the mark leads the name"
	)
	marked.free()


## The muster's sheet is the passes' own reading: it prints their line, marks
## exactly the forces they name and orders nothing (REQ-P2-03, REQ-P5-06;
## DR-20261122-03).
func test_the_muster_marks_the_forces_the_crowns_pass_would_send() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	var before: Array = _force_moved_flags(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	assert_true(panel.is_open(), "the muster opens")
	var pick: Dictionary = MapPlayForceCounsel.pick(play, panel._snapshot)
	assert_eq(
		panel.counsel_text(),
		MapPlayPickProse.sentence_of(pick),
		"the sheet prints the passes' own line"
	)
	assert_eq(
		panel._counsel.visible,
		not panel.counsel_text().is_empty(),
		"the line stands with its reading"
	)
	# Every force the reading names is on the sheet, and only those rows wear
	# the mark — a row the staff would leave alone never looks busy.
	var keys: Dictionary = pick.get("keys", {})
	var shown: Dictionary = {}
	for child: Node in panel._rows.get_children():
		var row := child as ForceLedgerRow
		if row == null:
			continue
		var key: String = MapPlayForceCounsel.force_key(row.data)
		shown[key] = true
		assert_eq(row.court, keys.has(key), "a row wears the mark when the court would send it")
		if row.court:
			assert_true(row._name.text.begins_with(ForceLedgerRow.COURT_MARK), row._name.text)
	for key: String in keys.keys():
		assert_true(shown.has(key), "the force the court would send is on the sheet")
	# A narrowing chip reorders the marks it already read: one read for the roll.
	panel._on_filter(ForceLedger.KIND_ARMY, false)
	assert_eq(panel._counsel.keys(), keys, "a chip press keeps the reading it was handed")
	assert_eq(_force_moved_flags(play), before, "the reading orders nothing")
	panel.close()


## The marks are the reading's own: a row wears `▸` when the pick's keys name it
## and no other, and the line painted is the pick's own sentence — so a mark
## never outruns the line it answers (DR-20261122-03).
func test_the_muster_marks_exactly_the_forces_its_reading_names() -> void:
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	var printed: Array[ForceLedgerRow] = _force_rows(panel)
	assert_true(printed.size() >= 1, "the crown fields a force")
	var named: String = MapPlayForceCounsel.force_key(printed[0].data)
	assert_false(named.is_empty(), "a row keys itself by chart, kind and id")
	var left_alone: Array[String] = []
	for row: ForceLedgerRow in printed.slice(1):
		left_alone.append(MapPlayForceCounsel.force_key(row.data))
	# A reading the staff would give: one force named, a key that names no row
	# and every other row left alone. The sheet repaints its widgets on a filter
	# pass, so the marks are read off the repainted rows.
	panel._counsel.show_value({
		"forces": [printed[0].data],
		"keys": {named: true, "9:army:99": true},
		"line": "the court would send the Home Army to take the field with 4 regiments this turn",
	})
	panel._apply_filter()
	var rows: Array[ForceLedgerRow] = _force_rows(panel)
	assert_eq(rows.size(), printed.size(), "the same view prints the same rows")
	var marked: int = 0
	for row: ForceLedgerRow in rows:
		if row.court:
			marked += 1
			assert_true(
				row._name.text.begins_with(ForceLedgerRow.COURT_MARK), row._name.text
			)
	assert_eq(marked, 1, "one force named, a key that names no row marks no row")
	assert_true(rows[0].court, "the force the reading names wears the mark")
	for row: ForceLedgerRow in rows.slice(1):
		assert_false(row.court, "a force the reading leaves alone wears none")
	assert_eq(left_alone.size(), rows.size() - 1)
	assert_eq(
		panel.counsel_text(),
		"The court would send the Home Army to take the field with 4 regiments this turn.",
		"the line is the reading's own sentence"
	)
	panel.close()


## The muster's printed rows, as the widgets the sheet painted.
func _force_rows(panel: ForceLedgerPanel) -> Array[ForceLedgerRow]:
	var rows: Array[ForceLedgerRow] = []
	for child: Node in panel._rows.get_children():
		var row := child as ForceLedgerRow
		if row != null:
			rows.append(row)
	return rows


## Every force's "already under way" flag, so a reading that marched or sailed
## one would show.
func _force_moved_flags(play: PlaySession) -> Array:
	var flags: Array = []
	for region: int in play.world.region_count():
		for army: ArmyState in MapPlayCourt.visible_armies(play, region):
			flags.append("%d:army:%s" % [region, army.moved])
		for fleet: FleetState in MapPlayCourt.region_fleets(play, region):
			flags.append("%d:fleet:%s" % [region, fleet.moved])
	return flags


## The province dossier's own reading: the work the court's civilian pass would
## put its crews to on this province's ground and the hosts its land pass would
## send here, merged under one court, with the gate the crown's own idle ground
## earns (wiki: world-model § The crown's provinces; DR-20261121-19).
func test_the_province_counsel_words_the_orders_of_its_own_ground() -> void:
	var crews: Array[Dictionary] = [
		{"role": "Builder", "short": "raise the lumber camp"},
		{"role": "Engineer", "short": "build a road"},
	]
	var armies: Array[Dictionary] = [
		{"line": "the field army at Tucapel to storm Cádiz"},
	]
	# The work first, then the hosts the court would send: one court, one verb.
	assert_eq(
		String(MapPlayProvinceCounsel.of(crews, armies)["line"]),
		"the court would order its Builder to raise the lumber camp, its Engineer"
		+ " to build a road and the field army at Tucapel to storm Cádiz this turn"
	)
	# One side alone reads its own clause.
	assert_eq(
		String(MapPlayProvinceCounsel.of(crews, [])["line"]),
		"the court would order its Builder to raise the lumber camp and its"
		+ " Engineer to build a road this turn"
	)
	assert_eq(
		String(MapPlayProvinceCounsel.of([], armies)["line"]),
		"the court would order the field army at Tucapel to storm Cádiz this turn"
	)
	# Three clauses are named and the fourth counted, so a busy ground stays one
	# line of chrome.
	var crowded: Array[Dictionary] = crews.duplicate()
	crowded.append({"role": "Spy", "short": "keep its watch at Cádiz"})
	assert_eq(
		String(MapPlayProvinceCounsel.of(crowded, armies)["line"]),
		"the court would order its Builder to raise the lumber camp, its Engineer"
		+ " to build a road, its Spy to keep its watch at Cádiz and 1 more this turn"
	)
	# A clause this module cannot say takes no place on the line.
	var silent: Array[Dictionary] = [{"role": "Builder", "short": ""}]
	assert_true(MapPlayProvinceCounsel.of(silent, [], 0).is_empty())
	# The sheet already shows the province, so a prospect names the tile alone:
	# two Explorers on one province read apart (issue #1304).
	var prospectors: Array[Dictionary] = [
		{
			"role": "Explorer",
			"short": "prospect this tile",
			"action": "prospect",
			"tile": Vector2i(12, 34),
			"place": "Cádiz",
		},
		{
			"role": "Explorer",
			"short": "prospect this tile",
			"action": "prospect",
			"tile": Vector2i(13, 34),
			"place": "Cádiz",
		},
	]
	assert_eq(
		String(MapPlayProvinceCounsel.of(prospectors, [])["line"]),
		"the court would order its Explorer to prospect the ground (12, 34) and its"
		+ " Explorer to prospect the ground (13, 34) this turn"
	)
	# The gate: the crown's own ground held an idle crew and the pass booked no
	# work here; ground with no idle crew says nothing.
	var gate: Dictionary = MapPlayProvinceCounsel.of([], [], 1)
	assert_eq(String(gate["line"]), MapPlayProvinceCounsel.NO_WORK_LINE)
	assert_eq(String(gate["kind"]), MapPlayProvinceCounsel.KIND_NO_WORK)
	assert_true(MapPlayProvinceCounsel.of([], [], 0).is_empty())
	assert_true(MapPlayProvinceCounsel.of([], []).is_empty())
	assert_eq(MapPlayProvinceCounsel.pick(null, null, -1), {})
	assert_eq(MapPlayProvinceCounsel.line(null, null, -1), "")


## The dossier's rail marks: the presses the court's crew pass would file on this
## ground, keyed by the action each press files. A work the rail carries no press
## for — a road, a prospect, a survey, a march — marks none, so a mark always
## names a press the sheet can press, and the line and the marks come off one
## read (wiki: world-model § The crown's provinces; DR-20261122-23).
func test_the_province_counsel_keys_the_press_the_court_would_take() -> void:
	var crews: Array[Dictionary] = [
		{"role": "Builder", "short": "raise the lumber camp", "action": "build_improvement"},
		{"role": "Builder", "short": "raise the town", "action": "upgrade_town"},
		{"role": "Engineer", "short": "raise the wall", "action": "build_fort"},
		{"role": "Engineer", "short": "raise a ward", "action": "build_hospital"},
	]
	var pick: Dictionary = MapPlayProvinceCounsel.of(crews, [])
	var marks: Dictionary = pick["keys"]
	assert_eq(marks.size(), 4, "one key per press the line names")
	for key: String in [
		MapPlayProvinceCounsel.KEY_IMPROVEMENT,
		MapPlayProvinceCounsel.KEY_TOWN,
		MapPlayProvinceCounsel.KEY_WALL,
		MapPlayProvinceCounsel.KEY_WARD,
	]:
		assert_true(marks.has(key), "the press the line names carries its key: %s" % key)
	# The rail's keys are the action strings the sheet's own presses file.
	assert_eq(MapPlayProvinceCounsel.KEY_IMPROVEMENT, "build")
	assert_eq(MapPlayProvinceCounsel.KEY_WALL, "raise_wall")
	# Work the rail carries no press for marks none.
	var elsewhere: Array[Dictionary] = [
		{"role": "Engineer", "short": "build a road", "action": "build_road"},
		{"role": "Explorer", "short": "prospect this tile", "action": "prospect"},
		{"role": "Merchant", "short": "screen a rival's court", "action": "screen"},
	]
	var quiet: Dictionary = MapPlayProvinceCounsel.of(elsewhere, [])
	assert_true(quiet["keys"].is_empty(), "no rail press, no mark")
	assert_eq(
		String(quiet.get("kind", "")),
		MapPlayProvinceCounsel.KIND_ORDERS,
		"the line still names the road the rail carries no press for",
	)
	# A plain entry (a fixture's crew, no action) and the gate's own pick mark
	# nothing: a mark never names a press the reading did not name.
	var plain: Array[Dictionary] = [{"role": "Builder", "short": "raise the lumber camp"}]
	assert_true(MapPlayProvinceCounsel.of(plain, [])["keys"].is_empty())
	assert_true(MapPlayProvinceCounsel.of([], [], 1)["keys"].is_empty())
	assert_true(MapPlayProvinceCounsel.marks_of([]).is_empty())


## Every crown crew's own order, so a reading that booked one would show.
func _crew_order_flags(play: PlaySession) -> Array:
	var flags: Array = []
	for unit: CivilianState in play.civilian_layer.units:
		if unit == null or unit.owner != play.player_faction:
			continue
		flags.append(
			"%d:%d:%s:%s" % [unit.id, unit.status, str(unit.moved), str(unit.work)]
		)
	return flags


## The dossier's reading is the passes' own: it names the work the civilian pass
## would put crews to on this province's ground and the hosts the land pass would
## send here, and books nothing (REQ-P2-03, REQ-P5-06; DR-20261121-19).
func test_the_province_dossier_names_the_orders_the_crowns_pass_would_give() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ProvincePanel = screen.hud.panels.panel
	assert_true(panel.counsel_source.is_valid(), "the dossier binds the passes' reading")
	var before_forces: Array = _force_moved_flags(play)
	var before_crews: Array = _crew_order_flags(play)
	var province_id: int = play.capital_province
	panel.refresh(screen.model, province_id)
	var counsel: String = panel.counsel_text()
	var pick: Dictionary = MapPlayProvinceCounsel.pick(play, screen.model, province_id)
	assert_eq(counsel, MapPlayPickProse.sentence(String(pick.get("line", ""))))
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(), "the line stands with its reading"
	)
	assert_eq(_force_moved_flags(play), before_forces, "the reading marches nothing")
	assert_eq(_crew_order_flags(play), before_crews, "the reading books no work")
	# The rail's marks are that same pick's keys, so the sentence and the presses
	# it names come off one read (DR-20261122-23).
	assert_eq(panel.court_marks(), pick.get("keys", {}), "the rail marks what the line names")
	for key: String in panel.court_marks().keys():
		assert_true(
			panel.press_text(key).begins_with(ProvinceOrdersSection.COURT_MARK),
			"the press the line names leads with the mark: %s" % key,
		)
	assert_eq(
		not panel._orders.court_legend_text().is_empty(),
		not panel.court_marks().is_empty(),
		"the legend stands while a mark does",
	)
	# The guards: no province and no chart name nothing, so a shut sheet or a
	# region switch can never print a line about ground nobody is showing.
	assert_true(MapPlayProvinceCounsel.pick(play, screen.model, -1).is_empty())
	assert_true(MapPlayProvinceCounsel.pick(play, null, province_id).is_empty())
	assert_eq(MapPlayProvinceCounsel.line(play, null, province_id), "")


## The seat's province sheet names the host that stands on its ground — the
## count the rules publish for a reading crown — bound by the boot, not by the
## sheet (wiki: fog-and-exploration § Order-of-battle readings; DR-20261123-13).
func test_the_province_sheet_reads_the_host_standing_on_the_seat() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ProvincePanel = screen.hud.panels.panel
	assert_true(panel.play != null, "the boot seats the host reading")
	var home: ArmyState = null
	for raw: Variant in play.army_layer.regions.value(play.model.region_id, []):
		var army: ArmyState = raw
		if army == null or army.owner != play.player_faction or not army.home:
			continue
		home = army
	assert_true(home != null, "the crown keeps a Home Army")
	var seat: int = play.capital_province
	assert_eq(home.province, seat, "the Home Army stands on the seat")
	panel.refresh(screen.model, seat)
	var crown: String = FactionCatalog.name_of(play.player_faction)
	assert_eq(
		panel.hosts_text(),
		MapPlayProvinceHosts.line(play, screen.model, seat),
		"the sheet prints the boot's own reading",
	)
	assert_true(
		panel.hosts_text().begins_with("%s " % crown),
		"the seat's row names the crown's own host first: %s" % panel.hosts_text(),
	)
	assert_true(
		panel.hosts_text().contains("regiment"),
		"the row counts regiments: %s" % panel.hosts_text(),
	)
	# A province off the chart, a chart the sheet does not show, a session with
	# no army layer and a session that runs no fog each name what they can.
	assert_eq(MapPlayProvinceHosts.line(play, screen.model, -1), "")
	assert_eq(MapPlayProvinceHosts.line(null, screen.model, seat), "")
	assert_eq(MapPlayProvinceHosts.line(play, null, seat), "")
	var fogless: VisibilityModel = play.visibility
	play.visibility = null
	assert_eq(
		MapPlayProvinceHosts.line(play, screen.model, seat),
		ProvinceHosts.line(
			play.army_layer.regions.value(play.model.region_id, []),
			seat, play.model.province_data(seat).owner, play.player_faction, true,
		),
		"no fog reads every host, as the session with no fog model does",
	)
	play.visibility = fogless


## The seat's province sheet names the squadrons riding its harbour — the hull
## count the rules publish for a reading crown — read off the session the boot
## seats, not off the sheet (wiki: fog-and-exploration § Order-of-battle
## readings; DR-20261123-14).
func test_the_province_sheet_reads_the_squadrons_in_the_seat_harbour() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ProvincePanel = screen.hud.panels.panel
	assert_true(panel.play != null, "the boot seats the harbour reading")
	var seat: int = play.capital_province
	panel.refresh(screen.model, seat)
	assert_eq(
		panel.harbour_text(),
		MapPlayProvinceHarbour.line(play, screen.model, seat),
		"the sheet prints the boot's own reading",
	)
	# The guards: no province, no chart, no play and no ship layer name nothing.
	assert_eq(MapPlayProvinceHarbour.line(play, screen.model, -1), "")
	assert_eq(MapPlayProvinceHarbour.line(null, screen.model, seat), "")
	assert_eq(MapPlayProvinceHarbour.line(play, null, seat), "")
	var layer: ShipLayer = play.ship_layer
	play.ship_layer = null
	assert_eq(MapPlayProvinceHarbour.line(play, screen.model, seat), "")
	play.ship_layer = layer
	# A session that runs no fog reads every harbour, as the fogged session reads
	# its own hulls alone.
	var fogless: VisibilityModel = play.visibility
	play.visibility = null
	assert_eq(
		MapPlayProvinceHarbour.line(play, screen.model, seat),
		ProvinceHarbour.line(
			layer.regions.value(play.model.region_id, []),
			seat, play.model.province_data(seat).owner, play.player_faction, true,
		),
		"no fog reads every squadron, as the session with no fog model does",
	)
	play.visibility = fogless
	# A squadron the crown keeps in the seat's berth is counted on the sheet, so
	# the row prints the court and its hulls rather than hiding.
	var table: MapRegionTable = layer.regions
	var region: int = play.model.region_id
	var roster: Array = table.value(region, [])
	var planted: FleetState = FleetState.in_port(
		9901, play.player_faction, seat, ["harbour_1", "harbour_2"], {}
	)
	table.set_region(region, roster + [planted])
	panel.refresh(screen.model, seat)
	assert_true(
		panel.harbour_text().begins_with("%s " % FactionCatalog.name_of(play.player_faction)),
		"the seat's row names the crown's own squadron first: %s" % panel.harbour_text(),
	)
	assert_true(
		panel.harbour_text().contains("hull"),
		"the row counts hulls: %s" % panel.harbour_text(),
	)
	# A host aboard the crown's own squadron names its men too, so the sheet
	# accounts for the regiments the Hosts row leaves to the fleet they sail with
	# (DR-20261123-18).
	planted.embarked_army = 9902
	var aboard: ArmyState = ArmyState.create(
		9902, play.player_faction, seat, false, ["harbour_r1", "harbour_r2"], {}
	)
	aboard.embarked_fleet = planted.id
	var army_table: MapRegionTable = play.army_layer.regions
	var army_roster: Array = army_table.value(region, [])
	army_table.set_region(region, army_roster + [aboard])
	panel.refresh(screen.model, seat)
	assert_true(
		panel.harbour_text().contains("2 regiments aboard"),
		"the row names the men the squadron carries: %s" % panel.harbour_text(),
	)
	army_table.set_region(region, army_roster)
	planted.embarked_army = -1
	panel.refresh(screen.model, seat)
	table.set_region(region, roster)
	panel.refresh(screen.model, seat)


## The realm's own reading: the crown's provinces the civilian and land passes
## would act in this turn, worded off data alone — one line that names the count
## against the realm it holds, then the first places (wiki: world-model § The
## crown's provinces; DR-20261121-21).
func test_the_realm_counsel_names_the_provinces_the_court_would_act_in() -> void:
	var provinces: Array[Dictionary] = [
		{"region": FactionCatalog.OLD_WORLD, "province": 2, "name": "Cádiz"},
		{"region": FactionCatalog.OLD_WORLD, "province": 5, "name": "Tucapel"},
		{"region": FactionCatalog.NEW_WORLD, "province": 1, "name": "Jaén"},
	]
	var pick: Dictionary = MapPlayRealmCounsel.of(provinces, 14)
	assert_eq(
		String(pick["line"]),
		"the court would act in 3 of its 14 provinces this turn — Cádiz,"
		+ " Tucapel and Jaén"
	)
	assert_eq(String(pick["kind"]), MapPlayRealmCounsel.KIND_ORDERS)
	# Every province is keyed by its own chart and id, because province ids are
	# minted per chart.
	var keys: Dictionary = pick["keys"]
	assert_eq(keys.size(), 3, "one key per province")
	assert_true(keys.has("%d:1" % FactionCatalog.NEW_WORLD), "the New World's own key")
	assert_true(keys.has("%d:2" % FactionCatalog.OLD_WORLD), "the Old World's own key")
	# Beyond three places the line counts the rest, so a wide realm stays one
	# line of chrome.
	var crowded: Array[Dictionary] = provinces.duplicate()
	crowded.append({"region": FactionCatalog.OLD_WORLD, "province": 7, "name": "Sevilla"})
	crowded.append({"region": FactionCatalog.OLD_WORLD, "province": 9, "name": "Badajoz"})
	assert_eq(
		String(MapPlayRealmCounsel.of(crowded, 20)["line"]),
		"the court would act in 5 of its 20 provinces this turn — Cádiz,"
		+ " Tucapel, Jaén and 2 more"
	)
	# Every province the crown holds is named without the count, and a realm of
	# one reads as one place.
	assert_eq(
		String(MapPlayRealmCounsel.of(provinces, 3)["line"]),
		"the court would act in every one of its 3 provinces this turn — Cádiz,"
		+ " Tucapel and Jaén"
	)
	assert_eq(
		String(MapPlayRealmCounsel.of(provinces.slice(0, 1), 1)["line"]),
		"the court would act in the one province it holds this turn — Cádiz"
	)
	# Nothing to name is no line at all.
	assert_true(MapPlayRealmCounsel.of([], 14).is_empty())
	assert_true(
		MapPlayRealmCounsel.of([{"region": 0, "province": 1, "name": ""}], 3).is_empty()
	)
	assert_eq(MapPlayRealmCounsel.pick(null), {})
	assert_eq(MapPlayRealmCounsel.line(null), "")
	# The gate: a pass named rows it left waiting, so the sheet says so; a realm
	# with nothing waiting reads nothing.
	assert_true(MapPlayRealmCounsel.gate(false).is_empty())
	assert_eq(String(MapPlayRealmCounsel.gate(true)["line"]), MapPlayRealmCounsel.NO_ORDER_LINE)
	assert_eq(String(MapPlayRealmCounsel.gate(true)["kind"]), MapPlayRealmCounsel.KIND_NONE)


## A realm row wears the counsel's mark before its own name, so a crown finds the
## ground its staff would act in among twenty rows (DR-20261121-21).
func test_a_realm_row_wears_the_courts_mark() -> void:
	var plain := ProvinceLedgerRow.new()
	plain.setup({"id": 4, "region": FactionCatalog.OLD_WORLD, "name": "Cádiz"})
	assert_eq(plain._name.text, "Cádiz", "an unmarked province reads its own name")
	plain.free()
	var marked := ProvinceLedgerRow.new()
	marked.court = true
	marked.setup({"id": 4, "region": FactionCatalog.OLD_WORLD, "name": "Cádiz"})
	assert_eq(
		marked._name.text,
		"%s Cádiz" % ProvinceLedgerRow.COURT_MARK,
		"the mark leads the name"
	)
	marked.free()


## A count of one reads in the singular on the realm row and the civilians head
## (issue #1435): "1 unit gathered", "1 farm", "1 gun emplaced", "1 province
## posted" — the same copy bar the dossiers keep (REQ-P1-07).
func test_a_count_of_one_reads_in_the_singular() -> void:
	var one := ProvinceLedgerRow.new()
	one.setup({
		"id": 4, "region": FactionCatalog.OLD_WORLD, "name": "Cádiz",
		"economy": {
			"output": 1, "value": 18, "estates": 1, "developed": 1,
			"headroom": 0, "by_kind": {"wheat": 1},
		},
	})
	assert_eq(
		one._reading.text,
		"1 unit gathered · 18 ducats at today's sell · 1 farm",
		"one unit of one kind reads in the singular"
	)
	one.free()
	var many := ProvinceLedgerRow.new()
	many.setup({
		"id": 4, "region": FactionCatalog.OLD_WORLD, "name": "Cádiz",
		"economy": {
			"output": 8, "value": 400, "estates": 8, "developed": 8,
			"headroom": 0, "by_kind": {"wheat": 8, "tree": 12},
		},
	})
	assert_eq(
		many._reading.text,
		"8 units gathered · 400 ducats at today's sell · 12 timber · 8 farms",
		"a count of many takes the plural, and a mass kind keeps its word"
	)
	many.free()
	# The defence line's guns take the same bar.
	var walled := ProvinceLedgerRow.new()
	walled.view = ProvinceLedger.VIEW_DEFENCE
	walled.setup({
		"id": 4, "region": FactionCatalog.OLD_WORLD, "name": "Cádiz",
		"defence": {"strength": 40.0, "multiplier": 1.0, "emplaced": 1.0, "guns": 1},
	})
	assert_true(walled._reading.text.contains("1 gun emplaced"), walled._reading.text)
	walled.free()
	# The civilians head counts the provinces its crews stand in.
	var head := CivilianRosterHead.new()
	head.render(
		{
			"total": 1, "idle": 1, "working": 0, "by_region": {},
			"groups": [{"region": 0, "province_id": 1}],
		},
		LedgerRows.REGION_ALL, CivilianRosterHead.TYPE_ALL
	)
	assert_true(head._region_line.text.ends_with("1 province posted"), head._region_line.text)
	head.render(
		{
			"total": 2, "idle": 2, "working": 0, "by_region": {},
			"groups": [
				{"region": 0, "province_id": 1}, {"region": 0, "province_id": 2},
			],
		},
		LedgerRows.REGION_ALL, CivilianRosterHead.TYPE_ALL
	)
	assert_true(head._region_line.text.ends_with("2 provinces posted"), head._region_line.text)
	head.free()


## The realm's sheet is the passes' own reading: it prints their line, marks
## exactly the provinces they name and orders nothing (REQ-P2-03, REQ-P5-06;
## DR-20261121-21).
func test_the_realm_marks_the_provinces_the_crowns_pass_would_use() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ProvinceLedgerPanel = screen.hud.province_ledger
	var before_forces: Array = _force_moved_flags(play)
	var before_crews: Array = _crew_order_flags(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	assert_true(panel.is_open(), "the realm opens")
	var pick: Dictionary = MapPlayRealmCounsel.pick(play)
	assert_eq(
		panel.counsel_text(),
		MapPlayPickProse.sentence_of(pick),
		"the sheet prints the passes' own line"
	)
	assert_eq(
		panel._counsel.visible, not panel.counsel_text().is_empty(),
		"the line stands with its reading"
	)
	# Every province the reading names is on the sheet, and only those rows wear
	# the mark — a row the court would leave alone never looks busy.
	var keys: Dictionary = pick.get("keys", {})
	var shown: Dictionary = {}
	for child: Node in panel._rows.get_children():
		var row := child as ProvinceLedgerRow
		if row == null:
			continue
		var key: String = "%d:%d" % [
			int(row.data.get("region", -1)), int(row.data.get("id", -1))
		]
		shown[key] = true
		assert_eq(row.court, keys.has(key), "a row wears the mark when the court acts there")
		if row.court:
			assert_true(
				row._name.text.begins_with(ProvinceLedgerRow.COURT_MARK), row._name.text
			)
	for key: String in keys.keys():
		assert_true(shown.has(key), "the province the court acts in is on the sheet")
	assert_eq(_force_moved_flags(play), before_forces, "the reading marches nothing")
	assert_eq(_crew_order_flags(play), before_crews, "the reading books no work")
	panel.close()


func test_an_embarked_army_visits_the_squadron_that_carries_it() -> void:
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
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
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")
	var escaped := InputEventAction.new()
	escaped.action = InputActions.CANCEL
	escaped.pressed = true
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	panel._input(escaped)
	assert_false(panel.is_open(), "Escape closes the ledger")


## Every whole-empire sheet reads the one session the screen plays, and the back
## gesture walks that same registry instead of a second copy of the list
## (REQ-P3-01, REQ-P5-07).
func test_the_sheets_bind_once_and_back_walks_the_registry() -> void:
	_attach()
	var sheets: Array[SheetFrame] = HudLedgerDoors.sheets(screen.hud)
	assert_eq(sheets.size(), 8, "the registry names every whole-empire sheet")
	for sheet: SheetFrame in sheets:
		assert_eq(sheet.play, screen.play, "the sheet reads the screen's session")
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
	assert_true(HudLedgerDoors.dismiss_open(screen.hud), "back takes the first open sheet")
	assert_false(screen.hud.muster_roll.is_open(), "the muster roll sets itself aside")
	assert_true(screen.hud.navy_ledger.is_open(), "the navy sheet waits its turn")
	assert_true(HudLedgerDoors.dismiss_open(screen.hud), "a second press closes the next")
	assert_false(screen.hud.navy_ledger.is_open(), "the navy sheet sets itself aside")
	assert_false(HudLedgerDoors.dismiss_open(screen.hud), "nothing open, nothing taken")


## Every door — a bar seal, a chip, a dossier line, a sibling sheet — names its
## sheet by one key, so the table has to answer each one and one press has to
## open it (REQ-P3-01, REQ-P3-02).
func test_every_door_key_opens_its_own_sheet() -> void:
	_attach()
	var keys: Dictionary = {}
	for spec: Dictionary in HudLedgerDoors.SHEETS:
		var key: String = String(spec["key"])
		assert_false(keys.has(key), "one row per door key: %s" % key)
		keys[key] = true
		var sheet: SheetFrame = HudLedgerDoors.sheet_for(screen.hud, key)
		assert_not_null(sheet, "the registry answers %s" % key)
		screen.hud.ledger_door_pressed.emit(key)
		assert_true(sheet.is_open(), "the key opens %s" % key)
		sheet.close()
	assert_null(
		HudLedgerDoors.sheet_for(screen.hud, "no-such-door"), "an unknown key names nothing"
	)


## The registry owns the mounted sheets; the HUD only views them. A row names
## its key and its layer, never a HUD field, so a renamed handle cannot leave a
## door answering null (REQ-P3-01, REQ-P3-02).
## Every sheet the HUD mounts: the seven ledgers plus the two screens that ride
## the same modal layers. A sheet added without its row here fails loudly.
func _hud_sheets(hud: GameHud) -> Array[SheetFrame]:
	var sheets: Array[SheetFrame] = []
	for sheet: SheetFrame in [
		hud.spy_ledger, hud.province_ledger, hud.muster_roll, hud.command_ledger,
		hud.navy_ledger, hud.army_ledger,
		hud.civilian_roster, hud.tech_tree, hud.dossier_screen,
	]:
		if sheet != null:
			sheets.append(sheet)
	assert_eq(sheets.size(), 9, "every sheet the HUD mounts is read")
	return sheets


func test_the_registry_owns_the_sheets_and_the_hud_only_views_them() -> void:
	_attach()
	assert_not_null(screen.hud.ledger_doors, "the HUD holds the registry")
	for spec: Dictionary in HudLedgerDoors.SHEETS:
		var key: String = String(spec["key"])
		assert_eq(spec.keys().size(), 2, "a row names its key and its layer only: %s" % key)
		var owned: SheetFrame = screen.hud.ledger_doors.sheet(key)
		assert_not_null(owned, "the registry holds %s" % key)
		assert_eq(
			HudLedgerDoors.sheet_for(screen.hud, key), owned,
			"the door answers the registry's own handle: %s" % key
		)
	var views: Dictionary = {
		HudLedgerDoors.CIVILIANS: screen.hud.civilian_roster,
		HudLedgerDoors.MUSTER: screen.hud.muster_roll,
		HudLedgerDoors.ARMY: screen.hud.army_ledger,
		HudLedgerDoors.PROVINCES: screen.hud.province_ledger,
		HudLedgerDoors.EYES: screen.hud.spy_ledger,
		HudLedgerDoors.COLONIES: screen.hud.colonies_ledger,
		HudLedgerDoors.COMMAND: screen.hud.command_ledger,
		HudLedgerDoors.NAVY: screen.hud.navy_ledger,
	}
	for key: String in views:
		assert_eq(
			views[key], screen.hud.ledger_doors.sheet(key),
			"the HUD's view is the registry's sheet: %s" % key
		)
	assert_null(screen.hud.ledger_doors.sheet("no-such-door"), "an unknown key holds nothing")


func test_the_rows_seal_visits_its_force() -> void:
	_attach()
	var panel: ForceLedgerPanel = screen.hud.muster_roll
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	var row: ForceLedgerRow = null
	for child: Node in panel._rows.get_children():
		if child is ForceLedgerRow:
			row = child
			break
	assert_not_null(row)
	_assert_visit_seal(row._visit, "Open ", "the muster roll's Visit")
	row._visit.pressed.emit()
	assert_false(panel.is_open(), "the seal visits the force")


func test_the_keyboard_action_toggles_from_the_map() -> void:
	_attach()
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
	LedgerFilterBar.new().render(LedgerRows.REGION_ALL, ProvinceLedger.VIEW_ECONOMY)

	var bar := LedgerFilterBar.new()
	add_child(bar)
	bar.fill(
		"Chart", "View", LedgerRows.REGION_FILTERS, ProvinceLedger.VIEWS,
		ProvinceLedger.view_label
	)
	var chart_row := bar.get_child(0) as HBoxContainer
	var reading_row := bar.get_child(1) as HBoxContainer
	assert_eq(_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(
		_chip_captions(reading_row),
		["Economy", "Defence", "Connectivity"],
		"the view chips are the realm's own words"
	)

	var presses: Array = []
	bar.chosen.connect(func(key: String, region_row: bool) -> void:
		presses.append([key, region_row])
	)
	_chip(reading_row, "Defence").pressed.emit()
	assert_eq(presses.size(), 1, "one press, one report")
	assert_eq(String((presses[0] as Array)[0]), ProvinceLedger.VIEW_DEFENCE)
	assert_false(bool((presses[0] as Array)[1]), "a reading chip is not the chart row")

	bar.render(LedgerRows.REGION_OLD, ProvinceLedger.VIEW_DEFENCE)
	var lit: Color = _chip(chart_row, "Old World").get_theme_color("font_color")
	var plain: Color = _chip(chart_row, "Both charts").get_theme_color("font_color")
	assert_eq(lit, Palette.GOLD_PALE, "the chosen chart reads gold")
	assert_ne(plain, lit, "the rest stay plain")


## The order row is the sheet's own: it carries the view's keys, reports a press
## and is rebuilt (not repainted) when the view offers a different set.
func test_the_order_row_follows_the_view_it_serves() -> void:
	var bar := LedgerFilterBar.new()
	add_child(bar)
	bar.fill("Chart", "View", LedgerRows.REGION_FILTERS, ProvinceLedger.VIEWS, ProvinceLedger.view_label)
	var presses: Array = []
	bar.sort_chosen.connect(func(key: String) -> void: presses.append(key))
	bar.fill_sort(
		"Order", ProvinceLedger.sort_keys(ProvinceLedger.VIEW_ECONOMY),
		ProvinceLedger.sort_label, ProvinceLedger.SORT_VALUE
	)
	var order_row := bar.get_child(2) as HBoxContainer
	assert_eq(
		_chip_captions(order_row), ["Total", "Timber", "Ore", "Riches", "Farm"],
		"the economy view orders by total and by each kind"
	)
	_chip(order_row, "Ore").pressed.emit()
	assert_eq(presses, ["ore"], "an order chip reports its key")
	bar.fill_sort(
		"Order", ProvinceLedger.sort_keys(ProvinceLedger.VIEW_DEFENCE),
		ProvinceLedger.sort_label, ProvinceLedger.SORT_DEFENCE
	)
	assert_eq(
		_chip_captions(bar.get_child(2) as HBoxContainer), ["Figure"],
		"a view with one figure offers one chip"
	)
	assert_eq(bar.get_child_count(), 3, "the row is replaced, never stacked")
	bar.render_sort(ProvinceLedger.SORT_DEFENCE)


## The chart pill on the map's corner: a short word for the chart in play, a
## press that reports the swap, and no press at all on a one-chart world.
func test_the_chart_pill_names_the_chart_and_reports_its_press() -> void:
	var pill := MapRegionToggle.new()
	add_child(pill)
	var presses: Array = []
	pill.cycle_pressed.connect(func() -> void: presses.append(true))
	pill.set_chart("OLD WORLD", true)
	assert_eq(pill.label.text, "OLD", "the pill keeps one word")
	assert_false(pill.button.disabled, "two charts offer the switch")
	assert_true(pill.button.tooltip_text.contains("OLD WORLD"), pill.button.tooltip_text)
	pill.button.pressed.emit()
	assert_eq(presses.size(), 1, "a press reports the swap")
	pill.set_chart("NEW WORLD", false)
	assert_eq(pill.label.text, "NEW")
	assert_true(pill.button.disabled, "a one-chart map offers no press")
	assert_true(pill.button.tooltip_text.contains("only charted"), pill.button.tooltip_text)
	pill.set_chart("", true)
	assert_eq(pill.label.text, "MAP", "an unnamed chart still prints a word")


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
	_seat_both_charts()
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
	_seat_both_charts()
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
	_seat_both_charts()
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


## Re-seats the crown on the both-charts capture (built once on first ask): the
## far chart's seat and its squadrons come back with the save, so the case does
## not swap both charts again to rebuild them.
func _seat_both_charts() -> void:
	_ensure_both_charts()
	Fixture.restore(Fixture.world(), both_charts_map)
	Fixture.suite_reset(screen, both_charts, Fixture.world())
	screen.play.ship_layer.deselect()
	screen.play.army_layer.deselect()
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS


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
	# A leader who publishes one side only names both figures, and the line reads
	# as the condition it describes — never as the pool the sheet just counted
	# (wiki: military-generals § The crown's command).
	var split: Dictionary = CommandLedger.snapshot(GeneralRoster.new(), 0, {}, "gustavus")
	var line: String = CommandLedger.fallback_line(split)
	assert_true(line.contains("2 medals attacking"), line)
	assert_true(line.contains("0 defending"), line)
	assert_true(line.begins_with("With no commander free"), line)


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
	_attach()
	var play: PlaySession = screen.play
	var data: Dictionary = MapPlayCommand.snapshot(play)

	assert_eq(int(data["cap"]), GeneralRoster.BASE_CAP, "the opening cap")
	assert_eq(int(data["held"]), 1, "the crown holds its opening commander")
	assert_false((data["rows"] as Array).is_empty(), "and the roll names him")

	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	assert_true(
		panel._subtitle.text.contains("1 of 1 commander"),
		"the count line reads the pool the rows print"
	)
	assert_true(not panel._empty.visible, "no empty-state note on the opening sheet")


func test_the_command_door_opens_the_ledger_and_lists_the_pool() -> void:
	_attach()
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
	_attach()
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
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


## The command's own reading: the hosts the land pass would lead into battle this
## turn against the pool that answers them, worded off data alone — one host per
## commander, then the leader's own medals (wiki: military-generals § Assignment;
## DR-20261122-02).
func test_the_command_counsel_names_the_hosts_the_court_would_lead() -> void:
	# Covered: every host the pass would send finds a commander.
	assert_eq(
		MapPlayCommandPick.pick_line(2, 2, 2),
		"the court would send 2 hosts into battle — each led by a commander"
	)
	assert_eq(
		MapPlayCommandPick.pick_line(1, 3, 1),
		"the court would send 1 host into battle — it is led by a commander"
	)
	# Short a commander: the fights past the pool fall back on the leader.
	assert_eq(
		MapPlayCommandPick.pick_line(3, 2, 2),
		"the court would send 3 hosts into battle — its 2 commanders would lead 2,"
		+ " and the last host would fight on the leader's own 2 medals"
	)
	assert_eq(
		MapPlayCommandPick.pick_line(4, 1, 3),
		"the court would send 4 hosts into battle — its 1 commander would lead 1,"
		+ " and the last 3 hosts would fight on the leader's own 3 medals"
	)
	# A pool with nobody free fights on the leader alone, and a leader with no
	# medal of its own says so rather than printing a zero.
	assert_eq(
		MapPlayCommandPick.pick_line(2, 0, 2),
		"the court would send 2 hosts into battle with no commander free —"
		+ " they would fight on the leader's own 2 medals"
	)
	assert_eq(
		MapPlayCommandPick.pick_line(1, 0, 0),
		"the court would send 1 host into battle with no commander free —"
		+ " it would fight with no medal at all"
	)
	# No fight at all: the sheet names the gate, never a line about nobody.
	assert_eq(MapPlayCommandPick.pick_line(0, 2, 2), MapPlayCommandPick.NO_HOST_LINE)
	var pick: Dictionary = MapPlayCommandPick.of(3, 2, 2)
	assert_eq(int(pick["hosts"]), 3)
	assert_eq(int(pick["led"]), 2, "the hosts past the pool are counted, not led")
	assert_eq(String(pick["line"]), MapPlayCommandPick.pick_line(3, 2, 2))
	assert_eq(MapPlayCommandPick.pick(null), {})
	assert_eq(
		MapPlayCommandPick.line(null), "", "a session that is not there names nothing"
	)


## Only the marches that fight spend a commander: a storm into ground the crown
## does not hold and a relief onto its own land are fights, while a frontier
## advance, a rotation home, a walk home and the seat's split are not
## (wiki: military-generals § Assignment — one general per attacking army).
func test_only_the_marches_that_fight_spend_a_commander() -> void:
	var armies: Array = [
		{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_STORM},
		{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_RELIEF},
		{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_FRONTIER},
		{"kind": MapPlayArmyPick.KIND_ROTATE, "why": ""},
		{"kind": MapPlayArmyPick.KIND_WALK_HOME, "why": ""},
		{"kind": MapPlayArmyPick.KIND_SPLIT, "why": ""},
	]
	assert_eq(MapPlayCommandPick.hosts_of(armies), 2, "a storm and a relief fight")
	assert_eq(MapPlayCommandPick.hosts_of([]), 0)
	assert_eq(
		MapPlayCommandPick.hosts_of([{"kind": MapPlayArmyPick.KIND_MARCH}]),
		0,
		"a march with no reason reads no fight"
	)


## The fights the command line names are printed on THE CROWN'S ARMY, where the
## standards they lead wear the counsel's mark, so the sheet carries the door
## that opens it — standing only while the reading names a fight
## (wiki: military-generals § The hosts the court would lead; DR-20261123-06;
## REQ-P5-01, REQ-P5-03, REQ-P5-06).
func test_the_command_line_carries_the_door_to_the_fights_it_names() -> void:
	# Pure: a reading that names a host leads, an empty read and the gate do not.
	assert_false(MapPlayCommandPick.leads({}), "no reading, no door")
	assert_false(
		MapPlayCommandPick.leads(MapPlayCommandPick.of(0, 2, 2)),
		"a gate names no fight"
	)
	assert_true(MapPlayCommandPick.leads(MapPlayCommandPick.of(2, 1, 2)))
	assert_true(
		MapPlayCommandPick.leads(MapPlayCommandPick.of(1, 0, 0)),
		"a host with no commander is still a fight"
	)

	_attach()
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	assert_true(panel.is_open())
	assert_not_null(panel.army_press(), "the sheet carries the door")
	assert_eq(panel.army_press().text, CommandLedgerPanel.ARMY_DOOR)
	assert_true(
		panel.army_press().tooltip_text.contains("THE CROWN'S ARMY"),
		"the door names the sheet it opens"
	)
	# A reading of no fight stands the press down with its line.
	panel._counsel.show_value(MapPlayCommandPick.of(0, 1, 2))
	panel._sync_army_door()
	assert_false(panel.army_press_shown(), "no fight, no door")
	# A reading that names fights stands it under the line.
	panel._counsel.show_value(MapPlayCommandPick.of(2, 1, 2))
	panel._sync_army_door()
	assert_true(panel.army_press_shown(), "a named fight carries the door")


## The door opens THE CROWN'S ARMY and this sheet steps aside, so the crown reads
## the page the fights are marked on rather than two sheets at once — and an army
## sheet already standing is left standing (DR-20261123-06; REQ-P5-01, REQ-P5-07).
func test_the_command_door_opens_the_army_and_steps_aside() -> void:
	_attach()
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	var keys: Array[String] = []
	panel.door_pressed.connect(func(key: String) -> void: keys.append(key))
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	panel._counsel.show_value(MapPlayCommandPick.of(2, 1, 2))
	panel._sync_army_door()
	panel.army_press().pressed.emit()
	assert_eq(keys.size(), 1, "one door press")
	assert_eq(keys[0], HudLedgerDoors.ARMY, "the door names the army sheet")
	assert_true(screen.hud.army_ledger.is_open(), "the door opens THE CROWN'S ARMY")
	assert_false(panel.is_open(), "the command sheet steps aside for it")
	# An army sheet already up stays up: the press does not toggle it shut.
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	assert_true(panel.is_open())
	panel._counsel.show_value(MapPlayCommandPick.of(2, 1, 2))
	panel._sync_army_door()
	panel.army_press().pressed.emit()
	assert_true(screen.hud.army_ledger.is_open(), "a sheet already up stays up")
	assert_false(panel.is_open())
	screen.hud.army_ledger.close()


## The line names the fights, not only their number: the standard the army sheet
## prints and the ground its order storms or relieves, three named and the rest
## counted, with the pool's answer after them (wiki: military-generals § The hosts
## the court would lead; DR-20261122-22).
func test_the_command_counsel_names_the_fights_it_would_lead() -> void:
	var storm: String = "the field army at Tucapel to storm Cádiz"
	var relief: String = "the Home Army to throw the host out of Lisbon"
	assert_eq(
		MapPlayCommandPick.pick_line(2, 2, 2, [storm, relief]),
		"the court would send 2 hosts into battle — %s and %s — each led by a commander"
		% [storm, relief]
	)
	# Short a commander: the names stand between the count and the answer.
	assert_eq(
		MapPlayCommandPick.pick_line(2, 1, 2, [storm, relief]),
		(
			"the court would send 2 hosts into battle — %s and %s — its 1 commander"
			+ " would lead 1, and the last host would fight on the leader's own 2 medals"
		) % [storm, relief]
	)
	# No commander free: the gate follows the names, never splits one.
	assert_eq(
		MapPlayCommandPick.pick_line(2, 0, 2, [storm, relief]),
		(
			"the court would send 2 hosts into battle — %s and %s — with no commander"
			+ " free, they would fight on the leader's own 2 medals"
		) % [storm, relief]
	)
	# Beyond three the line counts the rest, so a wide front stays one sentence.
	var four: Array[String] = [
		storm,
		relief,
		"the field army at Coimbra to storm Badajoz",
		"the field army at Oporto to storm Cádiz from the north",
	]
	assert_eq(
		MapPlayCommandPick.pick_line(4, 4, 0, four),
		(
			"the court would send 4 hosts into battle — %s, %s, %s and 1 more — each"
			+ " led by a commander"
		) % [four[0], four[1], four[2]]
	)
	# No fight the sheet can word prints the count-only line it printed before.
	assert_eq(
		MapPlayCommandPick.pick_line(2, 2, 2, []),
		"the court would send 2 hosts into battle — each led by a commander"
	)


## The fights are worded off the orders the army sheet prints: a storm into ground
## the crown does not hold and a relief onto its own land, in the pass's own order,
## while a frontier advance, a rotation and an entry the module cannot word name
## nothing (wiki: military-generals § Assignment; DR-20261122-22).
func test_only_the_fighting_marches_are_named() -> void:
	var armies: Array = [
		{
			"kind": MapPlayArmyPick.KIND_MARCH,
			"why": MapPlayArmyPick.WHY_FRONTIER,
			"standard": "the Home Army",
			"order": "to advance to Cádiz, the frontier",
		},
		{
			"kind": MapPlayArmyPick.KIND_MARCH,
			"why": MapPlayArmyPick.WHY_STORM,
			"standard": "the Home Army",
			"order": "to storm Cádiz",
		},
		{
			"kind": MapPlayArmyPick.KIND_MARCH,
			"why": MapPlayArmyPick.WHY_RELIEF,
			"standard": "the field army at Tucapel",
			"order": "to throw the host out of Lisbon",
		},
		{
			"kind": MapPlayArmyPick.KIND_ROTATE,
			"why": "",
			"standard": "the field army at Coimbra",
			"order": "home to Madrid to merge with the Home Army",
		},
		{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_STORM, "standard": "", "order": ""},
	]
	assert_eq(MapPlayCommandPick.hosts_of(armies), 3, "a storm, a relief and one unwording storm")
	assert_eq(
		MapPlayCommandPick.clauses_of(armies),
		[
			"the Home Army to storm Cádiz",
			"the field army at Tucapel to throw the host out of Lisbon",
		],
		"only the fights the sheet can name are named, in the pass's order"
	)
	# The pick the sheet prints: the count, the names and the pool's answer off one
	# read.
	var pick: Dictionary = MapPlayCommandPick.from(
		{"armies": armies}, {"held": 1, "fallback": {"attack": 2}}
	)
	assert_eq(int(pick["hosts"]), 3)
	assert_eq(int(pick["led"]), 1)
	assert_true(String(pick["line"]).contains("the Home Army to storm Cádiz"), pick["line"])
	# Two standards that would fight alike read as one clause, and the count keeps
	# both.
	var repeated: Dictionary = MapPlayCommandPick.from(
		{
			"armies": [
				{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_STORM, "standard": "the Home Army", "order": "to storm Cádiz"},
				{"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_STORM, "standard": "the Home Army", "order": "to storm Cádiz"},
			]
		},
		{"held": 2}
	)
	assert_eq(int(repeated["hosts"]), 2)
	assert_true(String(repeated["line"]).contains("and 1 more"), "a repeat keeps its count")
	assert_eq(
		MapPlayCommandPick.from({}, {}).get("line"),
		MapPlayCommandPick.NO_HOST_LINE,
		"no fight, no names"
	)


## The command sheet is the passes' own reading: it prints the line the land pass
## and the pool word and orders nothing (REQ-P2-03, REQ-P5-06; DR-20261122-02).
func test_the_command_sheet_prints_the_reading_it_is_handed() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: CommandLedgerPanel = screen.hud.command_ledger
	assert_true(panel.counsel_source.is_valid(), "the sheet binds the passes' reading")
	var before: Array = _force_moved_flags(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COMMAND)
	var counsel: String = panel.counsel_text()
	var pick: Dictionary = MapPlayCommandPick.pick(play, panel._snapshot)
	assert_eq(counsel, MapPlayPickProse.sentence_of(pick))
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(), "the line stands with its reading"
	)
	if not pick.is_empty():
		assert_true(counsel.begins_with("The court would send "), counsel)
	# Every standard's entry carries the reason it marches, so the sheet's count of
	# the fights is read off the same walk the army sheet prints.
	for raw: Variant in MapPlayArmyOrdersPick.pick(play).get("armies", []):
		assert_true((raw as Dictionary).has("why"), "an ordered standard carries its why")
		assert_true((raw as Dictionary).has("standard"), "and the title the sheet prints")
		assert_true((raw as Dictionary).has("order"), "and the order it words")
	assert_eq(_force_moved_flags(play), before, "the reading marches nothing")
	# An unwired sheet prints nothing, and the line stands down.
	var wired: Callable = panel.counsel_source
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	panel.counsel_source = wired
	panel.close()


## --- the world's colonies ---------------------------------------------------
## Every Tribe a Great Power bought into its empire, read as a ledger — who holds
## it, where it stands and what its suzerain's boycott shuts (wiki: diplomacy
## § GP–Tribe Rules — Join Empire, § Boycott; DR-20261117-02). The projection
## reads a small record over a two-chart fixture; the drive presses the court's
## COLONIES door on the mounted map.


func test_a_colony_reads_its_suzerain_place_and_open_trade() -> void:
	var state: DiplomacyState = _colony_state()
	var data: Dictionary = ColonyLedger.snapshot(
		_colony_regions(), state, FactionCatalog.PLAYER_FACTION
	)
	assert_eq(int(data["total"]), 1, "one tribe is bought")
	var row: Dictionary = (data["rows"] as Array)[0]
	assert_eq(
		String(row["name"]), FactionCatalog.name_of(_colony_tribe()), "the people are named"
	)
	assert_eq(String(row["suzerain_name"]), "England", "the court that bought it is named")
	assert_eq(String(row["place"]), "Veracruz", "the colony's capital is read off the chart")
	assert_eq(int(row["provinces"]), 2, "every province the people hold is counted")
	assert_eq(String(row["terms"]), "Open to every court", "no boycott, no bar")
	assert_true(
		String(row["standing"]).contains("Warm") or String(row["standing"]).length() > 0,
		"the herald's word is printed, never the score"
	)
	assert_true(
		ColonyLedger.summary(data, LedgerRows.REGION_ALL, 1).contains("1 of 1 colonies"),
		"the count line reads the roll"
	)


## The rule's bigger half: a boycott applies to every colony the issuer holds,
## so the bar is read on the colony and not only on the court pages.
func test_a_boycott_seals_every_colony_of_the_issuer() -> void:
	var state: DiplomacyState = _colony_state()
	state.boycotts[DiplomacyKeys.directed(_colony_parent(), 0)] = 1
	state.set_subsidy(_colony_parent(), _colony_tribe(), 10)
	var data: Dictionary = ColonyLedger.snapshot(_colony_regions(), state, 0)
	var row: Dictionary = (data["rows"] as Array)[0]
	assert_true(bool(row["sealed"]), "the issuer's colony wears the bar")
	assert_eq(String(row["terms"]), "Sealed to Spain", "the boycotted court is named")
	assert_eq(int(data["sealed"]), 1)
	assert_eq(int(row["subsidy"]), 10, "the subsidy the suzerain pays is read")
	assert_true(String(row["standing"]).contains("subsidy 10%"))


func test_the_colony_filters_narrow_the_roll_and_keep_their_tallies() -> void:
	var state: DiplomacyState = _colony_state()
	state.ensure_relation(0, _second_tribe(), 1)
	state.set_colony(_second_tribe(), 0)
	var data: Dictionary = ColonyLedger.snapshot(_colony_regions(), state, 0)
	assert_eq(int(data["total"]), 2, "both colonies are read")
	assert_eq(int(data["ours"]), 1, "one is the crown's own")
	assert_eq(ColonyLedger.count(data, LedgerRows.REGION_ALL, ColonyLedger.FILTER_OURS), 1)
	assert_eq(ColonyLedger.count(data, LedgerRows.REGION_ALL, ColonyLedger.FILTER_SEALED), 0)
	assert_eq(ColonyLedger.count(data, LedgerRows.REGION_NEW, ColonyLedger.FILTER_ALL), 1)
	var counts: Dictionary = ColonyLedger.filter_counts(data, LedgerRows.REGION_ALL)
	assert_eq(int(counts[ColonyLedger.FILTER_ALL]), 2)
	assert_true(
		bool((data["rows"] as Array)[0]["ours"]), "the crown's own colony leads the reading"
	)
	assert_eq(ColonyLedger.filter_label(ColonyLedger.FILTER_SUBSIDY), "Subsidised")


func test_an_unmet_people_prints_no_row() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	state.set_colony(_colony_tribe(), _colony_parent())
	# The crown's own dealings are struck, so neither the people nor the court
	# that bought them is known: a colony the crown never heard of is silent.
	state.clear_relations_of(0)
	var data: Dictionary = ColonyLedger.snapshot(_colony_regions(), state, 0)
	assert_eq(int(data["total"]), 0, "an undiscovered people is nobody's news")
	assert_true(
		(MapPlayColonies.snapshot(null)["rows"] as Array).is_empty(),
		"no session, no colony"
	)


func test_a_colony_row_reads_its_chip_place_and_bar() -> void:
	var row := ColonyLedgerRow.new()
	row.setup({
		"name": "The Inca",
		"suzerain_name": "Spain",
		"place": "Cusco",
		"region": 1,
		"region_label": "New World",
		"province": 4,
		"provinces": 3,
		"standing": "Warm · subsidy 10%",
		"terms": "Sealed to England",
		"flags": [ColonyLedger.FILTER_OURS],
	})
	assert_eq(row._name.text, "The Inca")
	assert_eq(row._chip.text, "OURS", "the crown's own colony is read first")
	assert_true(row._detail.text.contains("Cusco — colony of Spain"))
	assert_true(row._reading.text.contains("3 provinces"))
	assert_true(row._reading.text.contains("Sealed to England"))
	assert_eq(row._standing.text, "Warm · subsidy 10%")
	assert_not_null(row._visit, "a colony's capital is a place to visit")
	row.free()


func test_a_colony_row_with_no_seat_offers_no_visit_and_reads_its_subsidy() -> void:
	var row := ColonyLedgerRow.new()
	row.compact = true
	row.setup({
		"name": "A people",
		"suzerain_name": "England",
		"place": "No province",
		"region": 1,
		"province": ColonyLedger.NO_ID,
		"provinces": 0,
		"standing": "Neutral",
		"terms": "Open to every court",
		"flags": [ColonyLedger.FILTER_SUBSIDY],
	})
	assert_eq(row._chip.text, "PAYS", "a subsidy is the reading when nothing bars it")
	assert_null(row._visit, "no seat, no Visit")
	assert_true(row._detail.text.contains("0 provinces") or
		row._detail.text.contains("Open to every court"), "a phone folds the terms in")
	row.free()


func test_the_colonies_door_opens_the_sheet_it_reads() -> void:
	_attach()
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	assert_not_null(panel, "the HUD mounts the colony ledger")
	var door: Button = _colonies_door()
	assert_not_null(door, "the court carries the colonies door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the court's door opens it")
	assert_true(panel._subtitle.text.contains("colonies"), "the count line names the roll")
	assert_true(
		panel._empty.visible and panel._empty.text.contains("Join Empire"),
		"a world with no colony says how one is made"
	)
	panel.close()


func test_a_colony_on_the_live_map_is_listed_and_its_seat_is_visited() -> void:
	_attach()
	var play: PlaySession = screen.play
	play.diplomacy.ensure_relation(play.player_faction, _colony_tribe(), play.turn)
	play.diplomacy.set_colony(_colony_tribe(), _colony_parent())
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COLONIES)
	assert_true(panel.is_open())
	assert_true(_colony_row_widgets(panel) > 0, "the colony is listed")
	assert_true(panel._subtitle.text.contains("1 of 1"), "the count line reads the roll")
	var row: ColonyLedgerRow = _colony_row(panel)
	assert_not_null(row, "the colony mints its row")
	var visited: Array = []
	var visit := func(region: int, province_id: int) -> void:
		visited.append([region, province_id])
	row.visit_pressed.connect(visit)
	_assert_visit_seal(row._visit, "Open ", "the colony row's Visit")
	row._visit.pressed.emit()
	assert_eq(visited.size(), 1, "the row's Visit door asks for its capital")
	assert_eq(int(visited[0][1]), int(row.data["province"]), "the colony's own province")
	# The row lives on the shared panel, so this case's lambda must not outlive
	# it: a later case that presses the same door would call a capture the freed
	# test instance owned (the engine reports it as a freed lambda capture).
	row.visit_pressed.disconnect(visit)
	assert_true(BackRequest.handle(play, play.improvements), "back walks the sheets")
	assert_false(panel.is_open(), "back sets the ledger aside first")


## --- the colonies' own reading (DR-20261121-16) -----------------------------


## The door the line's own court answers (DR-20261123-05): a reading that names a
## Tribe opens it; a footing that shuts new chains names no court and opens
## nothing, so the press can never promise a sheet the sentence does not name.
func test_the_colonies_door_names_the_court_its_line_opens() -> void:
	var tribe: int = _colony_tribe()
	var chain: Dictionary = MapPlayColonyPick.of(
		{"target": tribe, "stage": DiplomacyCatalog.STAGE_CONSULATE}, {}
	)
	assert_eq(String(chain["kind"]), MapPlayColonyPick.KIND_CHAIN)
	assert_eq(MapPlayColonyPick.door(chain), tribe, "the chain's own court")
	var gate: Dictionary = MapPlayColonyPick.gated(
		{"target": tribe, "stage": DiplomacyCatalog.STAGE_JOIN_EMPIRE}, "a reason"
	)
	assert_eq(MapPlayColonyPick.door(gate), tribe, "a refused link still names its court")
	var study: Dictionary = MapPlayColonyPick.of(
		{"target": tribe, "stage": DiplomacyCatalog.STAGE_EMBASSY}, {}
	)
	assert_eq(String(study["kind"]), MapPlayColonyPick.KIND_STUDY)
	assert_eq(MapPlayColonyPick.door(study), tribe, "the door the chain owes names its court")
	# A footing that shuts new chains names no court, and nothing names none.
	assert_eq(
		MapPlayColonyPick.door({"kind": MapPlayColonyPick.KIND_CLOSED, "line": "x"}),
		-1,
		"a shut footing opens no door"
	)
	assert_eq(MapPlayColonyPick.door({}), -1, "no reading, no door")


## The door on a live sheet: the press stands only while the line names a court,
## it opens THE COURT on that court, and the colony sheet steps aside so the
## envoy rows are what the crown reads (DR-20261123-05; REQ-P5-01, REQ-P5-05).
func test_the_colonies_door_opens_the_court_the_line_names() -> void:
	_attach()
	var play: PlaySession = screen.play
	var faction: int = play.player_faction
	var model: MapModel = Fixture.region()
	var tribe: int = _colony_tribe()
	var seat: int = Fixture.inland_province(model)
	model.province_data(seat).owner = tribe
	play.economy.economy.treasury = 50000
	play.diplomacy.ensure_relation(faction, tribe, play.turn)
	play.diplomacy.relation(faction, tribe).score = 40.0
	play.diplomacy.set_overture(faction, tribe, DiplomacyCatalog.STAGE_NAP)
	# The envoy has already been to this court, so the reading names the gate and
	# keeps the Tribe: a door with nothing to promise still opens the sheet.
	play.diplomacy.claim(faction, tribe, "overture")
	play.ensure_ai()
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COLONIES)
	assert_true(panel.is_open(), "the colonies sheet is up")
	panel.refresh()
	var pick: Dictionary = MapPlayColonyPick.pick(play)
	assert_eq(int(pick.get("target", -1)), tribe, "the reading names the Tribe")
	var press: Button = panel.follow_press()
	assert_not_null(press, "the sheet carries its door")
	assert_true(press.visible, "the door stands while the line names a court")
	assert_eq(panel.door_court(), tribe, "the door names the court the line names")
	assert_true(
		press.tooltip_text.contains(FactionCatalog.name_of(tribe)),
		"the door says which court it opens"
	)
	# The one gate a court sheet answers, so a door never promises a sheet it
	# cannot stand on (REQ-P5-05).
	assert_true(
		MapPlayDiplomacy.can_open_court(play.diplomacy, faction, tribe),
		"a contacted court can be stood on"
	)
	assert_false(
		MapPlayDiplomacy.can_open_court(play.diplomacy, faction, -1), "no court, no sheet"
	)
	assert_false(
		MapPlayDiplomacy.can_open_court(play.diplomacy, faction, faction),
		"the crown's own court is no envoy target"
	)
	press.pressed.emit()
	assert_true(
		screen.hud.panels.is_diplomacy_open(), "the door opens THE COURT"
	)
	assert_eq(
		screen.hud.panels.diplomacy_panel.selected_faction(), tribe,
		"THE COURT stands on the court the line named"
	)
	assert_false(panel.is_open(), "the colony sheet steps aside for it")
	DiplomacyHud.hide(screen.hud.panels)


## The door's guards (DR-20261123-05): a sheet whose body never built carries no
## press, a reading that names no court opens nothing, and a court the crown
## cannot stand on answers in a toast rather than in silence (REQ-P5-05).
func test_a_door_with_no_court_says_so_and_opens_nothing() -> void:
	_attach()
	var play: PlaySession = screen.play
	var bare := ColonyLedgerPanel.new()
	bare._sync_follow()
	assert_null(bare.follow_press(), "a sheet with no body carries no door")
	bare._on_follow()
	assert_false(screen.hud.panels.is_diplomacy_open(), "no court named, no sheet")
	bare.free()
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COLONIES)
	var stranger: int = _court_never_met()
	assert_true(stranger >= 0, "the fixture leaves a court the crown never met")
	assert_false(
		MapPlayDiplomacy.can_open_court(play.diplomacy, play.player_faction, stranger),
		"a court never met cannot be stood on"
	)
	panel._pick = {"kind": MapPlayColonyPick.KIND_CHAIN, "target": stranger}
	# The lane holds its lines while a sheet covers it, which is where the door's
	# answer is read: a toast under an open roll waits its turn.
	screen.hud.despatches.set_covered(true)
	panel._on_follow()
	# Read the lane before it is uncovered: releasing it prints the held line.
	var said: PackedStringArray = screen.hud.despatches.waiting()
	screen.hud.despatches.set_covered(false)
	assert_false(
		screen.hud.panels.is_diplomacy_open(), "a stranger opens no court sheet"
	)
	assert_true(panel.is_open(), "the roll stays up rather than closing on nothing")
	assert_false(said.is_empty(), "the door answers in a toast, never in silence")
	if not said.is_empty():
		assert_true(
			String(said[said.size() - 1]).contains(FactionCatalog.name_of(stranger)),
			"the toast names the court it could not open"
		)
	panel.close()
	assert_false(MapPlayDiplomacy.open_court(null, 0), "no session, no court sheet")


## The first Tribe the crown holds no relation with.
func _court_never_met() -> int:
	for tribe: int in FactionCatalog.tribe_ids():
		if not screen.play.diplomacy.has_relation(screen.play.player_faction, tribe):
			return tribe
	return -1


## --- the colonies' own reading (DR-20261121-16) -----------------------------


## The Tribe the court's own envoy is buying, worded off one ambition read: each
## stage's own words, the study gate the pass names as the door it owes, and no
## clause for a stage this module cannot say (REQ-P2-03, REQ-P5-06).
func test_the_colony_pick_words_the_link_the_court_would_press() -> void:
	var tribe: int = _colony_tribe()
	var name: String = FactionCatalog.name_of(tribe)
	assert_eq(
		MapPlayColonyPick.chain_line("the %s" % name, DiplomacyCatalog.STAGE_CONSULATE),
		"the court would offer the %s a Trade Consulate this turn, one link toward a colony"
		% name
	)
	assert_eq(
		MapPlayColonyPick.chain_line("the %s" % name, DiplomacyCatalog.STAGE_NAP),
		"the court would offer the %s a Non-Aggression Pact this turn, "
		% name
		+ "one link toward a colony"
	)
	assert_eq(
		MapPlayColonyPick.chain_line("the %s" % name, DiplomacyCatalog.STAGE_JOIN_EMPIRE),
		"the court would offer the %s the Join Empire this turn — the bond that "
		% name
		+ "makes it a colony"
	)
	assert_eq(MapPlayColonyPick.chain_line("the %s" % name, "unknown"), "")
	# An embassy needs a study the court may not hold: the chain names the door
	# it owes instead of a link it cannot sign (DR-20261114-05).
	var embassy: Dictionary = {"target": tribe, "stage": DiplomacyCatalog.STAGE_EMBASSY}
	var study: String = TechCatalog.display_name("diplomatic_expertise")
	var gated: Dictionary = MapPlayColonyPick.of(embassy, {})
	assert_eq(String(gated["kind"]), MapPlayColonyPick.KIND_STUDY)
	assert_eq(String(gated["study"]), "diplomatic_expertise")
	assert_eq(
		String(gated["line"]),
		"the court's chain with the %s waits on %s" % [name, study]
	)
	# The study in hand, the same read is a link for the court to press.
	var opened: Dictionary = MapPlayColonyPick.of(embassy, {"diplomatic_expertise": 1})
	assert_eq(String(opened["kind"]), MapPlayColonyPick.KIND_CHAIN)
	assert_eq(String(opened["stage"]), DiplomacyCatalog.STAGE_EMBASSY)
	assert_eq(
		MapPlayPickProse.sentence(String(opened["line"])),
		"The court would offer the %s an Embassy this turn, one link toward a colony."
		% name
	)
	# No target or no stage names nothing at all.
	assert_true(MapPlayColonyPick.of({}, {}).is_empty())
	assert_true(MapPlayColonyPick.of({"target": -1, "stage": "unknown"}, {}).is_empty())
	assert_eq(MapPlayColonyPick.pick(null), {})
	assert_eq(MapPlayColonyPick.line(null), "", "a session that is not there names nothing")
	assert_eq(
		MapPlayPickProse.sentence(MapPlayColonyPick.CLOSED_LINE),
		"The court would open no colony chain this turn — at war, its envoy waits "
		+ "on the front."
	)


## The press's own gate (DR-20261121-16): a chain the envoy row would refuse
## names the rule's reason instead of an offer the crown cannot make this turn —
## the same gate `DiplomacyRules.can_establish_overture` answers the press with
## (REQ-P2-03, REQ-P5-06).
func test_the_colony_pick_names_the_gate_the_crowns_press_answers() -> void:
	var tribe: int = _colony_tribe()
	var name: String = FactionCatalog.name_of(tribe)
	var ambition: Dictionary = {
		"target": tribe, "stage": DiplomacyCatalog.STAGE_JOIN_EMPIRE,
	}
	var cold: Dictionary = MapPlayColonyPick.gated(
		ambition,
		"Join Empire needs a warmer court than this one — the gate stands one step "
		+ "up the meter."
	)
	assert_eq(String(cold["kind"]), MapPlayColonyPick.KIND_GATE)
	assert_eq(int(cold["target"]), tribe)
	assert_eq(
		MapPlayPickProse.sentence(String(cold["line"])),
		"The court's chain with the %s waits this turn (Join Empire needs a warmer "
		% name + "court than this one — the gate stands one step up the meter)."
	)
	# The rule's words are handed in whole: the line closes with one full stop.
	assert_false(String(cold["line"]).contains(".."), "the reason keeps one stop")
	# No reason to print, no line: a sheet with nothing to say stays silent.
	assert_eq(MapPlayColonyPick.gate_line("the %s" % name, ""), "")
	assert_eq(MapPlayColonyPick.gate_line("", "a reason"), "")
	assert_true(MapPlayColonyPick.gated(ambition, "").is_empty())
	assert_true(MapPlayColonyPick.gated({}, "a reason").is_empty())
	assert_true(MapPlayColonyPick.gated({"target": -1}, "a reason").is_empty())


## The same gate on a live session: a chain whose envoy row would refuse reads
## the rule's reason instead of a link, and a chain the press can take reads the
## link — so the gold line and the crown's own tap cannot disagree (REQ-P2-03).
func test_the_colonies_name_the_gate_a_live_press_would_refuse() -> void:
	_attach()
	var play: PlaySession = screen.play
	var faction: int = play.player_faction
	var model: MapModel = Fixture.region()
	var first: int = _colony_tribe()
	var seat: int = Fixture.inland_province(model)
	var data: ProvinceState = model.province_data(seat)
	assert_not_null(data, "the fixture names a province to seat")
	data.owner = first
	play.economy.economy.treasury = 50000
	play.diplomacy.ensure_relation(faction, first, play.turn)
	play.diplomacy.relation(faction, first).score = 40.0
	play.diplomacy.set_overture(faction, first, DiplomacyCatalog.STAGE_NAP)
	# The court's envoy has already been to this Tribe this turn.
	play.diplomacy.claim(faction, first, "overture")
	# The reading needs the crown's own planner state, which a boot makes lazily.
	play.ensure_ai()
	var refused: Dictionary = MapPlayColonyPick.pick(play)
	assert_eq(String(refused.get("kind", "")), MapPlayColonyPick.KIND_GATE)
	assert_eq(int(refused.get("target", -1)), first)
	assert_true(
		MapPlayPickProse.sentence(String(refused.get("line", ""))).contains(
			"An overture was already made to this court this turn"
		),
		"the rule's own words, not a second opinion"
	)
	# A second Tribe the same turn can still be offered: the warmer chain wins
	# the reading, and the press that signs it is on.
	var second: int = _second_tribe()
	var other: int = MapModel.NO_ID
	for province: ProvinceState in model.provinces:
		if province.id != seat:
			other = province.id
			break
	assert_ne(other, MapModel.NO_ID, "the fixture has a second province")
	model.province_data(other).owner = second
	play.diplomacy.ensure_relation(faction, second, play.turn)
	play.diplomacy.relation(faction, second).score = 60.0
	play.diplomacy.set_overture(faction, second, DiplomacyCatalog.STAGE_NAP)
	var offered: Dictionary = MapPlayColonyPick.pick(play)
	assert_eq(
		int(offered.get("target", -1)), second, "the chain the court could take is named"
	)
	# The court's one order may be this rung or bound elsewhere; either way the
	# sheet names this chain and never a second order (DR-20261121-18).
	var envoy: Dictionary = MapPlayDiplomacyPick.plan(play).get("action", {}) as Dictionary
	var next_stage: String = DiplomacyCatalog.next_stage(
		play.diplomacy.overture(faction, second)
	)
	if MapPlayColonyPick.envoy_gives(
		envoy, {"target": second, "stage": next_stage}
	):
		assert_eq(String(offered.get("kind", "")), MapPlayColonyPick.KIND_CHAIN)
		assert_eq(
			String(offered.get("line", "")),
			MapPlayColonyPick.chain_line(
				"the %s" % FactionCatalog.name_of(second), next_stage
			)
		)
	else:
		assert_eq(
			String(offered.get("kind", "")), MapPlayColonyPick.KIND_ENVOY,
			"a link the one order does not take reads the wait it is"
		)
		assert_eq(int(offered.get("other", -1)), int(envoy.get("target", -1)))


## The court's one order (DR-20261121-18): a link reads as an offer only when the
## envoy's own order is that rung; otherwise the sheet names the wait and the
## court the order went to, so THE COLONIES and THE COURT cannot promise two
## orders in one turn (REQ-P2-03, REQ-P5-05).
func test_the_colony_chain_waits_behind_the_envoys_one_order() -> void:
	var tribe: int = _colony_tribe()
	var name: String = FactionCatalog.name_of(tribe)
	var ambition: Dictionary = {"target": tribe, "stage": DiplomacyCatalog.STAGE_EMBASSY}
	# The planner's own rung: the same court at the same stage is the one order.
	assert_true(MapPlayColonyPick.envoy_gives({
		"kind": DiplomacyOrders.KIND_OVERTURE,
		"target": tribe,
		"stage": DiplomacyCatalog.STAGE_EMBASSY,
	}, ambition), "the chain's own rung is the one order")
	# Another court, another rung, or another kind of order is not this link.
	assert_false(MapPlayColonyPick.envoy_gives({
		"kind": DiplomacyOrders.KIND_OVERTURE,
		"target": _second_tribe(),
		"stage": DiplomacyCatalog.STAGE_EMBASSY,
	}, ambition), "an order to another court is not this chain")
	assert_false(MapPlayColonyPick.envoy_gives({
		"kind": DiplomacyOrders.KIND_OVERTURE,
		"target": tribe,
		"stage": DiplomacyCatalog.STAGE_CONSULATE,
	}, ambition), "another rung of the chain is not this link")
	assert_false(MapPlayColonyPick.envoy_gives({
		"kind": DiplomacyOrders.KIND_AID, "target": tribe, "stage": "",
	}, ambition), "a gift to the same court is not this link")
	assert_false(MapPlayColonyPick.envoy_gives({}, ambition), "no order, no link")
	# The wait names the court the order went to, in that court's own name.
	var behind: Dictionary = MapPlayColonyPick.behind(ambition, {
		"kind": DiplomacyOrders.KIND_WAR, "target": _colony_parent(),
	})
	assert_eq(String(behind["kind"]), MapPlayColonyPick.KIND_ENVOY)
	assert_eq(int(behind["target"]), tribe)
	assert_eq(int(behind["other"]), _colony_parent())
	assert_eq(
		MapPlayPickProse.sentence(String(behind["line"])),
		"The court's chain with the %s waits this turn — its one order goes to %s."
		% [name, FactionCatalog.name_of(_colony_parent())]
	)
	# A planner that weighed the turn and named nobody still says the wait.
	var none: Dictionary = MapPlayColonyPick.behind(ambition, {})
	assert_eq(int(none["other"]), -1)
	assert_eq(
		String(none["line"]),
		"the court's chain with the %s waits this turn — its envoy gives the "
		% name + "turn no order"
	)
	assert_true(MapPlayColonyPick.behind({}, {}).is_empty())
	assert_eq(MapPlayColonyPick.envoy_line("", 1), "")


## Two sheets, one turn: on a live chain the colony line reads the link when the
## court's one order is that rung, and otherwise names the court that order went
## to — never a second promise (REQ-P2-03, REQ-P5-05; DR-20261121-18).
func test_the_colonies_and_the_court_name_one_envoy_order() -> void:
	_attach()
	var play: PlaySession = screen.play
	var faction: int = play.player_faction
	var model: MapModel = Fixture.region()
	var tribe: int = _colony_tribe()
	var seat: int = Fixture.inland_province(model)
	var data: ProvinceState = model.province_data(seat)
	assert_not_null(data, "the fixture names a province to seat")
	data.owner = tribe
	play.economy.economy.treasury = 50000
	play.diplomacy.ensure_relation(faction, tribe, play.turn)
	play.diplomacy.relation(faction, tribe).score = 60.0
	# The last link needs no study, so the chain reads a link (or its wait) and
	# never the door a missing tech owes.
	play.diplomacy.set_overture(faction, tribe, DiplomacyCatalog.STAGE_NAP)
	# The reading needs the crown's own planner state, which a boot makes lazily.
	play.ensure_ai()
	var action: Dictionary = MapPlayDiplomacyPick.plan(play).get("action", {}) as Dictionary
	var stage: String = DiplomacyCatalog.next_stage(
		play.diplomacy.overture(faction, tribe)
	)
	var pick: Dictionary = MapPlayColonyPick.pick(play)
	assert_eq(int(pick.get("target", -1)), tribe, "the chain is the one read")
	var said: String = MapPlayPickProse.sentence(String(pick.get("line", "")))
	if MapPlayColonyPick.envoy_gives(action, {"target": tribe, "stage": stage}):
		assert_eq(
			String(pick.get("kind", "")), MapPlayColonyPick.KIND_CHAIN,
			"the one order is this link"
		)
		return
	assert_eq(
		String(pick.get("kind", "")), MapPlayColonyPick.KIND_ENVOY,
		"a link the one order does not take reads the wait it is"
	)
	assert_eq(int(pick.get("other", -1)), int(action.get("target", -1)))
	var other: int = int(action.get("target", -1))
	if other >= 0:
		assert_true(
			said.contains(FactionCatalog.name_of(other)),
			"the wait names the court the one order went to: " + said
		)
	else:
		assert_true(said.contains("gives the turn no order"), said)


## The sheet prints the reading it is handed and hides it when the reading is
## empty, so a session with no chain carries no gold line (REQ-P5-06).
func test_the_colonies_print_and_hide_the_counsel_they_are_handed() -> void:
	_attach()
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	var wired: Callable = panel.counsel_source
	panel.counsel_source = (
		func(_data: Dictionary) -> String:
			return "The court would offer the Guaraní a Trade Consulate this turn."
	)
	panel.open()
	assert_eq(
		panel.counsel_text(), "The court would offer the Guaraní a Trade Consulate this turn."
	)
	assert_true(panel._counsel.visible, "the sheet prints the line")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	# The case hands the panel back wired as the session left it, so a later case
	# reads the boot's own reading rather than this one's stand-in.
	panel.counsel_source = wired
	panel.close()


## The reading is the pass's own: THE COLONIES names the Tribe the crown's colony
## chain is buying, and no envoy step is signed by the reading (REQ-P2-03,
## REQ-P5-06; DR-20261121-16).
func test_the_colonies_name_the_tribe_the_crowns_pass_is_buying() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ColonyLedgerPanel = screen.hud.colonies_ledger
	assert_not_null(panel, "the HUD mounts the colony ledger")
	assert_true(panel.counsel_source.is_valid(), "the sheet binds the pass's reading")
	var before: Array = _colony_overtures(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.COLONIES)
	var counsel: String = panel.counsel_text()
	var pick: Dictionary = MapPlayColonyPick.pick(play)
	assert_eq(counsel, MapPlayPickProse.sentence(String(pick.get("line", ""))))
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(), "the line stands with its reading"
	)
	if not pick.is_empty():
		var target: int = int(pick.get("target", -1))
		if target >= 0:
			assert_true(
				counsel.contains(FactionCatalog.name_of(target)),
				"the line names the Tribe the court is buying"
			)
		assert_true(
			counsel.begins_with("The court would offer ")
			or counsel.begins_with("The court's chain with "),
			counsel
		)
	assert_eq(_colony_overtures(play), before, "a reading, not an envoy step")
	panel.close()


## Every Tribe's overture stage with the crown, so a reading can be proved not to
## have signed one.
func _colony_overtures(play: PlaySession) -> Array:
	var stages: Array = []
	for tribe: int in FactionCatalog.tribe_ids():
		stages.append(play.diplomacy.overture(play.player_faction, tribe))
	return stages


## The colony fixture: two charts where the first Tribe holds the New World land
## and a second holds the Old World's, so a chart filter has something to narrow.
func _colony_regions() -> Array[Dictionary]:
	var old: MapModel = Naval.build()
	var new: MapModel = Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = true
	new.provinces[1].name = "Tenochtitlan"
	new.provinces[1].capital = false
	for province: ProvinceState in new.provinces:
		province.owner = _colony_tribe()
	for province: ProvinceState in old.provinces:
		province.owner = _second_tribe()
	return [
		{"region": FactionCatalog.OLD_WORLD, "model": old},
		{"region": FactionCatalog.NEW_WORLD, "model": new},
	]


func _colony_state() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	state.ensure_relation(0, _colony_tribe(), 1)
	state.ensure_relation(0, _colony_parent(), 1)
	state.set_colony(_colony_tribe(), _colony_parent())
	return state


func _colony_tribe() -> int:
	return int(FactionCatalog.tribe_ids()[0])


func _second_tribe() -> int:
	return int(FactionCatalog.tribe_ids()[1])


func _colony_parent() -> int:
	return 1


## The court ledger's COLONIES door, found by its word so the suite presses the
## button the player presses.
func _colonies_door() -> Button:
	for node: Node in screen.hud._diplomacy_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("COLONIES"):
			return button
	return null


func _colony_row_widgets(panel: ColonyLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ColonyLedgerRow:
			total += 1
	return total


func _colony_row(panel: ColonyLedgerPanel) -> ColonyLedgerRow:
	for child: Node in panel._rows.get_children():
		if child is ColonyLedgerRow:
			return child
	return null


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
##
## One chart, two widths: the phone read resizes the viewport the desktop read
## mounted rather than booting a second `MapScreen` for it (docs/testing.md
## § Speed rules). A phone rotated in play reflows the same HUD, so the case
## proves what a player's screen does.
func test_every_sheet_reads_its_prose_across_at_desktop_and_phone_widths() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var chart: MapScreen = Fixture.attach_screen(viewport)
	await get_tree().process_frame
	await get_tree().process_frame
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(914, 411)]:
		viewport.size = size
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


## The sheet names what the level pays, not only what the step costs: the
## manufacture bonus the Extraction phase grants that level and the works its
## level opens, read off the same terms the crew's order row prints (wiki:
## extraction-and-improvements § Town manufacturing bonus; DR-20261118-06).
func test_a_ready_town_names_what_the_level_pays() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var home: Dictionary = _row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(
		String(home["preview_text"]),
		"L2 pays 1 manufacture per 4 raw its own estates deliver"
		+ " · the Garments works need a level-2 town",
		"the row prices the level, not only the step"
	)
	assert_eq(
		TownTerms.level_line(int(home["next_level"])),
		String(home["preview_text"]),
		"one wording for the sheet and the crew's order row"
	)


## A finished town and one a Builder is already raising have no level to price,
## so the sheet prints no payoff line for them — the walls sheet's own rule
## (REQ-P2-03; DR-20261118-06).
func test_a_town_with_no_step_to_price_prints_no_payoff() -> void:
	var snapshot: Dictionary = TownLedger.snapshot(_town_regions(_builders()), 0)
	var overseas: Dictionary = _row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(String(overseas["state"]), TownLedger.STATE_DEVELOPED)
	assert_eq(
		String(overseas.get("preview_text", "")), "", "a finished town owes nothing"
	)
	var builder: CivilianState = CivilianState.create(1, 0, "builder", TOWN_TILE)
	builder.start_work("upgrade_town", TOWN_TILE, 2, TOWN_TILE, {"town_level": 2})
	var at_work: Dictionary = _row(
		TownLedger.snapshot(_town_regions([builder]), 0), FactionCatalog.OLD_WORLD
	)
	assert_eq(String(at_work["state"]), TownLedger.STATE_AT_WORK)
	assert_eq(
		String(at_work.get("preview_text", "")), "", "the works in hand are the news"
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
		CivilianWorkRefusals.town_upgrade(
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


## The head of a row is minted once for every raise sheet: the province, the
## chart it stands on and the level as the court reads it, so a town, a wall and
## a ward can never disagree about what a row is (REQ-P3-01; DR-20261116-01).
func test_the_spine_mints_the_head_every_raise_row_carries() -> void:
	var province: ProvinceState = Naval.build().provinces[0]
	var head: Dictionary = RaiseLedger.row_head(
		province, FactionCatalog.NEW_WORLD, 3, "III"
	)
	assert_eq(int(head["id"]), province.id, "the press reads the province by its id")
	assert_eq(int(head["region"]), FactionCatalog.NEW_WORLD, "the chart the row stands on")
	assert_eq(
		String(head["region_label"]), FactionCatalog.region_label(FactionCatalog.NEW_WORLD)
	)
	assert_eq(String(head["name"]), String(province.name))
	assert_eq(bool(head["capital"]), province.capital)
	assert_eq(int(head["level"]), 3)
	assert_eq(String(head["level_text"]), "III")
	var town_row: Dictionary = _row(
		TownLedger.snapshot(_town_regions(_builders()), 0), FactionCatalog.OLD_WORLD
	)
	var wall_row: Dictionary = _row(
		WallLedger.snapshot(_wall_regions(_engineers()), 0), FactionCatalog.OLD_WORLD
	)
	for key: String in head.keys():
		assert_true(town_row.has(key), "a town row carries the shared head: %s" % key)
		assert_true(wall_row.has(key), "a wall row carries the shared head: %s" % key)


## A row's middle names the crew at the step and the price the press would pay,
## so the row and the order can never disagree (REQ-P2-03).
func test_the_spine_mints_the_step_fields_every_raise_row_carries() -> void:
	var builder: CivilianState = CivilianState.create(1, 0, "builder", TOWN_TILE)
	builder.start_work("upgrade_town", TOWN_TILE, 2, TOWN_TILE, {"town_level": 2})
	var step: Dictionary = RaiseLedger.row_step(
		TownLedger.STATE_AT_WORK, builder, "4 lumber + 4 cast iron", 2
	)
	assert_eq(String(step["state"]), TownLedger.STATE_AT_WORK)
	assert_eq(String(step["crew"]), builder.display_name(), "the crew that works it")
	assert_eq(int(step["remaining"]), 2, "the wait it still owes")
	assert_eq(String(step["cost_text"]), "4 lumber + 4 cast iron")
	assert_eq(int(step["turns"]), 2)
	var empty: Dictionary = RaiseLedger.row_step(TownLedger.STATE_NO_BUILDER, null, "—", 1)
	assert_eq(String(empty["crew"]), "", "no crew, no name")
	assert_eq(int(empty["remaining"]), 0)


## One wait, one wording: a single turn is never "1 turns" (REQ-P5-03).
func test_the_spine_prints_one_wait_for_a_step_however_long() -> void:
	assert_eq(RaiseLedger.turn_text(1), "1 turn")
	assert_eq(RaiseLedger.turn_text(3), "3 turns")
	assert_eq(RaiseLedger.turns_left(1), "1 turn left")
	assert_eq(RaiseLedger.turns_left(2), "2 turns left")
	assert_eq(
		RaiseLedger.next_note("wood fort", "3 lumber", 1), "Next: wood fort · 3 lumber · 1 turn"
	)
	assert_eq(
		RaiseLedger.next_note("field hospital", "3 lumber", 2),
		"Next: field hospital · 3 lumber · 2 turns"
	)


## The note a crew already at the work leaves names who works it and what it
## raises; a crown with no free hand names the crew it must train.
func test_the_spine_names_the_crew_the_step_and_the_training_a_wait_needs() -> void:
	var builder: CivilianState = CivilianState.create(1, 0, "builder", TOWN_TILE)
	builder.start_work("upgrade_town", TOWN_TILE, 2, TOWN_TILE, {"town_level": 2})
	assert_eq(
		RaiseLedger.at_work_note(builder, "it to II"),
		"%s raises it to II · 2 turns left." % builder.display_name()
	)
	assert_eq(
		RaiseLedger.no_crew_note("Builder"),
		"No idle Builder musters — train one at the capital."
	)
	assert_eq(
		RaiseLedger.no_crew_note("Engineer"),
		"No idle Engineer musters — train one at the capital."
	)


## The numeral is the sheet's own table, clamped to the ceiling its domain
## allows, so a level past the top still prints the sheet's top numeral (P1).
func test_the_spine_clamps_the_numeral_to_the_sheet_table() -> void:
	var walls: Array[String] = ["—", "I", "II", "III"]
	assert_eq(RaiseLedger.numeral(walls, 0, 3), "—", "an open shore is a dash")
	assert_eq(RaiseLedger.numeral(walls, 2, 3), "II")
	assert_eq(RaiseLedger.numeral(walls, 9, 3), "III", "past the top, the top numeral")
	var towns: Array[String] = ["", "I", "II", "III", "IV"]
	assert_eq(RaiseLedger.numeral(towns, 0, 4, 1), "I", "a town never prints a blank level")
	assert_eq(RaiseLedger.numeral(towns, 9, 4, 1), "IV")


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
	# The estates press reads its own noun on the same line (DR-20261116-06).
	assert_eq(
		RaiseLedger.batch_receipt(
			{"raised": 2, "total": 5, "refusal": "Stores are short of 1 lumber."},
			"estates"
		),
		"Raised 2 of 5 estates. The next waits: Stores are short of 1 lumber."
	)


# --- the line under the press -------------------------------------------------


## Two crown towns a Builder could raise, one level apart, on known stores: the
## fixture the line is walked over.
func _two_ready_towns(stock: Dictionary, second_level: int = 2) -> Dictionary:
	var regions: Array[Dictionary] = _town_regions(
		_builders(), {"national_bureaucracy": true}, stock
	)
	var home: MapModel = regions[0]["model"] as MapModel
	home.provinces[1].owner = 0
	home.provinces[1].town_development = second_level
	return TownLedger.snapshot(regions, 0)


## The line the towns sheet prints before the press: the walk's own sum, the
## stores it leaves and the crews it ties up (REQ-P2-03, REQ-P5-06;
## DR-20261118-12).
func test_the_raise_line_prices_every_ready_town_the_press_would_file() -> void:
	var snapshot: Dictionary = _two_ready_towns({"lumber": 40, "castIron": 40})
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 2, "two towns the study and the stores open")
	assert_eq(
		int((targets[0]["cost"] as Dictionary).get("lumber", 0)),
		4,
		"the target carries the row's own price"
	)
	var plan: Dictionary = RaiseLine.plan(targets, snapshot["stores"], 2, "Builder")
	assert_eq(int(plan["count"]), 2, "the walk reads the whole view")
	assert_eq(int(plan["filed"]), 2, "two free Builders carry both")
	assert_eq(int(plan["materials"].get("lumber", 0)), 12, "4 for the level-2 step, 8 for the next")
	assert_eq(int(plan["kept"].get("castIron", 0)), 28, "the stores the line leaves")
	assert_eq(String(plan["refusal"]), "", "nothing waits")
	assert_eq(
		RaiseLine.sheet_line(plan),
		"12 Lumber · 12 Cast Iron · 2 Builders — the stores keep 28 Lumber, 28 Cast Iron.",
		"one line, in the catalogues' own words"
	)


## The crews are the second gate on the line: one order ties one up, so five
## ready towns with one Builder carry one and the sheet says the rest wait
## (REQ-P2-03, REQ-P5-05; DR-20261118-12).
func test_the_raise_line_stops_where_the_free_crews_run_out() -> void:
	var snapshot: Dictionary = _two_ready_towns({"lumber": 40, "castIron": 40})
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	var plan: Dictionary = RaiseLine.plan(targets, snapshot["stores"], 1, "Builder")
	assert_eq(int(plan["filed"]), 1, "the one free Builder carries one step")
	assert_eq(int(plan["crews"]), 1, "and is named as tied up")
	assert_eq(
		String(plan["refusal"]),
		RaiseLedger.no_crew_note("Builder"),
		"the rules' own no-crew sentence is the refusal"
	)
	assert_eq(
		RaiseLine.sheet_line(plan),
		"4 Lumber · 4 Cast Iron · 1 Builder — 1 of 2 waits: "
		+ "No idle Builder musters — train one at the capital.",
		"the sheet names the row that waits and why"
	)


## The stores are the first gate: the walk prices each step against what the
## orders before it leave, so a line the stores cannot carry says so before the
## press (REQ-P2-03, REQ-P5-06; DR-20261118-12). Both towns stand at level 1, so
## each row passes the sheet's own store gate on five lumber and the line's
## second step is what the walk refuses.
func test_the_raise_line_stops_where_the_stores_run_short() -> void:
	var snapshot: Dictionary = _two_ready_towns({"lumber": 5, "castIron": 40}, 1)
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 2, "both steps are open on the sheet's own reading")
	var plan: Dictionary = RaiseLine.plan(targets, snapshot["stores"], 2, "Builder")
	assert_eq(int(plan["filed"]), 1, "the first step is paid, the second is not")
	assert_eq(
		String(plan["refusal"]),
		"Stores are short of 4 lumber.",
		"the work order's own shortfall sentence"
	)
	assert_eq(
		RaiseLine.sheet_line(plan),
		"4 Lumber · 4 Cast Iron · 1 Builder — 1 of 2 waits: Stores are short of 4 lumber.",
		"the line names the wait, not only the sum"
	)


## A sheet whose price moves with the stores — the estates' H8 bootstrap — is
## still walked by the plan: every ready row is priced against what the orders
## before it leave (REQ-P2-03; DR-20261118-12).
func test_the_raise_line_reads_a_price_that_moves_with_the_stores() -> void:
	var targets: Array[Dictionary] = [
		{"tile": Vector2i(1, 1), "cost": {"lumber": 1, "castIron": 1}},
		{"tile": Vector2i(2, 1), "cost": {"lumber": 1, "castIron": 1}},
	]
	var left_seen: Array[int] = []
	var plan: Dictionary = RaiseLine.plan(
		targets, {"lumber": 40, "castIron": 40}, 2, "Builder",
		func(_row: Dictionary, left: Dictionary) -> Dictionary:
			left_seen.append(int(left.get("lumber", 0)))
			return {"lumber": 1, "castIron": 1}
	)
	assert_eq(left_seen.size(), 2, "every ready row is priced")
	assert_eq(left_seen[1], 39, "the second reads the stores the first left")
	assert_eq(int(plan["filed"]), 2, "the line is carried")


## A crown that holds a Builder on each chart: the hands the press can send are
## the chart's own, so a New World Builder raises no Old World town
## (DR-20261118-17).
func test_the_raise_line_spends_only_the_hands_of_a_row_s_own_chart() -> void:
	var old_home: Array = [CivilianState.create(1, 0, "builder", TOWN_TILE)]
	var new_home: Array = [CivilianState.create(2, 0, "builder", TOWN_TILE)]
	var regions: Array[Dictionary] = _town_regions(
		old_home, {"national_bureaucracy": true}, {"lumber": 40, "castIron": 40}, new_home
	)
	# Both Old World towns stand at level 1 and the colony's at level 3, so the
	# walk meets the old chart's two steps before the new chart's one — the state
	# the towns sheet is really read in.
	var old_model: MapModel = regions[0]["model"] as MapModel
	old_model.provinces[1].owner = 0
	old_model.provinces[1].town_development = 1
	(regions[1]["model"] as MapModel).provinces[0].town_development = 3
	var snapshot: Dictionary = TownLedger.snapshot(regions, 0)
	var targets: Array[Dictionary] = RaiseLedger.ready_targets(snapshot, LedgerRows.REGION_ALL)
	assert_eq(targets.size(), 3, "two Old World towns and one New World town are ready")
	var hands: Dictionary = RaiseLedger.free_crews(snapshot["crews_by_region"], "builder")
	assert_eq(int(hands.get(FactionCatalog.OLD_WORLD, 0)), 1, "one Builder stands on the old chart")
	assert_eq(int(hands.get(FactionCatalog.NEW_WORLD, 0)), 1, "and one on the new")
	# One purse for the whole realm spends both hands on the old chart's towns and
	# promises a second order the old chart's single Builder cannot take.
	var pooled: Dictionary = RaiseLine.plan(targets, snapshot["stores"], 2, "Builder")
	assert_eq(int(pooled["filed"]), 2, "a pooled walk reads both hands as the old chart's")
	# The hands a crew can be sent with are the chart's own, and that is the walk
	# the press files (DR-20261118-17).
	var plan: Dictionary = RaiseLine.plan(
		targets, snapshot["stores"], 2, "Builder", Callable(), hands
	)
	assert_eq(int(plan["filed"]), 1, "one Old World Builder carries one Old World town")
	assert_eq(int(plan["crews"]), 1, "and is the one hand the line names")
	assert_eq(
		String(plan["refusal"]),
		RaiseLedger.no_crew_note("Builder"),
		"the second Old World town waits on a hand of its own chart"
	)
	assert_eq(
		RaiseLine.sheet_line(plan),
		"4 Lumber · 4 Cast Iron · 1 Builder — 2 of 3 wait: "
		+ "No idle Builder musters — train one at the capital.",
		"the line says what the press can file, not what the realm holds"
	)


## One step on each chart, with a hand on each: the line carries both, because
## neither chart's Builder is spent on the other's town (DR-20261118-17).
func test_the_raise_line_carries_a_step_on_each_chart_that_holds_a_hand() -> void:
	var targets: Array[Dictionary] = [
		{"region": FactionCatalog.OLD_WORLD, "cost": {"lumber": 4}},
		{"region": FactionCatalog.NEW_WORLD, "cost": {"lumber": 4}},
	]
	var hands: Dictionary = {
		FactionCatalog.OLD_WORLD: 1,
		FactionCatalog.NEW_WORLD: 1,
	}
	var plan: Dictionary = RaiseLine.plan(
		targets, {"lumber": 40}, 2, "Builder", Callable(), hands
	)
	assert_eq(int(plan["filed"]), 2, "each chart's own Builder carries its own town")
	assert_eq(int(plan["crews"]), 2, "both hands are tied up")
	assert_eq(String(plan["refusal"]), "", "nothing waits")


## The snapshot reads the hands chart by chart, so a sheet can never spend a crew
## where it does not stand (DR-20261118-17).
func test_the_snapshot_reads_its_free_crews_chart_by_chart() -> void:
	var regions: Array[Dictionary] = _town_regions(
		_builders(), {"national_bureaucracy": true}, {"lumber": 40, "castIron": 40}
	)
	regions[1]["units"] = [] as Array[CivilianState]
	var snapshot: Dictionary = TownLedger.snapshot(regions, 0)
	var by_region: Dictionary = snapshot["crews_by_region"]
	assert_eq(
		int(((by_region[FactionCatalog.OLD_WORLD] as Dictionary).get("builder", 0))),
		1,
		"the old chart's roster holds the Builder"
	)
	assert_eq(
		int(((by_region[FactionCatalog.NEW_WORLD] as Dictionary).get("builder", 0))),
		0,
		"the new chart holds none, and the sheet says so"
	)


# --- towns: the sheet ---


# --- the crown's estates: the one press --------------------------------------


## The estates reading and its ready walk: the press files the rows the view
## prints that the Build gate opens, in the order it prints them, and a narrowed
## reading narrows the press (REQ-P5-04; DR-20261116-06).
func test_the_estates_ready_walk_reads_only_the_rows_the_view_prints() -> void:
	var groups: Array[Dictionary] = [
		{
			"id": 0,
			"name": "Cádiz",
			"rows": [
				{"tile": Vector2i(1, 1), "can_build": true, "status": "vacant"},
				{"tile": Vector2i(2, 1), "can_build": false, "status": "maxed"},
				{"tile": Vector2i(3, 1), "can_build": true, "status": "producing"},
			],
		},
		{
			"id": 1,
			"name": "Coro",
			"rows": [
				{"tile": Vector2i(4, 1), "can_build": true, "status": "vacant"},
			],
		},
	]
	var all_ready: Array[Vector2i] = EstateLedger.ready_tiles(groups, "all")
	assert_eq(all_ready.size(), 3, "every open row is a target")
	assert_eq(all_ready[0], Vector2i(1, 1), "the sheet's own order leads")
	assert_eq(all_ready[1], Vector2i(3, 1), "a closed row is skipped, not reordered")
	assert_eq(all_ready[2], Vector2i(4, 1), "the second province follows")
	assert_eq(
		EstateLedger.ready_tiles(groups, "ready").size(), 3,
		"the ready reading is the same walk"
	)
	var vacant: Array[Vector2i] = EstateLedger.ready_tiles(groups, "vacant")
	assert_eq(vacant.size(), 2, "a narrowed reading narrows the press")
	assert_eq(vacant[1], Vector2i(4, 1), "and keeps the sheet's order")
	assert_eq(
		EstateLedger.ready_tiles(groups, "issues").size(), 0,
		"a reading with nothing open offers no press"
	)


## One arm, one confirm, and every ready estate the view prints takes a Builder —
## the receipt is the one line the court reads (REQ-P5-04, REQ-P5-05;
## DR-20261116-06).
func test_the_estates_press_files_every_ready_estate_in_one_confirmed_press() -> void:
	_attach()
	var panel: ImprovementPanel = screen.improvements
	var stock: Dictionary = screen.play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	panel.open()
	var ready: Array[Vector2i] = panel.ready_tiles()
	assert_true(
		ready.size() >= 2,
		"the capital holds estates the crown can raise: %d" % ready.size()
	)
	# One Builder per ready estate, so the walk files them all.
	for index in ready.size():
		screen.play.civilian_layer.units.append(
			CivilianState.create(
				400 + index, screen.play.player_faction, "builder", ready[index]
			)
		)
	panel.refresh()
	var press: RaiseBatchPress = panel._batch
	assert_not_null(press, "the card carries the batch press")
	assert_true(press.visible, "the press stands when the view holds a ready estate")
	assert_eq(
		press.text, "Raise all ready (%d)" % ready.size(), "the press names the count"
	)
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(
		press.text, "Confirm — raise %d estates" % ready.size(), "the second tap is named"
	)
	press.pressed.emit()
	assert_false(press.is_armed(), "the press forgets the arm once it files")
	assert_eq(
		_working_estate_builders(), ready.size(), "every ready estate took a Builder"
	)
	assert_eq(panel.ready_tiles().size(), 0, "the view holds no ready estate after the press")
	assert_false(press.visible, "and the press stands down")


## The estates card prices the line under its press: the stores the ready estates
## take and the Builders they tie up, printed before the second tap
## (REQ-P2-03, REQ-P5-06; DR-20261118-12).
func test_the_estates_sheet_prints_the_line_its_press_would_spend() -> void:
	_attach()
	var panel: ImprovementPanel = screen.improvements
	_cancel_works()
	var stock: Dictionary = screen.play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	panel.open()
	var ready: Array[Vector2i] = panel.ready_tiles()
	assert_gte(ready.size(), 1, "the capital holds an estate the crown can raise")
	screen.play.civilian_layer.units.append(
		CivilianState.create(700, screen.play.player_faction, "builder", ready[0])
	)
	panel.refresh()
	assert_true(panel._line.visible, "the card prices the line under its press")
	assert_true(panel._line.text.contains("Builder"), panel._line.text)
	assert_true(
		panel._line.text.contains("stores keep") or panel._line.text.contains(" wait"),
		panel._line.text
	)


## A card that opens fresh never carries an arm from the last visit, so one tap
## on a reopened sheet can never spend the stores (REQ-P5-04).
func test_the_estates_press_forgets_its_arm_when_the_card_reopens() -> void:
	_attach()
	var panel: ImprovementPanel = screen.improvements
	panel.open()
	var press: RaiseBatchPress = panel._batch
	if not press.visible:
		return
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap arms")
	panel.close()
	panel.open()
	assert_false(press.is_armed(), "a reopened card carries no arm")


## A press with no session behind it files nothing and prints nothing, so a
## screen torn down mid-press cannot raise an order on a freed chart.
func test_the_estates_press_files_nothing_without_a_session() -> void:
	MapPlayImprovements.raise_all(null, [Vector2i(1, 1)])
	assert_true(true, "a null session is a no-op")


## The estates ledger's own raise reading (DR-20261121-10): the estates the
## published Builder pass would raise, worded in the order the sheet prints its
## rows and capped so a rich plan stays one line of chrome (REQ-P5-06, REQ-P5-07).
func test_the_estates_pick_words_the_raise_in_the_ledgers_row_order() -> void:
	var snapshot: Dictionary = {
		"counts": {"idle_builders": 2},
		"groups": [
			{
				"id": 0,
				"name": "Cádiz",
				"rows": [{"tile": Vector2i(1, 1)}, {"tile": Vector2i(2, 1)}],
			},
			{"id": 1, "name": "Sevilla", "rows": [{"tile": Vector2i(3, 1)}]},
		],
	}
	var estates: Array[Dictionary] = [
		{"tile": Vector2i(3, 1), "name": "mine", "place": "Sevilla"},
		{"tile": Vector2i(1, 1), "name": "lumber camp", "place": "Cádiz"},
	]
	var pick: Dictionary = MapPlayEstatesPick.of(estates, snapshot)
	assert_eq(String(pick["kind"]), MapPlayEstatesPick.KIND_RAISE)
	assert_eq(
		String(pick["line"]),
		"the court would raise the lumber camp at Cádiz and the mine at Sevilla this phase"
	)
	assert_eq(
		MapPlayPickProse.sentence(String(pick["line"])),
		"The court would raise the lumber camp at Cádiz and the mine at Sevilla this phase."
	)
	# Beyond three the line counts the rows it cannot name.
	var many: Array[Dictionary] = []
	for index in 5:
		many.append({"tile": Vector2i(index, 1), "name": "farm", "place": "P%d" % index})
	assert_eq(
		String(MapPlayEstatesPick.of(many, {})["line"]),
		"the court would raise the farm at P0, the farm at P1, the farm at P2 and 2 more this phase"
	)


## No estate is raised: the ledger's own count names the gate when no Builder
## stands idle, and a snapshot that has not read the roster names nothing
## (REQ-P5-06).
func test_the_estates_pick_names_the_gate_when_no_builder_stands_idle() -> void:
	var none: Array[Dictionary] = []
	var idle: Dictionary = MapPlayEstatesPick.of(none, {"counts": {"idle_builders": 0}})
	assert_eq(String(idle["kind"]), MapPlayEstatesPick.KIND_NO_BUILDER)
	assert_eq(String(idle["line"]), MapPlayEstatesPick.NO_BUILDER_LINE)
	assert_true(
		MapPlayEstatesPick.of(none, {"counts": {"idle_builders": 2}}).is_empty(),
		"a Builder stands idle, so the pass books it elsewhere and the page names nothing"
	)
	assert_true(
		MapPlayEstatesPick.of(none, {}).is_empty(),
		"a snapshot with no count names no gate"
	)


## The reading is the pass's own: an idle Builder of the crown on a level-0
## estate is named with the estate the published planner would raise, the card
## prints it, and the plan is not applied (REQ-P2-03, REQ-P5-06; DR-20261121-10).
func test_the_estates_pick_names_the_estate_the_crowns_builder_would_raise() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ImprovementPanel = screen.improvements
	_cancel_works()
	var stock: Dictionary = play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	panel.open()
	var ready: Array[Vector2i] = panel.ready_tiles()
	assert_gte(ready.size(), 1, "the capital holds an estate the crown can raise")
	var tile: Vector2i = ready[0]
	play.civilian_layer.units.append(
		CivilianState.create(900, play.player_faction, "builder", tile)
	)
	panel.refresh()
	var pick: Dictionary = MapPlayEstatesPick.pick(play, panel._data)
	assert_eq(
		String(pick["kind"]), MapPlayEstatesPick.KIND_RAISE, "the Builder is given an estate"
	)
	var tiles: Array[Vector2i] = []
	for raw: Variant in pick["estates"]:
		var estate: Dictionary = raw
		tiles.append(Vector2i(estate["tile"]))
		assert_false(String(estate["name"]).is_empty(), "every estate names its work")
		assert_false(String(estate["place"]).is_empty(), "and the province it stands in")
	# One estate per estate pick the crew pass books, so the ledger cannot name a
	# raise the pass would not book (REQ-P2-03).
	var crew: Dictionary = MapPlayCivilianPick.picks(play, play.player_faction)
	var expected: int = 0
	for raw: Variant in crew.values():
		if String((raw as Dictionary).get("action", "")) == MapPlayEstatesPick.ACTION_ESTATE:
			expected += 1
	assert_eq(tiles.size(), expected, "one estate per estate pick")
	assert_true(
		panel.counsel_text().begins_with("The court would raise the "),
		panel.counsel_text()
	)
	assert_true(panel._counsel.visible, "the card prints the reading")
	assert_eq(_working_estate_builders(), 0, "a reading, not an order")


## The card prints the reading it is handed and hides it when the reading is
## empty, so a sheet with no planner carries no gold line (REQ-P5-06).
func test_the_estates_card_prints_and_hides_the_counsel_it_is_handed() -> void:
	_attach()
	var panel: ImprovementPanel = screen.improvements
	panel.counsel_source = (
		func(_data: Dictionary) -> Dictionary:
			return {"line": "the court would raise the farm at Cádiz"}
	)
	panel.open()
	assert_eq(panel.counsel_text(), "The court would raise the farm at Cádiz.")
	assert_true(panel._counsel.visible, "the card prints the line")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired card prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	panel.close()
	# Hand the session's own reading back, so a later case reads the pass again:
	# a lambda owned by this case dies with it.
	MapPlaySetup.build_hud(screen.play)


## The pick keys the tiles it names, so a ledger row can wear the mark with one
## lookup and a row the pass would leave alone never looks busy (DR-20261122-04).
func test_the_estates_pick_keys_the_estates_it_names() -> void:
	var estates: Array[Dictionary] = [
		{"tile": Vector2i(1, 1), "name": "lumber camp", "place": "Cádiz"},
		{"tile": Vector2i(3, 1), "name": "mine", "place": "Sevilla"},
	]
	var pick: Dictionary = MapPlayEstatesPick.of(estates, {})
	var keys: Dictionary = pick.get("keys", {})
	assert_eq(keys.size(), 2, "every estate the line names is keyed")
	assert_true(keys.has(Vector2i(1, 1)), "the lumber camp's own tile")
	assert_true(keys.has(Vector2i(3, 1)), "the mine's own tile")
	assert_false(keys.has(Vector2i(2, 1)), "a tile the reading never named takes no key")
	assert_eq(MapPlayEstatesPick.keys_of([]), {}, "nothing named, nothing marked")
	# The gate names no estate, so it marks none.
	var gate: Dictionary = MapPlayEstatesPick.of([], {"counts": {"idle_builders": 0}})
	assert_eq(gate.get("keys", {}), {}, "the gate marks no row")


## The estates ledger marks exactly the estates the court's own Builder pass
## would raise, so the crown finds the raise among a long page — and the reading
## orders nothing (REQ-P2-03, REQ-P5-03, REQ-P5-06; DR-20261122-04).
func test_the_estates_ledger_marks_the_estates_the_crowns_pass_would_raise() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ImprovementPanel = screen.improvements
	_cancel_works()
	var stock: Dictionary = play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	panel.open()
	var ready: Array[Vector2i] = panel.ready_tiles()
	assert_gte(ready.size(), 1, "the capital holds an estate the crown can raise")
	play.civilian_layer.units.append(
		CivilianState.create(901, play.player_faction, "builder", ready[0])
	)
	panel.refresh()
	var pick: Dictionary = MapPlayEstatesPick.pick(play, panel._data)
	assert_eq(
		String(pick["kind"]), MapPlayEstatesPick.KIND_RAISE, "the Builder is given an estate"
	)
	assert_eq(
		panel.counsel_text(),
		MapPlayPickProse.sentence_of(pick),
		"the sheet prints the pass's own line"
	)
	var keys: Dictionary = pick.get("keys", {})
	assert_gte(keys.size(), 1, "the reading keys the estates it names")
	# Every estate the reading names is on the sheet, and only those rows wear
	# the mark — a row the staff would leave alone never looks busy.
	var shown: Dictionary = {}
	for row: ImprovementRow in _estate_rows(panel):
		var tile: Vector2i = row.data.get("tile", CivilianState.NO_TILE)
		shown[tile] = true
		assert_eq(row.court, keys.has(tile), "a row wears the mark when the court would raise it")
		if row.court:
			assert_true(row._name.text.begins_with(ImprovementRow.COURT_MARK), row._name.text)
	for tile: Vector2i in keys.keys():
		assert_true(shown.has(tile), "the estate the court would raise is on the sheet")
	# A narrowing chip reorders the marks it already read: one read for the page.
	panel._head.set_filter("ready")
	panel._press_filter("ready")
	assert_eq(panel._counsel.keys(), keys, "a chip press keeps the reading it was handed")
	assert_eq(_working_estate_builders(), 0, "the reading orders nothing")
	panel.close()


## The estates card says what its mark means beside the mark, not in the footer a
## compact card drops: the legend stands under the gold line while that reading
## names an estate, and a card that names none explains no glyph
## (REQ-P1-07, REQ-P5-07; DR-20261123-03/07).
func test_the_estates_card_says_what_its_mark_means_beside_the_mark() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ImprovementPanel = screen.improvements
	_cancel_works()
	var stock: Dictionary = play.stockpile()
	for commodity: String in ["lumber", "castIron", "bronze", "paper"]:
		stock[commodity] = 400
	panel.open()
	var footer_hint: Label = panel._footer_box.get_child(0) as Label
	assert_false(
		footer_hint.text.contains("▸"),
		"the mark's meaning is not left to the footer a phone hides"
	)
	assert_eq(
		panel.legend_text(), ImprovementPanel.MARK_LEGEND,
		"the card says what its mark means"
	)
	assert_eq(
		panel.legend_shown(),
		not panel._counsel.keys().is_empty(),
		"the legend stands exactly when a row wears the mark"
	)
	# The legend is the body's, so the compact profile that drops the footer keeps
	# the sentence beside the glyph it explains.
	panel._apply_profile(true, true)
	assert_false(panel._footer_box.visible, "the compact card drops its footer")
	assert_eq(
		panel.legend_shown(),
		not panel._counsel.keys().is_empty(),
		"and keeps the legend beside the mark"
	)
	panel._apply_profile(false, false)
	panel.close()


## Every estate row the ledger prints, in its own order.
func _estate_rows(panel: ImprovementPanel) -> Array[ImprovementRow]:
	var rows: Array[ImprovementRow] = []
	for child: Node in panel._rows.get_children():
		var row := child as ImprovementRow
		if row != null:
			rows.append(row)
	return rows


func _working_estate_builders() -> int:
	var working: int = 0
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit == null or unit.owner != screen.play.player_faction:
			continue
		if unit.work_action() == "build_improvement":
			working += 1
	return working


# --- towns: fixtures ---


## Two charts of the naval fixture: the crown holds Cádiz at home (a level-1
## town) and Veracruz abroad (a finished town), and the rival's Coro carries a
## town of its own that must never reach the reading. `new_units` seats a roster
## of its own on the New World chart, so a case can hold a crew on each chart.
func _town_regions(
	units: Array,
	tech: Dictionary = {"national_bureaucracy": true},
	stockpile: Variant = null,
	new_units: Variant = null
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
			"units": units if new_units == null else new_units,
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


func _refuse_second(_target: Dictionary) -> Dictionary:
	var province_id: int = int(_target["id"])
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


## The sheet prices the raise, so it prices the prize too: the soak and the
## battery the next wall brings, read off the very fort table combat resolves
## against (REQ-P2-03, REQ-P5-06; DR-20261117-05).
func test_a_bare_shore_prices_the_wall_it_offers() -> void:
	var snapshot: Dictionary = WallLedger.snapshot(_wall_regions(_engineers()), 0)
	var home: Dictionary = _wall_row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(
		String(home["preview_text"]),
		"L1 soaks 40 wall hp with 1 gun (+40 hp, +1 gun)",
		"an open shore reads the first wall whole"
	)
	var overseas: Dictionary = _wall_row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(
		String(overseas["preview_text"]),
		"L2 soaks 80 wall hp with 2 guns (+40 hp, +1 gun)",
		"a wood wall's step names only what the level adds"
	)


## No line where there is no raise: a citadel has no level left, and a wall an
## Engineer is already raising has no press to price.
func test_a_finished_wall_and_a_crew_at_work_price_no_raise() -> void:
	var raised: Dictionary = _raised()
	assert_eq(String(raised["state"]), WallLedger.STATE_RAISED)
	assert_eq(String(raised["preview_text"]), "", "a citadel owes nothing")
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", TOWN_TILE)
	engineer.start_work("build_fort", TOWN_TILE, 2, TOWN_TILE, {"fort_level": 2})
	var working: Dictionary = _wall_row(
		WallLedger.snapshot(_wall_regions([engineer]), 0), FactionCatalog.OLD_WORLD
	)
	assert_eq(String(working["state"]), WallLedger.STATE_AT_WORK)
	assert_eq(String(working["preview_text"]), "", "the works in hand are the news")


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
		CivilianWorkRefusals.fort(0, {"mine_engineering": true}, {}),
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
	assert_eq(String(raised["note"]), "Fully walled — 5 guns, 200 wall hp.")
	assert_eq(String(raised["level_text"]), "V")


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


## The note quotes the fort table itself (issue #1314's ladder: 40 × level wall
## HP, one gun a level), so a crown never reads a ladder the combat would not
## fight (wiki: siege-mechanics § Wall Protection, § Emplaced Artillery). The
## note prints one figure per rung the table holds: a three-value note beside a
## five-level ladder told a crown the line topped out at Modern.
func test_the_rule_note_states_what_a_wall_buys() -> void:
	var note: String = WallLedger.rule_note()
	var rungs: PackedStringArray = PackedStringArray()
	for level in range(1, FortRules.MAX_LEVEL + 1):
		rungs.append(str(roundi(FortRules.wall_hp(level))))
	assert_true(
		note.contains("%s wall hp" % " / ".join(rungs)),
		"every rung of the wall's soak is printed, top of the ladder included: " + note
	)
	assert_eq(FortRules.MAX_LEVEL, 5, "the ladder the note is held to")
	assert_true(
		note.contains(str(roundi(FortRules.wall_hp(FortRules.MAX_LEVEL)))),
		"the Star wall's 200 hp is among the figures: " + note
	)
	assert_true(
		note.contains("1–%d emplaced guns" % FortRules.guns(FortRules.MAX_LEVEL)),
		"the battery tops out where the ladder does: " + note
	)
	assert_false(note.contains("10 / 20 / 30"), "the pre-retune ladder is gone")


# --- walls: the sheet ---


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


## The line leads by weight, not by spelling: the heavier class reads first and
## hulls of one class read by their instance number (wiki: ships-and-naval
## § The crown's navy — "the heavier class first, then the instance id").
func test_the_line_reads_the_heavier_class_first_and_hulls_by_number() -> void:
	var fleet := FleetState.in_port(
		1, OWNER, 0,
		["ship_10", "ship_9", "ship_4", "ship_3", "ship_2"],
		{
			"ship_10": "frigate", "ship_9": "frigate", "ship_4": "ironclad",
			"ship_3": "sloop", "ship_2": "carrack",
		}
	)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [fleet])

	var data: Dictionary = NavalLedger.snapshot(_world(), table, OWNER)
	var order: Array[String] = []
	for raw: Variant in data["rows"]:
		order.append(String((raw as Dictionary)["hull"]))

	assert_eq(
		order, ["ship_4", "ship_9", "ship_10", "ship_3", "ship_2"],
		"the ironclad leads the frigates, the frigates read 9 then 10, and the merchant hull trails"
	)


## Two classes of one weight read by their name, so the order never hangs on the
## roster: a Fluyte and a Trader both weigh 1.75.
func test_a_weight_tie_reads_the_class_name() -> void:
	var fleet := FleetState.in_port(
		1, OWNER, 0, ["ship_1", "ship_2"], {"ship_1": "trader", "ship_2": "fluyte"}
	)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [fleet])

	var data: Dictionary = NavalLedger.snapshot(_world(), table, OWNER)
	var order: Array[String] = []
	for raw: Variant in data["rows"]:
		order.append(String((raw as Dictionary)["hull"]))

	assert_eq(order, ["ship_2", "ship_1"], "the Fluyte reads before the Trader")


## A hull id that carries no number reads as text: the sheet never leans on an
## id it cannot parse.
func test_an_unparseable_hull_id_reads_as_text() -> void:
	var fleet := FleetState.in_port(
		1, OWNER, 0,
		["ship_x", "hull_b", "hull_a"],
		{"ship_x": "carrack", "hull_b": "carrack", "hull_a": "carrack"}
	)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [fleet])

	var data: Dictionary = NavalLedger.snapshot(_world(), table, OWNER)
	var order: Array[String] = []
	for raw: Variant in data["rows"]:
		order.append(String((raw as Dictionary)["hull"]))

	assert_eq(order, ["hull_a", "hull_b", "ship_x"], "three equal carracks read by their ids")


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
	assert_true(line.contains("1 warship, 2 merchant hulls"), line)
	assert_true(line.contains("8 holds"), "the merchant hulls' own cargo")
	assert_true(line.contains("strength"))
	var narrowed: String = NavalLedger.summary(
		data, LedgerRows.REGION_OLD, NavalLedger.READING_MERCHANT
	)
	assert_true(narrowed.contains("1 of 2 hulls in the Old World"), "the chart is the denominator")
	assert_true(narrowed.contains("merchant hulls only"))
	assert_true(NavalLedger.note().contains("holds cap"), "the rule a crown buys by is printed")


## The count line names one hull the way a crown says it: the opening home fleet
## flies a single warship, so "1 warships" was the first line a new court read
## (wiki: ships-and-naval § Ship combat and cargo stats; REQ-P5-05).
func test_the_count_line_says_one_warship_and_one_merchant_hull() -> void:
	var table := MapRegionTable.new()
	var trader := FleetState.at_sea(3, OWNER, 0, ["ship_3"], {"ship_3": "trader"})
	table.set_region(FactionCatalog.OLD_WORLD, [trader])
	var line: String = NavalLedger.summary(
		NavalLedger.snapshot(_world(), table, OWNER), LedgerRows.REGION_OLD
	)
	assert_true(line.contains("0 warships, 1 merchant hull · 5 holds"), line)
	var solo := MapRegionTable.new()
	var sloop := FleetState.at_sea(4, OWNER, 0, ["ship_4"], {"ship_4": "sloop"})
	solo.set_region(FactionCatalog.OLD_WORLD, [sloop])
	var one: String = NavalLedger.summary(
		NavalLedger.snapshot(_world(), solo, OWNER), LedgerRows.REGION_OLD
	)
	assert_true(one.contains("1 warship, 0 merchant hulls · 0 holds"), one)


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
	_assert_visit_seal(row._visit, "Open ", "the hull row's Visit")
	row._on_visit()
	assert_eq(seen.size(), 1)
	assert_eq(int((seen[0] as Array)[0]), FactionCatalog.NEW_WORLD)
	assert_eq(int((seen[0] as Array)[1]), 2, "her squadron, not the hull")
	row.free()


# --- navy: the sheet ---


func test_the_muster_rolls_door_opens_the_ledger() -> void:
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	assert_not_null(panel, "the HUD mounts the navy ledger")
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	var door: Button = _navy_door()
	assert_not_null(door, "the muster roll carries the navy door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the muster roll's navy door opens it")
	assert_true(_navy_row_widgets(panel) > 0, "the crown's hulls are listed")
	assert_true(panel._subtitle.text.contains("hulls"), "the count line names the fleet")
	assert_true(_has_text(panel._rows, "holds"), "a squadron heading prints her holds")
	screen.hud.muster_roll.close()


func test_the_readings_narrow_the_sheet() -> void:
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
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
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.bind(screen.play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
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
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	var chart_row := panel._bar.get_child(0) as HBoxContainer
	var reading_row := panel._bar.get_child(1) as HBoxContainer
	assert_eq(_navy_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(_navy_chip_captions(reading_row), ["All hulls", "Warships", "Merchant hulls"])


func test_navy_back_and_the_key_close_the_ledger() -> void:
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
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
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	panel.open()
	assert_true(panel.is_open())
	var row: NavalLedgerRow = _navy_first_row(panel)
	assert_not_null(row, "the campaign floats a hull")
	if row == null:
		return
	_assert_visit_seal(row._visit, "Open ", "the navy sheet's Visit")
	row._visit.pressed.emit()
	assert_false(panel.is_open(), "the sheet sets itself aside")
	assert_not_null(screen.play.ship_layer.selected(), "her squadron is the selection")


# --- navy: the court's own sails ---

## The navy's own reading (DR-20261121-13): the sails the published naval policy
## would order, worded down the sheet's own squadron headings and capped so a
## busy navy stays one line of chrome (REQ-P5-06, REQ-P5-07).
func test_the_navy_pick_words_the_sails_the_pass_would_order() -> void:
	var model: MapModel = Naval.build()
	var zone: int = 0
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_SORTIE, "zone": zone}, "Leopard"
		),
		"the Leopard into the %s" % model.sea_zone_name(zone)
	)
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_PURSUE, "zone": zone}, "Leopard"
		),
		"the Leopard in pursuit into the %s" % model.sea_zone_name(zone)
	)
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_RAID, "zone": zone}, "Leopard"
		),
		"the Leopard for the %s, the first leg toward a hostile coast"
		% model.sea_zone_name(zone)
	)
	# Home names the harbour when she can dock, else the first leg back.
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_HOME, "dock": true, "province": 0}, "Swallow"
		),
		"the Swallow home to %s" % model.province_name(0)
	)
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_HOME, "zone": zone}, "Swallow"
		),
		"the Swallow for the %s, the first leg home" % model.sea_zone_name(zone)
	)
	# A convoy reads as the hull's own move: home with the holds (issue #1258).
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_CONVOY, "zone": zone}, "Swallow"
		),
		"the Swallow home with the holds, toward the %s" % model.sea_zone_name(zone)
	)
	assert_eq(
		MapPlayNavyPick.clause(
			model, {"kind": MapPlayNavyPick.KIND_CONVOY, "dock": true, "province": 0}, "Swallow"
		),
		"the Swallow home with the holds, to %s" % model.province_name(0)
	)
	assert_eq(
		MapPlayNavyPick.clause(model, {"kind": "unknown", "zone": zone}, "Leopard"),
		"",
		"an order this module cannot say prints nothing"
	)
	assert_eq(
		MapPlayNavyPick.clause(model, {"kind": MapPlayNavyPick.KIND_SORTIE}, "Leopard"),
		"",
		"a sail to nowhere prints nothing"
	)
	for kind: String in [
		MapPlayNavyPick.KIND_PURSUE, MapPlayNavyPick.KIND_RAID,
	]:
		assert_eq(
			MapPlayNavyPick.clause(model, {"kind": kind}, "Leopard"),
			"",
			"a %s with no water prints nothing" % kind
		)
	assert_eq(
		MapPlayNavyPick.clause(model, {"kind": MapPlayNavyPick.KIND_HOME, "dock": true}, "Swallow"),
		"",
		"a harbour this module cannot name prints nothing"
	)
	assert_eq(
		MapPlayNavyPick.clause(model, {"kind": MapPlayNavyPick.KIND_HOME}, "Swallow"),
		"",
		"a road home with no water prints nothing"
	)
	assert_eq(MapPlayNavyPick.clause(model, {}, "Leopard"), "", "no order, no clause")
	assert_eq(
		MapPlayNavyPick.clause(model, {"kind": MapPlayNavyPick.KIND_SORTIE, "zone": zone}, ""),
		"",
		"a squadron with no flagship named reads nothing"
	)
	# One line, in the sheet's own heading order, the fourth and beyond counted.
	var squadrons: Array[Dictionary] = [
		{"region": 0, "fleet_id": 2, "line": "the Tern home to Cádiz"},
		{"region": 0, "fleet_id": 1, "line": "the Leopard into the Mar Caribe"},
		{"region": 0, "fleet_id": 3, "line": "the Swallow in pursuit into the Main"},
		{"region": 0, "fleet_id": 4, "line": "the Kite for the Main, the first leg home"},
	]
	var snapshot: Dictionary = {
		"groups": [
			{"region": 0, "fleet": 1},
			{"region": 0, "fleet": 2},
			{"region": 0, "fleet": 3},
			{"region": 0, "fleet": 4},
		],
	}
	assert_eq(
		String(MapPlayNavyPick.of(squadrons, snapshot)["line"]),
		"the court would send the Leopard into the Mar Caribe, the Tern home to"
		+ " Cádiz, the Swallow in pursuit into the Main and 1 more this turn"
	)
	assert_eq(
		MapPlayPickProse.sentence("the court would send the Leopard into the Mar Caribe"),
		"The court would send the Leopard into the Mar Caribe."
	)
	# No snapshot: the pass's own order, read as prose reads a pair.
	var one: Array[Dictionary] = [squadrons[0]]
	var two: Array[Dictionary] = [squadrons[0], squadrons[1]]
	assert_eq(
		String(MapPlayNavyPick.of(one, {})["line"]),
		"the court would send the Tern home to Cádiz this turn"
	)
	assert_eq(
		String(MapPlayNavyPick.of(two, {})["line"]),
		"the court would send the Tern home to Cádiz and the Leopard into the"
		+ " Mar Caribe this turn"
	)
	# An order this module cannot say takes no place on the line.
	var silent: Array[Dictionary] = [squadrons[0], squadrons[1], squadrons[2]]
	silent.append({"region": 0, "fleet_id": 9, "line": ""})
	silent.append(squadrons[3])
	assert_eq(
		String(MapPlayNavyPick.of(silent, {})["line"]),
		"the court would send the Tern home to Cádiz, the Leopard into the Mar"
		+ " Caribe, the Swallow in pursuit into the Main and 1 more this turn"
	)
	assert_true(MapPlayNavyPick.of([], {}).is_empty(), "no squadron, no clause")
	assert_eq(MapPlayNavyPick.pick_line([]), "", "no squadron, no line")
	assert_true(MapPlayNavyPick.gate(0).is_empty(), "no waiting squadron, no gate")
	assert_eq(String(MapPlayNavyPick.gate(2)["line"]), MapPlayNavyPick.NO_ORDER_LINE)
	assert_eq(MapPlayNavyPick.line(null), "", "a session that is not there names nothing")


## The sheet prints the reading it is handed and hides it when the reading is
## empty, so a session with no planner carries no gold line (REQ-P5-06).
func test_the_navy_sheet_prints_and_hides_the_counsel_it_is_handed() -> void:
	_attach()
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	var wired: Callable = panel.counsel_source
	panel.counsel_source = (
		func(_data: Dictionary) -> Dictionary:
			return {
				"squadrons": [{"region": 0, "fleet_id": 1, "line": "the Leopard into the Mar Caribe"}],
				"keys": {"0:1": true},
				"line": "the court would send the Leopard into the Mar Caribe",
			}
	)
	panel.open()
	assert_eq(panel.counsel_text(), "The court would send the Leopard into the Mar Caribe.")
	assert_true(panel._counsel.visible, "the sheet prints the line")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	# The case hands the panel back wired as the session left it, so a later case
	# reads the boot's own reading rather than this one's stand-in.
	panel.counsel_source = wired
	panel.close()


## The reading is the pass's own: a squadron the published policy would sail is
## named on THE CROWN'S NAVY, and nothing is moved or stationed (REQ-P2-03,
## REQ-P5-06; DR-20261121-13).
func test_the_navy_names_the_sails_the_crowns_pass_would_order() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	assert_not_null(panel, "the HUD mounts the navy ledger")
	assert_true(panel.counsel_source.is_valid(), "the session wires the pass's reading")
	var before: Array = _fleet_orders(play)
	panel.open()
	var counsel: String = panel.counsel_text()
	assert_true(
		counsel.is_empty() or counsel.begins_with("The court would send "), counsel
	)
	assert_true(counsel.is_empty() or counsel.ends_with("this turn."), counsel)
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(),
		"the line stands with its reading"
	)
	# A line the pass would not order is not printed: every named clause is one of
	# the pick's own squadrons.
	var pick: Dictionary = MapPlayNavyPick.pick(play, panel._snapshot)
	for raw: Variant in pick.get("squadrons", []):
		var squadron: Dictionary = raw
		var clause: String = String(squadron["line"])
		assert_true(
			counsel.to_lower().contains(clause),
			"every clause is the pass's own: %s" % clause
		)
	assert_eq(_fleet_orders(play), before, "a reading, not an order")
	panel.close()


## A squadron with no station of her own takes the road home: the policy's own
## order, named on THE CROWN'S NAVY, and nothing moves (wiki: ships-and-naval
## § Missions and Movement; DR-20261121-13).
func test_the_navy_names_the_road_home_the_policy_would_give() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	var fleet: FleetState = _sail_a_squadron(play)
	assert_not_null(fleet, "the crown floats a squadron")
	if fleet == null:
		return
	var before: Array = _fleet_orders(play)
	var pick: Dictionary = MapPlayNavyPick.pick(play, {})
	var squadrons: Array = pick.get("squadrons", [])
	assert_gte(squadrons.size(), 1, "the pass gives the afloat squadron her road home")
	var first: Dictionary = squadrons[0] if not squadrons.is_empty() else {}
	assert_eq(int(first.get("fleet_id", -1)), fleet.id, "the squadron the policy sailed")
	var clause: String = String(first.get("line", ""))
	assert_true(clause.contains("home"), clause)
	# The sheet prints that reading under its chips, and moves nothing.
	var wired: Callable = panel.counsel_source
	panel.counsel_source = (
		func(data: Dictionary) -> Dictionary: return MapPlayNavyPick.pick(play, data)
	)
	panel.open()
	assert_true(
		panel.counsel_text().begins_with("The court would send "), panel.counsel_text()
	)
	assert_true(panel.counsel_text().contains(clause), panel.counsel_text())
	assert_true(panel._counsel.visible, "the line stands with its reading")
	assert_eq(_fleet_orders(play), before, "a reading, not an order")
	panel.close()
	panel.counsel_source = wired


## Every squadron the navy's reading names is keyed by her chart and her id, so
## the sheet can mark the heading its line answers — a heading says `fleet`, the
## pick entry `fleet_id`, and one key law reads both (DR-20261122-05).
func test_the_navy_pick_keys_every_squadron_it_names() -> void:
	var squadrons: Array[Dictionary] = [
		{"region": 0, "fleet_id": 4, "line": "the Leopard into the Mar Caribe"},
		{"region": 1, "fleet_id": 2, "line": "the Tern home to Cadiz"},
	]
	var keys: Dictionary = MapPlayNavyPick.of(squadrons, {})["keys"]
	assert_eq(keys.size(), 2, "one key a squadron")
	for raw: Variant in squadrons:
		var squadron: Dictionary = raw
		assert_true(
			keys.has(MapPlayPickProse.row_key(squadron, "fleet_id")),
			"the reading keys the squadron it names"
		)
	# The sheet's own heading carries the id under `fleet`: the same key, so a
	# heading is marked exactly when the line names her.
	assert_true(keys.has(MapPlayPickProse.row_key({"region": 0, "fleet": 4}, "fleet")))
	assert_false(keys.has(MapPlayPickProse.row_key({"region": 1, "fleet": 4}, "fleet")))
	assert_true(MapPlayNavyPick.of([], {}).is_empty(), "no squadron to key")


## THE CROWN'S NAVY marks the squadrons its own gold line names, and no others,
## so a crown finds the sail her staff would order among a long roll — and a shut
## sheet carries no mark (DR-20261122-05, REQ-P5-06).
func test_the_navy_marks_the_squadrons_the_court_would_sail() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: NavalLedgerPanel = screen.hud.navy_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
	assert_true(panel.is_open(), "the crown's navy opens")
	var pick: Dictionary = MapPlayNavyPick.pick(play, panel._snapshot)
	var keys: Dictionary = pick.get("keys", {}) as Dictionary
	assert_eq(panel._counsel.keys(), keys, "the marks come off the one reading the line prints")
	var groups: Array[Dictionary] = NavalLedger.groups(
		panel._snapshot, LedgerRows.REGION_ALL, NavalLedger.READING_ALL
	)
	var marked: int = 0
	for group: Dictionary in groups:
		var named: bool = keys.has(MapPlayPickProse.row_key(group, "fleet"))
		assert_eq(panel._is_marked(group), named, "a heading is marked iff the line names her")
		var head: Control = panel._heading(group, 1)
		var label := head.get_child(0) as Label
		assert_eq(
			label.text.begins_with(ForceLedgerRow.COURT_MARK),
			named,
			"the counsel's mark leads the heading it answers: %s" % label.text
		)
		if named:
			marked += 1
		head.free()
	assert_true(marked <= keys.size(), "no heading wears a mark the reading did not name")
	# A reading of the sheet's own over its live headings: the mark follows the
	# keys it is handed and no other heading, so a pass that names nothing at boot
	# still proves the paint.
	if not groups.is_empty():
		var one: Dictionary = groups[0]
		var key: String = MapPlayPickProse.row_key(one, "fleet")
		var wired: Callable = panel.counsel_source
		panel.counsel_source = (
			func(_data: Dictionary) -> Dictionary:
				return {
					"squadrons": [{"region": int(one["region"]), "fleet_id": int(one["fleet"]), "line": "the Leopard into the Mar Caribe"}],
					"keys": {key: true},
					"line": "the court would send the Leopard into the Mar Caribe",
				}
		)
		panel.refresh()
		assert_eq(panel._counsel.keys(), {key: true}, "the marks follow the handed keys")
		assert_true(panel._is_marked(one), "the named squadron's heading is marked")
		var painted: int = 0
		for child: Node in panel._rows.get_children():
			var box := child as VBoxContainer
			if box == null or box.get_child_count() == 0:
				continue
			var head := box.get_child(0) as Label
			if head != null and head.text.begins_with(ForceLedgerRow.COURT_MARK):
				painted += 1
		assert_eq(painted, 1, "one heading wears the mark the reading named")
		panel.counsel_source = wired
	# A closed sheet asks the pass nothing and marks nothing.
	panel.close()
	panel.refresh()
	assert_eq(panel._counsel.keys(), {}, "a shut sheet carries no mark")
	assert_eq(panel.counsel_text(), "", "and prints no line")


## One of the crown's squadrons afloat off her own harbour, with no station and
## no move spent: the policy's road home is then the order it would give.
func _sail_a_squadron(play: PlaySession) -> FleetState:
	var model: MapModel = play.model
	var port: int = NavalMovement.home_harbour(model, play.player_faction)
	if port < 0:
		return null
	var zones: Array[int] = NavalMovement.province_sea_zones(model, port)
	if zones.is_empty():
		return null
	for region: int in play.ship_layer.regions.region_ids():
		if play.world.region(region) != model:
			continue
		for fleet: FleetState in MapPlayCourt.region_fleets(play, region):
			if fleet == null or fleet.owner != play.player_faction:
				continue
			if fleet.hulls.is_empty():
				continue
			fleet.location = FleetState.Location.AT_SEA
			fleet.province = MapModel.NO_ID
			fleet.sea_zone = zones[0]
			fleet.mission = FleetState.Mission.NONE
			fleet.moved = false
			return fleet
	return null


## Every squadron's orders as the sheet reads them: her station, her move flag
## and the water or harbour she stands in.
func _fleet_orders(play: PlaySession) -> Array:
	var seen: Array = []
	for region: int in play.ship_layer.regions.region_ids():
		for fleet: FleetState in MapPlayCourt.region_fleets(play, region):
			if fleet == null:
				continue
			seen.append("%d:%d:%s:%s:%s" % [
				fleet.id, region, fleet.mission, fleet.moved, fleet.sea_zone
			])
	seen.sort()
	return seen


# --- the crown's army, regiment by regiment ---

## The crown's army, regiment by regiment (wiki: military-armies § The muster
## roll, § The regiments behind an army; DR-20261116-16): the projection reads
## every regiment the crown fields in both charts, standard by standard, and the
## sheet drives it — the muster roll's door, the readings, back and the registry.
## One Godot boot: the projection cases read the muster fixture, the sheet cases
## mount the shared map screen (docs/testing.md).


func test_the_army_reads_every_regiment_of_both_charts() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _armies(), _fleets(), OWNER)
	assert_eq(int(data["total"]), 5, "one row per regiment the crown fields")
	assert_eq((data["groups"] as Array).size(), 3, "one heading per standard")
	assert_eq(ArmyLedger.count(data, LedgerRows.REGION_OLD), 3)
	assert_eq(ArmyLedger.count(data, LedgerRows.REGION_NEW), 2)
	assert_eq(ArmyLedger.army_count(data, LedgerRows.REGION_ALL), 3)
	for raw: Variant in data["rows"]:
		assert_ne(int((raw as Dictionary)["army"]), 3, "the rival's men stay out")


func test_a_regiment_row_reads_its_class_and_its_own_line() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _armies(), _fleets(), OWNER)
	var pikemen: Dictionary = _army_row_for(data, 1, "unit_1")
	assert_eq(String(pikemen["class"]), "Pikemen")
	assert_eq(String(pikemen["reading"]), ArmyLedger.READING_FOOT)
	assert_eq(String(pikemen["role_label"]), "FOOT")
	assert_eq(String(pikemen["line"]), RegimentCatalog.detail_line("pikemen"), "the catalogue's own line")
	assert_eq(String(pikemen["category"]), "Regular infantry")
	assert_true(String(pikemen["state"]).contains("health"), "the row reads its condition")
	assert_eq(String(pikemen["place"]), "Cádiz")


## The reading order is the sheet's own: the foot lead, then the horse, then the
## guns; inside a kind the heavier class, then the instance number.
func test_the_foot_lead_then_the_horse_then_the_guns() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var order: Array[String] = []
	for raw: Variant in data["rows"]:
		order.append(String((raw as Dictionary)["regiment"]))
	assert_eq(order, ["unit_501", "unit_502", "unit_503"], "the foot read before the horse and the guns")
	var guns: Dictionary = _army_row_of(data, "unit_503")
	assert_eq(String(guns["role_label"]), "GUNS")


func test_a_condition_reads_health_chevrons_and_colours() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var wounded: Dictionary = _army_row_of(data, "unit_501")
	assert_true(String(wounded["state"]).contains("20/"), "the health it holds")
	assert_eq(int(wounded["health"]), 20)
	assert_eq(int(wounded["max_health"]), RegimentCondition.max_health("pikemen"))
	var decorated: Dictionary = _army_row_of(data, "unit_502")
	assert_true(String(decorated["state"]).contains("2 chevrons"))
	var laurelled: Dictionary = _army_row_of(data, "unit_503")
	assert_true(String(laurelled["state"]).contains("laurelled +10%"), "the citation's own weight")
	assert_eq(int(laurelled["cited"]), 3)


func test_the_standard_heading_reads_where_it_stands_and_what_it_eats() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _armies(), _fleets(), OWNER)
	var groups: Array[Dictionary] = ArmyLedger.groups(data, LedgerRows.REGION_OLD)
	var home: Dictionary = groups[0]
	assert_eq(String(home["title"]), "Home Army", "the seat leads its chart")
	assert_true(String(home["heading"]).contains("HOME ARMY"))
	assert_eq(String(home["place"]), "Cádiz")
	assert_true(String(home["standing"]).contains("seat"))
	assert_eq(int(home["regiments"]), 2)
	var army: ArmyState = _army_of(_armies(), 1)
	var one: Array[ArmyState] = [army]
	assert_almost_eq(float(home["strength"]), ArmyForce.side_strength(one), 0.001)
	assert_eq(
		int(home["food"]),
		RegimentCatalog.food_upkeep("pikemen") + RegimentCatalog.food_upkeep("arquebusiers")
	)


## A standard's larder bill is the rules' own reading, the same one the dossier
## and the Consumption phase pay: the regiments' upkeep plus the staff of the
## field hospital train it carries (wiki: military-armies § The regiments behind
## an army, combat § Feeding; DR-20261112-07).
func test_a_standard_carrying_a_train_eats_its_staff_too() -> void:
	var table: MapRegionTable = _armies()
	var home: ArmyState = _army_of(table, 1)
	home.field_hospital = true
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), table, _fleets(), OWNER)
	var group: Dictionary = ArmyLedger.groups(data, LedgerRows.REGION_OLD)[0]
	var one: Array[ArmyState] = [home]
	assert_eq(int(group["food"]), ArmyRoster.food_upkeep_of(one, OWNER), "the larder's own bill")
	assert_eq(
		int(group["food"]),
		RegimentCatalog.food_upkeep("pikemen")
		+ RegimentCatalog.food_upkeep("arquebusiers")
		+ HospitalTrain.food(),
		"the train's staff eats with the men"
	)
	var chart: Array[ArmyState] = []
	for raw: Variant in table.value(FactionCatalog.OLD_WORLD, []):
		var army := raw as ArmyState
		if army != null and army.owner == OWNER:
			chart.append(army)
	assert_true(
		ArmyLedger.summary(data, LedgerRows.REGION_OLD).contains(
			"%d food a turn" % ArmyRoster.food_upkeep_of(chart, OWNER)
		),
		"the count line bills the same larder as the Consumption phase"
	)


func test_an_embarked_standard_reads_aboard_its_squadron() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _armies(), _fleets(), OWNER)
	var embarked: Dictionary = _army_row_for(data, 2, "unit_1")
	assert_true(String(embarked["place"]).contains("Aboard a squadron"))
	assert_true(String(embarked["place"]).contains("Cádiz"), "the carrying squadron's station")


## A standard whose carrying squadron the roster no longer holds, and one with
## no shore at all: the reading names the gap instead of inventing a place.
func test_a_standard_without_its_squadron_or_a_shore_reads_the_gap() -> void:
	var table := MapRegionTable.new()
	var adrift: ArmyState = ArmyState.muster(8, OWNER, MapModel.NO_ID, false, ["pikemen"], 801)
	adrift.embarked_fleet = 99
	var ashore: ArmyState = ArmyState.muster(9, OWNER, MapModel.NO_ID, false, ["pikemen"], 901)
	table.set_region(FactionCatalog.OLD_WORLD, [adrift, ashore])
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), table, _fleets(), OWNER)
	assert_eq(String(_army_row_for(data, 8, "unit_801")["place"]), "Aboard a squadron")
	assert_eq(String(_army_row_for(data, 9, "unit_901")["place"]), "In the field")


func test_the_readings_narrow_the_army_and_keep_their_tallies() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var counts: Dictionary = ArmyLedger.filter_counts(data, LedgerRows.REGION_ALL)
	assert_eq(int(counts[ArmyLedger.READING_ALL]), 3)
	assert_eq(int(counts[ArmyLedger.READING_FOOT]), 1)
	assert_eq(int(counts[ArmyLedger.READING_HORSE]), 1)
	assert_eq(int(counts[ArmyLedger.READING_GUNS]), 1)
	assert_eq(ArmyLedger.count(data, LedgerRows.REGION_NEW, ArmyLedger.READING_FOOT), 0)
	var horse: Array[Dictionary] = ArmyLedger.groups(
		data, LedgerRows.REGION_ALL, ArmyLedger.READING_HORSE
	)
	assert_eq(horse.size(), 1, "only the standard that still has a rider")
	for row: Dictionary in horse[0]["rows"]:
		assert_eq(String(row["reading"]), ArmyLedger.READING_HORSE)


func test_the_army_count_line_and_the_note_print_the_rules_own_figures() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var line: String = ArmyLedger.summary(data, LedgerRows.REGION_ALL)
	assert_true(line.contains("3 of 3 regiments in 1 standard"), "the count line reads the standard")
	assert_true(line.contains("1 foot, 1 horse, 1 gun"))
	assert_true(line.contains("strength"))
	assert_true(line.contains("food a turn"))
	var narrowed: String = ArmyLedger.summary(
		data, LedgerRows.REGION_OLD, ArmyLedger.READING_HORSE
	)
	assert_true(narrowed.contains("1 of 3 regiments in the Old World"), "the chart is the denominator")
	assert_true(narrowed.contains("horse only"))
	assert_true(ArmyLedger.note().contains("chevrons"), "the rule a crown fields by is printed")


func test_a_chart_with_no_standard_reads_empty_and_a_standard_without_men_reads_no_row() -> void:
	assert_eq(int(ArmyLedger.snapshot(null, _armies(), _fleets(), OWNER).get("total", -1)), 0)
	assert_eq(int(ArmyLedger.snapshot(_force_world(), null, _fleets(), OWNER).get("total", -1)), 0)
	var bare := ArmyState.muster(7, OWNER, 0, false, [], 1)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [bare])
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), table, _fleets(), OWNER)
	assert_eq(int(data["total"]), 0, "a standard with no regiment has no row to read")
	assert_eq(ArmyLedger.army_count(data, LedgerRows.REGION_ALL), 1, "the standard is still counted")
	assert_eq((data["groups"] as Array).size(), 0, "an empty standard prints no heading")
	assert_true(ArmyLedger.summary(data, LedgerRows.REGION_ALL).contains("0 of 0 regiments"))


# --- army: the row ---


func test_an_army_row_prints_its_name_chip_and_its_own_line() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var row := ArmyLedgerRow.new()
	row.setup(_army_row_of(data, "unit_501"))
	assert_ne(row._name.text, "", "every regiment flies a title")
	assert_eq(row._chip.text, "FOOT")
	assert_true(row._detail.text.contains("Cádiz"))
	assert_true(row._standing.text.contains("FPN"), "the catalogue's own line")
	assert_true(row._reading.text.contains("20/"), "the condition it holds")
	row.free()


func test_a_compact_army_row_folds_its_class_into_the_detail_line() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _line_standard(), _fleets(), OWNER)
	var row := ArmyLedgerRow.new()
	row.compact = true
	row.setup(_army_row_of(data, "unit_502"))
	assert_true(row._detail.text.contains("Knights"), "a phone row names the class")
	assert_true(row._detail.text.contains("Cádiz"))
	row.free()


func test_an_army_visit_asks_for_its_standards_chart() -> void:
	var data: Dictionary = ArmyLedger.snapshot(_force_world(), _armies(), _fleets(), OWNER)
	var row := ArmyLedgerRow.new()
	row.setup(_army_row_for(data, 2, "unit_1"))
	var seen: Array = []
	row.visit_pressed.connect(func(region: int, army_id: int) -> void:
		seen.append([region, army_id])
	)
	row._on_visit()
	assert_eq(seen.size(), 1)
	assert_eq(int((seen[0] as Array)[0]), FactionCatalog.OLD_WORLD)
	assert_eq(int((seen[0] as Array)[1]), 2, "the standard, not the regiment")
	row.free()


# --- army: the sheet ---


func test_the_muster_rolls_army_door_opens_the_army_ledger() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	assert_not_null(panel, "the HUD mounts the army ledger")
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	var door: Button = _army_door()
	assert_not_null(door, "the muster roll carries the army door")
	door.pressed.emit()
	assert_true(panel.is_open(), "the muster roll's army door opens it")
	assert_true(_army_row_widgets(panel) > 0, "the crown's regiments are listed")
	assert_true(panel._subtitle.text.contains("regiments"), "the count line names the army")
	assert_true(_has_text(panel._rows, "strength"), "a standard heading prints its strength")
	screen.hud.muster_roll.close()


func test_the_army_readings_narrow_the_sheet() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	assert_true(panel.is_open())
	panel._on_filter(ArmyLedger.READING_HORSE, false)
	assert_eq(panel._reading, ArmyLedger.READING_HORSE)
	assert_true(panel._subtitle.text.contains("horse only"))
	for child: Node in panel._rows.get_children():
		var row := child as ArmyLedgerRow
		if row != null:
			assert_eq(String(row.data["reading"]), ArmyLedger.READING_HORSE)
	panel._on_filter(LedgerRows.REGION_OLD, true)
	assert_eq(panel._region, LedgerRows.REGION_OLD)
	panel._on_filter(LedgerRows.REGION_ALL, true)
	panel._on_filter(ArmyLedger.READING_ALL, false)


func test_an_emptied_army_names_why_no_regiment_answers() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	panel.bind(screen.play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	assert_true(_army_row_widgets(panel) > 0, "the sheet opens on the crown's regiments")
	# A chart the crown fields nothing in: the whole army answers, this chart not.
	panel._snapshot = ArmyLedger.snapshot(_world(), _old_only_armies(), _fleets(), OWNER)
	panel._region = LedgerRows.REGION_NEW
	panel._apply_filter()
	assert_true(panel._empty.visible, "an empty chart prints the empty line")
	assert_eq(_army_row_widgets(panel), 0, "and the rows the last press left are cleared")
	assert_true(panel._empty.text.contains("No regiment answers this view"))
	# A standard with no men: the sheet names the drill yard rather than a gap.
	var bare := ArmyState.muster(7, OWNER, 0, false, [], 1)
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [bare])
	panel._snapshot = ArmyLedger.snapshot(_world(), table, _fleets(), OWNER)
	panel._region = LedgerRows.REGION_ALL
	panel._apply_filter()
	assert_true(panel._empty.text.contains("the drill yard raises the first"))
	# No standard at all: clearing a filter is the way back.
	panel._snapshot = ArmyLedger.snapshot(_world(), MapRegionTable.new(), _fleets(), OWNER)
	panel._apply_filter()
	assert_true(panel._empty.text.contains("Clear a filter"))
	panel._snapshot = {}
	panel._region = LedgerRows.REGION_ALL
	panel._reading = ArmyLedger.READING_ALL


func test_every_army_chip_names_its_own_reading() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	var chart_row := panel._bar.get_child(0) as HBoxContainer
	var reading_row := panel._bar.get_child(1) as HBoxContainer
	assert_eq(_navy_chip_captions(chart_row), ["Both charts", "Old World", "New World"])
	assert_eq(_navy_chip_captions(reading_row), ["All regiments", "Foot", "Horse", "Guns"])


func test_army_back_closes_the_ledger() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	assert_true(panel.is_open())
	assert_true(BackRequest.handle(screen.play, screen.play.improvements))
	assert_false(panel.is_open(), "back sets the ledger aside first")


## The orders the crown's army prints (DR-20261121-14): one clause per standard,
## the sheet's own heading order, the fourth and beyond counted, and the gate when
## standards wait for an order the pass does not give (REQ-P2-03, REQ-P5-06).
func test_the_army_orders_name_each_standard_and_count_the_rest() -> void:
	var model: MapModel = Naval.build()
	var home := ArmyState.muster(1, OWNER, 0, true, [], 1)
	var field := ArmyState.muster(2, OWNER, 1, false, [], 1)
	var storm: String = model.province_name(1)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, home, {"kind": MapPlayArmyPick.KIND_SPLIT, "regiments": 4}
		),
		"the Home Army to take the field with 4 regiments"
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, home, {"kind": MapPlayArmyPick.KIND_SPLIT, "regiments": 1}
		),
		"the Home Army to take the field with 1 regiment"
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, field, {
				"kind": MapPlayArmyPick.KIND_MARCH,
				"why": MapPlayArmyPick.WHY_STORM,
				"province": 1,
			}
		),
		"the field army at %s to storm %s" % [storm, storm]
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, field, {
				"kind": MapPlayArmyPick.KIND_MARCH,
				"why": MapPlayArmyPick.WHY_RELIEF,
				"province": 1,
			}
		),
		"the field army at %s to throw the host out of %s" % [storm, storm]
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, field, {
				"kind": MapPlayArmyPick.KIND_MARCH,
				"why": MapPlayArmyPick.WHY_FRONTIER,
				"province": 1,
			}
		),
		"the field army at %s to advance to %s, the frontier" % [storm, storm]
	)
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, field, {"kind": MapPlayArmyPick.KIND_ROTATE, "province": 0}
		),
		"the field army at %s home to %s to merge with the Home Army"
		% [storm, model.province_name(0)]
	)
	# An order this module cannot say takes no place on the line.
	assert_eq(MapPlayArmyOrdersPick.clause(model, field, {"kind": "unknown"}), "")
	assert_eq(
		MapPlayArmyOrdersPick.clause(
			model, field, {"kind": MapPlayArmyPick.KIND_MARCH, "why": MapPlayArmyPick.WHY_STORM}
		),
		"",
		"a march to nowhere prints nothing"
	)
	assert_eq(MapPlayArmyOrdersPick.clause(null, field, {"kind": "unknown"}), "")
	assert_eq(MapPlayArmyOrdersPick.clause(model, null, {}), "", "no standard, no clause")
	assert_eq(MapPlayArmyOrdersPick.standard(model, field), "the field army at %s" % storm)
	# One line, in the sheet's own heading order, the fourth and beyond counted.
	var armies: Array[Dictionary] = [
		{"region": 0, "army": 2, "line": "the field army at %s to storm %s" % [storm, storm]},
		{"region": 0, "army": 1, "line": "the Home Army to take the field with 4 regiments"},
		{"region": 0, "army": 3, "line": "the field army at %s to advance to %s, the frontier" % [storm, storm]},
		{"region": 0, "army": 4, "line": "the field army at %s home to %s to merge with the Home Army" % [storm, model.province_name(0)]},
	]
	var snapshot: Dictionary = {
		"groups": [
			{"region": 0, "army": 1},
			{"region": 0, "army": 2},
			{"region": 0, "army": 3},
			{"region": 0, "army": 4},
		],
	}
	assert_eq(
		String(MapPlayArmyOrdersPick.of(armies, snapshot)["line"]),
		(
			"the court would send the Home Army to take the field with 4 regiments, "
			+ "the field army at %s to storm %s, the field army at %s to advance to %s, "
			+ "the frontier and 1 more this turn"
		) % [storm, storm, storm, storm]
	)
	assert_eq(
		MapPlayPickProse.sentence("the court would send the Home Army to take the field"),
		"The court would send the Home Army to take the field."
	)
	assert_true(MapPlayArmyOrdersPick.of([], {}).is_empty(), "no standard, no clause")
	assert_eq(MapPlayArmyOrdersPick.pick_line([]), "", "no standard, no line")
	assert_true(MapPlayArmyOrdersPick.gate(0).is_empty(), "no waiting army, no gate")
	assert_eq(
		String(MapPlayArmyOrdersPick.gate(2)["line"]), MapPlayArmyOrdersPick.NO_ORDER_LINE
	)
	assert_eq(MapPlayArmyOrdersPick.line(null), "", "a session that is not there names nothing")


## Every standard the army's reading names is keyed by its chart and its id, so
## the sheet can mark the heading its line answers (DR-20261122-05).
func test_the_army_pick_keys_every_standard_it_names() -> void:
	var armies: Array[Dictionary] = [
		{"region": 0, "army": 1, "line": "the Home Army to take the field"},
		{"region": 1, "army": 2, "line": "the field army at Tucapel to storm Cadiz"},
	]
	var pick: Dictionary = MapPlayArmyOrdersPick.of(armies, {})
	var keys: Dictionary = pick["keys"] as Dictionary
	assert_eq(keys.size(), 2, "one key a standard")
	for raw: Variant in armies:
		var standard: Dictionary = raw
		assert_true(
			keys.has(MapPlayPickProse.row_key(standard, "army")),
			"the reading keys the standard it names"
		)
	assert_false(keys.has("0:2"), "a standard the line does not name is not keyed")
	assert_true(MapPlayArmyOrdersPick.of([], {}).is_empty(), "no standard to key")


## THE CROWN'S ARMY marks the standards its own gold line names, and no others,
## so a crown finds the standard her staff would order among a long roll — and a
## shut sheet carries no mark (DR-20261122-05, REQ-P5-06).
func test_the_army_marks_the_standards_the_court_would_order() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	assert_true(panel.is_open(), "the crown's army opens")
	var pick: Dictionary = MapPlayArmyOrdersPick.pick(play, panel._snapshot)
	var keys: Dictionary = pick.get("keys", {}) as Dictionary
	assert_eq(panel._counsel.keys(), keys, "the marks come off the one reading the line prints")
	var groups: Array[Dictionary] = ArmyLedger.groups(
		panel._snapshot, LedgerRows.REGION_ALL, ArmyLedger.READING_ALL
	)
	var marked: int = 0
	for group: Dictionary in groups:
		var named: bool = keys.has(MapPlayPickProse.row_key(group, "army"))
		assert_eq(panel._is_marked(group), named, "a heading is marked iff the line names it")
		var head: Control = panel._heading(group, 1)
		var label := head.get_child(0) as Label
		assert_eq(
			label.text.begins_with(ForceLedgerRow.COURT_MARK),
			named,
			"the counsel's mark leads the heading it answers: %s" % label.text
		)
		if named:
			marked += 1
		head.free()
	assert_true(marked <= keys.size(), "no heading wears a mark the reading did not name")
	# A reading of the sheet's own over its live headings: the mark follows the
	# keys it is handed and no other heading, so a pass that names nothing at boot
	# still proves the paint.
	if not groups.is_empty():
		var one: Dictionary = groups[0]
		var key: String = MapPlayPickProse.row_key(one, "army")
		var wired: Callable = panel.counsel_source
		panel.counsel_source = (
			func(_data: Dictionary) -> Dictionary:
				return {
					"armies": [{"region": int(one["region"]), "army": int(one["army"]), "line": "the Home Army to take the field"}],
					"keys": {key: true},
					"line": "the court would send the Home Army to take the field",
				}
		)
		panel.refresh()
		assert_eq(panel._counsel.keys(), {key: true}, "the marks follow the handed keys")
		assert_true(panel._is_marked(one), "the named standard's heading is marked")
		var painted: int = 0
		for child: Node in panel._rows.get_children():
			var box := child as VBoxContainer
			if box == null or box.get_child_count() == 0:
				continue
			var head := box.get_child(0) as Label
			if head != null and head.text.begins_with(ForceLedgerRow.COURT_MARK):
				painted += 1
		assert_eq(painted, 1, "one heading wears the mark the reading named")
		panel.counsel_source = wired
	# A closed sheet asks the pass nothing and marks nothing.
	panel.close()
	panel.refresh()
	assert_eq(panel._counsel.keys(), {}, "a shut sheet carries no mark")
	assert_eq(panel.counsel_text(), "", "and prints no line")


## Every sheet whose rows wear the counsel's ▸ says what the mark means beside the
## mark, not only in the footer a compact sheet drops: the legend stands under the
## gold line while the reading names a row, and stands down when it names none
## (REQ-P1-07, REQ-P5-07).
func test_the_marking_sheets_stand_their_legend_beside_the_marks() -> void:
	_attach()
	var cases: Array[Dictionary] = [
		{"door": HudLedgerDoors.ARMY, "word": "standards"},
		{"door": HudLedgerDoors.NAVY, "word": "squadrons"},
		{"door": HudLedgerDoors.MUSTER, "word": "forces"},
		{"door": HudLedgerDoors.EYES, "word": "spy"},
		{"door": HudLedgerDoors.PROVINCES, "word": "provinces"},
		{"door": HudLedgerDoors.CIVILIANS, "word": "crews"},
	]
	for case: Dictionary in cases:
		var door: String = String(case["door"])
		screen.hud.ledger_door_pressed.emit(door)
		var panel: SheetFrame = _sheet_for(door)
		assert_not_null(panel, "%s mounts a sheet" % door)
		assert_true(panel.is_open(), "%s opens" % door)
		assert_true(
			panel.legend_text().contains(String(case["word"])),
			"%s: the legend says what the mark means — %s" % [door, panel.legend_text()]
		)
		assert_false(
			panel.hint_text.contains("▸"),
			"%s: the mark's meaning is not left to the footer a phone hides" % door
		)
		var marked: bool = not panel._counsel.keys().is_empty()
		assert_eq(
			panel.legend_shown(),
			marked,
			"%s: the legend stands exactly when a row wears the mark" % door
		)
		panel._apply_profile(true, true)
		assert_eq(
			panel.legend_shown(),
			marked,
			"%s: a compact sheet keeps the legend its footer loses" % door
		)
		panel.close()
	# A reading that names no row explains no mark, whatever the sheet it opens on.
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.NAVY)
	var navy: NavalLedgerPanel = screen.hud.navy_ledger
	var wired: Callable = navy.counsel_source
	navy.counsel_source = (
		func(_data: Dictionary) -> Dictionary:
			return {"line": "the court would sail nothing this turn", "keys": {}}
	)
	navy.refresh()
	assert_false(navy.legend_shown(), "a line that names no squadron explains no mark")
	navy.counsel_source = wired
	navy.close()


## The sheet behind one ledger door, for a case that reads more than one sheet.
func _sheet_for(door: String) -> SheetFrame:
	match door:
		HudLedgerDoors.ARMY:
			return screen.hud.army_ledger
		HudLedgerDoors.NAVY:
			return screen.hud.navy_ledger
		HudLedgerDoors.MUSTER:
			return screen.hud.muster_roll
		HudLedgerDoors.EYES:
			return screen.hud.spy_ledger
		HudLedgerDoors.PROVINCES:
			return screen.hud.province_ledger
		HudLedgerDoors.CIVILIANS:
			return screen.hud.civilian_roster
	return null


## The sheet prints the reading it is handed and hides it when the reading is
## empty, so a session with no planner carries no gold line (REQ-P5-06).
func test_the_army_sheet_prints_and_hides_the_counsel_it_is_handed() -> void:
	_attach()
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	var wired: Callable = panel.counsel_source
	panel.counsel_source = (
		func(_data: Dictionary) -> Dictionary:
			return {
				"armies": [{"region": 0, "army": 1, "line": "the Home Army to take the field"}],
				"keys": {"0:1": true},
				"line": "the court would send the Home Army to take the field with 4 regiments",
			}
	)
	panel.open()
	assert_eq(
		panel.counsel_text(), "The court would send the Home Army to take the field with 4 regiments."
	)
	assert_true(panel._counsel.visible, "the sheet prints the line")
	panel.counsel_source = Callable()
	panel.refresh()
	assert_eq(panel.counsel_text(), "", "an unwired sheet prints nothing")
	assert_false(panel._counsel.visible, "and the line stands down")
	# The case hands the panel back wired as the session left it, so a later case
	# reads the boot's own reading rather than this one's stand-in.
	panel.counsel_source = wired
	panel.close()


## The reading is the pass's own: a standard the published land policy would order
## is named on THE CROWN'S ARMY, and nothing is split or marched (REQ-P2-03,
## REQ-P5-06; DR-20261121-14).
func test_the_army_names_the_orders_the_crowns_pass_would_give() -> void:
	_attach()
	var play: PlaySession = screen.play
	var panel: ArmyLedgerPanel = screen.hud.army_ledger
	assert_not_null(panel, "the HUD mounts the army ledger")
	assert_true(panel.counsel_source.is_valid(), "the session wires the pass's reading")
	var before: Array = _army_orders(play)
	screen.hud.ledger_door_pressed.emit(HudLedgerDoors.ARMY)
	var counsel: String = panel.counsel_text()
	var gate: String = MapPlayPickProse.sentence(MapPlayArmyOrdersPick.NO_ORDER_LINE)
	assert_true(
		counsel.is_empty()
		or counsel.begins_with("The court would send ")
		or counsel == gate,
		counsel
	)
	assert_eq(
		panel._counsel.visible, not counsel.is_empty(), "the line stands with its reading"
	)
	# A line the pass would not give is not printed: every named clause is one of
	# the pick's own standards.
	var pick: Dictionary = MapPlayArmyOrdersPick.pick(play, panel._snapshot)
	for raw: Variant in pick.get("armies", []):
		var standard: Dictionary = raw
		var clause: String = String(standard["line"])
		assert_true(
			counsel.to_lower().contains(clause), "every clause is the pass's own: %s" % clause
		)
	assert_eq(_army_orders(play), before, "a reading, not an order")
	panel.close()


## Every standard's place and move flag, so a reading that marched one shows.
func _army_orders(play: PlaySession) -> Array:
	var seen: Array = []
	for region: int in play.army_layer.regions.region_ids():
		for army: ArmyState in MapPlayCourt.visible_armies(play, region):
			if army == null:
				continue
			seen.append("%d:%d:%s" % [army.id, army.province, army.moved])
	seen.sort()
	return seen


## The one dress both forces print in stays inert until a force names itself: a
## bare spine has no layer to read, no projection, no rows and no Visit, so a
## half-wired sheet paints nothing over the chart (REQ-P3-01, REQ-P3-02).
func test_the_force_sheet_dress_reads_nothing_until_a_force_names_it() -> void:
	var sheet := ForceLedgerSheet.new()
	assert_false(sheet._can_open(), "no session, no sheet")
	sheet.refresh()
	assert_true(sheet._snapshot.is_empty(), "a bare spine reads no roster")
	assert_true(sheet._filters().is_empty())
	assert_eq(sheet._reading_word("all"), "all", "an unnamed reading names itself")
	assert_eq(sheet._row_word(1), "row")
	assert_eq(sheet._row_caption(), "Row", "the chip row capitalises the noun")
	assert_true(sheet._groups(LedgerRows.REGION_ALL, LedgerRows.ALL).is_empty())
	assert_eq(sheet._count(LedgerRows.REGION_ALL, LedgerRows.ALL), 0)
	assert_true(sheet._standing_text({}).is_empty(), "no group, no standing line")
	assert_null(sheet._note(), "no rule to print")
	assert_null(sheet._make_row({}, false), "no row to mint")
	sheet.free()


## One standard of three kinds, weakened and decorated, so the row reads the
## condition the rules would use: a wounded foot regiment, a chevroned rider and
## a laurelled gun.
func _line_standard() -> MapRegionTable:
	var table := MapRegionTable.new()
	var army: ArmyState = ArmyState.muster(
		5, OWNER, 0, false, ["pikemen", "knights", "culverin"], 501
	)
	army.regiment_health["unit_501"] = 20
	army.regiment_medals["unit_502"] = 2
	army.regiment_history["unit_503"] = {"cited": 3, "fields": []}
	table.set_region(FactionCatalog.OLD_WORLD, [army])
	return table


## The home chart alone: the New World holds no standard, so a one-chart view has
## an empty page and the whole army still answers.
func _old_only_armies() -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(FactionCatalog.OLD_WORLD, [_army_of(_armies(), 1)])
	return table


func _army_row_of(data: Dictionary, regiment_id: String) -> Dictionary:
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		if String(row["regiment"]) == regiment_id:
			return row
	return {}


func _army_row_for(data: Dictionary, army_id: int, regiment_id: String) -> Dictionary:
	for raw: Variant in data["rows"]:
		var row: Dictionary = raw
		if int(row["army"]) == army_id and String(row["regiment"]) == regiment_id:
			return row
	return {}


## The muster roll's army door, found by its word so the suite reads the button
## the player presses.
func _army_door() -> Button:
	for node: Node in screen.hud.muster_roll.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.begins_with("The crown's army"):
			return button
	return null


func _army_row_widgets(panel: ArmyLedgerPanel) -> int:
	var total: int = 0
	for child: Node in panel._rows.get_children():
		if child is ArmyLedgerRow:
			total += 1
	return total


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

# ==== merged from test_hospital_ledger.gd (one coverage boot; docs/testing.md § Speed rules) ====
## The crown's hospitals: the whole-empire ward ledger reads every province the
## crown holds that can carry a ward, the level it stands at, whether its staff
## ate and the step the Engineer would take next (wiki: combat § Regiment
## condition; DR-20261116-02) and the sheet drives it — the realm's door, the
## Raise press and back. Projection cases read small fixtures; drive cases call
## `_attach()` on the suite's one chart (no second mount under coverage).

const hospital_Naval = preload("res://tests/naval_fixture.gd")
const hospital_TOWN_TILE: Vector2i = Vector2i(1, 0)


# --- projection -------------------------------------------------------------


func test_snapshot_lists_every_ward_the_crown_can_raise_in_both_charts() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions(hospital__engineers()), 0)
	assert_eq(int(snapshot["total"]), 2, "one crown province per chart")
	assert_eq((snapshot["groups"] as Array).size(), 2, "one heading per chart")
	assert_eq(HospitalLedger.count(snapshot, LedgerRows.REGION_OLD), 1)
	assert_eq(HospitalLedger.count(snapshot, LedgerRows.REGION_NEW), 1)
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		assert_ne(String(row["name"]), "Coro", "the rival's shore stays out")


## A ward on each chart at different levels: one heading per chart, however the
## level order interleaves the charts (DR-20261116-02).
func test_the_wards_sheet_prints_one_heading_per_chart_whatever_the_levels() -> void:
	var regions: Array[Dictionary] = hospital__regions(hospital__engineers(), hospital__wide_tech())
	var home: MapModel = regions[0]["model"] as MapModel
	home.provinces[1].owner = 0
	home.provinces[1].hospital_level = 1
	var abroad: MapModel = regions[1]["model"] as MapModel
	abroad.provinces[0].hospital_level = 0
	var snapshot: Dictionary = HospitalLedger.snapshot(regions, 0)
	assert_eq(int(snapshot["total"]), 3, "two shores at home, one abroad")
	var groups: Array[Dictionary] = HospitalLedger.groups(snapshot, LedgerRows.REGION_ALL)
	assert_eq(groups.size(), 2, "one heading per chart, not one per level")
	assert_eq(int(groups[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq((groups[0]["rows"] as Array).size(), 2, "both home shores under one heading")
	assert_eq((groups[1]["rows"] as Array).size(), 1, "the colony under its own")


func test_hospital_a_bare_shore_names_the_step_it_waits_on_and_its_price() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions(hospital__engineers()), 0)
	var home: Dictionary = hospital__row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_READY, "a crew is free and no study is owed")
	assert_eq(String(home["level_text"]), "—", "an empty shore is a dash, not a zero")
	assert_eq(String(home["line"]), "No hospital")
	assert_eq(int(home["next_level"]), 1)
	assert_eq(String(home["cost_text"]), "3 lumber + 2 fabric", "the ward table's own price")
	assert_eq(int(home["turns"]), 1, "a field ward is one turn")
	assert_eq(
		String(home["note"]),
		"Next: field hospital · 3 lumber + 2 fabric · 1 turn",
		"the row names the ward, the price and the wait"
	)


## The ward's own arithmetic, priced before the crown pays: the rest, the wear
## and the ration the next level brings, straight off the table the turn's rest
## pass heals by (REQ-P2-03, REQ-P5-06; DR-20261117-05).
func test_hospital_a_bare_shore_prices_the_ward_it_offers() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions(hospital__engineers()), 0)
	var home: Dictionary = hospital__row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(
		String(home["preview_text"]),
		"L1 rests 40%, wear 80%, staff 2 food (+15% rest, -20% wear, +2 food)",
		"an empty shore reads the first ward whole"
	)
	var overseas: Dictionary = hospital__row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(
		String(overseas["preview_text"]),
		"L2 rests 55%, wear 65%, staff 4 food (+15% rest, -15% wear, +2 food)",
		"a field ward's step names only what the level adds"
	)


## No line where there is no raise: a general ward has no level left, and a ward
## an Engineer is already raising has no press to price.
func test_hospital_a_finished_ward_and_a_crew_at_work_price_no_raise() -> void:
	var raised: Dictionary = hospital__raised()
	assert_eq(String(raised["state"]), HospitalLedger.STATE_RAISED)
	assert_eq(String(raised["preview_text"]), "", "a general ward owes nothing")
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", hospital_TOWN_TILE)
	engineer.start_work(
		"build_hospital", hospital_TOWN_TILE, 2, hospital_TOWN_TILE, {"hospital_level": 1}
	)
	var working: Dictionary = hospital__row(
		HospitalLedger.snapshot(hospital__regions([engineer]), 0), FactionCatalog.OLD_WORLD
	)
	assert_eq(String(working["state"]), HospitalLedger.STATE_AT_WORK)
	assert_eq(String(working["preview_text"]), "", "the works in hand are the news")


func test_a_ward_without_the_study_is_locked_and_names_it() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(
		hospital__regions(hospital__engineers(), {"organised_regiments": true, "modern_military_funding": false}), 0
	)
	var overseas: Dictionary = hospital__row(snapshot, FactionCatalog.NEW_WORLD)
	assert_eq(String(overseas["state"]), HospitalLedger.STATE_LOCKED, "a field ward is up; the general one is gated")
	assert_true(
		String(overseas["note"]).contains("Modern Military Funding"),
		"the row names the study that opens it"
	)
	assert_eq(
		int(HospitalLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)[HospitalLedger.FILTER_READY]),
		1,
		"a locked ward is not counted as ready"
	)


func test_hospital_a_shore_with_no_idle_crew_waits_on_an_engineer() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions([] as Array), 0)
	var home: Dictionary = hospital__row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_NO_ENGINEER, "no crew musters")
	assert_true(String(home["note"]).contains("No idle Engineer"), "the row names the wait")


## The ward shares the town tile with the town and the wall, and the crew rule
## keeps one Builder, Engineer or Merchant a tile: a Raise offered while another
## crew already works the site would be refused, so the row names the busy tile
## instead (wiki: civilian-units § Per-player tile exclusivity; DR-20261116-02 —
## "no row offers a ward the order would refuse").
func test_hospital_a_crew_already_on_the_town_tile_closes_the_press() -> void:
	var builder: CivilianState = CivilianState.create(2, 0, "builder", hospital_TOWN_TILE)
	builder.start_work("upgrade_town", hospital_TOWN_TILE, 2, hospital_TOWN_TILE, {"town_level": 2})
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", Vector2i(0, 0))
	var units: Array[CivilianState] = [engineer, builder]
	var regions: Array[Dictionary] = hospital__regions(units)
	var home: Dictionary = hospital__row(HospitalLedger.snapshot(regions, 0), FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_LOCKED, "the order would refuse the tile")
	# The row speaks the order's own words, so the promise and the refusal match.
	var order: Dictionary = ImprovementOrders.build_hospital(
		regions[0]["model"] as MapModel, units, LandWorks.new(),
		{"lumber": 9, "fabric": 9}, VisibilityModel.new(), 0, 0, {},
		{"organised_regiments": true}
	)
	assert_false(bool(order.get("ok", true)), "the order refuses the busy tile")
	assert_eq(String(home["note"]), String(order.get("message", "")), "one wording")
	assert_eq(
		int(HospitalLedger.filter_counts(
			HospitalLedger.snapshot(regions, 0), LedgerRows.REGION_ALL
		)[HospitalLedger.FILTER_READY]),
		0,
		"a busy shore is never counted as ready"
	)


## A ward row is minted on the same head and the same step fields as the town
## and the wall, so the raise spine reads all three sheets alike (REQ-P3-01).
func test_a_ward_row_carries_the_shared_head_and_step_fields() -> void:
	var row: Dictionary = hospital__row(
		HospitalLedger.snapshot(hospital__regions(hospital__engineers()), 0),
		FactionCatalog.OLD_WORLD
	)
	for key: String in [
		"id", "region", "region_label", "name", "capital", "level", "level_text"
	]:
		assert_true(row.has(key), "the shared head: %s" % key)
	for key: String in ["state", "crew", "remaining", "cost_text", "turns"]:
		assert_true(row.has(key), "the shared step: %s" % key)
	assert_eq(String(row["level_text"]), "—", "an open shore prints the sheet's own dash")


## A finished ward that went unfed keeps its walls and loses its nurses: the note
## must not claim the ward's own rest share (wiki: combat § Regiment condition;
## DR-20261112-04).
func test_a_finished_ward_that_went_unfed_names_the_field_rest() -> void:
	var regions: Array[Dictionary] = hospital__regions(hospital__engineers(), hospital__wide_tech())
	var home: MapModel = regions[0]["model"] as MapModel
	home.provinces[0].hospital_level = HospitalRules.MAX_LEVEL
	home.provinces[0].hospital_staffed = false
	var row: Dictionary = hospital__row(HospitalLedger.snapshot(regions, 0), FactionCatalog.OLD_WORLD)
	assert_eq(String(row["state"]), HospitalLedger.STATE_RAISED, "nothing is left to raise")
	assert_true(String(row["line"]).contains("unstaffed"), "the line names the hunger")
	assert_true(String(row["note"]).contains("rest 25%"), "the note names the rest it gets")
	assert_false(String(row["note"]).contains("55%"), "never the ward's own share")
	assert_eq(
		HospitalRules.rest_share_at(home, 0),
		RegimentCondition.REST_SHARE,
		"and that is the share the province actually rests at"
	)


func test_hospital_an_engineer_already_at_work_is_read_from_its_own_record() -> void:
	var engineer: CivilianState = CivilianState.create(1, 0, "engineer", hospital_TOWN_TILE)
	engineer.start_work("build_hospital", hospital_TOWN_TILE, 2, hospital_TOWN_TILE, {"hospital_level": 1})
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions([engineer]), 0)
	var home: Dictionary = hospital__row(snapshot, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_AT_WORK)
	assert_eq(int(home["remaining"]), 2)
	assert_true(String(home["note"]).contains("raises the field hospital"), "the target ward is named")
	assert_true(String(home["note"]).contains("2 turns left"))


func test_a_general_hospital_reads_finished() -> void:
	var raised: Dictionary = hospital__raised()
	assert_eq(int(raised["level"]), HospitalRules.MAX_LEVEL)
	assert_eq(String(raised["state"]), HospitalLedger.STATE_RAISED, "a general ward owes nothing")
	assert_eq(
		String(raised["note"]),
		"Fully warded — rest 55%, wear 65%, staff 4 food a turn."
	)
	assert_eq(String(raised["level_text"]), "II")


func test_a_ward_that_went_unfed_says_so_and_leads_its_state() -> void:
	var regions: Array[Dictionary] = hospital__regions(hospital__engineers())
	(regions[0]["model"] as MapModel).provinces[0].hospital_level = 1
	(regions[0]["model"] as MapModel).provinces[0].hospital_staffed = false
	var snapshot: Dictionary = HospitalLedger.snapshot(regions, 0)
	var home: Dictionary = hospital__row(snapshot, FactionCatalog.OLD_WORLD)
	assert_false(bool(home["staffed"]), "the row knows the staff went unfed")
	assert_true(
		String(home["line"]).contains("unstaffed — no rations this turn"),
		"the line names the hunger"
	)
	var reading: Dictionary = HospitalLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["unfed"]), 1, "the count line names it too")
	assert_eq(int(reading["ration"]), 4, "a hungry ward still owes its ration")


func test_the_stores_gate_closes_a_row_the_order_would_refuse() -> void:
	var broke: Dictionary = HospitalLedger.snapshot(
		hospital__regions(hospital__engineers(), {"organised_regiments": true}, {}), 0
	)
	var home: Dictionary = hospital__row(broke, FactionCatalog.OLD_WORLD)
	assert_eq(String(home["state"]), HospitalLedger.STATE_LOCKED, "an empty purse offers no press")
	assert_true(
		String(home["note"]).contains("Stores are short of 3 lumber + 2 fabric"),
		"the row names the shortfall"
	)
	var paid: Dictionary = HospitalLedger.snapshot(
		hospital__regions(hospital__engineers(), {"organised_regiments": true}, {"lumber": 3, "fabric": 2}), 0
	)
	assert_eq(
		String(hospital__row(paid, FactionCatalog.OLD_WORLD)["state"]),
		HospitalLedger.STATE_READY,
		"paying the price opens the press"
	)
	var unpriced: Dictionary = HospitalLedger.snapshot(hospital__regions(hospital__engineers()), 0)
	assert_eq(
		String(hospital__row(unpriced, FactionCatalog.OLD_WORLD)["state"]),
		HospitalLedger.STATE_READY,
		"a projection that prices no spend never reads LOCKED on an empty purse"
	)


func test_hospital_filters_narrow_the_ledger_and_keep_their_tallies() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(
		hospital__regions(hospital__engineers(), {"organised_regiments": true, "modern_military_funding": false}), 0
	)
	var counts: Dictionary = HospitalLedger.filter_counts(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(counts[HospitalLedger.FILTER_ALL]), 2)
	assert_eq(int(counts[HospitalLedger.FILTER_READY]), 1)
	assert_eq(int(counts[HospitalLedger.FILTER_RAISED]), 0)
	assert_eq(int(counts[HospitalLedger.FILTER_AT_WORK]), 0)
	var ready: Array[Dictionary] = HospitalLedger.groups(
		snapshot, LedgerRows.REGION_ALL, HospitalLedger.FILTER_READY
	)
	assert_eq(ready.size(), 1, "only the chart that holds a ready ward")
	assert_eq(int(ready[0]["region"]), FactionCatalog.OLD_WORLD)
	assert_eq(
		HospitalLedger.count(snapshot, LedgerRows.REGION_NEW, HospitalLedger.FILTER_READY), 0
	)


func test_hospital_the_reading_leads_with_what_can_be_raised_now() -> void:
	var rows: Array = hospital__raised_snapshot()["rows"]
	assert_eq(
		String((rows[0] as Dictionary)["state"]),
		HospitalLedger.STATE_READY,
		"the empty shore leads"
	)
	assert_eq(
		String((rows[1] as Dictionary)["state"]),
		HospitalLedger.STATE_RAISED,
		"the general ward follows"
	)


func test_the_summary_names_where_nothing_heals_and_what_the_staffs_eat() -> void:
	var snapshot: Dictionary = HospitalLedger.snapshot(hospital__regions(hospital__engineers(), hospital__wide_tech()), 0)
	var reading: Dictionary = HospitalLedger.summary(snapshot, LedgerRows.REGION_ALL)
	assert_eq(int(reading["total"]), 2)
	assert_eq(int(reading["bare"]), 1, "one empty shore")
	assert_eq(int(reading["standing"]), 1, "one field ward")
	assert_eq(int(reading["ration"]), 2, "a field ward eats 2 food a turn")
	var built: Dictionary = hospital__raised_snapshot()
	var home: Dictionary = hospital__row(built, FactionCatalog.OLD_WORLD)
	assert_eq(int(home["level"]), HospitalRules.MAX_LEVEL, "the general ward stands")
	assert_eq(int(home["demand"]), 4, "and eats 4")
	assert_eq(
		int(HospitalLedger.summary(built, LedgerRows.REGION_ALL)["ration"]),
		6,
		"the whole staff's bill is the sum of the wards"
	)


func test_the_rule_note_states_what_a_ward_buys() -> void:
	var note: String = HospitalLedger.rule_note()
	assert_true(note.contains("rest 40%"), "the field ward's rest is printed")
	assert_true(note.contains("55%"), "the general ward's rest is printed")
	assert_true(note.contains("2 food a turn per level"), "the ration is printed")
	assert_true(note.contains("unfed"), "and what a hungry ward costs")
	# An unfed ward keeps its walls and loses its nurses: it rests at the field's
	# share, so the note must not claim it heals nothing (wiki: combat
	# § Regiment condition; DR-20261112-04).
	assert_true(note.contains("rests at the field's 25%"), "the share it still gets")
	assert_false(note.contains("heals nothing"), "never the old claim")


# --- the sheet --------------------------------------------------------------


# --- fixtures ---------------------------------------------------------------


## Two charts of the naval fixture: the crown holds Cádiz at home (a bare town)
## and Veracruz abroad (a field ward), and the rival's Coro carries a town of its
## own that must never reach the reading. The purse rides every chart the way
## [MapPlayCharts] hands it over; `null` prices no spend.
func hospital__regions(
	units: Array, tech: Dictionary = {"organised_regiments": true}, stockpile: Variant = null
) -> Array[Dictionary]:
	var old: MapModel = hospital_Naval.build()
	var new: MapModel = hospital_Naval.build()
	new.region_id = FactionCatalog.NEW_WORLD
	new.provinces[0].name = "Veracruz"
	new.provinces[0].capital = false
	new.provinces[0].town_tile = hospital_TOWN_TILE
	new.provinces[0].hospital_level = 1
	old.provinces[0].town_tile = hospital_TOWN_TILE
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


## The gates a general ward owes: Organised Regiments for the field ward, Modern
## Military Funding for the general one, so a raised ward is a finished ward.
func hospital__wide_tech() -> Dictionary:
	return {"organised_regiments": true, "modern_military_funding": true}


## One idle Engineer on the crown's own ground, so a ready shore has a crew free.
func hospital__engineers() -> Array:
	return [CivilianState.create(1, 0, "engineer", hospital_TOWN_TILE)]


## The crown's province at home, warded to the second level, so the finished
## reading has a row of its own.
func hospital__raised_snapshot() -> Dictionary:
	var regions: Array[Dictionary] = hospital__regions(hospital__engineers(), hospital__wide_tech())
	(regions[0]["model"] as MapModel).provinces[0].hospital_level = HospitalRules.MAX_LEVEL
	return HospitalLedger.snapshot(regions, 0)


func hospital__raised() -> Dictionary:
	return hospital__row(hospital__raised_snapshot(), FactionCatalog.OLD_WORLD)


func hospital__row(snapshot: Dictionary, region: int) -> Dictionary:
	for raw: Variant in snapshot["rows"]:
		var row: Dictionary = raw
		if int(row["region"]) == region:
			return row
	return {}


## The first crown province of the mounted campaign that can carry a ward, has
## not been finished yet and has no crew already at work on its site — so a case
## that raises a ward never leaves the next one reading `AT WORK`.
func _crown_ward() -> ProvinceState:
	for province: ProvinceState in screen.play.model.provinces:
		if province.owner != screen.play.player_faction:
			continue
		if province.hospital_level >= HospitalRules.MAX_LEVEL:
			continue
		var site: Vector2i = HospitalRules.site_tile(screen.play.model, province.id)
		if site.x < 0:
			continue
		if _ward_crew(site) != null:
			continue
		return province
	return null


## The realm ledger's hospitals door, found by its word so the suite reads the
## button the player presses.
func _hospitals_door() -> Button:
	for node: Node in screen.hud.province_ledger.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Hospitals ›":
			return button
	return null


## The Engineer the sheet sent: the crown's crew with a ward order on this site.
func _ward_crew(site: Vector2i) -> CivilianState:
	for unit: CivilianState in screen.play.civilian_layer.units:
		if unit.owner != screen.play.player_faction or not unit.is_working():
			continue
		if unit.work_action() == "build_hospital" and unit.work_tile() == site:
			return unit
	return null


func _crown_wards() -> int:
	var total: int = 0
	for region: int in screen.play.world.region_count():
		var model: MapModel = screen.play.world.region(region)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != screen.play.player_faction:
				continue
			if HospitalRules.site_tile(model, province.id).x >= 0:
				total += 1
	return total

