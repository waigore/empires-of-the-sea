extends GdToolsTest
## Phone geometry: one HUD unit is one point, and every control stays reachable
## on a landscape phone, a small phone and a tablet (REQ-P1-05, RUB-P1-05).
##
## Geometry runs in a SubViewport at the point size the device would report,
## because the root viewport is 1280x1280 under gd-tools and a Control's rects
## only settle after one idle frame.

const Fixture = preload("res://tests/map_fixture.gd")

## 1080x2400 at 2.625 density, held landscape (the emulated Android phone).
const PHONE := Vector2i(914, 411)
## 1600x720 at 2.0 density: a 360 dp phone held landscape (the modern floor).
const SMALL := Vector2i(800, 360)
const TABLET := Vector2i(1180, 820)
const DESKTOP := Vector2i(1280, 720)
const TOUCH_MIN := 40.0

var _viewport: SubViewport = null
var _screen: MapScreen = null


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	if is_instance_valid(_viewport):
		_viewport.free()
	_viewport = null


## --- density ---------------------------------------------------------------


func test_point_scale_turns_density_into_design_points() -> void:
	var phone: Vector2 = PlatformDisplay.point_size_for(Vector2(2400, 1080), 2.625)
	assert_almost_eq(phone.x, 914.0, 1.0)
	assert_almost_eq(phone.y, 411.0, 1.0)
	var tablet: Vector2 = PlatformDisplay.point_size_for(Vector2(2560, 1600), 2.0)
	assert_almost_eq(tablet.x, 1280.0, 1.0)
	assert_almost_eq(tablet.y, 800.0, 1.0)


func test_point_scale_keeps_aspect_and_stays_in_range() -> void:
	var tiny: Vector2 = PlatformDisplay.point_size_for(Vector2(320, 480), 1.0)
	assert_almost_eq(tiny.x, 480.0, 0.5)
	assert_almost_eq(tiny.y, 720.0, 0.5)
	var huge: Vector2 = PlatformDisplay.point_size_for(Vector2(8000, 4500), 1.0)
	assert_almost_eq(huge.x, PlatformDisplay.MAX_POINTS.x, 0.5)
	assert_almost_eq(huge.y / huge.x, 4500.0 / 8000.0, 0.001)
	assert_eq(PlatformDisplay.point_size_for(Vector2.ZERO, 2.0), Vector2.ZERO)


func test_density_prefers_the_effective_dpi_over_a_base_density() -> void:
	# An emulator reporting its base density 1.8 for a 2.625x screen.
	assert_almost_eq(PlatformDisplay.scale_for(1.8, 420.0), 2.625, 0.001)
	assert_almost_eq(PlatformDisplay.scale_for(3.0, 460.0), 3.0, 0.001)
	assert_almost_eq(PlatformDisplay.scale_for(1.0, 0.0), 1.0, 0.001)
	assert_almost_eq(PlatformDisplay.scale_for(9.0, 0.0), PlatformDisplay.MAX_SCALE, 0.001)


## --- chrome ----------------------------------------------------------------


func test_phone_chrome_fits_the_screen() -> void:
	for size: Vector2i in [PHONE, SMALL]:
		_open(size)
		await get_tree().process_frame
		var hud: GameHud = _screen.hud
		assert_true(HudLayout.is_compact(hud.size), "compact at %s" % size)
		_fits(hud.top_bar.get_global_rect(), _screen_rect(), "bar %s" % size)
		for chip: Control in hud.chips:
			_fits(chip.get_global_rect(), hud.top_bar.get_global_rect(), "chip %s" % size)
			assert_gt(
				chip.size.x, chip.get_combined_minimum_size().x - 0.5,
				"chip must not be squeezed at %s" % size
			)
		for node: Node in hud.top_row.get_children():
			if node is Button:
				_tappable(node as Button, "bar button %s at %s" % [(node as Button).text, size])
		_fits(hud.minimap_frame.get_global_rect(), _screen_rect(), "minimap %s" % size)
		_fits(hud.end_turn_wrap.get_global_rect(), _screen_rect(), "end turn %s" % size)
		_tappable(hud.end_turn_wrap.get_child(1), "end turn %s" % size)
		for button: Node in hud.zoom_box.get_children():
			_fits((button as Control).get_global_rect(), _screen_rect(), "zoom %s" % size)
			_tappable(button as Control, "zoom %s" % size)
		_tappable(hud.get_node("AudioControls/Trigger"), "audio %s" % size)
		var estates: Control = _screen.get_node("HUD/Improvements")
		_fits(estates._toggle.get_global_rect(), _screen_rect(), "estates %s" % size)
		_tappable(estates._toggle, "estates %s" % size)


