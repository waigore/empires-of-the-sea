class_name AutoBar
extends Control
## The Auto mode's chrome (wiki: auto-mode; issue #725): the AUTO plaque over the
## chart that arms and disarms the AI seat, the seat's state beside it, the speed
## seal and the crown's own action log. It is also the driver: `_process` spends
## one pacing tick on `MapPlayAuto` while the seat is held.
##
## Presentation only. The seat, the passes and the rules outcomes belong to
## MapPlayAuto and the MapPlayTurn* modules; this class reads them back into
## chrome and asks the player to confirm the two seat changes (REQ-P3-01).
##
## The plaque is map chrome, not a cartouche door: the measured bar has no room
## for another seal without stacking its row (docs/hud-top-bar.md § Geometry), and
## the parent issue asks for a control that is always in reach (issue #725).

## Lines the log panel prints, newest at the bottom.
const LOG_LINES: int = 7
const PANEL_WIDTH: float = 320.0
const TOUCH_HEIGHT: float = 44.0
const PLAQUE_WIDTH: float = 150.0
## Height the plaque and pace take under the cartouche; the despatch lane starts
## below it while the seat's chrome shows, so no toast prints over the seat.
const CHROME_HEIGHT: float = 52.0
## The log's fixed plate: its lines at 12 pt plus margins, so the box always
## carries its lines and never grows over the chart.
const LOG_HEIGHT: float = 128.0
const LOG_LINES_COMPACT: int = 4
const LOG_HEIGHT_COMPACT: float = 82.0

var play: PlaySession = null
## The always-present AUTO plaque: the seat's door and its state.
var toggle: Button = null

var _state_label: Label = null
var _speed_seal: Button = null
var _speed_icon: Icon = null
var _speed_label: Label = null
var _log_frame: PanelContainer = null
var _log_box: VBoxContainer = null
## The seat change the player is being asked to confirm.
var _prompt: AutoPrompt = null
var _elapsed: float = 0.0
## What the chrome last printed, so a quiet frame costs no rebuild.
var _signature: String = ""
## Whether the seat's chrome was up on the last mirror, so its two boundaries
## re-lay the despatch lane exactly once each.
var _was_showing: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_relayout)
	_mirror()


## The plaque follows every viewport change (GameHud lays its own chrome out the
## same way), so a phone rotation never strands the log off screen.
func _relayout() -> void:
	_layout(get_parent() as GameHud)


## True while the seat's chrome is up: armed, held, or the log has news.
func is_showing() -> bool:
	return play != null and (play.auto_active or play.auto_armed)


## Binds the session and lays the plaque out under the cartouche.
func bind(p_session: PlaySession, hud: GameHud) -> void:
	play = p_session
	_layout(hud)
	_signature = ""
	_mirror()


func _process(delta: float) -> void:
	if play == null:
		return
	_drive(delta)
	_mirror()


# --- driver ------------------------------------------------------------------


## One pacing tick per `MapPlayAuto.seconds(play)`. Paused Auto, an open
## confirmation and a decided campaign all hold the clock (wiki: auto-mode
## § Pacing).
func _drive(delta: float) -> void:
	if _prompt != null and _prompt.is_open():
		return
	if not MapPlayAuto.running(play):
		_elapsed = 0.0
		return
	var wait: float = MapPlayAuto.seconds(play)
	_elapsed += delta
	if _elapsed < wait:
		return
	_elapsed = 0.0
	MapPlayAuto.tick(play)


# --- build -------------------------------------------------------------------


