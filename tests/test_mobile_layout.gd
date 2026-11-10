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
		assert_almost_eq(hud.top_bar.size.y, 56.0, 0.5, "one-row bar at %s" % size)
		_fits(hud.top_bar.get_global_rect(), _screen_rect(), "bar %s" % size)
		for chip: Control in hud.chips:
			_fits(chip.get_global_rect(), hud.top_bar.get_global_rect(), "chip %s" % size)
			assert_gt(
				chip.size.x, chip.get_combined_minimum_size().x - 0.5,
				"chip must not be squeezed at %s" % size
			)
			assert_not_null(_medallion(chip as Button), "chip keeps its medallion at %s" % size)
			var chip_caption := _caption_label(chip as Button)
			assert_not_null(chip_caption, "chip has a caption label at %s" % size)
			assert_false(chip_caption.visible, "chip caption yields on a phone %s" % size)
		for door: Button in _bar_doors(hud):
			var caption: String = _caption(door)
			_tappable(door, "bar door %s at %s" % [caption, size])
			assert_not_null(_medallion(door), "bar door keeps its medallion at %s" % size)
			assert_false(caption.is_empty(), "bar door keeps its caption at %s" % size)
			var caption_label := _caption_label(door)
			assert_not_null(caption_label, "bar door has a caption label at %s" % size)
			if door.has_meta("compact_icon_only"):
				assert_false(caption_label.visible, "command caption yields on a phone %s" % size)
			else:
				assert_true(caption_label.visible, "region keeps its label %s" % size)
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
		assert_not_null(estates._toggle.icon, "estates door keeps its medallion %s" % size)
		_fits(hud._lens_button.get_global_rect(), _screen_rect(), "lens button %s" % size)
		_tappable(hud._lens_button, "lens button %s" % size)
		_fits(
			hud._diplomacy_lens_button.get_global_rect(), _screen_rect(),
			"diplomacy lens button %s" % size
		)
		_tappable(hud._diplomacy_lens_button, "diplomacy lens button %s" % size)
		assert_gt(
			hud._diplomacy_lens_button.get_global_rect().position.x,
			hud._lens_button.get_global_rect().end.x,
			"the two lens seals never overlap %s" % size
		)
		_fits(
			hud._crown_lens_button.get_global_rect(), _screen_rect(),
			"crown road lens button %s" % size
		)
		_tappable(hud._crown_lens_button, "crown road lens button %s" % size)
		assert_gt(
			hud._crown_lens_button.get_global_rect().position.x,
			hud._diplomacy_lens_button.get_global_rect().end.x,
			"the three lens seals never overlap %s" % size
		)
		_fits(hud.lens_legend.get_global_rect(), _screen_rect(), "survey key %s" % size)
		assert_gt(
			hud.lens_legend.get_global_rect().position.x,
			hud.size.x - LensLegend.WIDTH - 20.0,
			"survey key right-docked %s" % size
		)


## The political key dresses the same cartouche as the survey key and stays
## right-docked on a phone.
func test_diplomacy_key_fits_a_phone() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	await get_tree().process_frame
	assert_true(hud.lens_legend.visible)
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	_fits(hud.lens_legend.get_global_rect(), _screen_rect(), "diplomacy key")
	assert_gt(
		hud.lens_legend.get_global_rect().position.x,
		hud.size.x - LensLegend.WIDTH - 20.0,
		"diplomacy key right-docked"
	)


## The crown-road key dresses the same cartouche as the survey key and stays
## right-docked on a phone.
func test_crown_road_key_fits_a_phone() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	MapPlayInput.set_crown_lens(_screen.play, true)
	await get_tree().process_frame
	assert_true(hud.lens_legend.visible)
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	_fits(hud.lens_legend.get_global_rect(), _screen_rect(), "crown road key")
	assert_gt(
		hud.lens_legend.get_global_rect().position.x,
		hud.size.x - LensLegend.WIDTH - 20.0,
		"crown road key right-docked"
	)


## Rotating a phone back to a tablet width restores the caption words that the
## compact cartouche dropped (the medallions stay put).
func test_resize_restores_the_wide_cartouche() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	assert_false(_caption_label(hud.chips[0] as Button).visible, "compact drops chip words")
	var command: Button = null
	for door: Button in _bar_doors(hud):
		if door.has_meta("compact_icon_only"):
			command = door
			break
	assert_not_null(command, "a command door exists")
	if command != null:
		assert_false(_caption_label(command).visible, "compact drops command words")
	_viewport.size = DESKTOP
	hud._relayout()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(_caption_label(hud.chips[0] as Button).visible, "wide restores chip words")
	if command != null:
		assert_true(_caption_label(command).visible, "wide restores command words")


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


