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
## The bar's reading doors: each one opens the same full-screen modal (issue
## #692). The crew chip opens the roster, which already did.
const MODAL_DOORS: Array[String] = [
	"LEDGER", "RESEARCH", "COURT", "MUSTER", "ESTATES", "GAZETTE",
]

## One mount for the whole suite (docs/testing.md § Speed rules): a case that
## reads the chrome at a size re-seats the shared screen from this pristine save
## (~0.15 s) instead of mounting the chart again (~0.5 s under coverage).
## Non-underscore so before_all copies the node refs onto each case; underscore
## aliases are filled in before_each (gd-tools does not copy `_screen`).
var viewport: SubViewport = null
var mounted: MapScreen = null
var screen_pristine: Dictionary = {}
var world_snapshot: Array = []
var _viewport: SubViewport = null
var _screen: MapScreen = null


func before_all() -> void:
	world_snapshot = Fixture.snapshot(Fixture.world())
	Fixture.restore(Fixture.world(), world_snapshot)
	viewport = SubViewport.new()
	viewport.size = PHONE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	mounted = Fixture.attach_screen(viewport)
	screen_pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	_viewport = viewport
	_screen = mounted


func after_all() -> void:
	if is_instance_valid(mounted):
		if mounted.hud != null and mounted.hud.stats != null:
			mounted.hud.stats.clear_animations()
		mounted.free()
	mounted = null
	_screen = null
	if is_instance_valid(viewport):
		viewport.free()
	viewport = null
	_viewport = null
	Fixture.restore(Fixture.world(), world_snapshot)
	screen_pristine = {}
	world_snapshot = []


## Drops a door the last case left open: a full-screen modal is not a docked
## sheet, so the shared reset does not know to close it.
func _close_modals() -> void:
	for node: Node in _screen.find_children("*", "", true, false):
		var shell: ModalShell = node as ModalShell
		if shell != null and shell.is_open():
			shell.close()


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


## --- safe area -------------------------------------------------------------


## A punch-hole in the middle of an edge costs that edge only: reading the raw
## rectangles as a band would have pushed the whole HUD sideways.
func test_cutouts_eat_only_the_edge_they_are_cut_into() -> void:
	var screen := Vector2(2400.0, 1080.0)
	var units := Vector2(914.0, 411.0)
	var top_hole: Array[Rect2] = [Rect2(1180.0, 0.0, 40.0, 60.0)]
	var insets: Vector4 = PlatformDisplay.cutout_insets(top_hole, screen, units)
	assert_almost_eq(insets.y, 60.0 / 1080.0 * 411.0, 0.01)
	assert_almost_eq(insets.x, 0.0, 0.01)
	assert_almost_eq(insets.z, 0.0, 0.01)
	assert_almost_eq(insets.w, 0.0, 0.01)
	# A phone in landscape: the same hole is cut into the left edge instead.
	var landscape: Array[Rect2] = [Rect2(0.0, 500.0, 60.0, 40.0)]
	insets = PlatformDisplay.cutout_insets(landscape, screen, units)
	assert_almost_eq(insets.x, 60.0 / 2400.0 * 914.0, 0.01)
	assert_almost_eq(insets.y, 0.0, 0.01)
	assert_almost_eq(insets.z, 0.0, 0.01)
	assert_almost_eq(insets.w, 0.0, 0.01)


func test_cutouts_report_each_edge_in_points() -> void:
	var screen := Vector2(2340.0, 1080.0)
	var units := Vector2(780.0, 360.0)
	var edges: Array[Rect2] = [
		Rect2(0.0, 0.0, 90.0, 40.0),
		Rect2(2290.0, 0.0, 50.0, 120.0),
	]
	var insets: Vector4 = PlatformDisplay.cutout_insets(edges, screen, units)
	assert_almost_eq(insets.y, 120.0 / 1080.0 * 360.0, 0.01)
	assert_almost_eq(insets.x, 90.0 / 2340.0 * 780.0, 0.01)
	assert_almost_eq(insets.z, 50.0 / 2340.0 * 780.0, 0.01)
	assert_almost_eq(insets.w, 0.0, 0.01)
	var none: Array[Rect2] = []
	assert_eq(PlatformDisplay.cutout_insets(none, screen, units), Vector4.ZERO)


func test_safe_area_rectangle_becomes_insets() -> void:
	var screen := Vector2(1000.0, 500.0)
	var units := Vector2(500.0, 250.0)
	var insets: Vector4 = PlatformDisplay.edge_insets(Rect2(20.0, 10.0, 950.0, 470.0), screen, units)
	assert_almost_eq(insets.x, 10.0, 0.01)
	assert_almost_eq(insets.y, 5.0, 0.01)
	assert_almost_eq(insets.z, 15.0, 0.01)
	assert_almost_eq(insets.w, 10.0, 0.01)
	assert_eq(
		PlatformDisplay.edge_insets(Rect2(), screen, units), Vector4.ZERO, "no area reads as no insets"
	)


## The one rule no later edit may bend: Android reads the cutouts and ignores
## the safe area it is handed, because asking the engine for that area kills the
## process on Android 17 (docs/android-build.md).
func test_android_reads_cutouts_and_never_the_safe_area() -> void:
	var screen := Vector2(2400.0, 1080.0)
	var units := Vector2(914.0, 411.0)
	var cutouts: Array[Rect2] = [Rect2(1180.0, 0.0, 40.0, 60.0)]
	# A safe area that would claim a 200 px band on every edge: Android must not
	# read a single point of it.
	var area := Rect2(200.0, 200.0, 2000.0, 680.0)
	var phone: Vector4 = PlatformDisplay.insets_for(true, cutouts, area, screen, units)
	assert_almost_eq(phone.y, 60.0 / 1080.0 * 411.0, 0.01)
	assert_almost_eq(phone.x, 0.0, 0.01)
	assert_almost_eq(phone.z, 0.0, 0.01)
	assert_almost_eq(phone.w, 0.0, 0.01)
	# Every other handheld keeps the safe area it reports.
	var other: Vector4 = PlatformDisplay.insets_for(false, cutouts, area, screen, units)
	assert_almost_eq(other.x, 200.0 / 2400.0 * 914.0, 0.01)
	assert_almost_eq(other.w, 200.0 / 1080.0 * 411.0, 0.01)
	assert_eq(PlatformDisplay.insets_for(true, [] as Array[Rect2], Rect2(), screen, units), Vector4.ZERO)
	assert_eq(PlatformDisplay.insets_for(false, [] as Array[Rect2], Rect2(), screen, units), Vector4.ZERO)


func test_degenerate_cutouts_and_screens_read_as_no_insets() -> void:
	var units := Vector2(900.0, 400.0)
	var holes: Array[Rect2] = [Rect2(0.0, 0.0, 0.0, 0.0), Rect2(0.0, 0.0, 40.0, 60.0)]
	assert_eq(PlatformDisplay.cutout_insets(holes, Vector2.ZERO, units), Vector4.ZERO)
	var insets: Vector4 = PlatformDisplay.cutout_insets(holes, Vector2(1000.0, 500.0), units)
	assert_almost_eq(insets.y, 60.0 / 500.0 * 400.0, 0.01, "the empty rectangle is skipped")
	assert_eq(PlatformDisplay.safe_insets(null), Vector4.ZERO, "no window reads as no insets")