func _build() -> void:
	toggle = Button.new()
	toggle.name = "AutoToggle"
	toggle.custom_minimum_size = Vector2(PLAQUE_WIDTH, TOUCH_HEIGHT)
	toggle.tooltip_text = "Auto mode — hand the AI your seat for a while"
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_stylebox_override("normal", _plaque(Color(0.13, 0.10, 0.07, 0.82), Palette.GOLD_DIM))
	toggle.add_theme_stylebox_override("hover", _plaque(Color(0.22, 0.17, 0.11, 0.92), Palette.GOLD))
	toggle.add_theme_stylebox_override("pressed", _plaque(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_PALE))
	toggle.add_theme_stylebox_override("focus", _plaque(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE))
	toggle.pressed.connect(_on_toggle_pressed)
	add_child(toggle)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.add_child(row)

	var helm := Icon.new("auto", 20.0, Palette.GOLD)
	helm.name = "Medallion"
	row.add_child(helm)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = "AUTO"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Palette.GOLD_PALE)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption)

	_state_label = Label.new()
	_state_label.name = "AutoState"
	_state_label.add_theme_font_size_override("font_size", 10)
	_state_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_state_label)

	_speed_seal = Button.new()
	_speed_seal.name = "AutoSpeed"
	_speed_seal.tooltip_text = "Pace — pause, 1x, 2x, 3x"
	_speed_seal.custom_minimum_size = Vector2(TOUCH_HEIGHT, TOUCH_HEIGHT)
	_speed_seal.add_theme_stylebox_override("normal", _plaque(Color(0.13, 0.10, 0.07, 0.86), Palette.GOLD_DIM))
	_speed_seal.add_theme_stylebox_override("hover", _plaque(Color(0.22, 0.17, 0.11, 0.94), Palette.GOLD))
	_speed_seal.add_theme_stylebox_override("pressed", _plaque(Color(0.09, 0.07, 0.05, 0.96), Palette.GOLD_PALE))
	_speed_seal.pressed.connect(_on_speed_pressed)
	add_child(_speed_seal)

	var speed_row := HBoxContainer.new()
	speed_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.add_theme_constant_override("separation", 3)
	speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_seal.add_child(speed_row)
	_speed_icon = Icon.new("play", 16.0, Palette.GOLD_PALE)
	speed_row.add_child(_speed_icon)
	_speed_label = Label.new()
	_speed_label.text = "1x"
	_speed_label.add_theme_font_size_override("font_size", 12)
	_speed_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_row.add_child(_speed_label)

	_build_log()
	_prompt = AutoPrompt.new()
	_prompt.name = "AutoPrompt"
	_prompt.confirmed.connect(_on_prompt_confirmed)
	_prompt.cancelled.connect(_on_prompt_cancelled)
	add_child(_prompt)


func _plaque(fill: Color, border: Color) -> StyleBoxFlat:
	var style := UiTheme.box(fill, border, 1, 3, Vector4(8, 2, 8, 2))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0.0, 1.0)
	return style


func _build_log() -> void:
	_log_frame = PanelContainer.new()
	_log_frame.name = "AutoLog"
	_log_frame.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.06, 0.05, 0.04, 0.90), Palette.GOLD_DIM, 1, 3, Vector4(10, 8, 10, 8))
	)
	_log_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_frame.visible = false
	add_child(_log_frame)

	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 2)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_frame.add_child(_log_box)


## Geometry follows the viewport: the plaque rides top-centre under the
## cartouche, the pace beside it and the log beneath, so the chart keeps its
## middle and the gesture stays one thumb away on a phone.
func _layout(hud: GameHud) -> void:
	var height: float = 60.0
	if hud != null and hud.top_bar != null:
		height = hud.top_bar.offset_bottom
	var width: float = maxf((hud.size if hud != null else size).x, 1.0)
	var plaque: float = minf(PLAQUE_WIDTH, width * 0.4)
	toggle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toggle.offset_left = -plaque * 0.5
	toggle.offset_right = plaque * 0.5
	toggle.offset_top = height + 8.0
	toggle.offset_bottom = height + 8.0 + TOUCH_HEIGHT
	_speed_seal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_speed_seal.offset_left = plaque * 0.5 + 6.0
	_speed_seal.offset_right = plaque * 0.5 + 6.0 + TOUCH_HEIGHT
	_speed_seal.offset_top = height + 8.0
	_speed_seal.offset_bottom = height + 8.0 + TOUCH_HEIGHT
	# The log keeps the left rail under the cartouche on the atlas layout, and
	# the room above the minimap on a phone, so it never covers the despatch lane
	# (HudDespatches, top centre) or the chart's own readings.
	var view: Vector2 = hud.size if hud != null else size
	var log_width: float = minf(PANEL_WIDTH, width * 0.46)
	if HudLayout.is_compact(view):
		# A phone's despatch lane runs the full width under the cartouche, so the
		# log takes the foot of the chart instead, between the minimap and the
		# zoom pair, where nothing else prints.
		var compact_width: float = minf(PANEL_WIDTH, view.x * 0.62)
		_log_frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_log_frame.offset_left = -compact_width * 0.5
		_log_frame.offset_right = compact_width * 0.5
		_log_frame.offset_top = -LOG_HEIGHT_COMPACT - 10.0
		_log_frame.offset_bottom = -10.0
		return
	_log_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_log_frame.offset_left = 18.0
	_log_frame.offset_right = 18.0 + log_width
	_log_frame.offset_top = height + 8.0
	_log_frame.offset_bottom = _log_frame.offset_top + LOG_HEIGHT


