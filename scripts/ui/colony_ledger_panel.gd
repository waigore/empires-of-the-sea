class_name ColonyLedgerPanel
extends LedgerSheet
## The world's colonies: every Tribe bought into an empire, who bought it, where
## it stands and what bars its trade (wiki: diplomacy § GP–Tribe Rules — Join
## Empire, § Boycott; DR-20261117-02). The projection lives in [ColonyLedger] and
## the map hook in [MapPlayColonies]; this class only renders the rows and asks
## for the jump (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door
## park come from SheetFrame; the chips, rows and empty notice from LedgerSheet.
##
## No key of its own: the letters are spent (DR-20261116-16), so the court's
## own door is the one way in.

var _notes: VBoxContainer = null


func _init() -> void:
	title_text = "THE COLONIES"
	hint_text = (
		"Visit opens a colony's capital on the map. The roll reads the colonies "
		+ "the rules hold; it never signs a deed or lifts a boycott."
	)


## Re-reads both charts and the crown's diplomacy record, then repaints.
func refresh() -> void:
	if play == null:
		return
	_snapshot = MapPlayColonies.snapshot(play)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	var crest := TextureRect.new()
	crest.texture = ChromeIcons.texture("globe")
	crest.custom_minimum_size = Vector2(42, 42)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return crest


func _build_body(column: VBoxContainer) -> void:
	_build_filter_body(
		column, "Chart", "Reading", ColonyLedger.FILTERS, ColonyLedger.filter_label
	)
	# The rules a crown pays by, under the chips: what a boycott does to a
	# colony, and what a colony is not (REQ-P5-02, REQ-P2-03). A phone hides the
	# footer hint, so the rule sits on the sheet (REQ-P1-07, REQ-P5-03).
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override("separation", 2)
	column.add_child(_notes)
	_notes.add_child(_note(ColonyLedger.terms_line()))
	_notes.add_child(_note(ColonyLedger.colony_line()))


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.85))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	var groups: Array[Dictionary] = ColonyLedger.groups(_snapshot, _region, _reading)
	var shown: int = ColonyLedger.count(_snapshot, _region, _reading)
	_paint_filtered(groups, shown, _heading, _make_row)


func _empty_text() -> String:
	if int(_snapshot.get("total", 0)) == 0:
		return (
			"No colony answers this view. A Tribe becomes a colony at the end of "
			+ "the Join Empire chain, and a court the crown has not met is nobody's news."
		)
	return "No colony answers this view. Clear a filter to see the whole world."


func _heading(group: Dictionary, count: int) -> Control:
	return LedgerList.heading("%s  ·  %d colon%s" % [
		String(group["region_label"]).to_upper(), count, "y" if count == 1 else "ies"
	])


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ColonyLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


func _subtitle_text(shown: int) -> String:
	return ColonyLedger.summary(_snapshot, _region, shown)


func _visit(region: int, province_id: int) -> void:
	if play == null:
		return
	if MapPlayProvinces.focus(play, region, province_id):
		close()
