class_name AutoLogPlate
extends Control
## The Auto seat's action log (wiki: auto-mode § Pacing): the plate under the
## cartouche that prints the newest lines, and the whole-log [AutoLogSheet] the
## bar's LOG seal opens. A busy turn raises more orders than the plate has room
## for, so the sheet is where the turn's first lines are read (REQ-P5-05).
##
## Presentation only: the lines are MapPlayAuto's and the plate decides no
## outcome (REQ-P3-02). AutoBar owns the seal and the geometry beside its other
## seals; this module owns what the log prints and when it repaints.

const LOG_LINES: int = 7
const LOG_LINES_COMPACT: int = 4
const LOG_HEIGHT: float = 128.0
const LOG_HEIGHT_COMPACT: float = 82.0
const PANEL_WIDTH: float = 320.0

var play: PlaySession = null
## The HUD whose viewport the plate fits itself to (AutoBar hands it over).
var hud: GameHud = null
## Every line the session still keeps, oldest first.
var sheet: AutoLogSheet = null

var _frame: PanelContainer = null
var _box: VBoxContainer = null
## What the plate last printed, so a quiet frame costs no rebuild.
var _signature: String = ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = PanelContainer.new()
	_frame.name = "AutoLog"
	_frame.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.06, 0.05, 0.04, 0.90), Palette.GOLD_DIM, 1, 3, Vector4(10, 8, 10, 8))
	)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	add_child(_frame)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_box)


## Binds the session and mounts the whole-log sheet on its own layer above the
## pause menu, the way every cartouche door does (REQ-P1-07, REQ-P5-07).
func bind(p_session: PlaySession, p_hud: GameHud) -> void:
	play = p_session
	hud = p_hud
	if sheet == null and hud != null:
		sheet = AutoLogSheet.new()
		sheet.name = "AutoLogSheet"
		ModalShell.mount_layer(hud, "AutoLogLayer").add_child(sheet)
		sheet.bind(play)
	_signature = ""
	mirror()


## Geometry follows the viewport: the left rail under the cartouche on the atlas
## layout, the room above the minimap on a phone, so it never covers the
## despatch lane or the chart's own readings (REQ-P1-07).
func layout(bar_bottom: float) -> void:
	var view: Vector2 = hud.size if hud != null else size
	if HudLayout.is_compact(view):
		var compact_width: float = minf(PANEL_WIDTH, view.x * 0.62)
		_frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_frame.offset_left = -compact_width * 0.5
		_frame.offset_right = compact_width * 0.5
		_frame.offset_top = -LOG_HEIGHT_COMPACT - 10.0
		_frame.offset_bottom = -10.0
		return
	_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_frame.offset_left = 18.0
	_frame.offset_right = 18.0 + minf(PANEL_WIDTH, maxf(view.x, 1.0) * 0.46)
	_frame.offset_top = bar_bottom + 8.0
	_frame.offset_bottom = _frame.offset_top + LOG_HEIGHT


## Whether the plate belongs on screen: the seat's chrome is up and it has news.
func is_showing() -> bool:
	return play != null and (play.auto_active or play.auto_armed) and not play.auto_log.is_empty()


## True while the whole-log sheet covers the chart; the driver holds its clock
## so the log the player is reading does not move under them.
func sheet_open() -> bool:
	return sheet != null and sheet.is_open()


func open_sheet() -> void:
	if sheet == null or play == null:
		return
	sheet.bind(play)
	sheet.open()


## Repaints the plate when the log moved, and the open sheet with it; a quiet
## frame costs nothing.
func mirror() -> void:
	if play == null:
		return
	var signature: String = "%d|%s" % [
		play.auto_log.size(),
		String(play.auto_log.back()) if not play.auto_log.is_empty() else "",
	]
	if signature == _signature:
		return
	_signature = signature
	_frame.visible = is_showing()
	paint_lines()
	if sheet_open():
		sheet.refresh()


## Lines the plate prints: a phone keeps the last four, the atlas seven.
func visible_lines() -> int:
	if hud != null and HudLayout.is_compact(hud.size):
		return LOG_LINES_COMPACT
	return LOG_LINES


## Lines the session keeps that the plate does not print — what the LOG seal
## opens, so a busy turn's first orders are never lost (REQ-P5-05).
func held_back() -> int:
	if play == null:
		return 0
	return maxi(play.auto_log.size() - visible_lines(), 0)


func paint_lines() -> void:
	if play == null:
		return
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var first: int = maxi(play.auto_log.size() - visible_lines(), 0)
	for index: int in range(first, play.auto_log.size()):
		_box.add_child(_line(String(play.auto_log[index]), index == play.auto_log.size() - 1))


func _line(text: String, newest: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if newest else Palette.TEXT_DIM
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