## --- top bar ---------------------------------------------------------------


func test_top_bar_keeps_only_purposeful_plaques() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	assert_eq(hud.chips.size(), 4, "treasury, ships, civilians and troops remain")
	assert_null(hud.find_child("PrestigeChip", true, false), "prestige plaque removed")
	for node: Node in hud.top_bar.find_children("*", "Label", true, false):
		assert_ne((node as Label).text, "PRESTIGE", "no vanity counter survives")
	assert_eq(
		hud._income_label.text, TextFormat.delta(_screen.play.income),
		"treasury shows the projected turn income"
	)


func test_treasury_income_delta_is_signed_and_compact() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.set_income(240)
	assert_eq(hud._income_label.text, "+240")
	hud.set_income(-35)
	assert_eq(hud._income_label.text, "-35")
	hud.set_income(12_500)
	assert_eq(hud._income_label.text, "+12.5k", "large deltas keep the plaque width")
	hud.set_treasury(2_500, false)
	assert_true(hud._treasury_chip.tooltip_text.contains("+12.5k per turn"))


func test_status_plaques_find_the_next_force() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var hits: Array[int] = [0]
	hud.economy_pressed.connect(func() -> void: hits[0] += 1)
	_chip(hud, "TreasuryChip").pressed.emit()
	assert_eq(hits[0], 1, "treasury plaque opens the ledger")

	_chip(hud, "FleetChip").pressed.emit()
	await get_tree().process_frame
	assert_not_null(_screen.ship_layer.selected(), "ship plaque selects a squadron")
	_chip(hud, "CivilianChip").pressed.emit()
	await get_tree().process_frame
	assert_true(hud.civilian_roster.is_open(), "civilian plaque opens the empire roster")
	hud.civilian_roster.close()
	_chip(hud, "ArmyChip").pressed.emit()
	await get_tree().process_frame
	assert_not_null(_screen.army_layer.selected_army, "troop plaque selects an army")


func test_region_seal_goes_inert_with_a_single_region() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	HudChrome.set_region_label(hud, "OLD WORLD", false)
	assert_true(hud._region_button.disabled, "no fake switch on a one-region map")
	assert_eq(hud._region_label.text, "OLD WORLD", "region stays as context")
	assert_true(hud._region_button.tooltip_text.contains("only charted"))
	HudChrome.set_region_label(hud, "NEW WORLD", true)
	assert_false(hud._region_button.disabled, "two maps offer the switch again")


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
		assert_almost_eq(hud.top_bar.size.y, 60.0, 0.5)
		for chip: Control in hud.chips:
			assert_true(_caption_label(chip as Button).visible, "desktop chip keeps its word")
		for door: Button in _bar_doors(hud):
			assert_not_null(_medallion(door), "desktop door keeps its medallion")
			assert_false(_caption(door).is_empty(), "desktop door keeps its caption")
			assert_true(_caption_label(door).visible, "desktop door keeps its word")
		assert_almost_eq(hud.minimap_frame.size.x, 250.0, 0.5)
		assert_almost_eq(hud.end_turn_wrap.size.x, 212.0, 0.5)
		assert_eq(hud.panels.dock.width, GameHud.PANEL_WIDTH)


## --- dossiers --------------------------------------------------------------


func test_phone_dossier_keeps_its_orders_reachable() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.panels.panel.set_training_visible(true)
	hud.panels.show_province(_screen.model, _screen.capital_province)
	hud.panels.dock.place_shown(hud._panel_wrap)
	await get_tree().process_frame
	var panel: ProvincePanel = hud._panel
	_fits(panel.get_global_rect(), _screen_rect(), "dossier")
	assert_lt(panel._orders.get_global_rect().position.y, panel._grid.get_global_rect().position.y)
	var scroll: Control = panel.get_child(0).get_child(0)
	var immediate: int = 0
	for node: Node in panel._orders.find_children("*", "Button", true, false):
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
	assert_gt(panel._orders.get_global_rect().position.y, panel._grid.get_global_rect().position.y)
	_fits(panel.get_global_rect(), _screen_rect(), "dossier")
	assert_almost_eq(panel.size.x, GameHud.PANEL_WIDTH, 0.5)


