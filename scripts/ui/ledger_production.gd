class_name LedgerProduction
extends VBoxContainer
## PRODUCTION tab of the ledger: one row per available recipe with a stepper
## that emits the assignment intent. Presentation only (REQ-P2-03).

signal production_changed(recipe_id: String, units: int)

const ROW_HEIGHT: float = 38.0

var _economy: PlayerEconomy = null


func fill(economy: PlayerEconomy) -> void:
	_economy = economy
	UiRowBuilder.clear(self)
	for recipe_id: String in ProductionRecipes.available_ids(economy.tech_unlocked):
		add_child(_recipe_row(recipe_id))
	UiRowBuilder.spacer(self)


func _recipe_row(recipe_id: String) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(CommodityIcons.badge(ProductionRecipes.output(recipe_id)))
	var name_label := UiRowBuilder.label(LedgerText.recipe_title(recipe_id), 14, Palette.TEXT)
	name_label.tooltip_text = LedgerText.recipe_tooltip(recipe_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# The workshop tag: how long a multi-turn row waits, and what is already
	# serving its turns. Text only, so a phone row keeps its thumb-sized buttons.
	var note: String = LedgerText.workshop_note(_economy, recipe_id)
	if not note.is_empty():
		var tag := UiRowBuilder.label(note, 12, Palette.TEXT_DIM)
		var hint: String = LedgerText.workshop_tooltip(_economy, recipe_id)
		tag.tooltip_text = hint
		row.add_child(tag)

	var units: int = _economy.assignment_units(recipe_id)
	var stepper := UiRowBuilder.label("%d" % units, 14, Palette.GOLD_PALE)
	stepper.custom_minimum_size = Vector2(48, 0)
	stepper.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(stepper)

	var minus := UiRowBuilder.button("−", ROW_HEIGHT)
	minus.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	minus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units - 1))
	row.add_child(minus)

	var plus := UiRowBuilder.button("+", ROW_HEIGHT)
	plus.custom_minimum_size = Vector2(70, ROW_HEIGHT)
	plus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units + 1))
	row.add_child(plus)
	return row
