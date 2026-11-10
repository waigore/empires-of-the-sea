class_name GazettePlate
extends Control
## The crown's news sheet on the map: the turn-start plate, the archive of every
## prior sheet and the watchlist editor, all on one soft surface (wiki:
## the-gazette § When it appears, § History screen, § Courts of interest;
## DR-20261110-14).
##
## Soft, never modal: only the ruled plate takes the pointer, so the map and the
## crown's orders stay usable around it and one press sets it aside
## (REQ-P5-02, REQ-P5-06, REQ-P5-07). Presentation only — it prints the lines
## [Gazette] already built (REQ-P2-03).

signal dismissed
## The player added or removed a court on the watchlist.
signal watch_changed(faction: int)

enum Mode { SHEET, ARCHIVE, WATCHLIST }

const MAX_WIDTH: float = 640.0
const MIN_WIDTH: float = 288.0
const PLATE_TOP: float = 88.0
const VIEWPORT_MARGIN: float = 12.0
const EMPTY_LINE: String = "Nothing reached the presses this turn."
const NO_HISTORY: String = "The presses have not run yet."
const INK_SOFT: Color = Color(0.34, 0.26, 0.16)

var state: GazetteState = null
var diplomacy: DiplomacyState = null
var viewer: int = 0

var _mode: Mode = Mode.SHEET
var _sheet: Dictionary = {}
## Index into `state.history()` (newest first) while reading the archive.
var _at: int = 0
var _shown: bool = false

var _panel: PanelContainer = null
var _title: Label = null
var _stamp: Label = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _tabs: HBoxContainer = null
var _nav: HBoxContainer = null
var _newer: Button = null
var _older: Button = null
var _nav_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()
	visible = false
	resized.connect(_fit)


## Raises the sheet the turn just produced.
func open_sheet(
	sheet: Dictionary, p_state: GazetteState, p_diplomacy: DiplomacyState, who: int
) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	_sheet = sheet
	_mode = Mode.SHEET
	_show()


## Raises the newest filed sheet, with the whole archive behind it.
func open_archive(p_state: GazetteState, p_diplomacy: DiplomacyState, who: int) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	_at = 0
	_mode = Mode.ARCHIVE
	_show()


## Raises the watchlist editor on its own (reachable from the cartouche seal).
func open_watchlist(p_state: GazetteState, p_diplomacy: DiplomacyState, who: int) -> void:
	state = p_state
	diplomacy = p_diplomacy
	viewer = who
	_mode = Mode.WATCHLIST
	_show()


func is_shown() -> bool:
	return _shown


## One press sets the sheet aside; the map was never blocked (REQ-P5-06).
func dismiss() -> void:
	if not _shown:
		return
	_shown = false
	visible = false
	dismissed.emit()


## Repaints after the watchlist changed underneath.
func refresh() -> void:
	if _shown:
		_render()


func _show() -> void:
	_shown = true
	visible = true
	modulate.a = 0.0
	_render()
	_fit()
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.18)


# --- construction ------------------------------------------------------------


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Printed paper inside a brass rule, lifted off the map by its own shadow, so
	# the sheet reads as the crown's broadsheet rather than another dossier
	# (REQ-P1-02).
	var style := UiTheme.box(Palette.PAPER, Palette.GOLD_DIM, 2, 2, Vector4(20, 14, 20, 14))
	style.shadow_color = Color(0.05, 0.04, 0.03, 0.55)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	column.add_child(_header())
	# Double rule under the masthead, the way a printed gazette divides its flag
	# from the field (REQ-P1-02).
	column.add_child(_rule(Palette.INK_LINE))
	column.add_child(_rule(Palette.GOLD, 2))
	_tabs = _tabs_row()
	column.add_child(_tabs)
	_nav = _nav_row()
	column.add_child(_nav)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	# A wrapped line's height is only known once the plate has its width.
	_body.minimum_size_changed.connect(_fit)
	_scroll.add_child(_body)


func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	_title = _label("THE GAZETTE", 26, Palette.INK)
	column.add_child(_title)
	_stamp = _label("", 12, INK_SOFT, true)
	column.add_child(_stamp)
	row.add_child(column)
	var close := Button.new()
	close.text = "Set aside"
	close.tooltip_text = "Close the sheet — the map stays as it was"
	close.pressed.connect(dismiss)
	row.add_child(close)
	return row


func _tabs_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for entry: Array in [
		[Mode.SHEET, "The sheet"], [Mode.ARCHIVE, "History"], [Mode.WATCHLIST, "Watchlist"]
	]:
		var button := Button.new()
		button.text = String(entry[1])
		button.set_meta("mode", int(entry[0]))
		button.pressed.connect(_go.bind(int(entry[0])))
		row.add_child(button)
	return row


func _nav_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_newer = Button.new()
	_newer.text = "◀  Newer"
	_newer.pressed.connect(_step.bind(-1))
	row.add_child(_newer)
	_nav_label = _label("", 13, INK_SOFT)
	_nav_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_nav_label)
	_older = Button.new()
	_older.text = "Older  ▶"
	_older.pressed.connect(_step.bind(1))
	row.add_child(_older)
	return row


# --- render ------------------------------------------------------------------


func _go(mode: int) -> void:
	_mode = mode
	if _mode == Mode.ARCHIVE:
		_at = 0
	_render()


func _step(delta: int) -> void:
	if state == null:
		return
	_at = clampi(_at + delta, 0, maxi(state.sheets.size() - 1, 0))
	_render()