## --- chrome ----------------------------------------------------------------


func test_phone_chrome_fits_the_screen() -> void:
	for size: Vector2i in [PHONE, SMALL]:
		await _open(size)
		await get_tree().process_frame
		var hud: GameHud = _screen.hud
		assert_true(HudLayout.is_compact(hud.size), "compact at %s" % size)
		# One row while the measured row fits; the plaques fall to a second row
		# otherwise (never a third, never clipped text).
		assert_true(
			is_equal_approx(hud.top_bar.size.y, 56.0)
			or is_equal_approx(hud.top_bar.size.y, HudLayout.STACK_BAR_HEIGHT),
			"measured bar at %s (%.0f)" % [size, hud.top_bar.size.y]
		)
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
		_tappable(hud._end_turn_button, "end turn %s" % size)
		for button: Node in hud.zoom_box.get_children():
			_fits((button as Control).get_global_rect(), _screen_rect(), "zoom %s" % size)
			_tappable(button as Control, "zoom %s" % size)
		# The map carries no sound seal now: the pause menu holds the mix desk.
		assert_not_null(_screen.game_menu.sound_desk, "pause menu carries the desk %s" % size)
		var estates: Button = hud.top_row.find_child("EstatesSeal", true, false) as Button
		assert_not_null(estates, "estates door on the bar %s" % size)
		_fits(estates.get_global_rect(), hud.top_bar.get_global_rect(), "estates %s" % size)
		_tappable(estates, "estates %s" % size)
		assert_not_null(_medallion(estates), "estates door keeps its medallion %s" % size)
		_fits(hud.lens_seal.get_global_rect(), hud.top_bar.get_global_rect(), "lens seal %s" % size)
		assert_eq(_caption(hud.lens_seal), "LENS", "the one lens seal is named %s" % size)
		assert_not_null(
			hud.top_row.find_child("MenuSeal", true, false), "menu seal on the bar %s" % size
		)
		_fits(hud.lens_legend.get_global_rect(), _screen_rect(), "survey key %s" % size)
		assert_gt(
			hud.lens_legend.get_global_rect().position.x,
			hud.size.x - LensLegend.WIDTH - 20.0,
			"survey key right-docked %s" % size
		)


## The sea key dresses the same cartouche and stays right-docked on a phone: its
## five pennant rows are the tallest reading the cartouche carries.
func test_the_sea_key_fits_a_phone() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	MapPlayInput.set_sea_lens(_screen.play, true)
	await get_tree().process_frame
	assert_true(hud.lens_legend.visible)
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_SEA)
	_fits(hud.lens_legend.get_global_rect(), _screen_rect(), "sea key")
	assert_gt(
		hud.lens_legend.get_global_rect().position.x,
		hud.size.x - LensLegend.WIDTH - 20.0,
		"sea key right-docked"
	)


## The political key dresses the same cartouche as the survey key and stays
## right-docked on a phone.
func test_diplomacy_key_fits_a_phone() -> void:
	await _open(PHONE)
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


## Rotating a phone back to a tablet width restores the caption words that the
## compact cartouche dropped (the medallions stay put).
func test_resize_restores_the_wide_cartouche() -> void:
	await _open(PHONE)
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
	await get_tree().process_frame
	hud._relayout()
	await get_tree().process_frame
	assert_true(_caption_label(hud.chips[0] as Button).visible, "wide restores chip words")
	if command != null:
		assert_true(_caption_label(command).visible, "wide restores command words")
	# Unstack must put chips back before the gold door (not after it).
	assert_gt(
		hud.end_turn_wrap.get_global_rect().position.x,
		hud.size.x - 220.0,
		"wide keeps the end-turn door at the bar's right end"
	)


func test_chip_values_do_not_shift_the_bar() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var height: float = hud.top_bar.size.y
	hud.stats.set_treasury(123456, false)
	await get_tree().process_frame
	assert_almost_eq(hud.top_bar.size.y, height, 0.5)
	for chip: Control in hud.chips:
		_fits(chip.get_global_rect(), hud.top_bar.get_global_rect(), "chip after growth")


## --- top bar ---------------------------------------------------------------


func test_top_bar_keeps_only_purposeful_plaques() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	assert_eq(hud.chips.size(), 4, "treasury, ships, civilians and troops remain")
	assert_null(hud.find_child("PrestigeChip", true, false), "prestige plaque removed")
	for node: Node in hud.top_bar.find_children("*", "Label", true, false):
		assert_ne((node as Label).text, "PRESTIGE", "no vanity counter survives")
	assert_eq(
		hud.stats.income_label.text, TextFormat.delta(_screen.play.income),
		"treasury shows the projected turn income"
	)


func test_treasury_income_delta_is_signed_and_compact() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.stats.set_income(240)
	assert_eq(hud.stats.income_label.text, "+240")
	hud.stats.set_income(-35)
	assert_eq(hud.stats.income_label.text, "-35")
	hud.stats.set_income(12_500)
	assert_eq(hud.stats.income_label.text, "+12.5k", "large deltas keep the plaque width")
	hud.stats.set_treasury(2_500, false)
	assert_true(hud.stats.treasury_chip.tooltip_text.contains("+12.5k per turn"))


## The plaques state the standing the turn left: the count, its signed movement
## and the forces, each reachable from its own tooltip (REQ-P5-05).
func test_status_plaques_state_the_standing() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.stats.set_treasury(2_500, false)
	hud.stats.set_income(-35)
	hud.stats.set_fleets(7)
	hud.stats.set_civilians(3)
	hud.stats.set_armies(11)

	assert_eq(hud.stats.treasury_label.text, "2,500")
	assert_eq(hud.stats.income_label.text, "-35")
	assert_eq(hud.stats.fleet_label.text, "7")
	assert_eq(hud.stats.civilian_label.text, "3")
	assert_eq(hud.stats.army_label.text, "11")
	assert_true(hud.stats.treasury_chip.tooltip_text.contains("2,500"))
	assert_true(hud.stats.fleet_chip.tooltip_text.contains("7"))
	assert_true(hud.stats.civilian_chip.tooltip_text.contains("3"))
	assert_true(hud.stats.army_chip.tooltip_text.contains("11"))


## A coin gain lifts off the treasury plaque rather than repainting it in silence.
func test_a_coin_gain_lifts_off_the_treasury_plaque() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.stats.set_treasury(1_000, false)
	hud.stats.flash_income(240)
	var lifted: Label = null
	for node: Node in hud.get_children():
		if node is Label and (node as Label).text == "+240":
			lifted = node as Label
			break
	assert_not_null(lifted, "the gain shows its own line")
	if lifted != null:
		assert_eq(lifted.position.x, hud.stats.treasury_chip.get_global_rect().position.x)


