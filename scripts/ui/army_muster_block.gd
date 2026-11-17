class_name ArmyMusterBlock
extends VBoxContainer
## The army dossier's drill-yard rows (Home Army muster). Lifted out of
## ArmyPanel so the sheet keeps the toggle and scroll while this block owns
## only the yard list (REQ-P3-01). Rows come from ArmyTraining; the block
## renders and emits intents (REQ-P3-02).
##
## The yard's foot carries one press that files every ready row in the panel's
## order — the shared RaiseBatchPress arm, so a mis-tap never spends the
## realm's stores (REQ-P5-04; DR-20261118-07).

signal action_pressed(action: String)

## The one press under the rows; it owns the arm, its timeout and its words.
var _batch: RaiseBatchPress = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	visible = false
	_make_batch()


## The yard's one press, made once however the block is mounted: the sheet's own
## `_ready` or a suite handing it rows straight away.
func _make_batch() -> void:
	if _batch != null:
		return
	_batch = RaiseBatchPress.new()
	_batch.set_verb("muster")
	_batch.confirmed.connect(func() -> void: action_pressed.emit("recruit_all"))
	add_child(_batch)


## Rebuilds every drill-yard row from the training table, then the one press the
## rows earn: its count is the yard's own `batch_ready` flag, so the face names
## what the second tap would file (REQ-P5-05).
func fill(rows: Array[Dictionary]) -> void:
	_make_batch()
	for child: Node in get_children():
		if child != _batch:
			child.queue_free()
	var ready: int = 0
	for row: Dictionary in rows:
		if bool(row.get("batch_ready", false)):
			ready += 1
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
		var pending: int = int(row.get("pending", 0))
		if pending > 0:
			detail.text += "  ·  %d under orders" % pending
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)
		# The regiment's own numbers under the price, on every row — a type the
		# crown cannot raise yet included, because the study that opens it is
		# planned against those numbers (wiki: military-units § Tactical Stats;
		# DR-20261118-01). On the sheet, never in a hover (REQ-P1-07).
		var line: String = String(row.get("line", ""))
		if not line.is_empty():
			var stats := UiRowBuilder.line(10, Palette.TEXT_DIM)
			stats.text = line
			stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			entry.add_child(stats)
	_batch.set_ready(ready, "regiments")
	move_child(_batch, -1)
