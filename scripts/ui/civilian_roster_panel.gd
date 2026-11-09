class_name CivilianRosterPanel
extends Control
## Whole-empire civilian roster (REQ-P5-01, REQ-P5-03): every unit in the Old
## and New World in one ledger, filtered by region or craft, with a Visit action
## that opens the unit's map and dossier. The data projection lives in
## CivilianRoster; this class only renders rows and emits no rules calls.

const MARGIN_WIDE: int = 42
const MARGIN_COMPACT: int = 10

var play: PlaySession = null

var _overlay: Control = null
var _margin: MarginContainer = null
var _panel: PanelContainer = null
var _column: VBoxContainer = null
var _head: CivilianRosterHead = null
var _rows: VBoxContainer = null
var _title: Label = null
var _subtitle: Label = null
var _hint: Label = null
var _empty: Label = null
var _crest: Control = null
var _close: Button = null
var _region: String = CivilianRoster.REGION_ALL
var _type: String = CivilianRosterHead.TYPE_ALL
var _snapshot: Dictionary = {}
var _fade: Tween = null
## Last applied layout profile (-1 before the first fit); an orientation change
## rebuilds the rows because a row fixes its icon/state size at construction.
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
	if play == null or play.world == null or play.civilian_layer == null:
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


## The pause trigger lives on a higher canvas layer than the HUD; park it while
## the roster is up so its gold seal does not cut through the ledger's frame.
func _set_menu_visible(show_menu: bool) -> void:
	if play == null or not is_instance_valid(play.host):
		return
	var menu: Node = play.host.get_node_or_null("GameMenu")
	if menu is GameMenu and (menu as GameMenu).trigger != null:
		(menu as GameMenu).trigger.visible = show_menu


func _exit_tree() -> void:
	_set_menu_visible(true)


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if play == null or play.world == null or play.civilian_layer == null:
		return
	_snapshot = CivilianRoster.snapshot(
		play.world, play.civilian_layer.regions, play.player_faction
	)
	_head.render(_snapshot, _region, _type)
	_fit()
	_apply_filter()


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
	_head = CivilianRosterHead.new()
	_head.filter_changed.connect(_on_filter)
	column.add_child(_head)

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

	var crest := CivilianIcon.new("explorer", 42.0)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(crest)
	_crest = crest

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	var title := Label.new()
	title.text = "THE CROWN'S PEOPLE"
	title.add_theme_font_override("font", UiTheme.serif())
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	titles.add_child(title)
	_title = title

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(92, 40)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	_close = close_button
	return header


func _footer() -> Control:
	var hint := Label.new()
	hint.text = (
		"Visit opens the civilian's map and dossier. Filter by Old or New World, "
		+ "or by craft; the C key opens this roster from anywhere on the map."
	)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 0.76))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = hint
	return hint


func _on_filter(region_key: String, type_id: String) -> void:
	_region = region_key
	_type = type_id
	_head.render(_snapshot, _region, _type)
	_apply_filter()


func _apply_filter() -> void:
	for child: Node in _rows.get_children():
		if child == _empty:
			continue
		_rows.remove_child(child)
		child.queue_free()
	var groups: Array[Dictionary] = CivilianRoster.groups(_snapshot, _region, _type)
	var shown: int = CivilianRoster.count(_snapshot, _region, _type)
	_subtitle.text = _subtitle_text(shown)
	_empty.visible = shown == 0
	if shown == 0:
		_empty.text = (
			"No civilians answer this view. Train another at the capital, or clear "
			+ "a filter."
		)
		return
	_empty.visible = false
	for group: Dictionary in groups:
		var heading := Label.new()
		var rows: Array = group["rows"]
		heading.text = "%s  ·  %s  ·  %d civilian%s" % [
			String(group["region_label"]).to_upper(),
			String(group["province_name"]).to_upper(),
			rows.size(),
			"" if rows.size() == 1 else "s",
		]
		heading.add_theme_font_size_override("font_size", 11)
		heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
		_rows.add_child(heading)
		for raw: Variant in rows:
			var row := CivilianRosterRow.new()
			row.compact = HudLayout.is_compact(get_viewport_rect().size)
			row.visit_pressed.connect(_visit)
			_rows.add_child(row)
			row.setup(raw)


func _subtitle_text(shown: int) -> String:
	var scope: String = "in both worlds"
	if _region == CivilianRoster.REGION_OLD:
		scope = "in the Old World"
	elif _region == CivilianRoster.REGION_NEW:
		scope = "in the New World"
	var craft: String = ""
	if not _type.is_empty():
		craft = " · %s only" % CivilianCatalog.display_name(_type)
	return "Showing %d of %d civilians %s%s. Idle crews wait for orders." % [
		shown, int(_snapshot.get("total", 0)), scope, craft
	]


func _visit(region: int, unit_id: int) -> void:
	if play == null:
		return
	if MapPlayCivilianRoster.focus(play, region, unit_id):
		close()


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
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.99),
			Palette.GOLD_DIM,
			1,
			4,
			Vector4(12, 10, 12, 10) if compact else Vector4(20, 16, 20, 16)
		)
	)
	if _title != null:
		var narrow: bool = get_viewport_rect().size.x < 520.0
		_title.add_theme_font_size_override(
			"font_size", 20 if narrow else (22 if compact else 28)
		)
		_crest.visible = not narrow
		_close.custom_minimum_size.x = 64.0 if narrow else 92.0
	if _subtitle != null:
		_subtitle.visible = not compact
	if _hint != null:
		_hint.visible = not compact
	if _head != null:
		_head.set_compact(compact)
	var profile: int = 1 if compact else 0
	var changed: bool = _was_compact >= 0 and _was_compact != profile
	_was_compact = profile
	if changed and visible and not _snapshot.is_empty():
		_apply_filter()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(InputActions.CANCEL):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.CIVILIAN_ROSTER):
		return
	if play == null or play.campaign_over():
		return
	toggle()
	get_viewport().set_input_as_handled()
