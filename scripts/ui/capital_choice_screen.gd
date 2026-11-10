class_name CapitalChoiceScreen
extends Control
## Capital-choice phase, player-facing (wiki: capital-choice-phase § Player
## choice; game-setup § Capital-Choice Phase). A Great Power's court is seated
## before turn 1: the chart shows the crown's provinces, a tap picks one, a
## second tap places the seat, and the world it hands to the map screen is the
## one the rules will play. The auto-chosen seat is preselected, so confirming
## without touching the map is the documented setup default.
##
## Presentation only: every rule decision lives in `CapitalChoice` (REQ-P3-02).

signal capital_chosen(config: GameConfig, world: WorldMap)
signal back_pressed

const TILE_SIZE: float = PlaySession.TILE_SIZE
const SEA_MARGIN: float = 1400.0
const OLD_WORLD_INDEX: int = 0
const BANNER_MARGIN: float = 12.0
## A finger (or cursor) that travels farther than this between press and release
## is a pan, not a tap.
const TAP_SLOP: float = 12.0
## Two answers to the same tap land within this many world units of each other.
const TAP_MERGE_DISTANCE: float = 0.5
## Android delivers one back press twice, and may also deliver it as Escape.
## A second delivery inside this window is the same press, not a new one.
const BACK_DEBOUNCE_MS: int = 300

## When this chart last answered a back press, shared by every chart instance so
## the duplicate delivery of one press cannot leave two screens.
static var _last_back_ms: int = -BACK_DEBOUNCE_MS

## New-game choices from the setup screen. Tests set it before add_child.
var config: GameConfig = null
## Generated here unless a caller (tests, a future save) hands one over.
var world: WorldMap = null
var model: MapModel = null
## The crown's chosen province and seat tile; -1 until a world is bound.
var selected_province: int = -1
var selected_tile: Vector2i = CapitalChoice.NO_TILE

var back_button: Button = null
var confirm_button: Button = null
## The instruction plaque across the top of the chart.
var banner: PanelContainer = null

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var marker: CapitalSeatMarker = $World/SeatMarker
@onready var camera: MapCamera = $World/MapCamera
@onready var hud_layer: CanvasLayer = $Hud
@onready var hud_root: Control = $Hud/HudRoot

var _hint: Label = null
var _pick: Label = null
## One press slot per input stream: Android sends a touch and an emulated mouse
## click beside it, and sharing one slot lets the second press erase the first
## one's start, so that stream's release answers nothing.
var _touch_start: Vector2 = Vector2.INF
var _touch_index: int = -1
var _mouse_start: Vector2 = Vector2.INF
var _answered_tap_frame: int = -1
var _answered_tap_world: Vector2 = Vector2.INF


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The page is a container over the camera canvas, never a tap target: a
	# Control that stops pointer events here would eat chart taps silently.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	InputActions.ensure_actions()
	theme = UiTheme.build()
	if config == null:
		config = GameConfig.make(
			GameConfig.DEFAULT_SEED, GameConfig.DEFAULT_SIZE_INDEX
		)
	_build_tap_catcher()
	_build_hud()
	camera.tapped.connect(on_tapped)
	if world != null:
		bind_world(world)
		return
	_say("Charting the world…")
	confirm_button.disabled = true
	_generate.call_deferred()


## Back gesture / Escape leaves the phase for the setup screen. Android delivers
## the request twice and may also deliver it as Escape, so one press is answered
## once (the router would otherwise open setup and then leave it again).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.CANCEL):
		if not _back_is_repeat():
			back_pressed.emit()
		get_viewport().set_input_as_handled()


## Android back / iOS back gesture belongs to the chart, not the OS: the router
## swaps pages on the next idle frame, so this event cannot reach the setup page
## it installs (RUB-P5-07).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not _back_is_repeat():
		back_pressed.emit()


## True for the second delivery of a press this chart already answered.
func _back_is_repeat() -> bool:
	var now: int = Time.get_ticks_msec()
	var repeat: bool = now - _last_back_ms < BACK_DEBOUNCE_MS
	_last_back_ms = now
	return repeat


# --- chrome -----------------------------------------------------------------


