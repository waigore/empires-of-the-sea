class_name CapitalChoiceChrome
extends RefCounted
## The capital-choice page's chrome — the instruction plaque above the chart and
## the action row below it — and the composition it leaves the chart (REQ-P1-05).
##
## A phone banner owns the top fifth of a landscape screen, so a chart framed in
## the whole viewport put the northern seaboards, the provinces a player must
## tap, under it. The chart is composed in the band the chrome leaves free
## instead: the banner then covers open sea, with the crown's provinces centred
## in the band and water around them.

const MARGIN: float = 12.0
const ACTION_HEIGHT: float = 62.0
## The plaque's own height, title and two lines tall on a phone (three lines and a
## larger title on a wide screen). The chart's band is measured from it, so it is
## a design constant rather than whatever the first layout pass reports — before
## the window has a width a wrapped label reports a column of text.
const PLAQUE_HEIGHT: float = 64.0
const PLAQUE_HEIGHT_WIDE: float = 91.0
## Water kept around the crown's provinces, as a fraction of their box.
const CHOICE_PADDING: float = 1.45
## Points between the chrome and the chart's band.
const CHROME_GAP: float = 6.0
## A plaque taller than this share of the screen has not been laid out properly.
const MAX_PLAQUE_SHARE: float = 0.4

var banner: PanelContainer = null
var hint: Label = null
var pick: Label = null
var bar: HBoxContainer = null
var back_button: Button = null
var confirm_button: Button = null
## The plaque's height as it stands: its design height until a longer hint wraps
## it onto another line, which `_read_plaque` takes into the band.
var plaque_height: float = 0.0


## Builds the plaque and the action row under `root`. `short` is the page's
## compact answer (`MenuFrame.is_short`).
func build(root: Control, short: bool) -> CapitalChoiceChrome:
	var pad: Vector4 = Vector4(10, 5, 10, 5) if short else Vector4(14, 8, 14, 8)
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Palette.with_alpha(Palette.PARCHMENT, 0.96), Palette.GOLD_DIM, 1, 4, pad)
	)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = MARGIN
	banner.offset_right = -MARGIN
	banner.offset_top = MARGIN
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0 if short else 2)
	banner.add_child(column)
	column.add_child(MenuFrame.title("SEAT YOUR COURT", 18 if short else 26))
	hint = MenuFrame.subtitle("Tap one of your crown's provinces glowing gold.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13 if short else 15)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)
	pick = Label.new()
	pick.add_theme_font_size_override("font_size", 13 if short else 16)
	pick.add_theme_color_override("font_color", Palette.GOLD_PALE)
	pick.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.8))
	pick.add_theme_constant_override("outline_size", 3)
	pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(pick)

	plaque_height = PLAQUE_HEIGHT if short else PLAQUE_HEIGHT_WIDE
	banner.custom_minimum_size.y = plaque_height

	bar = HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.offset_top = -ACTION_HEIGHT
	bar.offset_bottom = -10.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)
	back_button = MenuFrame.small_button("BACK", 108.0)
	bar.add_child(back_button)
	confirm_button = MenuFrame.action_button("SEAT THE COURT", 52.0)
	confirm_button.custom_minimum_size = Vector2(196.0, 52.0)
	confirm_button.add_theme_font_size_override("font_size", 16)
	bar.add_child(confirm_button)
	return self


## Keeps the chart inside the strip the chrome leaves free. `reframe` also sets
## the opening frame — the crown's choices centred in the band, with water around
## them — which is what the page asks for when it opens and when the window
## changes shape. Chrome that only grew (a longer refusal) moves the band without
## stealing a view the player has panned or zoomed.
func compose(
	camera: MapCamera,
	model: MapModel,
	provinces: Array[int],
	seat: Vector2,
	tile_size: float,
	reframe: bool
) -> void:
	if camera == null or model == null:
		return
	var viewport: Vector2 = camera.viewport_size()
	_read_plaque(viewport)
	var free: Rect2 = band(viewport)
	if free.size.y <= 1.0:
		return
	camera.set_compose_band(free)
	if not reframe:
		return
	var choices: Rect2 = choices_rect(model, provinces, tile_size)
	var zoom: float = opening_zoom(free, viewport, camera.map_size, choices)
	camera.focus_on(
		opening_target(free, camera.map_size, choices, zoom, seat),
		zoom if zoom > 0.0 else camera.min_zoom(),
		true
	)


## The free strip under the plaque and above the action row, in page pixels. Both
## edges come from the chrome's own geometry, so the chart can be framed on the
## frame the page opens rather than after a layout pass.
func band(viewport: Vector2) -> Rect2:
	var top: float = MARGIN + plaque_height + CHROME_GAP
	var bottom: float = maxf(viewport.y - ACTION_HEIGHT - CHROME_GAP, top)
	return Rect2(0.0, top, viewport.x, bottom - top)


## Takes a wrapped line the plaque gained (a longer hint) into the band. A size
## past `MAX_PLAQUE_SHARE` of the screen is a layout pass that has not wrapped the
## text yet, not a taller plaque.
func _read_plaque(viewport: Vector2) -> void:
	if banner.size.y > plaque_height and banner.size.y <= viewport.y * MAX_PLAQUE_SHARE:
		plaque_height = banner.size.y


## The world box holding every province the crown may seat its court in. Empty
## for no provinces, which leaves the camera its own floor.
static func choices_rect(model: MapModel, provinces: Array[int], tile_size: float) -> Rect2:
	var box := Rect2()
	if model == null:
		return box
	for province_id: int in provinces:
		for tile: Vector2i in model.province_tiles(province_id):
			var tile_rect := Rect2(
				MapGeo.tile_center(tile.x, tile.y, tile_size)
				- Vector2(tile_size, tile_size) * 0.5,
				Vector2(tile_size, tile_size)
			)
			box = tile_rect if box.size == Vector2.ZERO else box.merge(tile_rect)
	return box


## The zoom the chart opens at, kept inside the band with water around the
## crown's provinces. A band too short to hold the whole grid at a legible size
## (a phone) instead frames the crown's own choices; a roomy one keeps the chart
## in view as it always did.
static func opening_zoom(
	band: Rect2, viewport: Vector2, map_size: Vector2, choices: Rect2
) -> float:
	if choices.size.x <= 0.0 or choices.size.y <= 0.0:
		return 0.0
	var choices_fit: float = CameraMath.fit_zoom(band.size, choices.size * CHOICE_PADDING)
	var chart_fit: float = maxf(
		CameraMath.fit_zoom(band.size, map_size),
		CameraMath.fit_cover(viewport, map_size)
	)
	return minf(choices_fit, chart_fit)


## The world point the opening frame centres: the crown's choices, except on an
## axis where the whole grid already fits the band — there the chart keeps its
## own middle, so the water around it reads evenly instead of running off one
## side of the screen.
static func opening_target(
	band: Rect2, map_size: Vector2, choices: Rect2, zoom: float, seat: Vector2
) -> Vector2:
	if choices.size.x <= 0.0 or zoom <= 0.0:
		return seat
	var target: Vector2 = choices.get_center()
	if map_size.x * zoom <= band.size.x + 0.5:
		target.x = map_size.x * 0.5
	if map_size.y * zoom <= band.size.y + 0.5:
		target.y = map_size.y * 0.5
	return target
