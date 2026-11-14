class_name BattlePlateFrame
extends Control
## The frame both battle plates wear: a scrim over the court, the gold panel and
## its column, a titled header with a one-tap Skip, the strip that names both
## sides and their strength, the three-line despatch log, and the outcome stamp
## with its Continue door. The land [QuickBattleOverlay] and the sea's
## [NavalPlate] share this chrome, so the fade, the skip, the log cap and the
## stamp are written once (REQ-P3-01, REQ-P5-06). Presentation only: it replays
## the record the resolver produced and never changes it (REQ-P2-03).
##
## A subclass names its look with [method _look], builds its own body, replays
## its report through [method add_line], the side strip and
## [method stamp_outcome], and owns every rule reading. The frame owns the
## furniture.

signal finished

## Despatch lines the log keeps: the plate reads the last three, never a wall.
const LOG_LINES: int = 3
const FADE_SECONDS: float = 0.18
const STAMP_SECONDS: float = 0.28
const BACKDROP: Color = Color(0.05, 0.04, 0.03, 0.74)
const MARGIN: int = 14
## A beaten report stamps in a warmer red than the gold of a won one.
const STAMP_LOSS: Color = Color(0.86, 0.60, 0.52)

## The engagement both sides read: the resolver's report, never rewritten here.
var battle: Dictionary = {}
var faction_names: Array = []

var _panel: PanelContainer = null
var _margin: MarginContainer = null
var _header_row: HBoxContainer = null
## The plate is movable by its header, so the chart it covers can be read while
## the report plays (REQ-P1-07).
var _drag: ModalDrag = null
var _title: Label = null
## The place of the fight (land) or the despatch's headline (sea).
var _headline: Label = null
var _skip: Button = null
var _atk_name: Label = null
var _atk_bar: ProgressBar = null
var _def_name: Label = null
var _def_bar: ProgressBar = null
var _log: VBoxContainer = null
var _outcome: Label = null
var _continue: Button = null
var _tween: Tween = null
var _shown: bool = false
var _finished: bool = false
var _look_data: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_look_data = _look()
	_build()
	visible = false


# --- subclass hooks ----------------------------------------------------------


## The plate's own look: title and its type size, the headline's size and wrap,
## the Skip's tooltip, the page colour, the room each side's name gets, and the
## outcome's size. Each plate spells out its own page; the fallbacks keep a new
## plate legible before it names anything.
func _look() -> Dictionary:
	return {}


## Whatever the plate reads beside the place, between it and the Skip door: the
## land plate's round counter.
func _build_header_tail(_header: HBoxContainer) -> void:
	pass


## The plate's own middle, between the header and the strength strip: the
## painted field or the painted water.
func _build_body(_column: VBoxContainer) -> void:
	pass


## Whatever the plate stands between its strength strip and the log: the land
## plate's round pips and the wall it fights over.
func _build_after_bars(_column: VBoxContainer) -> void:
	pass


## Paint the report the plate was handed; called once per opening.
func _populate() -> void:
	pass


## Start the replay; the subclass calls [method _finish] on its last beat.
func _play() -> void:
	pass


## Finish the report now: the subclass's aftermath, then [method stamp_outcome].
func _finish() -> void:
	pass


## Whatever the plate tells on skip before the aftermath: the land plate names
## the round it stopped in.
func _skip_to_end() -> void:
	pass


## Whatever a subclass clears beyond the frame on reset.
func _reset_body() -> void:
	pass