## The count animates to its new standing instead of jumping (REQ-P5-05).
func test_the_treasury_count_counts_up_to_the_standing() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.stats.set_treasury(0, false)
	hud.stats.set_treasury(1_200)
	# The chip tweens for 0.6 s; wait for the standing instead of a fixed sleep
	# so a loaded worker is not held past the animation (playbook: no sleeps).
	for _frame in 90:
		if hud.stats.treasury_label.text == "1,200":
			break
		await get_tree().process_frame
	assert_eq(hud.stats.treasury_label.text, "1,200")


func test_status_plaques_find_the_next_force() -> void:
	await _open(PHONE)
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


## The bar's one reading seal: a click walks every lens and wraps back to the
## plain map, and a long press names one on the menu instead. The crest beside
## it opens the pause menu, which now carries the mix desk.
func test_the_bar_seals_cycle_the_readings_and_open_the_menu() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var seal: LensSeal = hud.lens_seal
	assert_not_null(seal, "the bar carries one lens seal")
	assert_eq(seal.active_kind, "", "the map opens plain")

	for kind: String in [
		LensLegend.KIND_SURVEY, LensLegend.KIND_DIPLOMACY,
		LensLegend.KIND_CROWN_ROAD, LensLegend.KIND_DEFENCE, LensLegend.KIND_SEA,
	]:
		seal.pressed.emit()
		assert_eq(seal.active_kind, kind, "the click walks to %s" % kind)
		assert_true(seal.button_pressed, "%s shows the seal raised" % kind)
		assert_true(hud.lens_legend.visible, "%s raises the key" % kind)
		assert_eq(hud.lens_legend.kind, kind, "%s dresses the key" % kind)

	seal.pressed.emit()
	assert_eq(seal.active_kind, "", "the last step puts the map back to plain")
	assert_false(seal.button_pressed)
	assert_false(hud.lens_legend.visible)

	# A hold (or a right click) names the reading instead of walking it.
	seal._on_held()
	assert_true(seal.is_menu_open(), "the hold opens the lens list")
	seal.choose(LensLegend.KIND_CROWN_ROAD)
	assert_eq(seal.active_kind, LensLegend.KIND_CROWN_ROAD, "the pick raises its reading")
	assert_eq(hud.lens_legend.kind, LensLegend.KIND_CROWN_ROAD)
	var medallion := seal.find_child("Medallion", true, false) as TextureRect
	assert_not_null(medallion, "the seal keeps a medallion")
	if medallion != null:
		assert_eq(medallion.texture, ChromeIcons.texture("road"), "the pictogram follows the lens")
	assert_true(seal.tooltip_text.contains("crown road"), "the tooltip names the reading")
	seal.choose("")
	assert_eq(seal.active_kind, "", "the menu can put the reading down")
	assert_eq(medallion.texture, ChromeIcons.texture("lens"))

	# The crest opens the pause menu, and the desk is bound there.
	var door := hud.top_row.find_child("MenuSeal", true, false) as Button
	assert_not_null(door, "the cartouche carries the pause door")
	if door != null:
		door.pressed.emit()
	assert_true(_screen.game_menu.is_open(), "the crest opens the pause menu")
	assert_not_null(_screen.game_menu.sound_desk, "the pause menu carries the mix desk")
	assert_not_null(_screen.game_menu.sound_desk.music, "with its music slider")
	_screen.game_menu.close()
	assert_false(_screen.game_menu.is_open())


## The chart pill rides the map's own corner now (issue #1164): a short word on
## a one-chart world, and a live press as soon as a second chart exists.
func test_the_chart_pill_goes_inert_with_a_single_region() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	assert_not_null(hud.map_region, "the map carries its own chart pill")
	var rect: Rect2 = hud.map_region.get_global_rect()
	assert_true(
		rect.position.y >= hud.top_bar.offset_bottom,
		"the pill stands on the chart, under the cartouche"
	)
	assert_lt(rect.position.x, 40.0, "at the map's own left corner")
	assert_lt(hud.map_region.size.x, 70.0, "and stays small")
	HudChrome.set_region_label(hud, "OLD WORLD", false)
	assert_true(hud._region_button.disabled, "no fake switch on a one-region map")
	assert_eq(hud._region_label.text, "OLD", "the chart stays as context")
	assert_true(hud._region_button.tooltip_text.contains("only charted"))
	HudChrome.set_region_label(hud, "NEW WORLD", true)
	assert_false(hud._region_button.disabled, "two maps offer the switch again")
	assert_eq(hud._region_label.text, "NEW", "and the pill names the chart in play")


func test_desktop_chrome_keeps_its_atlas_geometry() -> void:
	for size: Vector2i in [DESKTOP, TABLET]:
		await _open(size)
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
		assert_almost_eq(hud.end_turn_wrap.size.x, EndTurnDoor.SIZE.x, 0.5)
		assert_eq(hud.panels.dock.width, GameHud.PANEL_WIDTH)


## --- map chrome ------------------------------------------------------------


## Non-navigation chrome lives on the bar: the chart keeps its corner, and the
## ledgers open from a seal that never sits over the map (REQ-P1-07).
func test_estates_and_gazette_doors_live_on_the_bar() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var estates := hud.top_row.find_child("EstatesSeal", true, false) as Button
	var gazette := hud.top_row.find_child("GazetteSeal", true, false) as Button
	assert_not_null(estates, "the estates door is on the bar")
	assert_not_null(gazette, "the Gazette door is on the bar")
	assert_eq(HudLayout.LEFT_RAIL, 0.0, "nothing is parked on the left rail")
	var panel: ImprovementPanel = _screen.improvements
	var loose: int = 0
	for node: Node in panel.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():
			loose += 1
	assert_eq(loose, 0, "the estates ledger parks no door over the chart")
	estates.pressed.emit()
	await get_tree().process_frame
	assert_true(panel.is_open(), "the bar door opens the estates ledger")
	panel.close()
	gazette.pressed.emit()
	await get_tree().process_frame
	assert_true(hud.gazette_plate.is_shown(), "the bar door opens the Gazette")
	hud.gazette_plate.dismiss()


## The turn is the bar's gold door: one reach from anywhere, no corner plate
## over the chart (REQ-P1-07, REQ-P5-01).
func test_end_turn_is_the_bars_gold_door() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var bar: Rect2 = hud.top_bar.get_global_rect()
	var door: Rect2 = hud.end_turn_wrap.get_global_rect()
	assert_true(
		door.position.y >= bar.position.y and door.end.y <= bar.end.y + 0.5,
		"the end-turn door sits in the bar"
	)
	assert_gt(door.position.x, hud.size.x - 220.0, "the door holds the bar's right end")
	_tappable(hud._end_turn_button, "end turn")
	assert_eq(hud._end_turn_button.text, "END TURN")
	assert_false(
		hud._end_turn_button.pressed.get_connections().is_empty(),
		"the door ends the turn"
	)


