class_name ArmyRosterBlock
extends VBoxContainer
## The army dossier's regiment column: medallion, title, type detail, condition,
## service record and detach. Lifted out of ArmyPanel so the sheet keeps the
## summary and orders while this block owns only the roster (REQ-P3-01). It
## reads state and emits intents; ArmyState owns every rule (REQ-P3-02).

signal action_pressed(action: String)
## The crown names one of its colours: the edit row's committed text, tidied by
## the rules before it is written (wiki: naming § Regiment names;
## DR-20261113-03).
signal rename_pressed(regiment_id: String, wanted: String)

const NAME_BUTTON: String = "Name"

var _army: ArmyState = null
var _is_player: bool = false
var _model: MapModel = null
## The instance whose name is being edited, or empty when no edit row is open.
var _editing: String = ""
var _field: LineEdit = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


## Rebuilds every regiment row for the open army. An open edit row closes, so a
## repaint never leaves a stale name field behind.
func fill(army: ArmyState, is_player: bool, model: MapModel) -> void:
	_army = army
	_is_player = is_player
	_model = model
	_editing = ""
	_render()


func _render() -> void:
	UiRowBuilder.clear(self)
	_field = null
	if _army == null:
		return
	for regiment_id: String in _army.regiments:
		var type_id: String = _army.type_of(regiment_id)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		add_child(entry)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		entry.add_child(row)
		row.add_child(UnitMedallion.of_regiment(type_id, 28.0))
		var label := UiRowBuilder.line(13, Palette.TEXT)
		## The regiment's own title, with its type beside it — the same read as
		## a hull's name in the fleet dossier (DR-20261111-18).
		label.text = "%s — %s" % [
			RegimentNames.of(_army, regiment_id), RegimentCatalog.display_name(type_id)
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if _is_player:
			row.add_child(_detach_button(regiment_id))
			row.add_child(_name_button(regiment_id))
		if _editing == regiment_id:
			_add_edit_row(entry, regiment_id)
		# Regiment detail: category, stats and its share of the food bill.
		var detail := UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = RegimentCatalog.detail_line(type_id)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)
		_add_condition(entry, _army, regiment_id)
		_add_record(entry, _army, regiment_id, _model)


## The crown's own door to rename a colour: compact so two orders still fit the
## name row at phone width (REQ-P5-07).
func _name_button(regiment_id: String) -> Button:
	var rename := UiRowBuilder.button(NAME_BUTTON, 32.0, 0.0)
	rename.custom_minimum_size = Vector2(56, 32)
	rename.add_theme_font_size_override("font_size", 12)
	rename.tooltip_text = "Give these colours a new name"
	rename.pressed.connect(func() -> void: begin_rename(regiment_id))
	return rename


func _detach_button(regiment_id: String) -> Button:
	var detach := UiRowBuilder.button("Detach", 36.0, 0.0)
	detach.custom_minimum_size = Vector2(82, 32)
	detach.add_theme_font_size_override("font_size", 12)
	detach.pressed.connect(
		func() -> void: action_pressed.emit("detach:%s" % regiment_id)
	)
	return detach


## Opens the name row for one instance without rebuilding the dossier.
func begin_rename(regiment_id: String) -> void:
	if _army == null or not _army.regiments.has(regiment_id):
		return
	_editing = regiment_id
	_render()