func test_chip_values_do_not_shift_the_bar() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var height: float = hud.top_bar.size.y
	hud.set_treasury(123456, false)
	await get_tree().process_frame
	assert_almost_eq(hud.top_bar.size.y, height, 0.5)
	for chip: Control in hud.chips:
		_fits(chip.get_global_rect(), hud.top_bar.get_global_rect(), "chip after growth")


func test_desktop_chrome_keeps_its_atlas_geometry() -> void:
	for size: Vector2i in [DESKTOP, TABLET]:
		_open(size)
		await get_tree().process_frame
		var hud: GameHud = _screen.hud
		assert_false(HudLayout.is_compact(hud.size), "atlas layout at %s" % size)
		_fits(hud.top_bar.get_global_rect(), _screen_rect(), "bar %s" % size)
		_fits(hud.minimap_frame.get_global_rect(), _screen_rect(), "minimap %s" % size)
		_fits(hud.end_turn_wrap.get_global_rect(), _screen_rect(), "end turn %s" % size)
		if size != DESKTOP:
			continue
		assert_almost_eq(hud.top_bar.size.y, 68.0, 0.5)
		assert_almost_eq(hud.minimap_frame.size.x, 250.0, 0.5)
		assert_almost_eq(hud.end_turn_wrap.size.x, 212.0, 0.5)
		assert_eq(hud.panels.dock.width, GameHud.PANEL_WIDTH)


## --- dossiers --------------------------------------------------------------


func test_phone_dossier_keeps_its_orders_reachable() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.panels.set_civilian_training(true)
	hud.panels.show_province(_screen.model, _screen.capital_province)
	hud.panels.dock.place_shown(hud._panel_wrap)
	await get_tree().process_frame
	var panel: ProvincePanel = hud._panel
	_fits(panel.get_global_rect(), _screen_rect(), "dossier")
	assert_lt(panel._orders_box.get_global_rect().position.y, panel._grid.get_global_rect().position.y)
	var scroll: Control = panel.get_child(0).get_child(0)
	var immediate: int = 0
	for node: Node in panel._orders_box.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		# Every live order is reachable by scrolling inside the sheet...
		_fits(button.get_global_rect(), panel._column.get_global_rect(), "order %s" % button.text)
		_tappable(button, "order %s" % button.text)
		if _contains(scroll.get_global_rect(), button.get_global_rect()):
			immediate += 1
	# ...and the build order plus one muster are there without scrolling.
	assert_gt(immediate, 1, "primary orders visible on a phone without scrolling")
	_fits(panel._dock.get_global_rect(), panel.get_global_rect(), "dock button")
	_tappable(panel._dock, "dock button")


func test_desktop_dossier_keeps_the_table_above_the_orders() -> void:
	_open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.panels.show_province(_screen.model, _screen.capital_province)
	hud.panels.dock.place_shown(hud._panel_wrap)
	await get_tree().process_frame
	var panel: ProvincePanel = hud._panel
	assert_gt(panel._orders_box.get_global_rect().position.y, panel._grid.get_global_rect().position.y)
	_fits(panel.get_global_rect(), _screen_rect(), "dossier")
	assert_almost_eq(panel.size.x, GameHud.PANEL_WIDTH, 0.5)