## An opened dossier is movable by its own chrome, so the chart feature it covers
## can be read without closing it (REQ-P1-07). The bar's doors are not draggable:
## they are modals and take the screen (REQ-P1-05).
func test_opened_dossiers_can_be_pushed_aside() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud

	# A docked dossier moves too, and opens from the dock again next time.
	hud.panels.show_province(_screen.model, _screen.capital_province)
	hud.panels.dock.place_shown(hud._panel_wrap)
	await get_tree().process_frame
	var wrap: Control = hud._panel_wrap
	var docked: Vector2 = wrap.get_global_rect().position
	_drag(hud._panel, Vector2(-40.0, 0.0))
	await get_tree().process_frame
	assert_almost_eq(
		wrap.get_global_rect().position.x, docked.x - 40.0, 1.0, "the dossier follows the drag"
	)
	hud.panels.hide_province()
	await get_tree().process_frame
	hud.panels.show_province(_screen.model, _screen.capital_province)
	await get_tree().process_frame
	var engine: ModalDrag = wrap.get_meta(ModalDrag.META) as ModalDrag
	assert_not_null(engine, "the dossier carries its drag")
	if engine != null:
		assert_eq(engine.offset(), Vector2.ZERO, "a reopened dossier starts from the dock")


## The plate keeps up with a fast pointer instead of fighting it (issue #1081).
## `gui_input` hands the pointer in the grab's own frame, and the grab rides the
## plate, so a drag that reads those points raw shortens its own delta every
## move: the plate trails by half the travel and springs back. This walks a
## pointer in equal steps and re-reads its local point against the plate as it
## now stands — exactly what the engine reports — so a local-frame drag stalls
## and a fixed-frame one never leaves the pointer.
func test_a_plate_follows_a_fast_pointer_without_springing_back() -> void:
	var stage := Control.new()
	stage.size = Vector2(800.0, 600.0)
	add_child(stage)
	var plate := Control.new()
	plate.position = Vector2(200.0, 150.0)
	plate.size = Vector2(240.0, 180.0)
	stage.add_child(plate)
	var grab := Control.new()
	grab.size = Vector2(240.0, 32.0)
	plate.add_child(grab)
	ModalDrag.attach(stage, plate, [grab] as Array[Control], plate)

	var grip := Vector2(12.0, 12.0)
	var start: Vector2 = plate.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = grip
	grab.gui_input.emit(press)

	var step := Vector2(37.0, -21.0)
	var travel := Vector2.ZERO
	for i: int in 6:
		travel += step
		# The engine reports the pointer relative to where the grab stands now.
		var move := InputEventMouseMotion.new()
		move.position = grip + travel - (plate.position - start)
		grab.gui_input.emit(move)
		assert_true(
			plate.position.is_equal_approx(start + travel),
			"step %d: the plate stands under the pointer (%s, wanted %s)"
			% [i + 1, plate.position, start + travel]
		)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = grip + travel - (plate.position - start)
	grab.gui_input.emit(release)
	stage.queue_free()
	await get_tree().process_frame


## Every door on the cartouche opens the one full-screen modal: a wash that takes
## the pointer, a plate that takes the screen's room, and back closing it cleanly
## (issue #692; REQ-P1-05, REQ-P1-07, REQ-P5-07).
func test_every_cartouche_door_opens_a_full_screen_modal() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var opened: int = 0
	for door: Button in _bar_doors(hud):
		var caption: String = _caption(door)
		if not MODAL_DOORS.has(caption):
			continue
		door.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var shell: ModalShell = _open_shell(_screen)
		assert_not_null(shell, "%s opens a sheet" % caption)
		if shell == null:
			continue
		opened += 1
		assert_true(shell.is_open(), "%s stays open" % caption)
		assert_true(shell._margin.get_global_rect().size.x >= hud.size.x - 0.5, "%s takes the bar's width" % caption)
		assert_eq(shell._overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "%s takes the pointer" % caption)
		# Android delivers back twice for one press, so the helper debounces;
		# let the clock pass between doors instead of borrowing a real wait.
		BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
		assert_true(
			BackRequest.handle(_screen.play, _screen.improvements),
			"%s back closes the sheet" % caption
		)
		await get_tree().process_frame
		assert_false(shell.is_open(), "%s closes on back" % caption)
		assert_false(shell._panel.get_global_rect().size.y > hud.size.y + 0.5, "%s fits the screen" % caption)
	assert_eq(opened, MODAL_DOORS.size(), "every bar reading has its own door")



## --- dossiers --------------------------------------------------------------


func test_phone_dossier_keeps_its_orders_reachable() -> void:
	await _open(PHONE)
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
	await _open(DESKTOP)
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
	await _open(DESKTOP)
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
	await _open(PHONE)
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
	await _open(PHONE)
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


## A port coast lists a whole province of ground — 32 rows at Madrid. The open
## list rides a window of whole rows inside the passengers block, so the dossier
## stays a short sheet and the way back never scrolls away from the crown
## (DR-20261119-03, REQ-P1-07, REQ-P5-07).
func test_phone_passengers_window_a_port_s_whole_land() -> void:
	for size: Vector2i in [PHONE, SMALL, TABLET]:
		await _open(size)
		var block := FleetCrewSection.new()
		_viewport.add_child(block)
		block.size = Vector2(320.0, 400.0)
		var tiles: Array = []
		for i in 32:
			tiles.append({"x": i % 8, "y": int(i / 8), "ground": "Plains · grain"})
		block.set_data({
			"count": 1, "note": "1 aboard: Builder", "embark": [], "sortie": [],
			"land": [{
				"province": 4, "name": "Madrid", "crew": "builder",
				"crew_name": "Builder", "tiles": tiles,
			}],
		})
		var coasts: Array[Node] = block.find_children("", "Button", true, false)
		(coasts[0] as Button).pressed.emit()
		await get_tree().process_frame
		var window: ScrollContainer = block._ground_scroll
		var compact: bool = HudLayout.is_compact(size)
		assert_eq(
			window.custom_minimum_size.y, GroundsWindow.height(32, compact),
			"%s: the window takes whole rows" % size
		)
		assert_eq(window.get_child(0).get_child_count(), 32, "%s: every ground rides it" % size)
		assert_true(
			block.get_combined_minimum_size().y < 32.0 * GroundsWindow.ROW_HEIGHT,
			"%s: 32 grounds do not grow the sheet (%s)"
			% [size, block.get_combined_minimum_size().y]
		)
		# The way back stands above the window, on the sheet, at every size.
		var back: Array[Node] = block.find_children("", "Button", true, false)
		assert_true(
			(back[0] as Button).get_global_rect().end.y
				<= window.get_global_rect().position.y + 0.5,
			"%s: the way back stays above the list" % size
		)
		block.free()


func test_phone_ledgers_fit_their_sheets() -> void:
	await _open(PHONE)
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


