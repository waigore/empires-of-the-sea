class_name ForceLedgerPanel
extends SheetFrame
## The crown's muster roll: every army and squadron in the Old and New World in
## one ledger, narrowed by region and kind, with a Visit action that opens the
## force's map and dossier (wiki: military-armies § The muster roll;
## DR-20261113-12). The projection lives in ForceLedger; this class only renders
## rows and asks MapPlayForceLedger to jump (REQ-P3-02, REQ-P3-03). The sheet
## chrome, fade and pause-door park come from SheetFrame.

var _rows: VBoxContainer = null
var _empty: Label = null
var _region_chips: Array[Button] = []
var _kind_chips: Array[Button] = []
var _region: String = ForceLedger.REGION_ALL
var _kind: String = ForceLedger.KIND_ALL
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S MUSTER"
	hint_text = (
		"Visit opens the force's map and dossier. The muster roll reads each "
		+ "standard and squadron as it stands; it never orders a march."
	)
	toggle_action = InputActions.MUSTER_ROLL


func bind(p_session: PlaySession) -> void:
	play = p_session


## Re-reads both layer rosters for the player's crown and repaints the view.
func refresh() -> void:
	if play == null or play.world == null:
		return
	_snapshot = ForceLedger.snapshot(
		play.world,
		play.army_layer.regions if play.army_layer != null else null,
		play.ship_layer.regions if play.ship_layer != null else null,
		play.player_faction
	)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	column.add_child(_filters())

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)


func _apply_profile(compact: bool, narrow: bool) -> void:
	super._apply_profile(compact, narrow)
	_title.add_theme_font_size_override(
		"font_size", 20 if narrow else (22 if compact else 28)
	)
	_crest.visible = not narrow
	_subtitle.visible = not compact


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- filters -----------------------------------------------------------------


## Two chip rows: which chart, and which kind of force. Every option stays on
## the page even at zero, so a filter never hides its own way back
## (REQ-P5-03, REQ-P5-07).
func _filters() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for spec: Array in [
		["Region", ForceLedger.REGION_FILTERS, true],
		["Force", ForceLedger.KIND_FILTERS, false],
	]:
		box.add_child(_filter_row(String(spec[0]), spec[1], bool(spec[2])))
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
			_kind_chips.append(chip)
	return row


func _chip_text(key: String, region_row: bool) -> String:
	if region_row:
		match key:
			ForceLedger.REGION_OLD:
				return "Old World"
			ForceLedger.REGION_NEW:
				return "New World"
		return "Both charts"
	match key:
		ForceLedger.KIND_ARMY:
			return "Armies"
		ForceLedger.KIND_SQUADRON:
			return "Squadrons"
	return "All forces"


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_kind = key
	refresh()


# --- rows --------------------------------------------------------------------


func _apply_filter() -> void:
	for child: Node in _rows.get_children():
		if child == _empty:
			continue
		_rows.remove_child(child)
		child.queue_free()
	_paint_chips()
	var groups: Array[Dictionary] = ForceLedger.groups(_snapshot, _region, _kind)
	var shown: int = ForceLedger.count(_snapshot, _region, _kind)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = "No force answers this view. Clear a filter to see the whole muster."
		return
	for group: Dictionary in groups:
		var heading := Label.new()
		var rows: Array = group["rows"]
		heading.text = "%s  ·  %d force%s" % [
			String(group["region_label"]).to_upper(), rows.size(), "" if rows.size() == 1 else "s"
		]
		heading.add_theme_font_size_override("font_size", 11)
		heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
		_rows.add_child(heading)
		for raw: Variant in rows:
			var row := ForceLedgerRow.new()
			row.compact = HudLayout.is_compact(get_viewport_rect().size)
			row.visit_pressed.connect(_visit)
			_rows.add_child(row)
			row.setup(raw)


func _paint_chips() -> void:
	for chip: Button in _region_chips:
		_style_chip(chip, String(chip.get_meta("key")) == _region)
	for chip: Button in _kind_chips:
		_style_chip(chip, String(chip.get_meta("key")) == _kind)


func _style_chip(chip: Button, active: bool) -> void:
	var fill: Color = Color(0.20, 0.16, 0.10, 0.95) if active else Color(0.12, 0.10, 0.07, 0.55)
	var edge: Color = Palette.GOLD if active else Color(0.54, 0.43, 0.12, 0.55)
	var pad := Vector4(9, 3, 9, 3)
	chip.add_theme_stylebox_override("normal", UiTheme.box(fill, edge, 1, 3, pad))
	chip.add_theme_stylebox_override("hover", UiTheme.box(fill, Palette.GOLD, 1, 3, pad))
	var ink: Color = Palette.GOLD_PALE if active else Color(0.78, 0.72, 0.60)
	chip.add_theme_color_override("font_color", ink)


func _subtitle_text(shown: int) -> String:
	var scope: String = "in both charts"
	if _region == ForceLedger.REGION_OLD:
		scope = "in the Old World"
	elif _region == ForceLedger.REGION_NEW:
		scope = "in the New World"
	var counts: Dictionary = ForceLedger.kind_counts(_snapshot, _region)
	var armies: int = int(counts.get(ForceLedger.KIND_ARMY, 0))
	var squadrons: int = int(counts.get(ForceLedger.KIND_SQUADRON, 0))
	var army_word: String = ForceLedger.kind_label(ForceLedger.KIND_ARMY, armies != 1)
	var squadron_word: String = ForceLedger.kind_label(ForceLedger.KIND_SQUADRON, squadrons != 1)
	return "Showing %d of %d forces %s — %d %s, %d %s." % [
		shown, int(_snapshot.get("total", 0)), scope, armies, army_word, squadrons, squadron_word,
	]


func _visit(region: int, kind: String, id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, kind, id):
		close()
