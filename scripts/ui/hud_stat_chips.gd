class_name HudStatChips
extends RefCounted
## The cartouche's status plaques: treasury and its net income, ships, civilians
## and troops. This builds the widgets the bar mounts and owns their parts — the
## caption and the value column the compact bar narrows — so no layout pass
## searches a plaque by node name (REQ-P1-02, REQ-P1-05, REQ-P3-02).

const TREASURY_SIZE := Vector2(122.0, 40.0)
const CHIP_SIZE := Vector2(88.0, 40.0)

var host: Control = null
var treasury_chip: Button = null
var fleet_chip: Button = null
var civilian_chip: Button = null
var army_chip: Button = null
var treasury_label: Label = null
var income_label: Label = null
var fleet_label: Label = null
var civilian_label: Label = null
var army_label: Label = null

var _treasury_value: int = 0
var _income_value: int = 0
var _treasury_tween: Tween = null
var _flash_tween: Tween = null
var _flash_label: Label = null
## One record per plaque: the parts the compact bar narrows, kept from the build
## so the fit never walks the tree for a caption or a value column.
var _parts: Array[Dictionary] = []


## Builds the four plaques on the bar's row and binds them: the treasury and its
## net income, the ships, the crews and the troops. Each plaque is the target of
## its own door, so the display doubles as a shortcut (REQ-P1-02, REQ-P5-01).
func build(hud: GameHud, row: HBoxContainer) -> void:
	var treasury := _chip("TreasuryChip", "coin", "TREASURY", true)
	treasury["root"].pressed.connect(func() -> void: hud.economy_pressed.emit())
	_mount(hud, row, treasury)

	var fleets := _chip("FleetChip", "ship", "SHIPS", false)
	fleets["root"].pressed.connect(func() -> void: hud.fleet_status_pressed.emit())
	_mount(hud, row, fleets)

	var civilians := _chip("CivilianChip", "people", "CREW ›", false)
	civilians["root"].pressed.connect(
		func() -> void: hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	)
	civilians["root"].tooltip_text = "Every civilian in the realm (C)"
	_mount(hud, row, civilians)

	var troops := _chip("ArmyChip", "swords", "TROOPS", false)
	troops["root"].pressed.connect(func() -> void: hud.army_status_pressed.emit())
	_mount(hud, row, troops)

	_bind(hud, treasury, fleets, civilians, troops)


## One plaque on the bar: the HUD keeps the chip for its layout, and this keeps
## the parts the compact fit narrows.
func _mount(hud: GameHud, row: HBoxContainer, chip: Dictionary) -> void:
	hud.chips.append(chip["root"])
	row.add_child(chip["root"])
	_parts.append(chip)


## The four plaques' readings, bound once the widgets exist.
func _bind(
	hud: Control,
	treasury: Dictionary,
	fleets: Dictionary,
	civilians: Dictionary,
	troops: Dictionary
) -> void:
	host = hud
	treasury_chip = treasury["root"]
	treasury_label = treasury["value"]
	income_label = treasury["delta"]
	fleet_chip = fleets["root"]
	fleet_label = fleets["value"]
	civilian_chip = civilians["root"]
	civilian_label = civilians["value"]
	army_chip = troops["root"]
	army_label = troops["value"]


## The compact cartouche keeps each plaque's medallion and value and drops its
## caption, narrowing the value column to the room a phone has (REQ-P1-05,
## REQ-P1-07). The parts come from the build, never a tree search.
func apply_compact(compact: bool) -> void:
	for part: Dictionary in _parts:
		var root: Button = part["root"]
		if not is_instance_valid(root):
			continue
		var caption: Label = part["caption"]
		if caption != null:
			caption.visible = not compact
		root.custom_minimum_size.x = float(
			part["compact_width"] if compact else part["wide_width"]
		)
		var column: Control = part["column"]
		if column != null:
			column.custom_minimum_size.x = float(
				part["compact_column"] if compact else part["wide_column"]
			)