func _render() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for child: Node in _tabs.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		var mode: int = int(button.get_meta("mode", Mode.SHEET))
		var current: bool = mode == int(_mode)
		button.add_theme_color_override("font_color", Palette.INK if current else INK_SOFT)
		button.add_theme_stylebox_override(
			"normal",
			UiTheme.box(
				Color(0.86, 0.80, 0.66, 1.0) if current else Color(0, 0, 0, 0),
				Palette.GOLD_DIM if current else Color(0, 0, 0, 0),
				1,
				2,
				Vector4(10, 4, 10, 4)
			)
		)
	_nav.visible = _mode == Mode.ARCHIVE
	match _mode:
		Mode.SHEET:
			_title.text = "THE GAZETTE"
			_stamp.text = DiplomacyHistory.stamp_for_turn(int(_sheet.get("turn", 0)))
			_sections(_sheet)
		Mode.ARCHIVE:
			_render_archive()
		Mode.WATCHLIST:
			_render_watchlist()


func _render_archive() -> void:
	_title.text = "THE GAZETTE  ·  ARCHIVE"
	var sheets: Array[Dictionary] = state.history() if state != null else []
	if sheets.is_empty():
		_stamp.text = ""
		_body.add_child(_label(NO_HISTORY, 14, Palette.INK))
		return
	_at = clampi(_at, 0, sheets.size() - 1)
	var sheet: Dictionary = sheets[_at]
	_stamp.text = DiplomacyHistory.stamp_for_turn(int(sheet.get("turn", 0)))
	_nav_label.text = "%d of %d" % [_at + 1, sheets.size()]
	_newer.disabled = _at <= 0
	_older.disabled = _at >= sheets.size() - 1
	_sections(sheet)


## Items arrive grouped World -> Our court -> Courts of interest, so a heading is
## printed whenever the class changes (wiki: the-gazette § Classes).
func _sections(sheet: Dictionary) -> void:
	var items: Array = sheet.get("items", []) as Array
	if items.is_empty():
		_body.add_child(_label(EMPTY_LINE, 14, Palette.INK))
		return
	var last: int = -1
	for raw: Variant in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw
		var cls: int = int(item.get("class", Gazette.Class.COURT))
		if cls != last:
			if last >= 0:
				_body.add_child(_spacer(8))
			_body.add_child(_rule(Palette.INK_FAINT))
			_body.add_child(_label(Gazette.heading(cls), 11, Color(0.45, 0.33, 0.12)))
			last = cls
		var text: String = String(item.get("text", ""))
		if not text.is_empty():
			_body.add_child(_label(text, 14, Palette.INK))


func _render_watchlist() -> void:
	_title.text = "THE GAZETTE  ·  WATCHLIST"
	_stamp.text = "Courts whose doings are reported"
	_body.add_child(
		_label(
			"Every court your crown has met may be followed. Struck-off courts stay "
			+ "struck off, even if a new treaty binds them.",
			13,
			INK_SOFT
		)
	)
	_body.add_child(_spacer(4))
	var followed: int = 0
	for faction: int in _known_courts():
		var row := CheckBox.new()
		row.text = "%s  ·  %s" % [
			FactionCatalog.name_of(faction),
			FactionCatalog.type_label(FactionCatalog.type_of(faction)),
		]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Palette.INK)
		row.button_pressed = state != null and state.is_watched(faction)
		if row.button_pressed:
			followed += 1
		row.toggled.connect(_on_watch_toggled.bind(faction))
		_body.add_child(row)
	if followed == 0:
		_body.add_child(_label("No court is followed — the sheet will be quiet.", 13, Palette.INK))


func _on_watch_toggled(on: bool, faction: int) -> void:
	if state == null:
		return
	state.set_watched(faction, on)
	watch_changed.emit(faction)
	call_deferred("_render")


## Every faction this crown has met, plus any it already follows.
func _known_courts() -> Array[int]:
	var ids: Array[int] = []
	if state != null:
		ids.append_array(state.watched)
	if diplomacy != null:
		for record: DiplomacyRelation in diplomacy.relations.values():
			if record == null or not (record.a == viewer or record.b == viewer):
				continue
			var other: int = record.other(viewer)
			if other >= 0 and not ids.has(other):
				ids.append(other)
	ids.sort()
	return ids


# --- layout and helpers ------------------------------------------------------


## Phones, tablets and desktop share the one plate; it only narrows to the room
## it has and stands as tall as the news it prints (REQ-P1-05, REQ-P5-07).
func _fit() -> void:
	if _panel == null or _body == null:
		return
	var room: float = maxf(size.x - VIEWPORT_MARGIN * 2.0, MIN_WIDTH)
	var width: float = minf(MAX_WIDTH, room)
	var left: float = (size.x - width) * 0.5
	_panel.offset_left = left
	_panel.offset_right = left + width
	_panel.offset_top = PLATE_TOP
	# The container takes its own content height; only the news scroll is capped,
	# so a quiet sheet is a short plate and a busy one runs on inside the scroll.
	_panel.offset_bottom = PLATE_TOP
	var room_left: float = maxf(size.y - PLATE_TOP - VIEWPORT_MARGIN - 150.0, 120.0)
	var content: float = _body.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, clampf(content, 120.0, room_left))


func _label(text: String, pixels: int, ink: Color, italic: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", UiTheme.serif_italic() if italic else UiTheme.serif())
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", ink)
	return label


func _rule(ink: Color, thickness: int = 1) -> Control:
	var line := ColorRect.new()
	line.color = ink
	line.custom_minimum_size = Vector2(0, thickness)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _spacer(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
