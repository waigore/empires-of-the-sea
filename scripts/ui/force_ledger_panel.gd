class_name ForceLedgerPanel
extends Control
## The crown's muster roll: every army and squadron in the Old and New World in
## one ledger, narrowed by region and kind, with a Visit action that opens the
## force's map and dossier (wiki: military-armies § The muster roll;
## DR-20261113-12). The projection lives in ForceLedger; this class only renders
## rows and asks MapPlayForceLedger to jump (REQ-P3-02, REQ-P3-03).

const MARGIN_WIDE: int = 42
const MARGIN_COMPACT: int = 10

var play: PlaySession = null

var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _rows: VBoxContainer = null
var _title: Label = null
var _subtitle: Label = null
var _hint: Label = null
var _empty: Label = null
var _crest: Control = null
var _close: Button = null
var _region_chips: Array[Button] = []
var _kind_chips: Array[Button] = []
var _region: String = ForceLedger.REGION_ALL
var _kind: String = ForceLedger.KIND_ALL
var _snapshot: Dictionary = {}
var _fade: Tween = null
## Last applied layout profile (-1 before the first fit); an orientation change
## rebuilds the rows because a row fixes its medallion size at construction.
var _was_compact: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build()
	visible = false
	resized.connect(_fit)


func bind(p_session: PlaySession) -> void:
	play = p_session


func open() -> void:
	if play == null or play.world == null:
		return
	visible = true
	refresh()
	_set_menu_visible(false)
	modulate.a = 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE)


func close() -> void:
	if not visible:
		return
	visible = false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	_set_menu_visible(true)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return visible


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


# --- construction -----------------------------------------------------------


func _build() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.04, 0.03, 0.80)
	_overlay.add_child(dim)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.99), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	_margin.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	_column = column
	column.add_child(_header())
	column.add_child(_filters())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows)

	_empty = Label.new()
	_empty.add_theme_font_size_override("font_size", 15)
	_empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_empty)

	column.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	_crest = Icon.new("crest", 42.0, Palette.GOLD)
	_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_crest)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	_title = Label.new()
	_title.text = "THE CROWN'S MUSTER"
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	titles.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)

	_close = Button.new()
	_close.text = "Close"
	_close.custom_minimum_size = Vector2(92, 40)
	_close.pressed.connect(close)
	header.add_child(_close)
	return header


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


func _footer() -> Control:
	_hint = Label.new()
	_hint.text = (
		"Visit opens the force's map and dossier. The muster roll reads each "
		+ "standard and squadron as it stands; it never orders a march."
	)
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 0.76))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _hint


# --- filtering --------------------------------------------------------------


func _on_filter(key: String, region_row: bool) -> void:
	if region_row:
		_region = key
	else:
		_kind = key
	refresh()


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


# --- layout -----------------------------------------------------------------


func _fit() -> void:
	if _margin == null:
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	var side: int = MARGIN_COMPACT if compact else MARGIN_WIDE
	# This ledger lives on its own canvas layer, outside HudRoot's safe-area
	# offsets, so it adds the device insets itself.
	var insets: Vector4 = PlatformDisplay.safe_insets(get_window())
	_margin.add_theme_constant_override("margin_left", side + int(insets.x))
	_margin.add_theme_constant_override("margin_right", side + int(insets.z))
	_margin.add_theme_constant_override("margin_top", (56 if compact else 88) + int(insets.y))
	_margin.add_theme_constant_override("margin_bottom", (6 if compact else 34) + int(insets.w))
	_column.add_theme_constant_override("separation", 6 if compact else 10)
	var pad := Vector4(12, 10, 12, 10) if compact else Vector4(20, 16, 20, 16)
	_panel.add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.10, 0.08, 0.06, 0.99), Palette.GOLD_DIM, 1, 4, pad)
	)
	var narrow: bool = get_viewport_rect().size.x < 520.0
	if _title != null:
		_title.add_theme_font_size_override("font_size", 20 if narrow else (22 if compact else 28))
	if _crest != null:
		_crest.visible = not narrow
	if _close != null:
		_close.custom_minimum_size.x = 64.0 if narrow else 92.0
	if _subtitle != null:
		_subtitle.visible = not compact
	if _hint != null:
		_hint.visible = not compact
	var profile: int = 1 if compact else 0
	var changed: bool = _was_compact >= 0 and _was_compact != profile
	_was_compact = profile
	if changed and visible and not _snapshot.is_empty():
		_apply_filter()


## The pause trigger sits on a higher canvas layer than the HUD; park it while
## the ledger is up so its gold seal does not cut through the frame.
func _set_menu_visible(show_menu: bool) -> void:
	if play == null or not is_instance_valid(play.host):
		return
	var menu: Node = play.host.get_node_or_null("GameMenu")
	if menu is GameMenu and (menu as GameMenu).trigger != null:
		(menu as GameMenu).trigger.visible = show_menu


func _exit_tree() -> void:
	_set_menu_visible(true)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.MUSTER_ROLL):
		return
	if play == null or play.campaign_over():
		return
	toggle()
	get_viewport().set_input_as_handled()