## The tallest ledger: every slot at study, so every row carries a spend line
## and a gauge instead of collapsing to an idle label.
func test_the_ledger_fits_a_phone_with_every_slot_at_study() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var state: ResearchState = _screen.economy.economy.research
	for tech_id: String in ["land_enclosure", "crop_rotation", "saw_mill"]:
		assert_true(bool(state.assign(tech_id, "medium")["ok"]), tech_id)
	hud.research_pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_size: Vector2 = hud._research_panel.get_combined_minimum_size()
	_fits(hud._research_wrap.get_global_rect(), _screen_rect(), "research sheet")
	assert_true(
		panel_size.y <= hud._research_wrap.size.y + 0.5,
		"research content must fit its sheet with every slot at study (%s > %s)"
		% [panel_size.y, hud._research_wrap.size.y]
	)


## The modern floor (800x360): three studies at once cannot stand above the
## press and the two lists at their own heights. The queue takes a window of
## whole rows and the lists keep their floor, so the sheet stays on the screen
## with nothing clipped (DR-20261119-02, REQ-P1-07, REQ-P5-07).
func test_phone_college_fits_the_small_screen() -> void:
	await _open(SMALL)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var state: ResearchState = _screen.economy.economy.research
	for tech_id: String in ["land_enclosure", "crop_rotation", "saw_mill"]:
		assert_true(bool(state.assign(tech_id, "medium")["ok"]), tech_id)
	hud.research_pressed.emit()
	for _frame in 3:
		await get_tree().process_frame
	var panel: ResearchPanel = hud.panels.research_panel
	var wrap: Control = hud._research_wrap
	_fits(wrap.get_global_rect(), _screen_rect(), "college sheet")
	assert_true(
		panel.get_combined_minimum_size().y <= wrap.size.y + 0.5,
		"the college must fit its sheet with every slot at study (%s > %s)"
		% [panel.get_combined_minimum_size().y, wrap.size.y]
	)
	# The lists keep a floor of their own: the queue never eats the catalogue.
	assert_true(
		panel._tabs.size.y >= ResearchSheetFit.LISTS_FLOOR - 0.5,
		"the lists keep their floor (%s)" % panel._tabs.size.y
	)
	# The queue's window holds a whole row and the rest is still reachable.
	var first: ResearchSlotRow = panel._slot_rows.get(0)
	assert_true(first != null, "the college keeps a row per slot")
	assert_true(
		panel._slots_scroll.size.y >= first.get_combined_minimum_size().y - 0.5,
		"one slot row stands whole in the window"
	)
	assert_true(
		panel._slots_scroll.size.y < panel._slots_body.get_combined_minimum_size().y + 0.5
		or panel._slots_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"the queue's window can scroll to the rows below"
	)
	# The one press stays on the sheet, under the window.
	var press: ResearchFundPress = panel.fund_press()
	assert_true(press != null and press.visible, "the press stays on the sheet")
	assert_true(
		press.get_global_rect().end.y <= panel.get_global_rect().end.y + 0.5,
		"the press sits inside the sheet"
	)


## The same sheet one state further: every slot at study, a goal set and a purse
## that cannot pay, so the goal strip and the unpaid notice both stand. The lists
## keep their floor, one whole row stands in the window, and the plate is still
## the room it is given — at the modern floor and on the 360 dp sheet
## (DR-20261120-03, REQ-P1-07, REQ-P5-07).
func test_phone_college_keeps_its_lists_with_a_goal_and_a_thin_purse() -> void:
	for size: Vector2i in [SMALL, Vector2i(720, 360)]:
		await _open(size)
		await get_tree().process_frame
		var hud: GameHud = _screen.hud
		var state: ResearchState = _screen.economy.economy.research
		for tech_id: String in ["land_enclosure", "crop_rotation", "saw_mill"]:
			assert_true(bool(state.assign(tech_id, "maximum")["ok"]), tech_id)
		hud.research_pressed.emit()
		for _frame in 3:
			await get_tree().process_frame
		var panel: ResearchPanel = hud.panels.research_panel
		panel.set_goal("saw_mill")
		_screen.economy.economy.treasury = 200
		_screen.economy.refresh_research_panel()
		for _frame in 3:
			await get_tree().process_frame
		var wrap: Control = hud._research_wrap
		_fits(wrap.get_global_rect(), _screen_rect(), "%s: college sheet" % size)
		assert_true(panel._head.notice_shown(), "%s: the unpaid rule speaks" % size)
		# The sheet is the room it is given: the plate never grows past its box.
		assert_true(
			panel.get_combined_minimum_size().y <= wrap.size.y + 0.5,
			"%s: the college fits its plate (%s > %s)"
			% [size, panel.get_combined_minimum_size().y, wrap.size.y]
		)
		assert_almost_eq(panel._last_room, wrap.size.y, 0.5, "%s: the room is the plate" % size)
		# The catalogue keeps its floor: the goal strip and the notice do not
		# spend it. The 360 dp sheet is a hair under the handset's floor (58 of
		# the 60 it promises), so it is held to the tab strip it can pay for.
		var lists_floor: float = (
			ResearchSheetFit.LISTS_FLOOR if size == SMALL else ResearchSheetFit.TABS_FLOOR
		)
		assert_true(
			panel._tabs.size.y >= lists_floor - 0.5,
			"%s: the lists keep their floor (%s of %s)"
			% [size, panel._tabs.size.y, lists_floor]
		)
		# The goal keeps its row and every control on it, inside the sheet.
		var first: ResearchSlotRow = panel._slot_rows.get(0)
		assert_true(first != null, "%s: the college keeps a row per slot" % size)
		assert_true(
			panel._slots_scroll.size.y >= first.get_combined_minimum_size().y - 0.5,
			"%s: one slot row stands whole in the window" % size
		)
		assert_true(panel._goal_row.visible, "%s: the goal keeps its reading" % size)
		assert_true(
			panel._goal_row.get_parent() == panel._head_row,
			"%s: the goal rides the slots heading" % size
		)
		_fits(panel._goal_row.get_global_rect(), panel._head_row.get_global_rect(), "goal strip")
		var press: ResearchFundPress = panel.fund_press()
		assert_true(press != null and press.visible, "%s: the press stays on the sheet" % size)
		assert_true(
			press.get_global_rect().end.y <= panel.get_global_rect().end.y + 0.5,
			"%s: the press sits inside the sheet" % size
		)


## A desktop plate is taller than the dock the dossiers ride, and the college now
## budgets the plate it stands in: with every slot at study, a goal and a starving
## purse the pages keep their room and the sheet's content fills the plate instead
## of stopping at the dock's short budget (DR-20261120-03).
func test_the_college_budgets_the_plate_on_a_desktop() -> void:
	await _open(DESKTOP)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var state: ResearchState = _screen.economy.economy.research
	for tech_id: String in ["land_enclosure", "crop_rotation", "saw_mill"]:
		assert_true(bool(state.assign(tech_id, "maximum")["ok"]), tech_id)
	hud.research_pressed.emit()
	for _frame in 3:
		await get_tree().process_frame
	var panel: ResearchPanel = hud.panels.research_panel
	panel.set_goal("saw_mill")
	_screen.economy.economy.treasury = 200
	_screen.economy.refresh_research_panel()
	for _frame in 3:
		await get_tree().process_frame
	var wrap: Control = hud._research_wrap
	assert_almost_eq(panel._last_room, wrap.size.y, 0.5, "the room is the plate, not the dock")
	assert_true(
		panel._tabs.size.y >= 120.0,
		"the pages keep their room with every slot at study (%s)" % panel._tabs.size.y
	)
	assert_true(
		panel.get_combined_minimum_size().y <= wrap.size.y + 0.5,
		"the college fits its plate"
	)