func set_treasury(value: int, animate: bool = true) -> void:
	if treasury_label == null:
		return
	var from: int = _treasury_value
	_treasury_value = value
	_refresh_treasury_tooltip()
	# A purse below zero is a debt, and the techs decided how deep it may go
	# (wiki: tech-tree-labour-economy § money_lending, banking). Crimson keeps the
	# chip from reading like any other balance (REQ-P5-05).
	treasury_label.add_theme_color_override(
		"font_color", Palette.CRIMSON if value < 0 else Palette.TEXT
	)
	_kill_treasury_tween()
	if not animate or host == null:
		treasury_label.text = TextFormat.thousands(value)
		return
	_treasury_tween = host.create_tween()
	_treasury_tween.tween_method(
		func(step: float) -> void:
			if is_instance_valid(treasury_label):
				treasury_label.text = TextFormat.thousands(int(round(step))),
		float(from), float(value), 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Net treasury movement per turn, shown beside the treasury count so the player
## reads solvency without opening the ledger. Zero is dim, not a fake gain.
func set_income(value: int) -> void:
	_income_value = value
	if income_label == null:
		return
	income_label.text = TextFormat.delta(value)
	income_label.add_theme_color_override(
		"font_color",
		Palette.TEXT_DIM if value == 0 else (
			Palette.GOLD_PALE if value > 0 else Palette.CRIMSON.lerp(Color.WHITE, 0.35)
		)
	)
	_refresh_treasury_tooltip()


func set_fleets(value: int) -> void:
	if fleet_label == null:
		return
	fleet_label.text = str(value)
	if fleet_chip != null:
		fleet_chip.tooltip_text = "Ships — %d · find the next squadron" % value


func set_civilians(value: int) -> void:
	if civilian_label == null:
		return
	civilian_label.text = str(value)
	if civilian_chip != null:
		civilian_chip.tooltip_text = (
			"Civilians — %d · open the empire roster (C)" % value
		)


func set_armies(value: int) -> void:
	if army_label == null:
		return
	army_label.text = str(value)
	if army_chip != null:
		army_chip.tooltip_text = "Troops — %d regiments · find the next army" % value


## The turn's coin movement lifts off the treasury plaque, so a gain reads as an
## event and not a silent repaint (REQ-P5-05).
func flash_income(amount: int) -> void:
	if host == null or treasury_chip == null:
		return
	_kill_flash_tween()
	_flash_label = Label.new()
	_flash_label.text = "+%s" % TextFormat.thousands(amount)
	_flash_label.add_theme_font_size_override("font_size", 18)
	_flash_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_flash_label)
	_flash_label.position = treasury_chip.get_global_rect().position + Vector2(0, 4)
	_flash_tween = host.create_tween().set_parallel(true)
	_flash_tween.tween_property(_flash_label, "position:y", _flash_label.position.y - 46.0, 1.1)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 1.1).set_delay(0.25)
	_flash_tween.chain().tween_callback(_flash_label.queue_free)


## Suite re-seat and a fresh count-up must not leave a prior plaque tween
## writing into a label mid-reset (gd-tools reports freed lambda captures).
func clear_animations() -> void:
	_kill_treasury_tween()
	_kill_flash_tween()
	if treasury_label != null:
		treasury_label.text = TextFormat.thousands(_treasury_value)


func _kill_treasury_tween() -> void:
	if _treasury_tween != null:
		_treasury_tween.kill()
		_treasury_tween = null


func _kill_flash_tween() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
		_flash_tween = null
	if is_instance_valid(_flash_label):
		_flash_label.queue_free()
	_flash_label = null


## One status plaque: icon, running value and (for the treasury) the net delta.
## The parts the compact fit narrows travel back with the widgets, so no layout
## pass reaches into the plaque by node name (REQ-P3-02).
func _chip(
	name_text: String, icon_kind: String, caption: String, delta: bool
) -> Dictionary:
	var button := Button.new()
	button.name = name_text
	button.custom_minimum_size = TREASURY_SIZE if delta else CHIP_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_meta("chip", true)
	button.add_theme_stylebox_override(
		"normal", UiTheme.cartouche(Color(0.16, 0.13, 0.09, 0.70), Color(0.54, 0.43, 0.12, 0.50))
	)
	button.add_theme_stylebox_override(
		"hover", UiTheme.cartouche(Color(0.24, 0.19, 0.12, 0.92), Palette.GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed", UiTheme.cartouche(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_PALE)
	)
	button.add_theme_stylebox_override(
		"focus", UiTheme.cartouche(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE)
	)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_right = -6.0
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var medallion := TextureRect.new()
	medallion.name = "Medallion"
	medallion.texture = ChromeIcons.texture(icon_kind)
	medallion.custom_minimum_size = Vector2(22, 22)
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(medallion)

	var column := VBoxContainer.new()
	column.name = "ValueColumn"
	column.custom_minimum_size = Vector2(74.0 if delta else 48.0, 0.0)
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)

	var cap := Label.new()
	cap.name = "Caption"
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 9)
	cap.add_theme_color_override("font_color", Palette.TEXT_DIM)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(cap)

	var delta_label: Label = null
	if delta:
		var push := Control.new()
		push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		push.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(push)
		delta_label = Label.new()
		delta_label.text = "+0"
		delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta_label.add_theme_font_size_override("font_size", 9)
		delta_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
		delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(delta_label)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Palette.TEXT)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(value)
	return {
		"root": button,
		"value": value,
		"delta": delta_label,
		"caption": cap,
		"column": column,
		"wide_width": TREASURY_SIZE.x if delta else CHIP_SIZE.x,
		"compact_width": 76.0 if delta else 64.0,
		"wide_column": 74.0 if delta else 48.0,
		"compact_column": 36.0 if delta else 24.0,
	}


## Estates and college only — the world market clears after them (world-market).
## A negative purse is named as debt, so a crown in the lending floor's shadow
## reads why it cannot fund a study (REQ-P5-05).
func _refresh_treasury_tooltip() -> void:
	if treasury_chip == null:
		return
	treasury_chip.tooltip_text = "Treasury %s ducats%s · %s per turn before the auction — open the ledger" % [
		TextFormat.thousands(_treasury_value),
		" (in debt)" if _treasury_value < 0 else "",
		TextFormat.delta(_income_value),
	]