# --- presses -----------------------------------------------------------------


func _on_toggle_pressed() -> void:
	if play == null or _prompt == null:
		return
	_prompt.ask(AutoPrompt.DISARM if play.auto_active else AutoPrompt.ARM)


func _on_prompt_confirmed(kind: String) -> void:
	if play != null:
		if kind == AutoPrompt.ARM:
			MapPlayAuto.arm(play)
		else:
			MapPlayAuto.disarm(play)
	_signature = ""
	_mirror()


func _on_prompt_cancelled() -> void:
	_mirror()


func _on_speed_pressed() -> void:
	if play == null:
		return
	MapPlayAuto.cycle_speed(play)
	_signature = ""
	_mirror()


# --- mirror ------------------------------------------------------------------


func _mirror() -> void:
	if play == null or toggle == null:
		return
	var signature: String = "%d|%d|%d|%d|%s" % [
		play.auto_speed,
		int(play.auto_active),
		int(play.auto_armed),
		play.auto_log.size(),
		String(play.auto_log.back()) if not play.auto_log.is_empty() else "",
	]
	if signature == _signature:
		return
	_signature = signature
	_speed_seal.visible = play.auto_active
	_log_frame.visible = (play.auto_active or play.auto_armed) and not play.auto_log.is_empty()
	_state_label.text = _state_text()
	_state_label.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if play.auto_active else Palette.TEXT_DIM
	)
	# Paused, the bars say it on their own; a live pace prints its rate beside
	# them, so the seal fits a phone's 44-point target either way.
	_speed_label.visible = play.auto_speed > 0
	_speed_label.text = MapPlayAuto.speed_label(play)
	_speed_icon.kind = "play" if play.auto_speed > 0 else "pause"
	_speed_icon.queue_redraw()
	toggle.add_theme_stylebox_override(
		"normal",
		_plaque(
			Color(0.22, 0.17, 0.11, 0.92) if play.auto_active
			else Color(0.13, 0.10, 0.07, 0.82),
			Palette.GOLD if play.auto_active else Palette.GOLD_DIM
		)
	)
	_refresh_log()
	var hud := get_parent() as GameHud
	if _was_showing != is_showing():
		_was_showing = is_showing()
		# The despatch lane starts below the seat's chrome while it shows, so the
		# bar and the lane are laid out again on the seat's two boundaries.
		if hud != null:
			hud._relayout()
	if hud != null and hud._end_turn_button != null:
		hud._end_turn_button.disabled = play.auto_active or hud.campaign_over
		if not hud.campaign_over:
			hud._end_turn_button.text = "AUTO" if play.auto_active else "END TURN"


## The plaque's second line names the seat in one phrase.
func _state_text() -> String:
	if play.auto_active and not play.auto_armed:
		return "ends with this turn"
	if play.auto_active:
		return "the AI holds your seat"
	if play.auto_armed:
		return "arms after this turn"
	return "hand the seat to the AI"


## Lines the plate carries: a phone keeps the last four, the atlas seven.
func _visible_lines() -> int:
	var hud := get_parent() as GameHud
	if hud != null and HudLayout.is_compact(hud.size):
		return LOG_LINES_COMPACT
	return LOG_LINES


func _refresh_log() -> void:
	for child: Node in _log_box.get_children():
		child.queue_free()
	var first: int = maxi(play.auto_log.size() - _visible_lines(), 0)
	for index: int in range(first, play.auto_log.size()):
		var line := Label.new()
		line.text = String(play.auto_log[index])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		var newest: bool = index == play.auto_log.size() - 1
		line.add_theme_color_override(
			"font_color", Palette.GOLD_PALE if newest else Palette.TEXT_DIM
		)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_log_box.add_child(line)
