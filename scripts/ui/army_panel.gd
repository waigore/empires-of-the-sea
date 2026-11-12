class_name ArmyPanel
extends PanelContainer
## Dockable dossier for the selected land army: station, composition, readiness
## and the detach/merge orders. Rules stay in ArmyState/ArmyMovement; the panel
## only reads state and emits intents.

signal close_pressed
signal dock_side_pressed
signal action_pressed(action: String)

var _header: DossierHeader = null
var _location: Label = null
var _strength: Label = null
var _command: Label = null
var _command_row: HBoxContainer = null
var _command_icon: TextureRect = null
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
var _hospital: Button = null


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

	_header = DossierHeader.make(19, true)
	_header.dock_pressed.connect(func() -> void: dock_side_pressed.emit())
	_header.close_pressed.connect(func() -> void: close_pressed.emit())
	shell.add_child(_header)

	_location = UiRowBuilder.line(15, Palette.TEXT)
	shell.add_child(_location)

	_strength = UiRowBuilder.line(13, Palette.TEXT_DIM)
	shell.add_child(_strength)

	# The crown's commanders: a general's medallion beside every name and medal,
	# the same shell frame a roster row wears (REQ-P1-08).
	_command_row = HBoxContainer.new()
	_command_row.add_theme_constant_override("separation", 8)
	_command_row.visible = false
	shell.add_child(_command_row)
	_command_icon = TextureRect.new()
	_command_icon.texture = ChromeIcons.texture("commander")
	_command_icon.custom_minimum_size = Vector2(22, 22)
	_command_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_command_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_command_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_command_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_row.add_child(_command_icon)

	_command = UiRowBuilder.line(12, Palette.TEXT_DIM)
	_command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_row.add_child(_command)

	_composition = UiRowBuilder.line(13, Palette.GOLD_PALE)
	_composition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_composition)

	_muster_button = UiRowBuilder.button("Muster regiments", 36.0, 0.0)
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

	_merge = UiRowBuilder.button("Combine armies here", 36.0, 0.0)
	_merge.pressed.connect(func() -> void: action_pressed.emit("merge"))
	_merge.visible = false
	shell.add_child(_merge)

	_embark = UiRowBuilder.button("Embark aboard the fleet", 36.0, 0.0)
	_embark.pressed.connect(func() -> void: action_pressed.emit("embark"))
	_embark.visible = false
	shell.add_child(_embark)

	_plan = UiRowBuilder.button("Crown battle plan: Balanced", 36.0, 0.0)
	_plan.tooltip_text = (
		"One plan for every battle this crown fights — tap to cycle "
		+ "Aggressive / Balanced / Defensive"
	)
	_plan.pressed.connect(func() -> void: action_pressed.emit("plan:next"))
	_plan.visible = false
	shell.add_child(_plan)

	# The army's own tents (DR-20261112-07): a blocked order still shows, with
	# the rules' reason as its caption, so the crown never hunts for a hidden
	# refusal.
	_hospital = UiRowBuilder.button("Pitch a field hospital", 36.0, 0.0)
	_hospital.pressed.connect(func() -> void: action_pressed.emit("hospital"))
	_hospital.visible = false
	shell.add_child(_hospital)

	_detach_all = UiRowBuilder.button("Detach all regiments", 36.0, 0.0)
	_detach_all.pressed.connect(func() -> void: action_pressed.emit("detach_all"))
	_detach_all.visible = false
	shell.add_child(_detach_all)

	_status = UiRowBuilder.line(13, Palette.GOLD_PALE)
	shell.add_child(_status)

	_hint = UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_hint)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _header != null:
		_header.set_dock_affordance(glyph, tip)


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
	plan: String = "balanced",
	hospital: Dictionary = {}
) -> void:
	if model == null or army == null:
		return
	_header.flag.color = Palette.faction_color(army.owner)
	var title: String = "ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	if army.home:
		title = "HOME ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	_header.title.text = title
	if army.is_embarked():
		_location.text = "Aboard a fleet"
	else:
		_location.text = "At %s" % model.province_name(army.province)
	_strength.text = "%d regiments · %d strength · %d food" % [
		army.count(), int(army.strength()), _food(army)
	]
	var own_side: Array[ArmyState] = [army]
	var chevrons: int = RegimentCondition.chevrons(own_side)
	if chevrons > 0:
		_strength.text += " · %d chevrons" % chevrons
	if not army.is_embarked():
		var ward: int = HospitalRules.effective_level(model, army.province)
		if army.field_hospital:
			# The army's own tents carry the field's tempo wherever it stands;
			# a province ward still beats them (DR-20261112-07).
			_strength.text += " · field hospital · rest %d%%" % roundi(
				FieldHospitalTrain.army_rest_share(model, army.province, true) * 100.0
			)
		elif ward > 0:
			_strength.text += " · rest %d%%" % roundi(
				HospitalRules.rest_share(ward) * 100.0
			)
		elif HospitalRules.level_at(model, army.province) > 0:
			# The ward is there but its staff went unfed (DR-20261112-04).
			_strength.text += " · hospital unstaffed"
	_command.text = command
	_command_row.visible = not command.is_empty()
	_composition.text = army.composition_text()
	_fill_roster(army, is_player and not army.is_embarked(), model)
	_fill_muster(muster)
	if not (is_player and army.home):
		_muster_open = false
	_muster_button.visible = is_player and army.home and not muster.is_empty()
	_muster_box.visible = _muster_button.visible and _muster_open
	_merge.visible = is_player and can_merge and not army.is_embarked() and army.count() > 0
	_detach_all.visible = is_player and not army.is_embarked() and army.count() > 1
	_embark.visible = is_player and not embark.is_empty() and not army.is_embarked()
	_plan.visible = is_player and not army.is_embarked() and army.count() > 0
	_plan.text = "Crown battle plan: %s" % QuickBattleActions.normalize_plan(plan).capitalize()
	_hospital.visible = is_player and not army.is_embarked() and not hospital.is_empty()
	_hospital.disabled = not bool(hospital.get("ok", false))
	_hospital.text = String(hospital.get("caption", "Pitch a field hospital"))
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


