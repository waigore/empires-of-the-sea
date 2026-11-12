extends GdToolsTest
## One boot for the small UI parts that mount no chart: court reports and dossier,
## toasts, the panel dock, ledger text/helpers and the civilian layer parts.

## Merged from test_court_reports, test_court_dossier_screen, test_hud_toast,
## test_panel_dock, test_ledger_text, test_ledger_helpers, test_civilian_layer_parts.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.
const Fixture = preload("res://tests/civilian_fixture.gd")

const VIEWER: int = 0
const ENGLAND: int = 1
const GENOA: int = 6
const court_dossier_screen_VIEWER: int = 0
const court_dossier_screen_ENGLAND: int = 1
const court_dossier_screen_GENOA: int = 6
const LINE := "France holds Burgundy — 2 of 2 emplaced guns silenced"
const TEMP_PATH := "user://test_panel_dock.cfg"

var _hud: GameHud = null

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"hud_toast":
			_teardown_hud_toast()
		"panel_dock":
			_teardown_panel_dock()
	_suite_setup = ""

func _setup_hud_toast() -> void:
	_suite_setup = "hud_toast"
	_hud = GameHud.new()
	add_child(_hud)

func _setup_panel_dock() -> void:
	_suite_setup = "panel_dock"
	pass

func _teardown_hud_toast() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	_hud = null

func _teardown_panel_dock() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

# --- test_court_reports ---

func _reports(lines: Array, shadowed: Array = [ENGLAND]) -> Dictionary:
	return {"turn": 4, "shadowed": shadowed, "lines": {ENGLAND: lines}}

func test_a_shadowed_court_shows_the_kept_despatch() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(ENGLAND, _reports(["took Coro from Spain", "finished Crop Rotation"]))
	assert_true(_has_text(panel, "COURT REPORTS"), "the block names itself")
	assert_true(_has_text(panel, "Turn 4"), "and stamps the turn")
	assert_true(_has_text(panel, "took Coro from Spain"))
	assert_true(_has_text(panel, "finished Crop Rotation"))
	panel.free()

func test_an_unwatched_court_shows_no_block() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(GENOA, _reports(["took Coro from Spain"]))
	assert_eq(panel.get_child_count(), 0, "no spy, no section")
	panel.free()

func test_a_quiet_court_says_so() -> void:
	var panel := CourtReportsPanel.new()
	add_child(panel)
	panel.fill(ENGLAND, _reports([]))
	assert_true(_has_text(panel, CourtReportsPanel.QUIET_LINE))
	panel.free()

func test_the_court_panel_carries_the_despatch_for_the_selected_crown() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, VIEWER, 2500, {}, _reports(["took Coro from Spain"]))
	panel.select_faction(ENGLAND)
	assert_true(_has_text(panel._detail, "COURT REPORTS"))
	assert_true(_has_text(panel._detail, "took Coro from Spain"))
	panel.select_faction(GENOA)
	assert_false(_has_text(panel._detail, "COURT REPORTS"), "Genoa has no spy")
	panel.free()

func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false

# --- test_court_dossier_screen ---

func _state() -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	return state

func _screen(state: DiplomacyState, subject: int) -> CourtDossierScreen:
	var screen := CourtDossierScreen.new()
	add_child(screen)
	screen.show_for(state, null, court_dossier_screen_VIEWER, subject)
	return screen

