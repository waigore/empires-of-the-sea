class_name TownLedgerPanel
extends SheetFrame
## The crown's towns: every province it holds that has a town, the level it
## stands at and the step the Builder would take next, narrowed by chart and by
## what the step waits on, with one press that files the order (wiki:
## extraction-and-improvements § Town manufacturing bonus, civilian-units
## § Builder upgrade_town; DR-20261115-12). The projection lives in
## [TownLedger] and the map hooks in [MapPlayTowns]; this class only renders
## rows and asks for the order (REQ-P3-02, REQ-P3-03). The sheet chrome, fade
## and pause-door park come from SheetFrame.

var _rows: VBoxContainer = null
var _empty: Label = null
var _region_chips: Array[Button] = []
var _filter_chips: Array[Button] = []
var _region: String = TownLedger.REGION_ALL
var _filter: String = TownLedger.FILTER_ALL
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S TOWNS"
	hint_text = (
		"Raise sends the nearest idle Builder; the price and the wait are the "
		+ "work plan's own, so a row never offers an order the rules refuse."
	)
	toggle_action = InputActions.TOWNS_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = MapPlayTowns.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	column.add_child(_filters())
	# The rule a crown needs before it pays for a level sits on the sheet, not
	# in a hover: a phone hides the footer hint (REQ-P1-07, REQ-P5-03).
	var note := UiRowBuilder.label(TownLedger.bonus_note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


## Two chip rows: which chart, and what the next step waits on. Every option
## stays on the page even at zero, so a filter never hides its own way back
## (REQ-P5-03, REQ-P5-07).
func _filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_filter_row("Chart", TownLedger.REGION_FILTERS, true))
	box.add_child(_filter_row("Reading", TownLedger.FILTERS, false))
	return box


func _filter_row(caption: String, keys: Array, region_row: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = caption.to_upper()
	label.custom_minimum_size = Vector2(58, 0)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.GOLD_DIM)
	row.add_child(label)
	for key: String in keys:
		var chip := Button.new()
		chip.text = _chip_text(key, region_row)
		chip.custom_minimum_size = Vector2(0, 34)
		chip.focus_mode = Control.FOCUS_ALL
		chip.add_theme_font_size_override("font_size", 12)
		chip.set_meta("key", key)
		chip.pressed.connect(func() -> void: _on_filter(key, region_row))
		row.add_child(chip)
		if region_row:
			_region_chips.append(chip)
		else:
			_filter_chips.append(chip)
	return row


func _chip_text(key: String, region_row: bool) -> String:
	if region_row:
		match key:
			TownLedger.REGION_OLD:
				return "Old World"
			TownLedger.REGION_NEW:
				return "New World"
		return "Both charts"
	return TownLedger.filter_label(key)


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_filter = key
	refresh()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	for child: Node in _rows.get_children():
		if child == _empty:
			continue
		_rows.remove_child(child)
		child.queue_free()
	_paint_chips()
	var groups: Array[Dictionary] = TownLedger.groups(_snapshot, _region, _filter)
	var shown: int = TownLedger.count(_snapshot, _region, _filter)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = "No town answers this view. Clear a filter to see the whole realm."
		return
	for group: Dictionary in groups:
		var heading := Label.new()
		var rows: Array = group["rows"]
		heading.text = "%s  ·  %d town%s" % [
			String(group["region_label"]).to_upper(), rows.size(), "" if rows.size() == 1 else "s"
		]
		heading.add_theme_font_size_override("font_size", 11)
		heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
		_rows.add_child(heading)
		for raw: Variant in rows:
			var row := TownLedgerRow.new()
			row.compact = HudLayout.is_compact(get_viewport_rect().size)
			row.raise_pressed.connect(_raise)
			_rows.add_child(row)
			row.setup(raw)


func _paint_chips() -> void:
	for chip: Button in _region_chips:
		_style_chip(chip, String(chip.get_meta("key")) == _region)
	for chip: Button in _filter_chips:
		_style_chip(chip, String(chip.get_meta("key")) == _filter)


func _style_chip(chip: Button, active: bool) -> void:
	var fill: Color = Color(0.20, 0.16, 0.10, 0.95) if active else Color(0.12, 0.10, 0.07, 0.55)
	var edge: Color = Palette.GOLD if active else Color(0.54, 0.43, 0.12, 0.55)
	var pad := Vector4(9, 3, 9, 3)
	chip.add_theme_stylebox_override("normal", UiTheme.box(fill, edge, 1, 3, pad))
	chip.add_theme_stylebox_override("hover", UiTheme.box(fill, Palette.GOLD, 1, 3, pad))
	var ink: Color = Palette.GOLD_PALE if active else Color(0.78, 0.72, 0.60)
	chip.add_theme_color_override("font_color", ink)


## The count line names the filter and what the view means, so a crown reads
## what it is looking at before it reads a row (REQ-P5-05).
func _subtitle_text(shown: int) -> String:
	var scope: String = "in both charts"
	if _region == TownLedger.REGION_OLD:
		scope = "in the Old World"
	elif _region == TownLedger.REGION_NEW:
		scope = "in the New World"
	var counts: Dictionary = TownLedger.filter_counts(_snapshot, _region)
	var line: String = "Showing %d of %d towns %s — %d ready, %d at work, %d developed." % [
		shown,
		int(_snapshot.get("total", 0)),
		scope,
		int(counts.get(TownLedger.FILTER_READY, 0)),
		int(counts.get(TownLedger.FILTER_AT_WORK, 0)),
		int(counts.get(TownLedger.FILTER_DEVELOPED, 0)),
	]
	if _filter != TownLedger.FILTER_ALL:
		line += " Reading: %s only." % TownLedger.filter_label(_filter).to_lower()
	return line


func _raise(region: int, province_id: int) -> void:
	if play == null:
		return
	MapPlayTowns.raise(play, region, province_id)
	refresh()