## The plate is the room it is given, in every room: a budget too short to stand
## even the tab strip beside a slot row is answered by the queue's window, which
## scrolls, rather than by a college taller than its box (DR-20261120-03).
func test_the_college_never_asks_for_more_than_its_room() -> void:
	await _open(SMALL)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	var state: ResearchState = _screen.economy.economy.research
	for tech_id: String in ["land_enclosure", "crop_rotation", "saw_mill"]:
		assert_true(bool(state.assign(tech_id, "maximum")["ok"]), tech_id)
	hud.research_pressed.emit()
	for _frame in 3:
		await get_tree().process_frame
	var panel: ResearchPanel = hud.panels.research_panel
	var pad: float = panel.get_theme_stylebox("panel").get_minimum_size().y
	for room: float in [298.0, 200.0, 120.0]:
		var fit: Dictionary = ResearchSheetFit.split(
			panel._column, panel._slots_scroll, panel._tabs, panel._slots_body, room, pad
		)
		assert_true(
			float(fit["slots"]) + float(fit["tabs"]) <= room + 0.5,
			"a %s-point room is not asked for more (%s + %s)"
			% [room, fit["slots"], fit["tabs"]]
		)
	# A room that cannot carry the tab strip gives the window up, not the plate.
	var tight: Dictionary = ResearchSheetFit.split(
		panel._column, panel._slots_scroll, panel._tabs, panel._slots_body, 120.0, pad
	)
	assert_true(
		float(tight["tabs"]) < ResearchSheetFit.TABS_FLOOR,
		"the queue's window yields before the plate grows (%s)" % tight["tabs"]
	)


func test_ledger_header_fits_a_short_viewport() -> void:
	await _open(PHONE)
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


## The stockpile is the widest ledger page — medallion, name, workshop tag, hold,
## figure and two stepper buttons on one row — so on a phone it must fit the
## tab's width rather than scroll sideways (issue #453; REQ-P1-05, REQ-P1-07).
func test_the_stockpile_tab_fits_a_phone_width() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	_screen.economy.open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Control = panel.page_body(EconomyPanel.TAB_PRODUCTION) as Control
	var scroll: Control = body.get_parent() as Control
	assert_true(
		body.get_combined_minimum_size().x <= scroll.size.x + 0.5,
		"the stockpile must fit the tab's width (%s > %s)"
		% [body.get_combined_minimum_size().x, scroll.size.x]
	)


## The stockpile reads in columns, so a normal desktop sheet shows the whole
## catalogue without scrolling: Food | Raw materials | Manufactured, with Riches
## as a strip under them (issue #1196; REQ-P1-05, REQ-P1-07).
func test_the_stockpile_page_reads_in_three_columns_on_desktop() -> void:
	var parts: Array = await _stockpile(DESKTOP)
	var body: LedgerProduction = parts[0] as LedgerProduction
	var scroll: Control = parts[1] as Control
	var columns: HBoxContainer = body.get_child(0) as HBoxContainer
	assert_not_null(columns, "the page lays its sections in columns")
	assert_eq(columns.get_child_count(), 3, "Food, Raw materials and Manufactured")
	var heads: Array[Control] = []
	for column: Node in columns.get_children():
		heads.append(column.get_child(0) as Control)
	for index in range(1, heads.size()):
		assert_gt(
			heads[index].get_global_rect().position.x,
			heads[index - 1].get_global_rect().position.x + 1.0,
			"column %d stands beside the one before it" % index
		)
	var strip: Control = body.get_child(1) as Control
	assert_gt(
		strip.get_global_rect().position.y,
		columns.get_global_rect().position.y + 1.0,
		"Riches is a strip under the columns"
	)
	assert_true(
		body.get_combined_minimum_size().y <= scroll.size.y + 0.5,
		"the whole catalogue fits the sheet without scrolling (%s > %s)"
		% [body.get_combined_minimum_size().y, scroll.size.y]
	)


## A phone keeps two columns — the holdings share one, the workshop the other —
## and the steppers keep their thumb size (issue #1196; REQ-P5-07).
func test_the_stockpile_page_keeps_two_columns_on_a_phone() -> void:
	var parts: Array = await _stockpile(PHONE)
	var body: LedgerProduction = parts[0] as LedgerProduction
	var columns: HBoxContainer = body.get_child(0) as HBoxContainer
	assert_eq(columns.get_child_count(), 2, "two columns on a phone")
	var rows: Dictionary = body.recipe_rows()
	assert_gt(rows.size(), 0, "the workshop prints its rows")
	for recipe_id: String in rows.keys():
		var plus: Button = rows[recipe_id]["plus"] as Button
		assert_true(
			plus.size.y >= TOUCH_MIN - 0.5,
			"%s keeps a thumb-sized stepper (%s)" % [recipe_id, plus.size.y]
		)


## HAVE and SET sit over the figures they name on every Manufactured row: the
## heading reserves the steppers' own widths, so the workshop note and the two
## buttons can never throw the grid (issue #1197).
func test_the_manufactured_captions_sit_above_their_figures() -> void:
	for size: Vector2i in [DESKTOP, PHONE]:
		var parts: Array = await _stockpile(size)
		var body: LedgerProduction = parts[0] as LedgerProduction
		var head: Control = _manufactured_head(body)
		assert_not_null(head, "%s: the Manufactured heading carries its captions" % size)
		if head == null:
			continue
		var captions: Dictionary = {}
		for child: Node in head.get_children():
			var label := child as Label
			if label != null and not label.text.is_empty():
				captions[label.text] = label
		var rows: Dictionary = body.recipe_rows()
		for recipe_id: String in rows.keys():
			var have: Label = rows[recipe_id]["have"] as Label
			var stepper: Label = rows[recipe_id]["stepper"] as Label
			assert_almost_eq(
				(captions["HAVE"] as Label).get_global_rect().position.x,
				have.get_global_rect().position.x, 0.5,
				"%s: HAVE sits over the hold" % recipe_id
			)
			assert_almost_eq(
				(captions["SET"] as Label).get_global_rect().position.x,
				stepper.get_global_rect().position.x, 0.5,
				"%s: SET sits over the runs" % recipe_id
			)