func test_the_sheet_reads_every_section_in_order() -> void:
	var state: DiplomacyState = _state()
	DiplomacyRules.declare_war(state, court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(screen.is_open(), "the sheet is up")
	assert_true(_court_dossier_screen_has_text(screen, "THE DOSSIER"))
	assert_true(_court_dossier_screen_has_text(screen, "England"), "the court is named")
	assert_true(_court_dossier_screen_has_text(screen, "SUSPICION"))
	assert_true(_court_dossier_screen_has_text(screen, "TIMELINE"))
	assert_true(_court_dossier_screen_has_text(screen, "BEHAVIOUR & BUILD NOTES"))
	assert_true(_court_dossier_screen_has_text(screen, "Reading:"), "the best guess leads")
	assert_true(_court_dossier_screen_has_text(screen, "Warmonger"), "every agenda is listed, banded or not")
	assert_true(_court_dossier_screen_has_text(screen, "Declared war on Genoa."), "the act reaches the page")
	screen.free()

func test_the_reading_names_the_band_never_the_agenda_truth() -> void:
	var state: DiplomacyState = _state()
	for _index in 4:
		state.record_event("warDeclared", court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(_court_dossier_screen_has_text(screen, "Likely 60%"), "the band and its confidence are printed")
	assert_false(_court_dossier_screen_has_text(screen, "Confirmed 100%"), "nothing is certain at four acts")
	screen.free()

## The strongest reading starts open; every other row opens on a press, so the
## sheet reads as a table first and a story second.
func test_an_agenda_row_toggles_its_own_timeline() -> void:
	var state: DiplomacyState = _state()
	DiplomacyRules.declare_war(state, court_dossier_screen_ENGLAND, court_dossier_screen_GENOA)
	state.record_event("grantAid", court_dossier_screen_ENGLAND, court_dossier_screen_GENOA, {"amount": 100})
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	var pacifist: Button = _agenda_button(screen, "Peacemaker")
	assert_not_null(pacifist, "the quieter reading still has a row")
	assert_true(pacifist.text.begins_with("▸"), "a quiet agenda starts folded")
	pacifist.pressed.emit()
	assert_true(pacifist.text.begins_with("▾"), "a press unfolds its timeline")
	screen.free()

func test_a_quiet_court_says_so_instead_of_showing_an_empty_sheet() -> void:
	var screen: CourtDossierScreen = _screen(_state(), court_dossier_screen_GENOA)
	assert_true(_court_dossier_screen_has_text(screen, "no act has yet spoken"), "the reading says it plainly")
	assert_true(_court_dossier_screen_has_text(screen, "No observable act has been written down."))
	assert_true(_court_dossier_screen_has_text(screen, "No observable act feeds this reading yet."))
	screen.free()

func test_the_build_notes_name_what_a_spy_watched() -> void:
	var state: DiplomacyState = _state()
	state.record_event(
		IntelEvidence.SPY_BUILD, court_dossier_screen_ENGLAND, court_dossier_screen_VIEWER, {"works": {"improvement": 2, "town": 1}}
	)
	state.record_event(IntelEvidence.SPY_TECH, court_dossier_screen_ENGLAND, court_dossier_screen_VIEWER, {"tech": "crop_rotation"})
	var screen: CourtDossierScreen = _screen(state, court_dossier_screen_ENGLAND)
	assert_true(_court_dossier_screen_has_text(screen, "Under your spy's eye"), "the sightings are listed")
	assert_true(_court_dossier_screen_has_text(screen, "2 estates"))
	assert_true(_court_dossier_screen_has_text(screen, "1 town finished"))
	assert_true(_court_dossier_screen_has_text(screen, "1 finished study"))
	assert_true(_court_dossier_screen_has_text(screen, "Finished Crop Rotation while our spy watched."))
	screen.free()

func test_close_dismisses_the_sheet() -> void:
	var screen: CourtDossierScreen = _screen(_state(), court_dossier_screen_ENGLAND)
	screen.close()
	assert_false(screen.is_open())
	screen.free()

func _agenda_button(screen: CourtDossierScreen, label: String) -> Button:
	for child: Node in screen._body.get_children():
		if child is Button and String((child as Button).text).contains(label):
			return child as Button
	return null

func _court_dossier_screen_has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _court_dossier_screen_has_text(child, needle):
			return true
	return false

# --- test_hud_toast ---

func test_a_plain_toast_keeps_its_single_label() -> void:
	_setup_hud_toast()
	_hud.toast("The turn opens")
	var panel: Control = _hud._toast_box.get_child(0)
	assert_eq(panel.get_child_count(), 1)
	var label: Label = panel.get_child(0) as Label
	assert_true(label != null)
	assert_eq(label.text, "The turn opens")

func test_a_siege_toast_carries_the_silenced_battery_medallion() -> void:
	_setup_hud_toast()
	_hud.toast(LINE, "silenced_gun")
	var panel: Control = _hud._toast_box.get_child(0)
	var row: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert_true(row != null, "the medallion sits in a row with its line")
	var medallion: TextureRect = row.get_child(0) as TextureRect
	assert_true(medallion != null)
	assert_true(medallion.texture != null, "the icon asset is imported")
	assert_eq(medallion.custom_minimum_size, Vector2(26.0, 26.0))
	var label: Label = row.get_child(1) as Label
	assert_true(label != null)
	assert_eq(label.text, LINE)

func test_a_hidden_hud_keeps_no_toast_plates() -> void:
	_setup_hud_toast()
	_hud.visible = false
	_hud.toast(LINE, "silenced_gun")
	assert_eq(_hud._toast_box.get_child_count(), 0)

# --- test_panel_dock ---

func test_defaults_to_right() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_eq(dock.side, PanelDock.Side.RIGHT)
	assert_false(dock.is_left())

func test_toggle_flips_side() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_eq(dock.toggle(), PanelDock.Side.LEFT)
	assert_eq(dock.toggle(), PanelDock.Side.RIGHT)

func test_save_and_load_round_trip() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	assert_true(dock.save(TEMP_PATH))

	var fresh := PanelDock.new()
	assert_true(fresh.load_from(TEMP_PATH))
	assert_eq(fresh.side, PanelDock.Side.LEFT)

func test_missing_file_keeps_default() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	assert_false(dock.load_from("user://definitely_not_panel_dock.cfg"))
	assert_eq(dock.side, PanelDock.Side.RIGHT)

func test_right_shown_offsets_match_legacy_panel() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, -(PanelDock.WIDTH + PanelDock.MARGIN))
	assert_eq(wrap.offset_right, -PanelDock.MARGIN)
	wrap.free()

func test_left_shown_offsets_clear_the_margin() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, PanelDock.MARGIN)
	assert_eq(wrap.offset_right, PanelDock.MARGIN + PanelDock.WIDTH)
	wrap.free()

