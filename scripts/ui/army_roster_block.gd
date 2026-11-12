class_name ArmyRosterBlock
extends VBoxContainer
## The army dossier's regiment column: medallion, title, type detail, condition,
## service record and detach. Lifted out of ArmyPanel so the sheet keeps the
## summary and orders while this block owns only the roster (REQ-P3-01). It
## reads state and emits intents; ArmyState owns every rule (REQ-P3-02).

signal action_pressed(action: String)


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


## Rebuilds every regiment row for the open army.
func fill(army: ArmyState, is_player: bool, model: MapModel) -> void:
	for child in get_children():
		child.queue_free()
	for regiment_id: String in army.regiments:
		var type_id: String = army.type_of(regiment_id)
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
			RegimentNames.of(army, regiment_id), RegimentCatalog.display_name(type_id)
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		# Regiment detail: category, stats and its share of the food bill.
		var detail := UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = RegimentCatalog.detail_line(type_id)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)
		_add_condition(entry, army, regiment_id)
		_add_record(entry, army, regiment_id, model)
		if not is_player:
			continue
		var detach := UiRowBuilder.button("Detach", 36.0, 0.0)
		detach.custom_minimum_size = Vector2(82, 32)
		detach.add_theme_font_size_override("font_size", 12)
		detach.pressed.connect(
			func() -> void: action_pressed.emit("detach:%s" % regiment_id)
		)
		row.add_child(detach)


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
