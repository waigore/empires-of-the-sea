class_name EstatesHead
extends VBoxContainer
## Top of the estates ledger: summary figures, exact-yield line and the filter
## strip. Owns no rules state — the panel hands it a snapshot and it renders,
## emitting only filter intents (REQ-P3-02). Filtering lives in EstateLedger.

signal filter_selected(key: String)

const FILTERS: Array[String] = ["all", "producing", "building", "vacant", "issues"]
const FILTER_LABELS: Dictionary = {
	"all": "All",
	"producing": "Producing",
	"building": "Works",
	"vacant": "Vacant",
	"issues": "Issues",
}

var _stat_values: Dictionary = {}
var _stats: Control = null
var _output_line: Label = null
var _stores_line: Label = null
var _filter_buttons: Dictionary = {}
var filter: String = "all"


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_build_stats()
	_build_filters()
	_build_stores()


func _build_stats() -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 26)
	add_child(stats)
	_stats = stats
	for spec: Array in [
		["estates", "ESTATES"],
		["producing", "PRODUCING"],
		["output", "YIELD / TURN"],
		["building", "WORKS"],
	]:
		stats.add_child(_stat_box(String(spec[0]), String(spec[1])))
	_output_line = Label.new()
	_output_line.add_theme_font_size_override("font_size", 13)
	_output_line.add_theme_color_override("font_color", Palette.GOLD)
	_output_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_output_line)


func _stat_box(key: String, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	var value := Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 22)
	value.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(value)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	box.add_child(label)
	_stat_values[key] = value
	return box


func _build_filters() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for key: String in FILTERS:
		var button := Button.new()
		button.text = String(FILTER_LABELS[key])
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 28)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_press_filter.bind(key))
		_filter_buttons[key] = button
		row.add_child(button)


func _build_stores() -> void:
	_stores_line = Label.new()
	_stores_line.add_theme_font_size_override("font_size", 11)
	_stores_line.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.8))
	_stores_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_stores_line)


func _press_filter(key: String) -> void:
	set_filter(key)
	filter_selected.emit(key)


## Selects a filter without emitting (the panel pushes the key when it opens).
func set_filter(key: String) -> void:
	filter = key if FILTERS.has(key) else "all"
	for candidate: String in _filter_buttons.keys():
		(_filter_buttons[candidate] as Button).set_pressed_no_signal(candidate == filter)


## Renders the summary rows from an ImprovementLedger snapshot.
func render(snapshot: Dictionary, stockpile: Dictionary) -> void:
	var counts: Dictionary = snapshot.get("counts", {})
	var totals: Dictionary = snapshot.get("totals", {})
	(_stat_values["estates"] as Label).text = str(int(counts.get("estates", 0)))
	(_stat_values["producing"] as Label).text = str(int(counts.get("producing", 0)))
	(_stat_values["output"] as Label).text = str(EstateLedger.total_output(totals))
	(_stat_values["building"] as Label).text = str(int(counts.get("building", 0)))
	_output_line.text = "Projected yield: %s  ·  idle Builders: %d" % [
		ImprovementSystem.output_text(totals),
		int(counts.get("idle_builders", 0)),
	]
	_stores_line.text = "Stores: %d lumber · %d cast iron · %d bronze · %d paper · %d grain" % [
		int(stockpile.get("lumber", 0)),
		int(stockpile.get("castIron", 0)),
		int(stockpile.get("bronze", 0)),
		int(stockpile.get("paper", 0)),
		int(stockpile.get("grain", 0)),
	]


## Phone-sized filter buttons, exposed so layout tests can assert tap targets.
func filter_buttons() -> Dictionary:
	return _filter_buttons


## Phone layout: thumb-sized filters and the stat boxes traded for list rows
## (the projection line still carries the yield).
func set_compact(compact: bool) -> void:
	for button: Button in _filter_buttons.values():
		button.custom_minimum_size.y = 40.0 if compact else 28.0
	if _stats != null:
		_stats.visible = not compact