## The field, the commit and the way out: a tap either writes the name or closes
## the row, and the rules name the refusal when they refuse (REQ-P5-05).
func _add_edit_row(entry: VBoxContainer, regiment_id: String) -> void:
	var edit := HBoxContainer.new()
	edit.add_theme_constant_override("separation", 6)
	entry.add_child(edit)
	var field := LineEdit.new()
	field.text = RegimentNames.of(_army, regiment_id)
	field.max_length = RegimentRename.MAX_CHARS
	field.placeholder_text = "Name these colours"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(0, 36)
	field.add_theme_font_size_override("font_size", 14)
	field.add_theme_color_override("font_color", Palette.TEXT)
	field.add_theme_color_override("font_placeholder_color", Palette.TEXT_DIM)
	field.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.INK_SOFT, Palette.GOLD_DIM, 1, 3, Vector4(10, 4, 10, 4))
	)
	field.add_theme_stylebox_override(
		"focus", UiTheme.box(Palette.INK_SOFT, Palette.GOLD, 1, 3, Vector4(10, 4, 10, 4))
	)
	field.text_submitted.connect(
		func(_text: String) -> void: commit_rename(regiment_id)
	)
	edit.add_child(field)
	_field = field
	var keep := UiRowBuilder.button("Keep", 32.0, 0.0)
	keep.custom_minimum_size = Vector2(56, 36)
	keep.add_theme_font_size_override("font_size", 12)
	keep.pressed.connect(func() -> void: commit_rename(regiment_id))
	edit.add_child(keep)
	var cancel := UiRowBuilder.button("Cancel", 32.0, 0.0)
	cancel.custom_minimum_size = Vector2(64, 36)
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(cancel_rename)
	edit.add_child(cancel)
	## A phone's keyboard only opens on a field that is already in the tree; a
	## panel built outside one (a test sheet) keeps the row and takes no focus.
	if is_inside_tree():
		field.grab_focus()


## Hands the typed name to the caller; the row closes on the repaint that
## follows a written name or a named refusal.
func commit_rename(regiment_id: String) -> void:
	if _field == null or _editing != regiment_id:
		return
	rename_pressed.emit(regiment_id, _field.text)


func cancel_rename() -> void:
	_editing = ""
	_render()


## The engagements a regiment has stood in and the honours on its colours, then
## the despatch it holds (DR-20261111-18, DR-20261112-02, DR-20261112-10).
func _add_record(
	entry: VBoxContainer, army: ArmyState, regiment_id: String, model: MapModel
) -> void:
	_add_service_line(entry, RegimentRecord.line(army, regiment_id, model), Palette.GOLD_PALE)
	_add_service_line(
		entry, RegimentDecorations.line(army, regiment_id, model), Palette.TEXT_DIM
	)


## One wrapped service line under a regiment's condition; empty text adds none.
func _add_service_line(entry: VBoxContainer, text: String, color: Color) -> void:
	if text.is_empty():
		return
	var service := UiRowBuilder.line(10, color)
	service.text = text
	service.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(service)


## Condition under a name: a chevron per badge, a bar while mauled (REQ-P1-07).
func _add_condition(entry: VBoxContainer, army: ArmyState, regiment_id: String) -> void:
	var data: Dictionary = army.condition_of(regiment_id)
	var medals: int = int(data["medals"])
	var fraction: float = float(data["fraction"])
	if medals <= 0 and fraction >= 0.999:
		return
	var condition := HBoxContainer.new()
	condition.add_theme_constant_override("separation", 5)
	entry.add_child(condition)
	if medals > 0:
		var badge := TextureRect.new()
		badge.texture = ChromeIcons.texture("chevron")
		badge.custom_minimum_size = Vector2(15, 15)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.tooltip_text = "%d chevron%s · +%d%% firepower" % [
			medals, "" if medals == 1 else "s", medals * 10
		]
		condition.add_child(badge)
		var count := UiRowBuilder.line(11, Palette.GOLD)
		count.text = "×%d" % medals
		condition.add_child(count)
	if fraction >= 0.999:
		return
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(76, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = fraction
	bar.add_theme_stylebox_override(
		"background",
		UiTheme.box(Color(0.17, 0.14, 0.10), Palette.INK_LINE, 1, 2, Vector4.ZERO)
	)
	var fill_color: Color = Palette.HEALTH_HIGH.lerp(Palette.HEALTH_LOW, 1.0 - fraction)
	bar.add_theme_stylebox_override(
		"fill", UiTheme.box(fill_color, fill_color.lightened(0.20), 1, 2, Vector4.ZERO)
	)
	condition.add_child(bar)
	var pct := UiRowBuilder.line(11, Palette.TEXT_DIM)
	pct.text = "%d%%" % roundi(fraction * 100.0)
	condition.add_child(pct)
