class_name LedgerFrame
extends PanelContainer
## The one docked ledger the crown reads at the chart's edge: the gold sheet,
## a masthead with its Close door, a tab strip and the phone profile. The
## economy, the college and the court ledgers share this chrome, so the padding,
## the close door and the compact fit are written once (REQ-P3-01, REQ-P1-07).
##
## A subclass names its masthead, builds its body and repaints it. The frame
## never reads rules and never orders anything.

signal close_pressed

## The ledger's fill: near-black parchment, so the chart's ink never shows
## through the sheet.
const FILL: Color = Color(Palette.PARCHMENT, 0.97)
const PADDING: Vector4 = Vector4(20, 14, 20, 14)
const PADDING_COMPACT: Vector4 = Vector4(12, 8, 12, 8)
const TITLE_PIXELS: int = 24
const TITLE_PIXELS_COMPACT: int = 20
## The Close door is the shared seal; a phone keeps the same thumb-sized one
## (REQ-P5-07).
const CREST_PIXELS: float = 30.0
const CREST_PIXELS_COMPACT: float = 24.0

## The masthead's title, named once by the subclass before the frame builds.
var title_text: String = ""

var _column: VBoxContainer = null
var _title: Label = null
var _close: Button = null
var _crest: Control = null
## The standing line under the body; a ledger only has one if it asks for it.
var _hint: Label = null


func _ready() -> void:
	_paint(false)
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


# --- subclass hooks ----------------------------------------------------------


## The medallion at the masthead's left; null leaves the title at the edge.
func _build_crest() -> Control:
	return null


## The body between the masthead and the standing line: the ledger's own rows.
func _build_body(_column: VBoxContainer) -> void:
	pass


## The extra phone work a ledger's own rows need (sizes, strips, page chips).
func _apply_profile(_compact: bool) -> void:
	pass


# --- shell -------------------------------------------------------------------


## The sheet re-fits itself for the viewport it is actually shown in.
func _fit_to_viewport() -> void:
	if not is_inside_tree():
		return
	set_compact(HudLayout.is_compact(get_viewport_rect().size))


## Atlas or phone chrome: one padding, one title size, one Close door. A ledger
## adds its own rows through `_apply_profile` (REQ-P1-07).
func set_compact(compact: bool) -> void:
	if _column == null:
		return
	_paint(compact)
	if _title != null:
		_title.add_theme_font_size_override(
			"font_size", TITLE_PIXELS_COMPACT if compact else TITLE_PIXELS
		)
	if _crest != null:
		var crest: float = CREST_PIXELS_COMPACT if compact else CREST_PIXELS
		_crest.custom_minimum_size = Vector2(crest, crest)
	if _hint != null:
		_hint.visible = not compact
	_column.add_theme_constant_override("separation", 4 if compact else 8)
	_apply_profile(compact)


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	add_child(_column)
	_column.add_child(_masthead())
	_build_body(_column)


func _paint(compact: bool) -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			FILL, Palette.GOLD_DIM, 1, 4, PADDING_COMPACT if compact else PADDING
		)
	)


## Title and Close door: both are the same in every ledger, so the frame draws
## them and the ledger only names itself (REQ-P3-01).
func _masthead() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_crest = _build_crest()
	if _crest != null:
		header.add_child(_crest)
	_title = UiRowBuilder.serif_line(title_text, TITLE_PIXELS, Palette.GOLD_PALE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close = CloseSeal.make()
	_close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(_close)
	return header


## The standing line a ledger says under its rows: dim, wrapped, and hidden on
## a phone, where the sheet keeps its room for the list (REQ-P1-07).
func _make_hint(text: String) -> Label:
	_hint = UiRowBuilder.wrapped_line(text, 11, Palette.TEXT_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_hint)
	return _hint


## A tab strip that gives way on a short sheet; `min_height` is its atlas height.
func _make_tabs(min_height: float) -> TabContainer:
	var tabs := TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0.0, min_height)
	tabs.add_theme_color_override("font_selected_color", Palette.GOLD_PALE)
	tabs.add_theme_color_override("font_unselected_color", Palette.TEXT_DIM)
	_column.add_child(tabs)
	return tabs


## One scrolling tab: the body keeps the sheet's width and its rows their gap.
func _add_tab(tabs: TabContainer, title: String, body: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	return body
