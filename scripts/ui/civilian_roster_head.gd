class_name CivilianRosterHead
extends VBoxContainer
## Whole-empire civilian roster: empire totals, the Old/New World switch, one
## icon chip per craft and the order chips (all / idle / at work). Owns no rules
## state; the panel hands it a snapshot and it emits filter intents (REQ-P3-02).

signal filter_changed(region_key: String, type_id: String, status_key: String)

const TYPE_ALL: String = ""

var region: String = CivilianRoster.REGION_ALL
var type_id: String = TYPE_ALL
var status: String = CivilianRoster.STATUS_ALL

var _stat_values: Dictionary = {}
var _stats: Control = null
var _region_line: Label = null
var _region_buttons: Dictionary = {}
var _type_buttons: Dictionary = {}
var _type_flow: HBoxContainer = null
var _type_scroll: ScrollContainer = null
var _status_buttons: Dictionary = {}
var _status_flow: HBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", 9)
	_build_stats()
	_build_regions()
	_build_types()
	_build_status()


func _build_stats() -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 28)
	add_child(stats)
	_stats = stats
	for spec: Array in [["total", "CIVILIANS"], ["idle", "IDLE"], ["working", "AT WORK"]]:
		stats.add_child(_stat_box(String(spec[0]), String(spec[1])))
	_region_line = Label.new()
	_region_line.add_theme_font_size_override("font_size", 12)
	_region_line.add_theme_color_override("font_color", Palette.GOLD)
	add_child(_region_line)


func _stat_box(key: String, caption: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	var value := Label.new()
	value.text = "0"
	value.add_theme_font_size_override("font_size", 24)
	value.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(value)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	box.add_child(label)
	_stat_values[key] = value
	return box


func _build_regions() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var caption := Label.new()
	caption.text = "REGION"
	caption.custom_minimum_size = Vector2(52, 0)
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	for key: String in CivilianRoster.REGION_FILTERS:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 30)
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_press_region.bind(key))
		_region_buttons[key] = button
		row.add_child(button)


func _build_types() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var caption := Label.new()
	caption.text = "CRAFT"
	caption.custom_minimum_size = Vector2(52, 0)
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_type_scroll = ScrollContainer.new()
	_type_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_type_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_type_scroll.custom_minimum_size = Vector2(0, 30)
	_type_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_type_scroll)
	_type_flow = HBoxContainer.new()
	_type_flow.add_theme_constant_override("separation", 4)
	_type_scroll.add_child(_type_flow)
	var all := _type_button(TYPE_ALL, "All crafts")
	_type_flow.add_child(all)
	for type: String in CivilianCatalog.ORDER:
		_type_flow.add_child(_type_button(type, CivilianCatalog.display_name(type)))


func _type_button(key: String, caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_constant_override("icon_max_width", 22)
	var texture: Texture2D = CivilianArt.medallion(key) if not key.is_empty() else null
	if texture != null:
		button.icon = texture
	button.pressed.connect(_press_type.bind(key))
	_type_buttons[key] = button
	return button


## Who waits for orders: the one reading a crown acts on every turn, so it sits
## beside the world and craft filters rather than behind a menu (REQ-P5-03,
## REQ-P5-04). Three chips share the row, so a phone never scrolls for them.
func _build_status() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var caption := Label.new()
	caption.text = "ORDERS"
	caption.custom_minimum_size = Vector2(52, 0)
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_status_flow = HBoxContainer.new()
	_status_flow.add_theme_constant_override("separation", 4)
	_status_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_flow)
	for key: String in CivilianRoster.STATUS_FILTERS:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_press_status.bind(key))
		_status_buttons[key] = button
		_status_flow.add_child(button)


func _press_region(key: String) -> void:
	region = key if CivilianRoster.REGION_FILTERS.has(key) else CivilianRoster.REGION_ALL
	filter_changed.emit(region, type_id, status)


func _press_type(key: String) -> void:
	if key.is_empty():
		type_id = TYPE_ALL
	elif key == type_id:
		type_id = TYPE_ALL
	else:
		type_id = key
	filter_changed.emit(region, type_id, status)


