class_name BattleSimSetup
extends PanelContainer
## The Battle Simulator's setup rail: ground, fort, three regiment slots a side,
## plans and seed. It emits intents and hands a plain spec dictionary to
## [BattleScenario] — it never resolves a rule itself (REQ-P2-03, REQ-P3-01).

signal run_requested
signal step_requested
signal reset_requested

const SLOTS: int = 3
const MAX_COUNT: int = 20

const TERRAIN_ROWS: Array[Array] = [
	["open", "Open field"], ["hill", "Hillside"], ["woods", "Woods"],
	["town", "Town streets"], ["marsh", "Marsh"],
]
const FORT_LABELS: Array[String] = ["No fort", "Wood fort", "Stone fort", "Modern fort"]
const PLAN_LABELS: Array[String] = ["Aggressive", "Balanced", "Defensive"]
const PLAN_KEYS: Array[String] = ["aggressive", "balanced", "defensive"]

var _terrain: OptionButton = null
var _fort: OptionButton = null
var _attacker_plan: OptionButton = null
var _defender_plan: OptionButton = null
var _seed: SpinBox = null
var _types: Array[String] = []
var _attacker_slots: Array[Dictionary] = []
var _defender_slots: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(10, 8, 10, 8))
	)
	_types = BattleScenario.catalog_types()
	_build()


func spec() -> Dictionary:
	return {
		"attacker": _types_of(_attacker_slots, ["musketeers", "musketeers", "musketeers", "musketeers"]),
		"defender": _types_of(_defender_slots, ["pikemen", "pikemen", "pikemen"]),
		"fort": _fort.selected,
		"terrain": String(TERRAIN_ROWS[maxi(_terrain.selected, 0)][0]),
		"attacker_plan": PLAN_KEYS[maxi(_attacker_plan.selected, 0)],
		"defender_plan": PLAN_KEYS[maxi(_defender_plan.selected, 0)],
		"seed": int(_seed.value),
	}


func _build() -> void:
	## The rail scrolls on a short window so the seed and buttons never clip.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(_title("BATTLE SIMULATOR", 18, Palette.GOLD_PALE))
	column.add_child(_hint("Runs the live Quick Battle resolver. Change a number and fight again."))
	column.add_child(_section("Ground"))
	_terrain = _option(TERRAIN_ROWS)
	_terrain.selected = 0
	column.add_child(_terrain)
	column.add_child(_section("Fort"))
	_fort = _option_labeled(FORT_LABELS)
	_fort.selected = 2
	column.add_child(_fort)
	column.add_child(_section("Attacker"))
	_attacker_slots = _slot_block(column, "attacker")
	column.add_child(_section("Defender"))
	_defender_slots = _slot_block(column, "defender")
	column.add_child(_section("Orders"))
	var plans := HBoxContainer.new()
	plans.add_theme_constant_override("separation", 6)
	column.add_child(plans)
	_attacker_plan = _plan_picker(plans, "Attacker plan")
	_defender_plan = _plan_picker(plans, "Defender plan")
	_defender_plan.selected = 2
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	column.add_child(seed_row)
	var seed_label := _hint("Seed")
	seed_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	seed_label.custom_minimum_size = Vector2(48, 0)
	seed_row.add_child(seed_label)
	_seed = SpinBox.new()
	_seed.min_value = 0
	_seed.max_value = 99999
	_seed.value = 11
	_seed.custom_minimum_size = Vector2(96, 0)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	buttons.add_child(_button("Fight", run_requested))
	buttons.add_child(_button("Next round", step_requested))
	buttons.add_child(_button("Reset", reset_requested))


## Three type/count rows; the first slot carries a sensible default.
func _slot_block(column: VBoxContainer, side: String) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for index in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		column.add_child(row)
		var picker := _option_types()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(picker)
		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = MAX_COUNT
		count.custom_minimum_size = Vector2(58, 0)
		row.add_child(count)
		slots.append({"picker": picker, "count": count})
	_apply_defaults(slots, side)
	return slots


## Defaults: a musket-and-gun attack against a pike-and-gun garrison.
func _apply_defaults(slots: Array[Dictionary], side: String) -> void:
	var rows: Array = (
		[["musketeers", 8], ["culverin", 2], ["knights", 0]] if side == "attacker"
		else [["pikemen", 4], ["musketeers", 3], ["culverin", 1]]
	)
	for index in mini(rows.size(), slots.size()):
		var type_id: String = String((rows[index] as Array)[0])
		slots[index]["picker"].selected = maxi(_types.find(type_id), 0)
		slots[index]["count"].value = int((rows[index] as Array)[1])


func _types_of(slots: Array[Dictionary], fallback: Array) -> Array[String]:
	var types: Array[String] = []
	for slot: Dictionary in slots:
		var picker: OptionButton = slot["picker"]
		var type_id: String = _types[clampi(picker.selected, 0, _types.size() - 1)]
		for _index in int((slot["count"] as SpinBox).value):
			types.append(type_id)
	if types.is_empty():
		for entry: Variant in fallback:
			types.append(String(entry))
	return types


# --- widgets ----------------------------------------------------------------


func _option(rows: Array[Array]) -> OptionButton:
	var picker := OptionButton.new()
	for row: Array in rows:
		picker.add_item(String(row[1]))
	return picker


func _option_labeled(labels: Array[String]) -> OptionButton:
	var picker := OptionButton.new()
	for label: String in labels:
		picker.add_item(label)
	return picker


func _option_types() -> OptionButton:
	var picker := OptionButton.new()
	for type_id: String in _types:
		picker.add_item(RegimentCatalog.display_name(type_id))
	return picker


func _plan_picker(row: HBoxContainer, label: String) -> OptionButton:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(_hint(label))
	var picker := _option_labeled(PLAN_LABELS)
	box.add_child(picker)
	return picker


func _button(text: String, output: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: output.emit())
	return button


func _title(text: String, size_px: int, color: Color) -> Label:
	var label := _hint(text)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _section(text: String) -> Label:
	var label := _hint(text.to_upper())
	label.add_theme_color_override("font_color", Palette.GOLD)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
