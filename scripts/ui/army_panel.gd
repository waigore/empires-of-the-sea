class_name ArmyPanel
extends PanelContainer
## Dockable dossier for the selected land army: station, composition, readiness
## and the detach/merge orders. Rules stay in ArmyState/ArmyMovement; the panel
## only reads state and emits intents.

signal close_pressed
signal dock_side_pressed
signal action_pressed(action: String)

var _flag: ColorRect = null
var _title: Label = null
var _dock: Button = null
var _location: Label = null
var _strength: Label = null
var _command: Label = null
var _composition: Label = null
var _status: Label = null
var _hint: Label = null
var _roster: VBoxContainer = null
var _scroll: ScrollContainer = null
var _muster_button: Button = null
var _muster_box: VBoxContainer = null
var _muster_open: bool = false
var _detach_all: Button = null
var _merge: Button = null
var _embark: Button = null
var _plan: Button = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(18, 12, 18, 12)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	shell.add_child(header)

	_flag = ColorRect.new()
	_flag.custom_minimum_size = Vector2(14, 14)
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_flag)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)

	_dock = _small_button("◀", "Dock left")
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	header.add_child(_dock)

	var close := _small_button("×", "Close")
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)

	_location = _line(15, Palette.TEXT)
	shell.add_child(_location)

	_strength = _line(13, Palette.TEXT_DIM)
	shell.add_child(_strength)

	_command = _line(12, Palette.TEXT_DIM)
	_command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command.visible = false
	shell.add_child(_command)

	_composition = _line(13, Palette.GOLD_PALE)
	_composition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_composition)

	_muster_button = _make_button("Muster regiments")
	_muster_button.pressed.connect(func() -> void: set_muster_open(not _muster_open))
	_muster_button.visible = false
	shell.add_child(_muster_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	_scroll = scroll

	# One column inside the scroll: the roster must stack above the drill yard,
	# not share the scroll's origin with it.
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	_roster = VBoxContainer.new()
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster.add_theme_constant_override("separation", 4)
	content.add_child(_roster)

	_muster_box = VBoxContainer.new()
	_muster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_muster_box.add_theme_constant_override("separation", 8)
	_muster_box.visible = false
	content.add_child(_muster_box)

	_merge = _make_button("Combine armies here")
	_merge.pressed.connect(func() -> void: action_pressed.emit("merge"))
	_merge.visible = false
	shell.add_child(_merge)

	_embark = _make_button("Embark aboard the fleet")
	_embark.pressed.connect(func() -> void: action_pressed.emit("embark"))
	_embark.visible = false
	shell.add_child(_embark)

	_plan = _make_button("Battle plan: Balanced")
	_plan.tooltip_text = "Tap to cycle Aggressive / Balanced / Defensive"
	_plan.pressed.connect(func() -> void: action_pressed.emit("plan:next"))
	_plan.visible = false
	shell.add_child(_plan)

	_detach_all = _make_button("Detach all regiments")
	_detach_all.pressed.connect(func() -> void: action_pressed.emit("detach_all"))
	_detach_all.visible = false
	shell.add_child(_detach_all)

	_status = _line(13, Palette.GOLD_PALE)
	shell.add_child(_status)

	_hint = _line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_hint)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


## Opens or closes the drill-yard list without rebuilding the dossier.
func set_muster_open(open: bool) -> void:
	_muster_open = open
	if _muster_box != null:
		_muster_box.visible = open and _muster_button.visible
	if open and _scroll != null:
		_scroll_to_muster.call_deferred()


## Brings the first drill-yard row under the top of the scroll viewport.
func _scroll_to_muster() -> void:
	if _scroll == null or _muster_box == null:
		return
	_scroll.scroll_vertical = int(_muster_box.position.y)


