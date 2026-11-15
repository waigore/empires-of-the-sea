class_name ProvinceLedgerPanel
extends SheetFrame
## The crown's provinces: every province it holds in the Old and New World in
## one ledger, narrowed by chart and by what the province lacks, with a Visit
## action that opens the province's map and dossier (wiki: world-model
## § Provinces and Tiles; DR-20261115-09). The projection lives in
## [ProvinceLedger] and the map hooks in [MapPlayProvinces]; this class only
## renders rows and asks for the jump (REQ-P3-02, REQ-P3-03). The sheet chrome,
## fade and pause-door park come from SheetFrame.

## The realm prints each province's town level; the towns sheet is the step
## that raises it, so the door sits on the reading that raises the question
## (DR-20261115-12).
signal towns_pressed

var _rows: VBoxContainer = null
var _empty: Label = null
var _region_chips: Array[Button] = []
var _filter_chips: Array[Button] = []
var _region: String = ProvinceLedger.REGION_ALL
var _filter: String = ProvinceLedger.FILTER_ALL
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S PROVINCES"
	hint_text = (
		"Visit opens the province's map and dossier. The roll reads each "
		+ "province as it stands; it never orders a work or a march."
	)
	toggle_action = InputActions.PROVINCE_LEDGER


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both charts for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = MapPlayProvinces.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("compass", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	column.add_child(_filters())
	column.add_child(_towns_door())

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


## The door to the crown's towns: the realm prints the level, the towns sheet
## prints the step that raises it, and the press is one reach from here
## (REQ-P5-01, REQ-P5-04; DR-20261115-12). A full-width row keeps it a
## thumb-sized tap on a phone sheet.
func _towns_door() -> Control:
	var door := Button.new()
	door.text = "Towns ›"
	door.tooltip_text = "Every town the crown holds, and the step that raises it (B)"
	door.custom_minimum_size = Vector2(0, 34)
	door.add_theme_font_size_override("font_size", 12)
	door.pressed.connect(func() -> void: towns_pressed.emit())
	return door


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


## Two chip rows: which chart, and what the province lacks. Every option stays
## on the page even at zero, so a filter never hides its own way back
## (REQ-P5-03, REQ-P5-07).
func _filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_filter_row("Chart", ProvinceLedger.REGION_FILTERS, true))
	box.add_child(_filter_row("Reading", ProvinceLedger.FILTERS, false))
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
			ProvinceLedger.REGION_OLD:
				return "Old World"
			ProvinceLedger.REGION_NEW:
				return "New World"
		return "Both charts"
	return ProvinceLedger.filter_label(key)


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
	var groups: Array[Dictionary] = ProvinceLedger.groups(_snapshot, _region, _filter)
	var shown: int = ProvinceLedger.count(_snapshot, _region, _filter)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = "No province answers this view. Clear a filter to see the whole realm."
		return
	for group: Dictionary in groups:
		var heading := Label.new()
		var rows: Array = group["rows"]
		heading.text = "%s  ·  %d province%s" % [
			String(group["region_label"]).to_upper(), rows.size(), "" if rows.size() == 1 else "s"
		]
		heading.add_theme_font_size_override("font_size", 11)
		heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
		_rows.add_child(heading)
		for raw: Variant in rows:
			var row := ProvinceLedgerRow.new()
			row.compact = HudLayout.is_compact(get_viewport_rect().size)
			row.visit_pressed.connect(_visit)
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
	if _region == ProvinceLedger.REGION_OLD:
		scope = "in the Old World"
	elif _region == ProvinceLedger.REGION_NEW:
		scope = "in the New World"
	var counts: Dictionary = ProvinceLedger.filter_counts(_snapshot, _region)
	var line: String = "Showing %d of %d provinces %s — %d cut off, %d ungarrisoned, %d at works." % [
		shown,
		int(_snapshot.get("total", 0)),
		scope,
		int(counts.get(ProvinceLedger.FILTER_CUT, 0)),
		int(counts.get(ProvinceLedger.FILTER_UNGARRISONED, 0)),
		int(counts.get(ProvinceLedger.FILTER_WORKS, 0)),
	]
	if _filter != ProvinceLedger.FILTER_ALL:
		line += " Reading: %s only." % ProvinceLedger.filter_label(_filter).to_lower()
	return line


func _visit(region: int, province_id: int) -> void:
	if play == null:
		return
	if MapPlayProvinces.focus(play, region, province_id):
		close()