func test_phone_fleet_dossier_fits() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	MapPlayFleets.select(_screen.play, _screen.ship_layer.ships[0])
	hud.panels.dock.place_shown(hud._fleet_wrap)
	await get_tree().process_frame
	var wrap: Control = hud._fleet_wrap
	_fits(wrap.get_global_rect(), _screen_rect(), "fleet dossier")
	assert_true(hud.panels.is_fleet_panel_open())
	assert_true(
		hud._fleet_panel.get_combined_minimum_size().y <= wrap.size.y + 0.5,
		"fleet content must fit its sheet (%s > %s)"
		% [hud._fleet_panel.get_combined_minimum_size().y, wrap.size.y]
	)


func test_phone_ledgers_fit_their_sheets() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.research_pressed.emit()
	await get_tree().process_frame
	_fits(hud._research_wrap.get_global_rect(), _screen_rect(), "research sheet")
	assert_true(
		hud._research_panel.get_combined_minimum_size().y <= hud._research_wrap.size.y + 0.5,
		"research content must fit its sheet"
	)
	hud.diplomacy_pressed.emit()
	await get_tree().process_frame
	_fits(hud._diplomacy_wrap.get_global_rect(), _screen_rect(), "court sheet")
	assert_true(
		hud._diplomacy_panel.get_combined_minimum_size().y <= hud._diplomacy_wrap.size.y + 0.5,
		"court content must fit its sheet"
	)


func test_ledger_header_fits_a_short_viewport() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_screen.economy.open_panel()
	await get_tree().process_frame
	var wrap: Control = hud._economy_wrap
	_fits(wrap.get_global_rect(), _screen_rect(), "ledger")
	var panel: EconomyPanel = hud.panels.economy_panel
	assert_true(
		panel.get_combined_minimum_size().y <= wrap.size.y + 0.5,
		"ledger content must not overflow its sheet (%s > %s)"
		% [panel.get_combined_minimum_size().y, wrap.size.y]
	)
	assert_eq(panel.tabs_min_height(), 0.0)


func test_estates_rows_are_thumb_sized_on_a_phone() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var estates: ImprovementPanel = _screen.improvements
	estates.open(_screen.capital_province)
	await get_tree().process_frame
	_fits(estates._panel.get_global_rect(), _screen_rect(), "estates card")
	var actions: int = 0
	for node: Node in estates._rows.find_children("*", "Button", true, false):
		_tappable(node as Control, "estate action")
		actions += 1
	assert_gt(actions, 0, "estate rows expose their actions")
	for button: Button in estates.filter_buttons().values():
		_tappable(button, "estate filter %s" % button.text)


## --- helpers ---------------------------------------------------------------


func _open(size: Vector2i) -> void:
	if is_instance_valid(_screen):
		_screen.free()
		_screen = null
	if is_instance_valid(_viewport):
		_viewport.free()
		_viewport = null
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_screen = Fixture.attach_screen(_viewport)
	_screen.hud._relayout()


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _screen.hud.size)


func _fits(inner: Rect2, outer: Rect2, what: String) -> void:
	var pad: float = 0.5
	assert_true(
		inner.position.x >= -pad and inner.position.y >= -pad
		and inner.end.x <= outer.end.x + pad and inner.end.y <= outer.end.y + pad,
		"%s must fit: %s inside %s" % [what, inner, outer]
	)


func _contains(outer: Rect2, inner: Rect2) -> bool:
	var pad: float = 0.5
	return (
		inner.position.x >= outer.position.x - pad
		and inner.position.y >= outer.position.y - pad
		and inner.end.x <= outer.end.x + pad
		and inner.end.y <= outer.end.y + pad
	)


func _tappable(control: Control, what: String) -> void:
	assert_gt(control.get_global_rect().size.y, TOUCH_MIN - 0.5, "%s touch height" % what)
