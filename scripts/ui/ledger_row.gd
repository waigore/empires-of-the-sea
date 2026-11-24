class_name LedgerRow
extends PanelContainer
## One row of a crown ledger — the muster roll, the province ledger, the civilian
## roster, the command pool and the eyes. The five sheets print the same
## skeleton: a gold panel, a medallion, a serif name beside its one-word chip, a
## detail line, an optional state column and a Visit seal — an icon-only door at
## the close seal's touch floor, its words in a tooltip, so a phone needs no
## hover (REQ-P5-01, REQ-P5-04).
##
## The skeleton and the Visit door live here; a row only says what it prints
## through the hooks below and its `_fill` (REQ-P3-01, RUB-P3-01). `compact` is
## set before `setup`, so a phone row is built at phone sizes once, not resized
## later. The row body is a reading, not a door: a tap on the name, the chip or
## the detail line orders nothing.
##
## Presentation only: every figure arrives in the row dictionary.

## The Visit seal's glyph and the words its tooltip carries until a row names its
## own place. Of the medallion set only the globe still reads as one symbol at
## this size — "the chart" — so a step above the close seal's 22 points buys the
## pictogram legibility without moving the seal off its touch floor
## (ChromeIcons).
const VISIT_ICON: String = "globe"
const VISIT_GLYPH_PIXELS: int = 26
const VISIT_TIP: String = "Visit"

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
## The state column's own two lines, mounted by `_reading_column`: the standing
## line over the condition the row holds. A row that prints no column leaves both
## null.
var _standing: Label = null
var _reading: Label = null


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


## Whether the row carries the Visit seal.
func _wants_visit() -> bool:
	return true


## A press of the row's Visit seal, in the row's own words.
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


# --- the shared dress --------------------------------------------------------


## The state column the crown's place and force rows wear: the place's standing
## line over the condition it holds. The row names the column's width and the ink
## of the line a crown scans first; a phone folds the column into the detail line,
## so it is built once at phone sizes and never shown. A row with no such reading
## never calls this, and its column stays unmounted.
func _reading_column(state: VBoxContainer, standing_pixels: int = 12, width: int = 190) -> void:
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(width, 0)
	state.visible = not compact
	_standing = UiRowBuilder.wrapped_line("", standing_pixels, Palette.TEXT)
	state.add_child(_standing)
	_reading = UiRowBuilder.wrapped_line("", 11, Palette.TEXT_DIM)
	state.add_child(_reading)


## The detail line of a row that prints where it stands: the place, the chart it
## stands in and — on a phone, where the state column is folded away — the middle
## reading the column would have carried.
func _place_detail(place: String, compact_middle: String = "") -> void:
	var chart: String = String(data.get("region_label", "Uncharted"))
	if compact:
		_detail.text = "%s  ·  %s  ·  %s" % [place, compact_middle, chart]
		return
	_detail.text = "%s  ·  %s" % [place, chart]


# --- skeleton ----------------------------------------------------------------


func _build() -> void:
	add_theme_stylebox_override("panel", _panel_style())
	# The body stops a click that reaches it (a padding, a gap) from falling
	# through to the chart behind the sheet; it never orders a visit.
	mouse_filter = Control.MOUSE_FILTER_STOP
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
		_visit = _visit_door()
		_body.add_child(_visit)


## The Visit seal: the close door's dress in a row — an icon-only medallion at
## the same touch floor, its words in a tooltip, so a thumb reaches it on a phone
## and a pointer reads it on the chart (REQ-P1-05, REQ-P5-01). A row names its
## place in `_fill`; the seal never prints a caption of its own.
func _visit_door() -> Button:
	var door := Button.new()
	door.name = "Visit"
	door.custom_minimum_size = CloseSeal.SIZE
	door.size_flags_horizontal = Control.SIZE_SHRINK_END
	door.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	door.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	door.tooltip_text = VISIT_TIP
	ChromeIcons.apply(door, VISIT_ICON, VISIT_GLYPH_PIXELS)
	door.pressed.connect(_on_visit)
	return door


func _panel_style() -> StyleBox:
	return UiTheme.box(
		Palette.with_alpha(Palette.PARCHMENT_ROW, 0.88),
		Palette.with_alpha(Palette.GOLD_DIM, 0.55),
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