# --- shell -------------------------------------------------------------------


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	_margin = margin

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			_look_data.get("panel_fill", Color(0.09, 0.07, 0.05, 0.97)),
			Palette.GOLD, 2, 6, Vector4(16, 12, 16, 12)
		)
	)
	margin.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_build_header(column)
	_build_body(column)
	_build_bars(column)
	_build_log(column)
	_build_footer(column)


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	header.add_child(ModalDrag.grip())
	_header_row = header
	var grabs: Array[Control] = [header]
	_drag = ModalDrag.attach(self, _margin, grabs, _panel)
	_title = _label(
		String(_look_data.get("title", "")), int(_look_data.get("title_pixels", 24)),
		Palette.GOLD_PALE
	)
	header.add_child(_title)
	_headline = _label("", int(_look_data.get("headline_pixels", 16)), Palette.TEXT)
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(_look_data.get("wrap_headline", false)):
		_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_headline)
	_build_header_tail(header)
	_skip = Button.new()
	_skip.text = "Skip"
	_skip.tooltip_text = String(_look_data.get("skip_tip", "Skip the animation"))
	_skip.pressed.connect(skip)
	header.add_child(_skip)


## The two sides' names and bars: the attacker reads in from the left, the
## defender out to the right, so each colour owns its own edge.
func _build_bars(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var width: float = float(_look_data.get("name_width", 120.0))
	var wrap: bool = bool(_look_data.get("wrap_names", false))
	_atk_name = _label("", 13, Palette.TEXT)
	_atk_name.custom_minimum_size = Vector2(width, 0)
	row.add_child(_atk_name)
	_atk_bar = UiTheme.progress(Palette.CRIMSON)
	row.add_child(_atk_bar)
	_def_bar = UiTheme.progress(Palette.NAVY)
	row.add_child(_def_bar)
	_def_name = _label("", 13, Palette.TEXT)
	_def_name.custom_minimum_size = Vector2(width, 0)
	_def_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_def_name)
	if wrap:
		for who: Label in [_atk_name, _def_name]:
			who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_def_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_build_after_bars(column)


func _build_log(column: VBoxContainer) -> void:
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)


func _build_footer(column: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_outcome = _label(
		"", int(_look_data.get("outcome_pixels", 22)), Palette.GOLD_PALE
	)
	_outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_outcome)
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.custom_minimum_size = Vector2(140, 0)
	_continue.pressed.connect(_on_continue)
	_continue.visible = false
	footer.add_child(_continue)


# --- the plate's life --------------------------------------------------------


## Hands the frame a new report and plays it: a plate calls this from its own
## public entry point once it has named the place.
func _reveal(p_battle: Dictionary, p_names: Array) -> void:
	battle = p_battle
	faction_names = p_names
	_shown = true
	_finished = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_reset()
	_populate()
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	_play()


func is_shown() -> bool:
	return _shown


## One tap tells the whole report, so the juice never holds the court
## (REQ-P5-06).
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _finished:
		return
	_skip_to_end()
	_finish()


func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for child: Node in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	_outcome.text = ""
	_continue.visible = false
	_skip.visible = true
	_reset_body()


## Appends one despatch line and drops the oldest past the three the plate reads.
func add_line(text: String) -> void:
	var line := _label(text, 12, Palette.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(line)
	while _log.get_child_count() > LOG_LINES:
		var oldest: Node = _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()


## Paints one side's name and strength bar in its own colours (REQ-P1-07).
func _tint_side(who: Label, bar: ProgressBar, owner: int) -> void:
	var color: Color = Palette.faction_color(owner)
	who.add_theme_color_override("font_color", color)
	bar.add_theme_stylebox_override(
		"fill", UiTheme.box(color, color.lightened(0.25), 1, 3, Vector4.ZERO)
	)


## Ends the report: the outcome stamps down, Skip gives way to Continue.
func stamp_outcome(text: String, good: bool) -> void:
	if _finished:
		return
	_finished = true
	_outcome.text = text
	_outcome.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if good else STAMP_LOSS
	)
	_outcome.pivot_offset = _outcome.size * 0.5
	_outcome.scale = Vector2(0.7, 0.7)
	_skip.visible = false
	_continue.visible = true
	var stamp: Tween = create_tween()
	stamp.tween_property(_outcome, "scale", Vector2.ONE, STAMP_SECONDS).set_trans(
		Tween.TRANS_BACK
	)


func _on_continue() -> void:
	_shown = false
	visible = false
	ModalDrag.reset_on(_margin)
	finished.emit()


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