func _fill_roster(army: ArmyState, is_player: bool, model: MapModel) -> void:
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
		var type_id: String = String(row["type_id"])
		top.add_child(UnitMedallion.of_regiment(type_id, 28.0))
		var name := UiRowBuilder.line(13, Palette.TEXT)
		name.text = String(row["name"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		top.add_child(name)
		var muster := UiRowBuilder.button("Muster", 36.0, 0.0)
		muster.custom_minimum_size = Vector2(84, 40)
		muster.add_theme_font_size_override("font_size", 12)
		muster.disabled = not bool(row["ok"])
		muster.tooltip_text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		muster.pressed.connect(func() -> void: action_pressed.emit("recruit:%s" % type_id))
		top.add_child(muster)
		var detail := UiRowBuilder.line(10, Color(0.74, 0.68, 0.55, 0.75))
		detail.text = (
			String(row["cost_text"]) if bool(row["ok"]) else String(row["reason"])
		)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(detail)


## The engagements a regiment has stood in and the honours on its colours, under
## its condition. A green regiment gains no line, so a fresh roster stays short
## (DR-20261111-18, DR-20261112-02).
func _add_record(
	entry: VBoxContainer, army: ArmyState, regiment_id: String, model: MapModel
) -> void:
	var text: String = RegimentRecord.line(army, regiment_id, model)
	if text.is_empty():
		return
	var service := UiRowBuilder.line(10, Palette.GOLD_PALE)
	service.text = text
	service.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(service)


func _food(army: ArmyState) -> int:
	var total: int = 0
	for regiment_id: String in army.regiments:
		total += RegimentCatalog.food_upkeep(army.type_of(regiment_id))
	return total


## A regiment's condition under its name: a chevron for each experience badge
## and a health bar while it is still mauled (REQ-P1-07, REQ-P1-08).
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
	var fill: Color = Palette.HEALTH_HIGH.lerp(Palette.HEALTH_LOW, 1.0 - fraction)
	bar.add_theme_stylebox_override(
		"fill", UiTheme.box(fill, fill.lightened(0.20), 1, 2, Vector4.ZERO)
	)
	condition.add_child(bar)
	var pct := UiRowBuilder.line(11, Palette.TEXT_DIM)
	pct.text = "%d%%" % roundi(fraction * 100.0)
	condition.add_child(pct)