## The sheet answers the two questions a developing province raises: how far its
## town has grown, and whether its estates can reach the crown at all
## (wiki: extraction-and-improvements § Extraction formula and town development
## cap, capital-and-connectivity § Connectivity).
func test_dossier_reports_the_town_level_and_the_crown_link() -> void:
	_open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var play: PlaySession = _screen.play
	var panel: ProvincePanel = hud._panel
	var capital: int = _screen.capital_province
	hud.panels.show_province(
		play.model, capital,
		LandConnectivity.province_link(
			play.model, play.land_works, play.player_faction, play.capital_tile,
			capital
		)
	)
	await get_tree().process_frame
	assert_eq(panel._grid.town.text, "Level 4 · full", "a Great Power seat is level 4")
	assert_true(
		panel._grid.road.text.contains("linked to the crown"),
		panel._grid.road.text
	)
	# An unlinked province (a fresh conquest has no setup road) says so and how
	# much road is left; the sheet repaints in place when the network changes.
	panel.refresh_crown({"linked": false, "roads": 2, "distance": 4})
	await get_tree().process_frame
	assert_eq(
		panel._grid.road.text, "2 road tiles · no road to the crown (4 tiles away)"
	)
	panel.refresh_crown({"linked": true, "roads": 3, "distance": 0})
	await get_tree().process_frame
	assert_eq(panel._grid.road.text, "3 road tiles · linked to the crown")
	# Build/Work repaints the open sheet from the live crown link.
	play.selected_province = capital
	MapPlayCivilians.resolve_work(play)
	await get_tree().process_frame
	var roads: int = int(
		MapPlayImprovements.crown_link(play, capital).get("roads", 0)
	)
	assert_eq(
		panel._grid.road.text,
		"%d road tile%s · linked to the crown" % [roads, "" if roads == 1 else "s"]
	)


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


## The strength block gains the zone's odds line when a hostile squadron shares
## the water: the tallest dossier still has to fit a phone sheet (REQ-P1-07).
func test_phone_fleet_dossier_fits_with_a_contested_zone() -> void:
	_open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var ship: Ship = _screen.ship_layer.ships[0]
	var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
	fleet.location = FleetState.Location.AT_SEA
	fleet.province = MapModel.NO_ID
	var rival: int = 1 if fleet.owner != 1 else 2
	var enemy := FleetState.at_sea(
		77, rival, fleet.sea_zone, ["ship_77"], {"ship_77": "frigate"}
	)
	_screen.ship_layer.fleets.append(enemy)
	if _screen.play.diplomacy == null:
		_screen.play.diplomacy = DiplomacyState.new()
	_screen.play.diplomacy.ensure_relation(fleet.owner, rival, _screen.play.turn)
	DiplomacyRules.declare_war(_screen.play.diplomacy, fleet.owner, rival, false)

	MapPlayFleets.select(_screen.play, ship)
	hud.panels.dock.place_shown(hud._fleet_wrap)
	await get_tree().process_frame

	assert_true(hud._fleet_panel._strength._zone.visible, "the zone's odds are shown")
	assert_true(
		hud._fleet_panel.get_combined_minimum_size().y <= hud._fleet_wrap.size.y + 0.5,
		"a contested dossier must fit its sheet (%s > %s)"
		% [hud._fleet_panel.get_combined_minimum_size().y, hud._fleet_wrap.size.y]
	)
	_screen.ship_layer.fleets.erase(enemy)


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


func _chip(hud: GameHud, name_text: String) -> Button:
	var button := hud.find_child(name_text, true, false) as Button
	assert_not_null(button, "%s exists" % name_text)
	return button


func _bar_doors(hud: GameHud) -> Array[Button]:
	var doors: Array[Button] = []
	for node: Node in hud.top_row.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or hud.chips.has(button):
			continue
		doors.append(button)
	return doors


func _medallion(button: Button) -> Texture2D:
	var rect := button.find_child("Medallion", true, false) as TextureRect
	return rect.texture if rect != null else null


func _caption(button: Button) -> String:
	var label := _caption_label(button)
	return label.text if label != null else ""


func _caption_label(button: Button) -> Label:
	return button.find_child("Caption", true, false) as Label
