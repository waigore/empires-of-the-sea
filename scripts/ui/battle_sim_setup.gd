class_name BattleSimSetup
extends PanelContainer
## The Battle Simulator's setup rail: ground, fort, the garrison's battery line,
## three regiment slots a side, plans and medals. It emits intents and hands a
## plain spec dictionary to [BattleScenario] — it never resolves a rule itself
## (REQ-P2-03, REQ-P3-01).

signal run_requested
signal step_requested
signal reset_requested

const SLOTS: int = 3
const MAX_COUNT: int = 20
## The garrison's emplaced line, as the studies the battery reads (wiki:
## siege-mechanics § Emplaced Artillery): Royal by default, Heavy once mined,
## Siege once the heavy line is mastered. Each row is the tech key the table
## names, so the rail cannot offer a gun line `FortRules` does not know.
const GUN_ROWS: Array[Array] = [
	["", "Royal guns"], ["heavy_emplaced_artillery", "Heavy guns"],
	["emplaced_siege_guns", "Siege guns"],
]
## Chevrons a commander's colours have won (wiki: combat § Strength): the
## resolver reads 0–4 as a 1.0–1.4 multiplier, so the rail offers the same span.
const MEDAL_MAX: int = 4

const TERRAIN_ROWS: Array[Array] = [
	["open", "Open field"], ["hill", "Hillside"], ["woods", "Woods"],
	["town", "Town streets"], ["marsh", "Marsh"],
]
const FORT_LABELS: Array[String] = ["No fort", "Wood fort", "Stone fort", "Modern fort"]
const PLAN_LABELS: Array[String] = ["Aggressive", "Balanced", "Defensive"]
const PLAN_KEYS: Array[String] = ["aggressive", "balanced", "defensive"]

var _terrain: OptionButton = null
var _fort: OptionButton = null
var _guns: OptionButton = null
var _attacker_plan: OptionButton = null
var _defender_plan: OptionButton = null
var _attacker_medals: SpinBox = null
var _defender_medals: SpinBox = null
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
		"attacker": _types_of(_attacker_slots),
		"defender": _types_of(_defender_slots),
		"fort": _fort.selected,
		"terrain": String(TERRAIN_ROWS[maxi(_terrain.selected, 0)][0]),
		"attacker_plan": PLAN_KEYS[maxi(_attacker_plan.selected, 0)],
		"defender_plan": PLAN_KEYS[maxi(_defender_plan.selected, 0)],
		"attacker_medals": int(_attacker_medals.value),
		"defender_medals": int(_defender_medals.value),
		"tech": _gun_line(),
	}


## The studies the picked gun line implies, as the defending court's unlocked
## techs — the shape `FortRules.emplaced_type` reads. A later line carries the
## studies the table builds on, so Siege guns imply the heavy battery: the rail
## offers the published chain, never a gun no court could hold.
func _gun_line() -> Dictionary:
	var studies: Dictionary = {}
	if _guns == null:
		return studies
	for index in range(maxi(_guns.selected, 0) + 1):
		var tech: String = String(GUN_ROWS[index][0])
		if not tech.is_empty():
			studies[tech] = true
	return studies


func _build() -> void:
	## The rail scrolls on a short window so the levers and buttons never clip.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(UiRowBuilder.serif_wrapped("BATTLE SIMULATOR", 18, Palette.GOLD_PALE))
	column.add_child(_hint("Runs the live Quick Battle resolver. Change a number and fight again."))
	column.add_child(_section("Ground"))
	_terrain = _option(TERRAIN_ROWS)
	_terrain.selected = 0
	column.add_child(_terrain)
	column.add_child(_section("Fort"))
	_fort = _option_labeled(FORT_LABELS)
	_fort.selected = 2
	column.add_child(_fort)
	## The wall's battery follows the defending court's line (wiki: siege-mechanics
	## § Emplaced Artillery), so the rail names it where the fort is chosen.
	_guns = _option(GUN_ROWS)
	column.add_child(_guns)
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
	## Chevrons are the commander's own rank (wiki: combat § Strength), so each
	## side gets its span beside its plan.
	var medals := HBoxContainer.new()
	medals.add_theme_constant_override("separation", 6)
	column.add_child(medals)
	_attacker_medals = _medal_picker(medals, "Attacker medals", 0)
	_defender_medals = _medal_picker(medals, "Defender medals", 0)
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


## The men the rail holds, in slot order. A slot at zero adds none: the sandbox
## fights the army the rail shows, never a default one the playtester never set
## (REQ-P2-03).
func _types_of(slots: Array[Dictionary]) -> Array[String]:
	var types: Array[String] = []
	for slot: Dictionary in slots:
		var picker: OptionButton = slot["picker"]
		var type_id: String = _types[clampi(picker.selected, 0, _types.size() - 1)]
		for _index in int((slot["count"] as SpinBox).value):
			types.append(type_id)
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


## The commander's chevrons: the 0–4 span the resolver multiplies strength by
## (wiki: combat § Strength), on the rail so a playtester can fight the same men
## with and without their honours.
func _medal_picker(row: HBoxContainer, label: String, start: int) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(_hint(label))
	var medals := SpinBox.new()
	medals.min_value = 0
	medals.max_value = MEDAL_MAX
	medals.value = start
	medals.custom_minimum_size = Vector2(58, 0)
	box.add_child(medals)
	return medals


func _button(text: String, output: Signal) -> Button:
	var button := UiRowBuilder.button(text, 0.0, 0.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: output.emit())
	return button


func _section(text: String) -> Label:
	return UiRowBuilder.serif_wrapped(text.to_upper(), 12, Palette.GOLD)


func _hint(text: String) -> Label:
	return UiRowBuilder.serif_wrapped(text, 12, Palette.TEXT_DIM)
