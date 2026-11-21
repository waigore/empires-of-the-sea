class_name LedgerFilterBar
extends VBoxContainer
## The two chip rows at the head of a crown ledger: which chart, and which
## reading of the sheet's one family — a force's kind, a province's defect, a
## town's step. Every option stays on the page at zero, so a filter never hides
## its own way back (REQ-P5-03, REQ-P5-07), and the chosen chip carries the gold
## edge and ink (REQ-P1-07).
##
## The ledger names its keys and the words of its reading; the bar builds the
## chips once, paints the chosen pair and reports the press. It owns no rules
## state and never reads a snapshot (REQ-P3-02).

## A chip was pressed: which row it sits in, and the key it carries.
signal chosen(key: String, region_row: bool)
## A sort chip was pressed: the key the view orders its rows by.
signal sort_chosen(key: String)

const CAPTION_WIDTH: float = 58.0
const CHIP_HEIGHT: float = 34.0
const SEPARATION: int = 6

var _chart_row: HBoxContainer = null
var _reading_row: HBoxContainer = null
## The optional third row: the order the sheet prints its rows in. A sheet that
## offers no order leaves it unmounted.
var _sort_row: HBoxContainer = null
var _sort_keys: Array = []


## "Both charts" / "Old World" / "New World": the chart axis is the same on
## every crown ledger, so its words come from the catalogue's own region keys
## instead of a copy per sheet.
static func chart_word(key: String) -> String:
	for index in FactionCatalog.REGION_KEYS.size():
		if key == FactionCatalog.region_key(index):
			return FactionCatalog.region_label(index)
	return "Both charts"


## Builds both rows; `reading_word(key)` names one chip of the reading row.
func fill(
	chart_caption: String,
	reading_caption: String,
	chart_keys: Array,
	reading_keys: Array,
	reading_word: Callable
) -> void:
	add_theme_constant_override("separation", 4)
	_chart_row = _chip_row(
		chart_caption, chart_keys, true, Callable(),
		func(key: String) -> void: chosen.emit(key, true)
	)
	_reading_row = _chip_row(
		reading_caption, reading_keys, false, reading_word,
		func(key: String) -> void: chosen.emit(key, false)
	)
	add_child(_chart_row)
	add_child(_reading_row)


## Paints the chosen pair: one gold chip per row, the rest plain.
func render(chart_key: String, reading_key: String) -> void:
	_paint(_chart_row, chart_key)
	_paint(_reading_row, reading_key)


## Paints the chosen sort chip; a sheet without a sort row asks nothing of it.
func render_sort(sort_key: String) -> void:
	_paint(_sort_row, sort_key)


## The order row: which figure the sheet sorts by. The keys change with the
## reading (a defence view offers one figure, an economy view one per resource),
## so the row is rebuilt only when the key list itself changes.
func fill_sort(caption: String, keys: Array, word: Callable, active_key: String) -> void:
	if keys == _sort_keys and _sort_row != null:
		_paint(_sort_row, active_key)
		return
	_sort_keys = keys.duplicate()
	if _sort_row != null:
		remove_child(_sort_row)
		_sort_row.queue_free()
	_sort_row = _chip_row(
		caption, keys, false, word, func(key: String) -> void: sort_chosen.emit(key)
	)
	add_child(_sort_row)
	_paint(_sort_row, active_key)


## One chip row: the caption, one chip per key, and the `sink` that a press
## reports its key to (`chosen` for the chart and reading axes, `sort_chosen`
## for the order).
func _chip_row(
	caption: String, keys: Array, region_row: bool, word: Callable, sink: Callable
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SEPARATION)
	var label := UiRowBuilder.caption(caption.to_upper(), 9, Palette.GOLD_DIM, CAPTION_WIDTH)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	for key: String in keys:
		var chip := Button.new()
		chip.text = chart_word(key) if region_row else String(word.call(key))
		chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
		chip.focus_mode = Control.FOCUS_ALL
		chip.add_theme_font_size_override("font_size", 12)
		chip.set_meta("key", key)
		chip.pressed.connect(func() -> void: sink.call(key))
		row.add_child(chip)
	return row


func _paint(row: HBoxContainer, active_key: String) -> void:
	if row == null:
		return
	for child: Node in row.get_children():
		var chip := child as Button
		if chip == null:
			continue
		_style(chip, String(chip.get_meta("key")) == active_key)


func _style(chip: Button, active: bool) -> void:
	var fill: Color = Color(0.20, 0.16, 0.10, 0.95) if active else Color(0.12, 0.10, 0.07, 0.55)
	var edge: Color = Palette.GOLD if active else Color(0.54, 0.43, 0.12, 0.55)
	var pad := Vector4(9, 3, 9, 3)
	chip.add_theme_stylebox_override("normal", UiTheme.box(fill, edge, 1, 3, pad))
	chip.add_theme_stylebox_override("hover", UiTheme.box(fill, Palette.GOLD, 1, 3, pad))
	var ink: Color = Palette.GOLD_PALE if active else Color(0.78, 0.72, 0.60)
	chip.add_theme_color_override("font_color", ink)