## Tapping the lit chip clears it, the way the craft chips do.
func _press_status(key: String) -> void:
	if key == CivilianRoster.STATUS_ALL or key == status:
		status = CivilianRoster.STATUS_ALL
	else:
		status = key
	filter_changed.emit(region, type_id, status)


func render(
	snapshot: Dictionary, selected_region: String, selected_type: String,
	selected_status: String = CivilianRoster.STATUS_ALL
) -> void:
	region = selected_region
	type_id = selected_type
	status = selected_status
	(_stat_values["total"] as Label).text = str(int(snapshot.get("total", 0)))
	(_stat_values["idle"] as Label).text = str(int(snapshot.get("idle", 0)))
	(_stat_values["working"] as Label).text = str(int(snapshot.get("working", 0)))
	var by_region: Dictionary = snapshot.get("by_region", {})
	var old_count: int = int(by_region.get(FactionCatalog.OLD_WORLD, 0))
	var new_count: int = int(by_region.get(FactionCatalog.NEW_WORLD, 0))
	_region_line.text = "Old World %d  ·  New World %d  ·  %d provinces posted" % [
		old_count, new_count, _province_count(snapshot)
	]
	for key: String in _region_buttons.keys():
		var count: int = int(snapshot.get("total", 0))
		if key == CivilianRoster.REGION_OLD:
			count = old_count
		elif key == CivilianRoster.REGION_NEW:
			count = new_count
		var button: Button = _region_buttons[key]
		button.text = "%s %d" % [_region_label(key), count]
		button.set_pressed_no_signal(key == region)
	var counts: Dictionary = CivilianRoster.type_counts(snapshot, region, status)
	for key: String in _type_buttons.keys():
		var button: Button = _type_buttons[key]
		var count: int = int(counts.get(key, 0)) if not key.is_empty() else int(snapshot.get("total", 0))
		if key.is_empty() and region != CivilianRoster.REGION_ALL:
			count = old_count if region == CivilianRoster.REGION_OLD else new_count
		button.text = "%s  %d" % [
			"All crafts" if key.is_empty() else CivilianCatalog.display_name(key), count
		]
		button.set_pressed_no_signal(key == type_id)
	_render_status(snapshot)


## The order chips count what the world and craft filters leave, so a tally is
## never a number the press would not show. Idle crews read gold: a crown that
## ends the turn on them has spent a turn of work (REQ-P5-05).
func _render_status(snapshot: Dictionary) -> void:
	var counts: Dictionary = CivilianRoster.status_counts(snapshot, region, type_id)
	for key: String in _status_buttons.keys():
		var button: Button = _status_buttons[key]
		var count: int = int(counts.get(key, 0))
		button.text = "%s  %d" % [CivilianRoster.status_label(key), count]
		button.set_pressed_no_signal(key == status)
		if key == CivilianRoster.STATUS_IDLE and count > 0:
			button.add_theme_color_override("font_color", Palette.GOLD)
		else:
			button.remove_theme_color_override("font_color")


func _region_label(key: String) -> String:
	match key:
		CivilianRoster.REGION_OLD:
			return "Old World"
		CivilianRoster.REGION_NEW:
			return "New World"
	return "All"


func _province_count(snapshot: Dictionary) -> int:
	var seen: Dictionary = {}
	for group: Dictionary in snapshot.get("groups", []):
		seen["%d:%d" % [int(group["region"]), int(group["province_id"])]] = true
	return seen.size()


func filter_buttons() -> Dictionary:
	var out: Dictionary = {}
	out.merge(_region_buttons)
	out.merge(_type_buttons)
	out.merge(_status_buttons)
	return out


func set_compact(compact: bool) -> void:
	_stats.visible = not compact
	_region_line.visible = not compact
	add_theme_constant_override("separation", 5 if compact else 9)
	for button: Button in _region_buttons.values():
		button.custom_minimum_size.y = 40.0 if compact else 30.0
	for button: Button in _type_buttons.values():
		button.custom_minimum_size.y = 40.0 if compact else 30.0
	for button: Button in _status_buttons.values():
		button.custom_minimum_size.y = 40.0 if compact else 30.0
	if _type_scroll != null:
		_type_scroll.custom_minimum_size.y = 40.0 if compact else 30.0