func refresh(
	model: MapModel,
	army: ArmyState,
	is_player: bool,
	can_merge: bool = false,
	command: String = "",
	muster: Array[Dictionary] = [],
	embark: String = "",
	plan: String = "balanced"
) -> void:
	if model == null or army == null:
		return
	_flag.color = Palette.faction_color(army.owner)
	var title: String = "ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	if army.home:
		title = "HOME ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	_title.text = title
	if army.is_embarked():
		_location.text = "Aboard a fleet"
	else:
		_location.text = "At %s" % model.province_name(army.province)
	_strength.text = "%d regiments · %d strength · %d food" % [
		army.count(), int(army.strength()), _food(army)
	]
	_command.text = command
	_command.visible = not command.is_empty()
	_composition.text = army.composition_text()
	_fill_roster(army, is_player)
	_fill_muster(muster)
	if not (is_player and army.home):
		_muster_open = false
	_muster_button.visible = is_player and army.home and not muster.is_empty()
	_muster_box.visible = _muster_button.visible and _muster_open
	_merge.visible = is_player and can_merge and not army.is_embarked() and army.count() > 0
	_detach_all.visible = is_player and not army.is_embarked() and army.count() > 1
	_embark.visible = is_player and not embark.is_empty() and not army.is_embarked()
	_plan.visible = is_player and not army.is_embarked() and army.count() > 0
	_plan.text = "Battle plan: %s" % plan.capitalize()
	if not is_player:
		_status.text = "Enemy colours · no orders"
		_hint.text = "Observe only. Orders require your own army."
	elif army.is_embarked():
		_status.text = "Aboard the fleet"
		_hint.text = "The squadron carries the army; land on an owned coast."
	elif army.home:
		_status.text = "Home Army · never leaves the capital"
		_hint.text = "Detach a regiment to form a field army, then march it."
	elif army.moved:
		_status.text = "Has marched this turn"
		_hint.text = "End the turn to march again."
	else:
		_status.text = "1 march this turn"
		_hint.text = "Tap a highlighted province; your own land is open, enemy land must border you."


func _fill_roster(army: ArmyState, is_player: bool) -> void:
	for child in _roster.get_children():
		child.queue_free()
	for regiment_id: String in army.regiments:
		var type_id: String = army.type_of(regiment_id)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		_roster.add_child(entry)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		entry.add_child(row)
		var label := _line(13, Palette.TEXT)
		label.text = RegimentCatalog.display_name(type_id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		# Regiment detail: category, stats and its share of the food bill.
		var detail := _line(10, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = RegimentCatalog.detail_line(type_id)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)
		if not is_player:
			continue
		var detach := _make_button("Detach")
		detach.custom_minimum_size = Vector2(82, 32)
		detach.add_theme_font_size_override("font_size", 12)
		detach.pressed.connect(
			func() -> void: action_pressed.emit("detach:%s" % regiment_id)
		)
		row.add_child(detach)


## Drill-yard rows come from ArmyTraining; the panel only renders them and
## emits the recruit intent (REQ-P3-02).
func _fill_muster(rows: Array[Dictionary]) -> void:
	for child in _muster_box.get_children():
		child.queue_free()
	for row: Dictionary in rows:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		_muster_box.add_child(entry)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		entry.add_child(top)
		var name := _line(13, Palette.TEXT)
		name.text = String(row["name"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(name)
		var muster := _make_button("Muster")
		muster.custom_minimum_size = Vector2(84, 40)
		muster.add_theme_font_size_override("font_size", 12)
		muster.disabled = not bool(row["ok"])
		muster.tooltip_text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		var type_id: String = String(row["type_id"])
		muster.pressed.connect(func() -> void: action_pressed.emit("recruit:%s" % type_id))
		top.add_child(muster)
		var detail := _line(10, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)


func _food(army: ArmyState) -> int:
	var total: int = 0
	for regiment_id: String in army.regiments:
		total += RegimentCatalog.food_upkeep(army.type_of(regiment_id))
	return total


func _line(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _small_button(text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(40, 40)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	return button