## A stepper press sets the run and leaves the ledger open on PRODUCTION: the
## sheet repaints in place, so a crown never loses the page it was reading
## (issue #1197; REQ-P1-05).
func test_a_stepper_press_keeps_the_ledger_open_on_production() -> void:
	for size: Vector2i in [DESKTOP, PHONE]:
		var parts: Array = await _stockpile(size)
		var body: LedgerProduction = parts[0] as LedgerProduction
		var panel: EconomyPanel = parts[2] as EconomyPanel
		var economy: PlayerEconomy = _screen.economy.economy
		var recipe_id: String = ""
		for id: String in body.recipe_rows().keys():
			if not (body.recipe_rows()[id]["plus"] as Button).disabled:
				recipe_id = id
				break
		assert_false(recipe_id.is_empty(), "%s: a row offers a run" % size)
		var plus: Button = body.recipe_rows()[recipe_id]["plus"] as Button
		_tap(plus)
		await get_tree().process_frame
		assert_eq(
			economy.production.assignment_units(recipe_id), 1,
			"%s: the press set one run" % size
		)
		assert_true(
			_screen.hud.panels.is_economy_open(), "%s: the ledger stays open" % size
		)
		assert_eq(
			panel._tabs.current_tab, 0, "%s: the sheet keeps the PRODUCTION tab" % size
		)
		var minus: Button = body.recipe_rows()[recipe_id]["minus"] as Button
		_tap(minus)
		await get_tree().process_frame
		assert_eq(
			economy.production.assignment_units(recipe_id), 0,
			"%s: the minus took the run back" % size
		)
		assert_true(
			_screen.hud.panels.is_economy_open(), "%s: the ledger stays open" % size
		)


## The PRODUCTION tab sets runs one row at a time: the Queue-all press and its
## priced line are gone (issue #1196; REQ-P5-04).
func test_the_stockpile_page_carries_no_queue_all_press() -> void:
	var parts: Array = await _stockpile(DESKTOP)
	var body: LedgerProduction = parts[0] as LedgerProduction
	for node: Node in body.find_children("*", "", true, false):
		assert_false(node is RaiseBatchPress, "the page carries no batch press")
		var label := node as Label
		if label != null:
			assert_false(
				label.text.begins_with("Queue all"), "no Queue-all line: %s" % label.text
			)


## The PRODUCTION page at `size`, opened and laid out: the page, its scroll
## window and the panel it stands in.
func _stockpile(size: Vector2i) -> Array:
	await _open(size)
	await get_tree().process_frame
	_screen.economy.open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.select_tab(0)
	await get_tree().process_frame
	var body: LedgerProduction = panel.page_body(EconomyPanel.TAB_PRODUCTION) as LedgerProduction
	return [body, body.get_parent() as Control, panel]


## The Manufactured heading row: the one that carries the SET caption.
func _manufactured_head(body: Control) -> Control:
	for node: Node in body.find_children("*", "Label", true, false):
		if (node as Label).text == "SET":
			return node.get_parent() as Control
	return null


## A real tap on a control, through the viewport the sheet is drawn in.
func _tap(target: Control) -> void:
	var at: Vector2 = target.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		_viewport.push_input(event)



## The WORKERS tab carries two actions per trained row; on a phone both must be
## thumb-sized and inside the sheet's edge. The tab scrolls, so a row may sit
## below the fold — the drag area is the body, never a button (REQ-P1-05, REQ-P1-07).
func test_ledger_worker_actions_are_thumb_sized_on_a_phone() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_screen.economy.open_panel()
	await get_tree().process_frame
	var panel: EconomyPanel = hud.panels.economy_panel
	panel.select_tab(2)
	await get_tree().process_frame
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var sheet: Rect2 = hud._economy_wrap.get_global_rect()
	var marks: Dictionary = workers.tier_marks()
	assert_eq(marks.size(), WorkerPool.TIER_COUNT, "every tier row wears its medallion")
	for tier: Variant in marks.keys():
		var mark: Control = marks[tier] as Control
		assert_eq(
			mark.custom_minimum_size,
			Vector2(WorkerTierArt.MARK_COMPACT, WorkerTierArt.MARK_COMPACT),
			"a phone row grows the mark so the tier still reads"
		)
		assert_true(
			mark.get_global_rect().end.x <= sheet.end.x + 0.5,
			"the tier mark stays inside the sheet edge"
		)
	var buttons: Dictionary = workers.action_buttons()
	assert_true(buttons.has("disband:%d" % WorkerPool.Tier.APPRENTICE), "a trained row offers disband")
	assert_false(buttons.has("disband:%d" % WorkerPool.Tier.PEASANT), "a peasant row does not")
	for key: String in buttons.keys():
		var button: Button = buttons[key] as Button
		_tappable(button, "ledger action %s" % key)
		var rect: Rect2 = button.get_global_rect()
		assert_true(
			rect.position.x >= sheet.position.x - 0.5 and rect.end.x <= sheet.end.x + 0.5,
			"ledger action %s stays inside the sheet edge: %s in %s" % [key, rect, sheet]
		)
	# A tier the crown can pay for more than once adds one full-width batch press
	# under its row; it must be thumb-sized and inside the sheet too (REQ-P5-04).
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["fabric"] = 6
	_screen.economy.open_panel()
	await get_tree().process_frame
	workers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	var batches: Dictionary = workers.batch_buttons()
	assert_true(batches.has(WorkerPool.Tier.PEASANT), "six fabric pay for three peasants")
	for tier: Variant in batches.keys():
		var batch: Button = batches[tier] as Button
		_tappable(batch, "ledger batch %s" % tier)
		var batch_rect: Rect2 = batch.get_global_rect()
		assert_true(
			batch_rect.position.x >= sheet.position.x - 0.5
			and batch_rect.end.x <= sheet.end.x + 0.5,
			"ledger batch %s stays inside the sheet edge: %s in %s" % [tier, batch_rect, sheet]
		)


func test_estates_rows_are_thumb_sized_on_a_phone() -> void:
	await _open(PHONE)
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
	# The one press under the chips is a thumb target too, and it stays inside
	# the card's edge (REQ-P5-04, REQ-P5-07; DR-20261116-06).
	if estates._batch != null and estates._batch.visible:
		_tappable(estates._batch, "estate batch press")
		var press_rect: Rect2 = estates._batch.get_global_rect()
		var card: Rect2 = estates._panel.get_global_rect()
		assert_true(
			press_rect.position.x >= card.position.x - 0.5
			and press_rect.end.x <= card.end.x + 0.5,
			"the estates press stays inside the card edge: %s in %s" % [press_rect, card]
		)


## --- compact sheets ---------------------------------------------------------