## A screen-space catcher under the chart's own chrome. Taps reach the map
## through two paths: the camera's `tapped` signal (desktop-pointer favourite)
## and this Control's `gui_input`. The GUI path is the one every platform
## delivers, so a chart tap is answered even where the page's world-space
## rectangle — or anything else in the camera canvas — would stop the event
## before `_unhandled_input` (REQ-P1-05, REQ-P5-05).
func _build_tap_catcher() -> void:
	var catcher := Control.new()
	catcher.name = "TapCatcher"
	catcher.mouse_filter = Control.MOUSE_FILTER_PASS
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_catcher_input)
	hud_layer.add_child(catcher)
	# Under the chart's chrome: the banner and the action bar must keep their taps.
	hud_layer.move_child(catcher, 0)


func _build_hud() -> void:
	var short: bool = MenuFrame.is_short(self)
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(14, 8, 14, 8)
		)
	)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = BANNER_MARGIN
	banner.offset_right = -BANNER_MARGIN
	banner.offset_top = BANNER_MARGIN
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(banner)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	banner.add_child(column)
	column.add_child(MenuFrame.title("SEAT YOUR COURT", 20 if short else 26))
	_hint = MenuFrame.subtitle("Tap one of your crown's coastal provinces.")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hint)
	_pick = Label.new()
	_pick.add_theme_font_size_override("font_size", 14 if short else 16)
	_pick.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_pick.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.8))
	_pick.add_theme_constant_override("outline_size", 3)
	_pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_pick)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = BANNER_MARGIN
	bar.offset_right = -BANNER_MARGIN
	bar.offset_top = -62.0
	bar.offset_bottom = -10.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	hud_root.add_child(bar)
	back_button = MenuFrame.small_button("BACK", 108.0)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(back_button)
	confirm_button = MenuFrame.action_button("SEAT THE COURT", 52.0)
	confirm_button.custom_minimum_size = Vector2(196.0, 52.0)
	confirm_button.add_theme_font_size_override("font_size", 16)
	confirm_button.pressed.connect(confirm)
	bar.add_child(confirm_button)


func _say(text: String, bad: bool = false) -> void:
	if _hint == null:
		return
	_hint.text = text
	_hint.add_theme_color_override(
		"font_color", Palette.CRIMSON if bad else Palette.TEXT_DIM
	)


## The banner's current line (instructions and refusals alike), for tests and
## for a future toast.
func hint_text() -> String:
	return _hint.text if _hint != null else ""


func _refresh() -> void:
	if _pick == null:
		return
	if selected_province < 0:
		_pick.text = "No court seated yet."
		return
	_pick.text = "%s · seat at %d, %d" % [
		model.province_name(selected_province), selected_tile.x, selected_tile.y
	]


# --- world ------------------------------------------------------------------


## One generation, then the chart: the map screen later reuses this world, so
## the player's seat is the one the campaign starts on (no second roll).
func _generate() -> void:
	world = MapGenerator.new().generate_world(
		config.map_seed, config.map_width, config.map_height
	)
	bind_world(world)


func bind_world(p_world: WorldMap) -> void:
	world = p_world
	model = world.region(OLD_WORLD_INDEX)
	_mount_chart()
	confirm_button.disabled = false
	var seat: int = CapitalChoice.seat_province(model, config.player_faction)
	if seat < 0:
		seat = int(
			CapitalChoice.pick_province(model, config.player_faction)["province_id"]
		)
	if seat >= 0:
		pick_province(seat)
	camera.focus_on(_seat_world_position(), camera.min_zoom(), true)
	_refresh()


## Sea, ink and camera sized to the Old World chart.
func _mount_chart() -> void:
	var map_size: Vector2 = MapGeo.world_size(model, TILE_SIZE)
	sea_backdrop.position = Vector2(-SEA_MARGIN, -SEA_MARGIN)
	sea_backdrop.size = map_size + Vector2(SEA_MARGIN, SEA_MARGIN) * 2.0
	if sea_backdrop.material is ShaderMaterial:
		(sea_backdrop.material as ShaderMaterial).set_shader_parameter(
			"world_size", sea_backdrop.size
		)
	canvas.build(model, world)
	camera.configure(map_size)
	camera.position = map_size * 0.5


func _seat_world_position() -> Vector2:
	if selected_tile.x >= 0:
		return MapGeo.tile_center(selected_tile.x, selected_tile.y, TILE_SIZE)
	return MapGeo.world_size(model, TILE_SIZE) * 0.5


# --- picking ----------------------------------------------------------------