func test_prepare_wrap_uses_left_anchors_when_docked_left() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.prepare_wrap(wrap)
	assert_eq(wrap.anchor_left, 0.0)
	assert_eq(wrap.anchor_right, 0.0)
	assert_eq(wrap.offset_left, PanelDock.MARGIN - PanelDock.WIDTH)
	wrap.free()

## A show right after a hide must cancel the outgoing slide: its callback would
## otherwise park the panel off screen while the dossier reports it open.
func test_a_slide_in_cancels_a_running_slide_out() -> void:
	_setup_panel_dock()
	var dock := PanelDock.new()
	var host := Node.new()
	add_child(host)
	var wrap := Control.new()
	host.add_child(wrap)
	dock.prepare_wrap(wrap)
	dock.slide_out(host, wrap, func() -> void: wrap.visible = false)
	var outgoing: Tween = wrap.get_meta(PanelDock.SLIDE_KEY)

	dock.slide_in(host, wrap)

	assert_false(outgoing.is_valid(), "the slide-out tween is killed")
	assert_true(wrap.visible)
	assert_ne(wrap.get_meta(PanelDock.SLIDE_KEY), outgoing)
	host.free()

# --- test_ledger_text ---

func test_a_quiet_market_prints_nothing() -> void:
	assert_eq(LedgerText.market_summary({}, 0), "")

## The disband row promises no refund and names what the tier eats
## (wiki: workers-and-population § Disband, § Tiers).
func test_the_disband_hint_names_the_promise_and_the_saving() -> void:
	var hint: String = LedgerText.disband_hint(WorkerPool.Tier.APPRENTICE)
	assert_true(hint.contains("no recruit cost is refunded"), hint)
	assert_true(hint.contains("An apprentice eats 2 food"), hint)
	assert_true(hint.contains("a unit of Refined Sugar"), hint)
	var master: String = LedgerText.disband_hint(WorkerPool.Tier.MASTER)
	assert_true(master.contains("A master eats 2 food and a unit of Fur Hats"), master)

func test_fills_carry_and_lapse_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"bought": 2, "spent": 60, "sold": 1}},
		"carry": [{"commodity": "timber"}],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 0,
			"commodity": "grain",
		}],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("bought 2 for 60 ducats"))
	assert_true(line.contains("sold 1"))
	assert_true(line.contains("1 order carried"))
	assert_true(line.contains("1 order lapsed"))