## The card keeps its list: on a 411-point phone the header, filters and hint
## must not eat the scroll viewport, and a row folds its detail into one wide
## line instead of a narrow column (REQ-P1-07).
func test_phone_estates_keeps_the_list_in_view() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var estates: ImprovementPanel = _screen.improvements
	estates.open(_screen.capital_province)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Rect2 = estates._panel.get_global_rect()
	var list: Control = estates._rows.get_parent() as Control
	assert_true(
		list.size.y > card.size.y * 0.45,
		"the list keeps most of the card: %s of %s" % [list.size.y, card.size.y]
	)
	assert_false(estates._footer_box.visible, "the build hint yields on a phone")
	assert_false(estates._head._stores_line.visible, "the stores line yields; the ledger carries it")
	assert_false(estates._subtitle.visible, "the subtitle yields")
	var row: ImprovementRow = _first_estate_row(estates)
	assert_not_null(row, "the capital holds an estate row")
	if row == null:
		return
	assert_null(row._status, "no narrow state column on a phone")
	assert_not_null(row._detail, "location and status share one wide line")
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS, "a drag on the row scrolls the list")
	for node: Node in row.find_children("*", "Label", true, false):
		assert_ne(
			(node as Label).mouse_filter,
			Control.MOUSE_FILTER_STOP,
			"no label eats the drag that should scroll the list"
		)
	assert_true(row.get_global_rect().size.y <= 120.0, "one row stays compact")


## A phone sheet holds the court's news while it is up: stacked plates over a
## 411-point sheet would cover the very controls the player just opened. The
## opening turn may still be raising its own lines, so assert the line we
## raised is held (and absent from the lane), not the queue's exact size.
func test_phone_news_waits_while_the_estates_card_is_open() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_clear_news(hud)
	hud.toast("The Indies await")
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "a phone tells one line at a time")
	_screen.improvements.open(_screen.capital_province)
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 0, "the card clears the lane")
	assert_true(hud.despatches.held().has("The Indies await"), "the news waits")
	_screen.improvements.close()
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "the news prints once the card closes")


## The cartouche's GAZETTE door is a full-screen modal too, so the lane holds
## its lines while the crown reads the news it is standing on (issue #692).
func test_phone_news_waits_while_the_gazette_is_open() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_clear_news(hud)
	hud.toast("The Indies await")
	await get_tree().process_frame
	hud.gazette_pressed.emit()
	await get_tree().process_frame
	assert_true(hud.gazette_plate.is_shown(), "the GAZETTE door opens the sheet")
	assert_eq(hud.despatches.box.get_child_count(), 0, "no plate over the news sheet")
	assert_true(hud.despatches.held().has("The Indies await"), "the news waits")
	hud.gazette_plate.dismiss()
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "the news prints once the sheet closes")


func test_phone_news_waits_while_a_dossier_is_open() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_clear_news(hud)
	hud.panels.show_province(_screen.model, _screen.capital_province)
	await get_tree().process_frame
	hud.toast("A dispatch from the court")
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 0, "no plate over the dossier")
	assert_eq(hud.despatches.held().size(), 1)
	hud.panels.hide_province()
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "the news returns with the sheet closed")


## Cards the panel dock does not own (the empire roster) cover the lane just as
## completely; the HUD follows their open state even without a slot hook.
func test_phone_news_waits_while_the_roster_is_open() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_clear_news(hud)
	hud.toast("A dispatch from the court")
	await get_tree().process_frame
	hud.civilian_roster.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 0, "no plate over the roster")
	assert_true(hud.despatches.held().has("A dispatch from the court"), "the news waits")
	hud.civilian_roster.close()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "the news returns with the roster closed")


func test_phone_tells_one_despatch_at_a_time() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_clear_news(hud)
	hud.toast("one")
	hud.toast("two")
	hud.toast("three")
	await get_tree().process_frame
	assert_eq(hud.despatches.box.get_child_count(), 1, "one plate at a time")
	assert_eq(hud.despatches.waiting().size(), 2, "the rest wait their turn")


## The college's fixed chrome (three slot rows, goal strip, standing line) used
## to leave the tech list about one row tall; a phone keeps the list instead.
func test_phone_college_keeps_the_tech_list_in_view() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	hud.research_pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: ResearchPanel = hud.panels.research_panel
	assert_true(panel._head.summary_hidden(), "the standing line yields")
	assert_false(panel._hint.visible, "the standing hint yields")
	for row: Variant in panel._slot_rows.values():
		assert_almost_eq(
			(row as ResearchSlotRow).custom_minimum_size.y, 26.0, 0.5, "idle slot is tight"
		)
	assert_gt(panel._tabs.size.y, 150.0, "the tech list keeps the sheet's room")


## The ledger's "Next turn" projection is one clipped line on a phone, not an
## autowrapped paragraph over the production rows.
func test_phone_ledger_projection_is_one_line() -> void:
	await _open(PHONE)
	await get_tree().process_frame
	var hud: GameHud = _screen.hud
	_screen.economy.open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: EconomyPanel = hud.panels.economy_panel
	assert_lt(panel._preview.size.y, 20.0, "the projection is one line")
	assert_gt(panel._tabs.size.y, 170.0, "the tab body keeps the sheet's room")


## --- helpers ---------------------------------------------------------------


func _first_estate_row(estates: ImprovementPanel) -> ImprovementRow:
	for node: Node in estates._rows.get_children():
		if node is ImprovementRow:
			return node as ImprovementRow
	return null


func _clear_news(hud: GameHud) -> void:
	for child: Node in hud.despatches.box.get_children():
		hud.despatches.box.remove_child(child)
		child.free()
	hud.despatches._live = 0
	hud.despatches._compact_queue.clear()
	hud.despatches._queue = PackedStringArray()
	hud.despatches._queue_narrated.clear()
	hud.despatches._covered = false


## Resize the shared SubViewport and re-seat the chart. The viewport is resized
## per case; the screen under it is not rebuilt. Await one frame before
## relayout so chrome does not bake a compact bar into a wide view.
func _open(size: Vector2i) -> void:
	if not is_instance_valid(_screen):
		return
	_close_modals()
	_viewport.size = size
	Fixture.restore(Fixture.world(), world_snapshot)
	Fixture.suite_reset(_screen, screen_pristine)
	await get_tree().process_frame
	_screen.hud._relayout()


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _screen.hud.size)


## The modal a cartouche door just opened.
func _open_shell(screen: MapScreen) -> ModalShell:
	for node: Node in screen.find_children("*", "", true, false):
		var shell: ModalShell = node as ModalShell
		if shell != null and shell.is_open():
			return shell
	return null


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


## One left-press, move and release on a plate's grab: the pointer path a
## player's mouse (or an emulated touch) takes through ModalDrag.
func _drag(grab: Control, delta: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(8.0, 8.0)
	grab.gui_input.emit(press)
	var move := InputEventMouseMotion.new()
	move.position = press.position + delta
	grab.gui_input.emit(move)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = move.position
	grab.gui_input.emit(release)


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
		# The turn's gold door is a plaque with its own caption, not a seal.
		if button == hud._end_turn_button:
			continue
		doors.append(button)
	return doors


## Every bar door keeps a pictogram: the brass PNG medallions, and the vector
## crest the MENU door has always carried.
func _medallion(button: Button) -> Control:
	return button.find_child("Medallion", true, false) as Control


func _caption(button: Button) -> String:
	var label := _caption_label(button)
	return label.text if label != null else ""


func _caption_label(button: Button) -> Label:
	return button.find_child("Caption", true, false) as Label
