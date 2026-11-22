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

## The mark the counsel reads by: a pattern the court's own muster would raise
## wears it before its name, the mark the muster's forces and the realm's
## provinces wear (DR-20261122-12).
const COURT_MARK: String = "▸"

## The one press under the rows; it owns the arm, its timeout and its words.
var _batch: RaiseBatchPress = null
## The line above the press: what the whole line costs and the purse it leaves,
## read from the rows' own plan. One label, re-read on every fill, so a redraw
## never stacks a second copy of the sum on the sheet (DR-20261118-11).
var _sum_line: Label = null
## The line the court's own muster would raise, in gold above the yard — the
## published policy's reading, never an order (DR-20261121-03).
var _pick_line: Label = null
## The pick the yard is printing, kept whole so the line and the mark come off
## one read: a pattern the line names wears COURT_MARK (DR-20261122-12).
var _pick: Dictionary = {}


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
	_sum_line = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	add_child(_sum_line)
	_pick_line = UiRowBuilder.wrapped_line("", 12, Palette.GOLD)
	_pick_line.visible = false


## Rebuilds every drill-yard row from the training table, then the one press the
## rows earn: its count is the yard's own `batch_ready` flag, so the face names
## what the second tap would file (REQ-P5-05). `pick` is the court's own muster
## reading, kept whole so the line above the rows and the row's mark come off one
## read (DR-20261121-03, DR-20261122-12); a rival's dossier answers to her own
## court and carries none.
func fill(rows: Array[Dictionary], pick: Dictionary = {}) -> void:
	_make_batch()
	for child: Node in get_children():
		if child != _batch and child != _sum_line and child != _pick_line:
			child.queue_free()
	_fill_pick(pick)
	var mark: String = _mark()
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
		# The counsel's mark leads the pattern the line would raise, so a crown
		# finds that row among the yard's whole table (DR-20261122-12).
		name.text = (
			"%s %s" % [COURT_MARK, String(row["name"])]
			if not mark.is_empty() and type_id == mark
			else String(row["name"])
		)
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
	# What the whole line costs, before it is pressed: the walk's own sum and the
	# purse it leaves, printed from the plan the press files, so a crown never
	# learns the drill yard's price after it signs (REQ-P5-06; DR-20261118-11).
	var plan: Dictionary = _batch_plan(rows)
	_fill_sum(RaiseBatchSum.sheet_line(plan))
	# The armed face names the line's own count, so the confirm under the sum
	# describes the tap the line prices and not the view above it (DR-20261118-21).
	_batch.set_ready(ready, "regiments", RaiseBatchSum.carries(plan))
	move_child(_batch, -1)
	if _sum_line.get_parent() != null:
		move_child(_sum_line, _batch.get_index())


## The sum line stands on the sheet only while there is a sum to print: a caller
## that hands the block rows with no plan of their own (a suite's fixture) keeps
## the sheet's published shape, and a redraw re-reads the one label rather than
## stacking a second copy of the price (DR-20261118-11).
func _fill_sum(text: String) -> void:
	_sum_line.text = text
	if text.is_empty():
		if _sum_line.get_parent() != null:
			remove_child(_sum_line)
		return
	if _sum_line.get_parent() == null:
		add_child(_sum_line)


## The yard's own pick stands above the rows only while there is one: a court the
## published muster would arm reads the line it would raise, and one it arms
## nothing for keeps the yard's published shape (DR-20261121-03). The line is
## worded from the pick the block holds, so the mark below cannot outrun it
## (DR-20261122-12).
func _fill_pick(pick: Dictionary) -> void:
	_pick = pick if pick != null else {}
	var text: String = MapPlayPickProse.sentence_of(_pick)
	_pick_line.text = text
	_pick_line.visible = not text.is_empty()
	if text.is_empty():
		if _pick_line.get_parent() != null:
			remove_child(_pick_line)
		return
	if _pick_line.get_parent() == null:
		add_child(_pick_line)
	move_child(_pick_line, 0)


## The pattern the line names, or empty when it names none (the yard stands at
## its target, or a gate holds it): the pick's own `type`, never a second read
## (DR-20261122-12).
func _mark() -> String:
	return String(_pick.get("type", ""))


## The pick the yard is printing, for tests and the mobile audit (REQ-P3-02).
func pick_line() -> String:
	return MapPlayPickProse.sentence_of(_pick)


## The pattern the yard's rows mark, for tests and the mobile audit (REQ-P3-02).
func mark_type() -> String:
	return _mark()


## The plan the yard's rows carry, or an empty one when a caller handed the block
## rows of its own with no ledger behind them (a suite's fixture): the sum line
## then prints nothing and the press keeps its published face (DR-20261118-11).
func _batch_plan(rows: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in rows:
		if row.has("batch"):
			return row["batch"]
	return RaiseBatchSum.blank()