## A sale names the ducats it paid, and the overseas share is named even when
## the court traded nothing itself: the auction is the purse movement the
## per-turn figure cannot project (wiki: world-market § Trade orders, § First
## right of refusal).
func test_a_sale_and_an_overseas_share_are_named() -> void:
	var report: Dictionary = {
		"fills": {0: {"sold": 1, "earned": 50}},
		"credits": {"by_gp": {0: 89.4}},
		"carry": [],
		"notes": [],
	}
	var line: String = LedgerText.market_summary(report, 0)
	assert_true(line.contains("sold 1 for 50 ducats"), line)
	assert_true(line.contains("89 ducats in shares"), line)
	# A court with no fills of its own still reads its share.
	var quiet: Dictionary = {"fills": {}, "credits": {"by_gp": {0: 12.0}}}
	assert_true(
		LedgerText.market_summary(quiet, 0).contains("12 ducats in shares"),
		LedgerText.market_summary(quiet, 0),
	)
	assert_eq(LedgerText.share_credit({"credits": {0: 7.6}}, 0), 8, "a bare map is read too")

## The "Next turn" promise names the orders that settle after it, so a staged
## order is never read as already counted (wiki: stockpiles-and-production
## § Production flow — the auction clears after Production).
func test_the_preview_names_the_auction_it_excludes() -> void:
	var staged: Dictionary = {
		"stockpile_delta": {"grain": 3},
		"treasury_delta": 0,
		"staged_orders": 2,
	}
	var line: String = LedgerText.preview(staged)
	assert_true(line.contains("Grain +3"), line)
	assert_true(line.contains("2 orders settle at the auction"), line)
	var one: Dictionary = {"stockpile_delta": {}, "treasury_delta": 0, "staged_orders": 1}
	assert_true(
		LedgerText.preview(one).contains("1 order settles at the auction"),
		LedgerText.preview(one),
	)
	# Nothing staged: the calm line stays exactly as it was.
	assert_eq(
		LedgerText.preview({"stockpile_delta": {}, "treasury_delta": 0}),
		"Next turn: no stock changes.",
	)

func test_another_courts_lapse_is_not_ours() -> void:
	var report: Dictionary = {
		"fills": {},
		"carry": [],
		"notes": [{
			"code": "carry_forward_dropped_cargo_insufficient",
			"faction": 1,
			"commodity": "grain",
		}],
	}
	assert_eq(LedgerText.market_summary(report, 0), "")

# --- test_ledger_helpers ---

func test_thousands_groups_and_keeps_the_sign() -> void:
	assert_eq(TextFormat.thousands(0), "0")
	assert_eq(TextFormat.thousands(999), "999")
	assert_eq(TextFormat.thousands(1000), "1,000")
	assert_eq(TextFormat.thousands(1234567), "1,234,567")
	assert_eq(TextFormat.thousands(-1234), "-1,234")

func test_recipe_title_names_the_single_input() -> void:
	var recipe_id: String = ProductionRecipes.available_ids({})[0]
	var title: String = LedgerText.recipe_title(recipe_id)
	assert_true(title.contains(CommodityCatalog.label(ProductionRecipes.output(recipe_id))))
	assert_true(LedgerText.recipe_tooltip(recipe_id).contains("→"))

func test_the_summary_reads_the_report() -> void:
	var economy: PlayerEconomy = PlayerEconomy.new()
	economy.treasury = 1234
	var report: Dictionary = {
		"consumption": {"idle_labour": 3, "strikers": 2, "navy_demand": 5},
	}
	var line: String = LedgerText.summary(economy, report)
	assert_true(line.contains("1,234 ducats"))
	assert_true(line.contains("labour 3 /"))
	assert_true(line.contains("strikes 2"))

func test_the_preview_reports_deltas_or_calm() -> void:
	assert_eq(LedgerText.preview({}), "Next turn: no stock changes.")
	var line: String = LedgerText.preview(
		{"stockpile_delta": {"grain": 3}, "treasury_delta": -10}
	)
	assert_true(line.contains("+3"))
	assert_true(line.contains("ducats -10"))

