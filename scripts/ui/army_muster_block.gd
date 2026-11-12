class_name ArmyMusterBlock
extends VBoxContainer
## The army dossier's drill-yard rows (Home Army muster). Lifted out of
## ArmyPanel so the sheet keeps the toggle and scroll while this block owns
## only the yard list (REQ-P3-01). Rows come from ArmyTraining; the block
## renders and emits intents (REQ-P3-02).

signal action_pressed(action: String)


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	visible = false


## Rebuilds every drill-yard row from the training table.
func fill(rows: Array[Dictionary]) -> void:
	for child in get_children():
		child.queue_free()
	for row: Dictionary in rows:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		add_child(entry)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		entry.add_child(top)
		var type_id: String = String(row["type_id"])
		top.add_child(UnitMedallion.of_regiment(type_id, 28.0))
		var name := UiRowBuilder.line(13, Palette.TEXT)
		name.text = String(row["name"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(name)
		var muster := UiRowBuilder.button("Muster", 36.0, 0.0)
		muster.custom_minimum_size = Vector2(84, 40)
		muster.add_theme_font_size_override("font_size", 12)
		muster.disabled = not bool(row["ok"])
		muster.tooltip_text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		muster.pressed.connect(func() -> void: action_pressed.emit("recruit:%s" % type_id))
		top.add_child(muster)
		var detail := UiRowBuilder.line(10, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)
