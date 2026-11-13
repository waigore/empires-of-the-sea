class_name CivilianRosterPanel
extends SheetFrame
## Whole-empire civilian roster (REQ-P5-01, REQ-P5-03): every unit in the Old
## and New World in one ledger, filtered by region or craft, with a Visit action
## that opens the unit's map and dossier. The data projection lives in
## CivilianRoster; this class only renders rows and emits no rules calls. The
## sheet chrome, fade and pause-door park come from SheetFrame.

var _head: CivilianRosterHead = null
var _rows: VBoxContainer = null
var _empty: Label = null
var _region: String = CivilianRoster.REGION_ALL
var _type: String = CivilianRosterHead.TYPE_ALL
var _snapshot: Dictionary = {}


func _init() -> void:
	title_text = "THE CROWN'S PEOPLE"
	hint_text = (
		"Visit opens the civilian's map and dossier. Filter by Old or New World, "
		+ "or by craft; the C key opens this roster from anywhere on the map."
	)
	toggle_action = InputActions.CIVILIAN_ROSTER


func bind(p_session: PlaySession) -> void:
	play = p_session


func refresh() -> void:
	if play == null or play.world == null or play.civilian_layer == null:
		return
	_snapshot = CivilianRoster.snapshot(
		play.world, play.civilian_layer.regions, play.player_faction
	)
	_head.render(_snapshot, _region, _type)
	_fit()
	_apply_filter()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return CivilianIcon.new("explorer", 42.0)


func _can_open() -> bool:
	return super._can_open() and play.civilian_layer != null


func _build_body(column: VBoxContainer) -> void:
	_head = CivilianRosterHead.new()
	_head.filter_changed.connect(_on_filter)
	column.add_child(_head)

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
	if _head != null:
		_head.set_compact(compact)


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_apply_filter()


# --- rows --------------------------------------------------------------------


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
