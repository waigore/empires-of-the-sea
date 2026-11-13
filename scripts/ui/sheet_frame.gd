class_name SheetFrame
extends Control
## The one full-screen sheet the crown's ledgers stand in: a dim overlay, a
## safe-area margin, the gold panel, a titled header with a Close door, a
## scrolling body and a hint footer. The civilian roster, the muster roll and
## the court dossier share this chrome, so open/close, the fade, the compact
## profile and the pause-door park are written once (REQ-P3-01, REQ-P5-07).
##
## A subclass owns what its sheet reads: it names the title, builds its body and
## repaints it. The frame never reads rules and never orders anything.
##
## Sheets live on their own canvas layer, outside the HUD's safe-area offsets,
## so the frame applies the device insets itself.

const MARGIN_WIDE: int = 42
const MARGIN_COMPACT: int = 10

## The session a subclass binds when it parks the pause door; null for a sheet
## with no door to hold (the court dossier).
var play: PlaySession = null

## Chrome a subclass names once, before the frame builds itself.
var title_text: String = ""
var title_pixels: int = 28
var hint_text: String = ""
var hint_pixels: int = 10
## The InputMap action that toggles the sheet; empty leaves the key unused.
var toggle_action: String = ""

var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _scroll: ScrollContainer = null
var _title: Label = null
var _subtitle: Label = null
var _crest: Control = null
var _close: Button = null
var _hint: Label = null
var _fade: Tween = null
## Last applied layout profile (-1 before the first fit).
var _was_compact: int = -1
## This sheet holds the pause door while it is up (mirrored park/release).
var _parked_menu: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()
	visible = false
	resized.connect(_fit)
	_fit()


# --- subclass hooks ----------------------------------------------------------


## The medallion at the header's left. Roster overrides with a civilian icon.
func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


## The body between the header and the hint: filters, a scrolling row column,
## whatever the sheet reads.
func _build_body(column: VBoxContainer) -> void:
	pass


## Whether a session is ready for this sheet to open.
func _can_open() -> bool:
	return play != null and play.world != null


## Repaint whatever the sheet reads; the frame calls it before it opens.
func refresh() -> void:
	pass


## The compact/narrow profile, once per fit. A subclass scales its own titles
## and repaints rows that fix their size at construction.
func _apply_profile(compact: bool, narrow: bool) -> void:
	if _close != null:
		_close.custom_minimum_size.x = 64.0 if narrow else 92.0
	if _hint != null:
		_hint.visible = not compact


## True when the compact profile changed after the first fit.
func _on_profile_changed() -> void:
	pass


# --- shell -------------------------------------------------------------------


func _build() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.80)
	_overlay.add_child(dim)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.99), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16)
		)
	)
	_margin.add_child(_panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_panel.add_child(_column)
	_column.add_child(_header())
	_build_body(_column)
	_column.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	_crest = _build_crest()
	_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_crest)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	_title = _label(title_text, title_pixels, Palette.GOLD_PALE)
	_title.add_theme_font_override("font", UiTheme.serif())
	titles.add_child(_title)

	_subtitle = _label("", 12, Palette.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)

	_close = Button.new()
	_close.text = "Close"
	_close.custom_minimum_size = Vector2(92, 40)
	_close.pressed.connect(close)
	header.add_child(_close)
	return header


func _footer() -> Control:
	_hint = _label(hint_text, hint_pixels, Color(0.80, 0.74, 0.62, 0.76))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _hint


## A scrolling body column; the roster and the muster print their rows into it.
func _append_scroll(column: VBoxContainer) -> ScrollContainer:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	return _scroll


## The explanation a ledger prints when a filter leaves no row.
func _make_empty(rows: VBoxContainer, font_size: int = 15) -> Label:
	var empty := _label("", font_size, Palette.TEXT_DIM)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(empty)
	return empty


static func _label(text: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	return label


# --- open / close ------------------------------------------------------------


func open() -> void:
	if not _can_open():
		return
	visible = true
	refresh()
	_set_menu_visible(false)
	_reveal()


func close() -> void:
	if not visible:
		return
	visible = false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	_set_menu_visible(true)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func _reveal() -> void:
	visible = true
	modulate.a = 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


## The pause trigger sits on a higher canvas layer than the HUD; park it while
## the sheet is up so its gold seal does not cut through the frame. The notifier
## mirrors the park: a sheet that closes without ever opening does not release
## another ledger's or the observer's frame.
func _set_menu_visible(show_menu: bool) -> void:
	var door: GameMenuDoor = play.pause_menu.door if play != null and play.pause_menu != null else null
	_parked_menu = GameMenuDoor.set_held(door, show_menu, _parked_menu)


func _exit_tree() -> void:
	_set_menu_visible(true)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action.is_empty() or not event.is_action_pressed(toggle_action):
		return
	if play == null or play.campaign_over():
		return
	toggle()
	get_viewport().set_input_as_handled()


# --- layout ------------------------------------------------------------------


func _fit() -> void:
	if _margin == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var compact: bool = HudLayout.is_compact(view)
	var side: int = MARGIN_COMPACT if compact else MARGIN_WIDE
	var insets: Vector4 = PlatformDisplay.safe_insets(get_window())
	_margin.add_theme_constant_override("margin_left", side + int(insets.x))
	_margin.add_theme_constant_override("margin_right", side + int(insets.z))
	_margin.add_theme_constant_override("margin_top", (56 if compact else 88) + int(insets.y))
	_margin.add_theme_constant_override("margin_bottom", (6 if compact else 34) + int(insets.w))
	_column.add_theme_constant_override("separation", 6 if compact else 10)
	var pad := Vector4(12, 10, 12, 10) if compact else Vector4(20, 16, 20, 16)
	_panel.add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.10, 0.08, 0.06, 0.99), Palette.GOLD_DIM, 1, 4, pad)
	)
	_apply_profile(compact, view.x < 520.0)
	var profile: int = 1 if compact else 0
	var changed: bool = _was_compact >= 0 and _was_compact != profile
	_was_compact = profile
	if changed:
		_on_profile_changed()