func test_the_cargo_banner_covers_three_states() -> void:
	assert_true(LedgerText.cargo_line({}).contains("unknown"))
	var empty: Dictionary = {"holds": 0, "free": 0}
	assert_true(LedgerText.cargo_line(empty).contains("No cargo holds"))
	assert_eq(LedgerText.cargo_color(empty), Palette.GOLD_PALE)
	var laden: Dictionary = {"holds": 4, "free": 1}
	assert_true(LedgerText.cargo_line(laden).contains("4 holds"))
	assert_eq(LedgerText.cargo_color(laden), Palette.TEXT)

func test_report_counters_default_to_zero() -> void:
	assert_eq(LedgerText.idle_labour({}), 0)
	assert_eq(LedgerText.navy_food({"consumption": {"navy_demand": 7}}), 7)

func _group(id: int, name: String, rows: Array) -> Dictionary:
	var producing: int = 0
	for row: Dictionary in rows:
		if int(row.get("output", 0)) > 0:
			producing += 1
	return {"id": id, "name": name, "rows": rows, "producing": producing}

func _rows() -> Array:
	return [
		{"output": 2, "working": false, "status": "producing"},
		{"output": 0, "working": true, "status": "building"},
		{"output": 0, "working": false, "status": "vacant"},
		{"output": 0, "working": false, "status": "disconnected"},
	]

func test_groups_keep_province_order_and_merge_duplicates() -> void:
	var snapshot: Dictionary = {
		"groups": [
			_group(4, "OLD", _rows().slice(0, 2)),
			_group(4, "OLD", _rows().slice(2)),
			_group(9, "NEW", _rows().slice(0, 1)),
		],
	}
	var groups: Array[Dictionary] = EstateLedger.grouped(snapshot)
	assert_eq(groups.size(), 2)
	assert_eq(groups[0]["name"], "OLD")
	assert_eq((groups[0]["rows"] as Array).size(), 4)

func test_province_filter_keeps_one_group() -> void:
	var groups: Array[Dictionary] = EstateLedger.grouped(
		{"groups": [_group(1, "A", _rows()), _group(2, "B", _rows())]}
	)
	assert_eq(EstateLedger.in_province(groups, -1).size(), 2)
	assert_eq(EstateLedger.in_province(groups, 2).size(), 1)

func test_each_filter_selects_its_rows() -> void:
	var rows: Array = _rows()
	assert_eq(EstateLedger.matching(rows, "all").size(), 4)
	assert_eq(EstateLedger.matching(rows, "producing").size(), 1)
	assert_eq(EstateLedger.matching(rows, "building").size(), 1)
	assert_eq(EstateLedger.matching(rows, "vacant").size(), 1)
	assert_eq(EstateLedger.matching(rows, "issues").size(), 1)

func test_total_output_sums_every_yield() -> void:
	assert_eq(EstateLedger.total_output({"lumber": 2, "iron": 3}), 5)
	assert_eq(EstateLedger.total_output({}), 0)

func test_row_builder_builds_themed_widgets() -> void:
	var row: HBoxContainer = UiRowBuilder.row(38.0)
	assert_eq(row.custom_minimum_size.y, 38.0)
	var label: Label = UiRowBuilder.label("hi", 14, Palette.TEXT)
	assert_eq(label.text, "hi")
	var caption: Label = UiRowBuilder.caption("x", 10, Palette.TEXT_DIM, 44.0)
	assert_eq(caption.custom_minimum_size.x, 44.0)
	var button: Button = UiRowBuilder.button("Go", 38.0, 70.0)
	assert_eq(button.text, "Go")
	assert_eq(button.custom_minimum_size, Vector2(70, 38))
	row.free()
	label.free()
	caption.free()
	button.free()

func test_clear_empties_a_container() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	UiRowBuilder.spacer(box)
	box.add_child(UiRowBuilder.label("gone", 12, Palette.TEXT))
	box.add_child(UiRowBuilder.label("gone too", 12, Palette.TEXT))
	assert_eq(box.get_child_count(), 3)
	UiRowBuilder.clear(box)
	assert_eq(box.get_child_count(), 0)
	box.queue_free()

# --- test_civilian_layer_parts ---

