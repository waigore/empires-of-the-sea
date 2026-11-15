class_name CommandLedgerPanel
extends SheetFrame
## The crown's commanders: every general its pool holds, the medals each wears
## and the study that raises the cap next (wiki: military-generals § Generals,
## § Count and tech-gated cap, § Medals; DR-20261115-11). The projection lives
## in [CommandLedger] and the map hook in [MapPlayCommand]; this class only
## renders the reading (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and
## pause-door park come from SheetFrame.

var _summary: Label = null
var _road: VBoxContainer = null
var _medal: Label = null
var _fallback: Label = null
var _rows: VBoxContainer = null
var _empty: Label = null
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S COMMAND"
	hint_text = (
		"A commander is drawn for each battle from this pool. The roll reads "
		+ "the pool as it stands; it never appoints one."
	)
	toggle_action = InputActions.COMMAND_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads the crown's pool and repaints the view.
func refresh() -> void:
	if play == null:
		return
	_snapshot = MapPlayCommand.snapshot(play)
	_fit()
	_paint()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crown", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)

	# The road: every study that raises the cap, in the wiki's order, so a
	# crown reads why it holds one commander and what the second costs.
	_road = VBoxContainer.new()
	_road.add_theme_constant_override("separation", 2)
	column.add_child(_road)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)

	_medal = _note(column)
	_fallback = _note(column)


## A footnote under the roll: what a medal buys and who leads when none is free.
func _note(column: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.85))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	return label


func _apply_profile(compact: bool, narrow: bool) -> void:
	super._apply_profile(compact, narrow)
	_title.add_theme_font_size_override(
		"font_size", 20 if narrow else (22 if compact else 28)
	)
	_crest.visible = not narrow
	_subtitle.visible = not compact


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_paint()


# --- rows --------------------------------------------------------------------


func _paint() -> void:
	_paint_road()
	_subtitle.text = CommandLedger.summary(_snapshot)
	_medal.text = CommandLedger.medal_line()
	_fallback.text = CommandLedger.fallback_line(_snapshot)
	for child: Node in _rows.get_children():
		if child == _empty:
			continue
		_rows.remove_child(child)
		child.queue_free()
	var rows: Array = _snapshot.get("rows", []) as Array
	_empty.visible = rows.is_empty()
	if rows.is_empty():
		_empty.text = (
			"The crown holds no commanders yet: only a Great Power musters a "
			+ "general, and the pool opens with the first turn."
		)
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	for raw: Variant in rows:
		var row := CommandLedgerRow.new()
		row.compact = compact
		_rows.add_child(row)
		row.setup(raw as Dictionary)


func _paint_road() -> void:
	for child: Node in _road.get_children():
		_road.remove_child(child)
		child.queue_free()
	var road: Array = _snapshot.get("road", []) as Array
	if road.is_empty():
		_road.visible = false
		return
	_road.visible = true
	for raw: Variant in road:
		var rung: Dictionary = raw
		var label := Label.new()
		var unlocked: bool = bool(rung.get("unlocked", false))
		label.text = "Cap %d · %s — %s" % [
			int(rung["cap"]),
			String(rung["name"]),
			"studied" if unlocked else "not studied",
		]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override(
			"font_color", Palette.GOLD if unlocked else Palette.TEXT_DIM
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_road.add_child(label)