## Selects an owned sea-bound province; the seat defaults to the province's
## capital tile when it already holds the court, else to the auto-choice tile.
func pick_province(province_id: int) -> bool:
	if model == null:
		return false
	if not CapitalChoice.can_seat(model, config.player_faction, province_id):
		_say(_refusal(province_id), true)
		return false
	selected_province = province_id
	selected_tile = _default_tile(province_id)
	marker.set_seat(model, province_id, selected_tile)
	_say("Tap a tile in %s to place the court." % model.province_name(province_id))
	_refresh()
	return true


## Places the seat on a land tile of the selected province. Tapping another
## crown province selects it first, so one tap is enough on a new province.
func pick_tile(tile: Vector2i) -> bool:
	if model == null:
		return false
	if not model.in_bounds(tile.x, tile.y):
		_say("That is open sea. The court must sit on land.", true)
		return false
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		_say("That is open sea. The court must sit on land.", true)
		return false
	if selected_province < 0 or province_id != selected_province:
		return pick_province(province_id)
	selected_tile = tile
	marker.set_seat(model, province_id, tile)
	_say("Tap SEAT THE COURT to begin here.")
	_refresh()
	return true


func on_tapped(world_position: Vector2) -> void:
	_answer_tap(world_position)


## Touch and mouse taps from the HUD catcher: the press is remembered, and a
## release within `TAP_SLOP` is a tap on the chart. Drags and pinches are left
## to the camera, which still owns panning and zooming.
func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_touch_index = event.index
		elif event.index == _touch_index:
			var touch_start: Vector2 = _touch_start
			_touch_start = Vector2.INF
			_touch_index = -1
			_finish_tap(touch_start, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_start = event.position
		elif _mouse_start != Vector2.INF:
			var mouse_start: Vector2 = _mouse_start
			_mouse_start = Vector2.INF
			_finish_tap(mouse_start, event.position)


## A release close to its press is a tap; anything farther belongs to the pans.
func _finish_tap(start: Vector2, position: Vector2) -> void:
	if start != Vector2.INF and position.distance_to(start) <= TAP_SLOP:
		_tap_at(position)


## A screen point in the chart's own pixels to the world: the canvas transform
## is the camera's authoritative mapping (content scaling, zoom and clamping
## included), so a tap lands on the tile the player sees.
func _tap_at(screen_position: Vector2) -> void:
	if model == null:
		return
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_position
	_answer_tap(world)


## One seat answer per tap, however many paths deliver it: Android sends an
## emulated mouse click beside every touch, and the camera may report the same
## release the catcher sees.
func _answer_tap(world_position: Vector2) -> void:
	var frame: int = Engine.get_process_frames()
	if (
		frame == _answered_tap_frame
		and world_position.distance_to(_answered_tap_world) < TAP_MERGE_DISTANCE
	):
		return
	_answered_tap_frame = frame
	_answered_tap_world = world_position
	pick_tile(MapGeo.tile_at_world(world_position, TILE_SIZE))


func _default_tile(province_id: int) -> Vector2i:
	var province: ProvinceState = model.get_province(province_id)
	if province != null and province.capital and province.capital_tile.x >= 0:
		return province.capital_tile
	return CapitalChoice.choose_tile(model, province_id)


func _refusal(province_id: int) -> String:
	var province: ProvinceState = model.get_province(province_id)
	if province == null:
		return "There is no province there."
	if province.owner != config.player_faction:
		return "%s is not yours to seat." % model.province_name(province_id)
	return "%s has no seaboard; a Great Power's court must sit on the sea." % (
		model.province_name(province_id)
	)


# --- confirm ----------------------------------------------------------------


## Applies the seat through the rules and hands the world to the map screen.
func confirm() -> bool:
	if model == null or selected_province < 0 or selected_tile.x < 0:
		_say("Choose one of your coastal provinces first.", true)
		return false
	var result: Dictionary = CapitalChoice.seat_capital(
		model, config.player_faction, selected_province, selected_tile
	)
	if not bool(result.get("ok", false)):
		_say(_seat_refusal(String(result.get("error", ""))), true)
		return false
	capital_chosen.emit(config, world)
	return true


func _seat_refusal(code: String) -> String:
	match code:
		CapitalChoice.ERROR_NOT_OWNED:
			return "That province is not yours."
		CapitalChoice.ERROR_NOT_SEA_BOUND:
			return "That province has no seaboard."
		CapitalChoice.ERROR_TILE_OUTSIDE:
			return "That tile is not in the chosen province."
	return "The court cannot be seated there."
