class_name LedgerRow
extends PanelContainer
## One row of a crown ledger — the muster roll, the province ledger, the civilian
## roster, the command pool and the eyes. The five sheets print the same
## skeleton: a gold panel, a medallion, a serif name beside its one-word chip, a
## detail line, an optional state column and a Visit action that the whole row
## doubles as a tap target for, so a phone needs no hover (REQ-P5-01, REQ-P5-04).
##
## The skeleton and the tap live here; a row only says what it prints through the
## hooks below and its `_fill` (REQ-P3-01, RUB-P3-01). `compact` is set before
## `setup`, so a phone row is built at phone sizes once, not resized later.
##
## Presentation only: every figure arrives in the row dictionary.

var data: Dictionary = {}
## Phone rows fold the state column into the detail line and get thumb actions.
var compact: bool = false

var _body: HBoxContainer = null
var _info: VBoxContainer = null
var _name: Label = null
var _chip: Label = null
var _detail: Label = null
var _state: VBoxContainer = null
var _visit: Button = null


func setup(row: Dictionary) -> void:
	data = row
	_build()
	_fill()


# --- hooks a row fills in ----------------------------------------------------


## The medallion at the row's left: an `Icon`, a painted unit or a portrait.
func _build_icon() -> Control:
	return null


## Whether the row wears the one word a crown scans for beside its name.
func _wants_chip() -> bool:
	return true


## The right-hand column: a standing line, a tally, a progress bar. A row with
## nothing to add leaves it empty and the column is not mounted. The column's
## own width, separation and compact visibility are the row's to set.
func _build_state(_state: VBoxContainer) -> void:
	pass


## Whether the row carries the Visit door (and the whole-row tap with it).
func _wants_visit() -> bool:
	return true


## A tap on the row or on its Visit door, in the row's own words.
func _on_visit() -> void:
	pass


## The detail line's size and ink; a row that prints more than place and state
## may read one step louder.
func _detail_pixels() -> int:
	return 11


func _detail_color() -> Color:
	return Color(0.82, 0.76, 0.64)


## The row's own reading, painted into the labels the skeleton mounted.
func _fill() -> void:
	pass


# --- skeleton ----------------------------------------------------------------


func _build() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _wants_visit():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 10 if compact else 12)
	add_child(_body)

	var icon: Control = _build_icon()
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_body.add_child(icon)

	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 1)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_info)

	var name_holder: Control = _info
	if _wants_chip():
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		_info.add_child(heading)
		name_holder = heading

	_name = UiRowBuilder.serif_line("", 17 if compact else 19, Palette.GOLD_PALE)
	# A heading is one line: an autowrapped name inside this HBox reports no
	# minimum width, so the box hands it one glyph and the chip lands on it.
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_holder.add_child(_name)

	if _wants_chip():
		_chip = UiRowBuilder.label("", 9, Palette.INK)
		name_holder.add_child(_chip)

	_detail = UiRowBuilder.wrapped_line("", _detail_pixels(), _detail_color())
	_info.add_child(_detail)

	var state := VBoxContainer.new()
	_build_state(state)
	if state.get_child_count() > 0:
		_state = state
		_body.add_child(state)

	if _wants_visit():
		_visit = UiRowBuilder.button(
			"Visit", 42.0 if compact else 36.0, 72.0 if compact else 78.0
		)
		_visit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_visit.pressed.connect(_on_visit)
		_body.add_child(_visit)


func _panel_style() -> StyleBox:
	return UiTheme.box(
		Color(0.13, 0.11, 0.08, 0.88),
		Color(0.54, 0.43, 0.12, 0.55),
		1,
		3,
		Vector4(8, 5, 8, 5) if compact else Vector4(10, 7, 10, 7)
	)


## The chip's one colour: the row names its reading, the skeleton paints it.
func _paint_chip(fill: Color) -> void:
	if _chip == null:
		return
	_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(fill, fill, 0, 2, Vector4(6, 1, 6, 1))
	)


## The whole row is the Visit door, so a thumb never has to find the button.
func _gui_input(event: InputEvent) -> void:
	if not _wants_visit() or not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_visit()