func test_capital_tile_prefers_the_seat() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_true(seat.x >= 0)
	assert_true(model.is_land(seat.x, seat.y))

func test_capital_tile_guards_and_falls_back() -> void:
	assert_eq(CivilianPlacement.capital_tile(null, 0), Vector2i(-1, -1))
	var model: MapModel = Fixture.build()
	assert_eq(CivilianPlacement.capital_tile(model, 99), Vector2i(-1, -1))
	var data: ProvinceState = model.province_data(0)
	data.capital_tile = Vector2i(-1, -1)
	var fallback: Vector2i = CivilianPlacement.capital_tile(model, 0)
	assert_eq(fallback, model.province_tiles(0)[0])

func test_mustering_tile_keeps_the_seat_clear() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [], 0)
	assert_true(tile.x >= 0)
	assert_ne(tile, seat, "fresh crews leave the capital seat readable")

func test_spies_and_nulls_do_not_block_mustering() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var taken: Dictionary = {seat: true}
	var open: Vector2i = CivilianPlacement.free_tile(model, 0, seat, taken)
	assert_true(open.x >= 0)
	var spy := CivilianState.create(1, 0, SpyRules.TYPE, open)
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, [null, spy], 0)
	assert_eq(tile, open, "a spy's tile stays free for mustering")
	assert_eq(CivilianPlacement.free_tile(null, 0, seat, {}), Vector2i(-1, -1))
	assert_eq(CivilianPlacement.mustering_tile(null, [], 0), Vector2i(-1, -1))

func test_a_full_province_reclaims_the_seat() -> void:
	var model: MapModel = Fixture.build()
	var seat: Vector2i = CivilianPlacement.capital_tile(model, 0)
	var units: Array[CivilianState] = []
	var id: int = 1
	for tile: Vector2i in model.province_tiles(0):
		if tile == seat:
			continue
		units.append(CivilianState.create(id, 0, "builder", tile))
		id += 1
	var tile: Vector2i = CivilianPlacement.mustering_tile(model, units, 0)
	assert_eq(tile, seat, "when every other tile is taken the seat musters")

func test_turn_pass_restores_moves_on_every_region() -> void:
	var model: MapModel = Fixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, 0, 0, [], false)
	var explorer: CivilianState = layer.add_unit(0, "explorer", Vector2i(1, 1))
	layer.regions.set_region(model.region_id, layer.units)
	assert_true(bool(CivilianMovement.apply_move(model, explorer, Vector2i(2, 1))["ok"]))
	assert_true(explorer.moved)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(explorer.moved, "the pass restores moves without the layer")
	layer.free()

func test_turn_pass_guards_and_offscreen_rosters() -> void:
	assert_eq(CivilianTurnPass.resolve(null, null, null).size(), 0)
	var home: MapModel = Fixture.build()
	var away: MapModel = Fixture.build()
	away.region_id = 1
	var world := WorldMap.new()
	world.add_region(home)
	world.add_region(away)
	var layer := CivilianLayer.new()
	layer.spawn(home, 0, 0, [], false)
	var idle: CivilianState = CivilianState.create(9, 0, "explorer", Vector2i(1, 1))
	idle.moved = true
	var remote: Array[CivilianState] = [null, idle]
	layer.regions.set_region(1, remote)
	CivilianTurnPass.resolve(layer, world, null)
	assert_false(idle.moved, "an off-screen crew still gets its move back")
	layer.free()

func test_paint_covers_mines_woods_riches_and_ports() -> void:
	LandWorksPaint.paint(null, null, null, 22.0)
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	works.set_improvement(model, Fixture.IRON_TILE, 2)
	works.set_improvement(model, Fixture.TIMBER_TILE, 1)
	var gold := Vector2i(2, 2)
	model.resource[model.index_of(gold.x, gold.y)] = 3
	works.set_improvement(model, gold, 1)
	var farm := Vector2i(0, 1)
	model.resource[model.index_of(farm.x, farm.y)] = 4
	works.set_improvement(model, farm, 1)
	works.add_port(model, Fixture.COAST_TILE)
	var layer := CivilianLayer.new()
	add_child(layer)
	layer.model = model
	layer.works = works
	layer.queue_redraw()
	await get_tree().process_frame
	layer.free()
