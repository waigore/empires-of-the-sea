class_name TopBar
extends RefCounted
## Cartouche bar: nation and turn, the realm and lens seals, the command seals
## and the status plaques; the pause menu mounts its own MENU crest in the first
## slot. Every element either answers a question the player asks every turn or
## performs an action; the bar carries no vanity counters. The chart switch lives
## on the map's own corner now (issue #1164), so the bar keeps no region seal.
## HudLayout re-anchors the parts captured on `hud` (REQ-P1-02, REQ-P1-05).
##
## The doors register their own caption at the dress, so the compact fit reads
## the part it built instead of searching the tree by node name (REQ-P3-02).

const SEAL_SIZE := Vector2(52.0, 44.0)
## The parts one dressed door owns: the caption the compact bar hides and the
## medallion the lens seal repaints when the screen reports a reading.
class DoorSkin:
	var caption: Label = null
	var medallion: Control = null


static func build(hud: GameHud) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = GameHud.BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.box(
		Color(0.06, 0.05, 0.04, 0.98), Palette.GOLD_DIM, 0, 0, Vector4.ZERO
	)
	style.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	hud.add_child(bar)
	hud.top_bar = bar

	var ornament := TopBarOrnament.new()
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(ornament)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	column.add_child(row)
	hud.top_row = row

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.alignment = BoxContainer.ALIGNMENT_END
	chip_row.visible = false
	column.add_child(chip_row)
	hud.chip_row = chip_row

	row.add_child(_identity(hud))

	var command := HBoxContainer.new()
	command.add_theme_constant_override("separation", 3)
	row.add_child(command)
	# The realm is the bar's first command: every province, read three ways
	# (issue #1164; REQ-P5-01, REQ-P5-07).
	var realm := _seal(
		hud, "globe", "REALM", "Every province you hold — economy, defence, connectivity (T)",
		func() -> void: hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	)
	realm.name = "RealmSeal"
	command.add_child(realm)
	command.add_child(_lens_seal(hud))
	command.add_child(_seal(
		hud, "capitol", "CAPITAL", "Centre the map on your seat (F)",
		func() -> void: hud.focus_capital_pressed.emit()
	))
	command.add_child(_seal(
		hud, "ledger", "LEDGER", "Treasury, trade and upkeep",
		func() -> void: hud.economy_pressed.emit()
	))
	command.add_child(_seal(
		hud, "research", "RESEARCH", "College slots and funding",
		func() -> void: hud.research_pressed.emit()
	))
	command.add_child(_seal(
		hud, "crown", "COURT", "Diplomacy, alliances and war",
		func() -> void: hud.diplomacy_pressed.emit()
	))
	command.add_child(_seal(
		hud, "commander", "MUSTER", "Every army and squadron in one ledger (O)",
		func() -> void: hud.ledger_door_pressed.emit(HudLedgerDoors.MUSTER)
	))
	# Non-navigation chrome lives on the bar, never as a loose seal over the
	# chart (REQ-P1-07): the estates ledger and the crown's news.
	var estates := _seal(
		hud, "manor", "ESTATES", "The crown's estates and works",
		func() -> void: hud.estates_pressed.emit()
	)
	estates.name = "EstatesSeal"
	command.add_child(estates)
	var gazette := _seal(
		hud, "gazette", "GAZETTE", "This turn's news and the archive",
		func() -> void: hud.gazette_pressed.emit()
	)
	gazette.name = "GazetteSeal"
	command.add_child(gazette)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	hud.stats.build(hud, row)
	_end_turn(hud, row)


static func _identity(hud: GameHud) -> VBoxContainer:
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -5)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var nation := Label.new()
	nation.text = "ESPAÑA"
	nation.add_theme_font_size_override("font_size", 19)
	nation.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.add_child(nation)
	hud._nation_label = nation

	hud._turn_label = Label.new()
	hud._turn_label.text = TurnTime.label_for_turn(1)
	hud._turn_label.add_theme_font_size_override("font_size", 12)
	hud._turn_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	title.add_child(hud._turn_label)
	return title


## The turn's one gold door: the bar's right end, so the chart keeps its corner
## and the turn stays one reach from anywhere (REQ-P1-07, REQ-P5-01). The soft
## glow still marks it as the turn's action without covering the map.
static func _end_turn(hud: GameHud, row: HBoxContainer) -> void:
	EndTurnDoor.build(hud, row)


## One command seal: pictogram over a one-word caption, so the icon carries the
## glance and the word carries first-time discovery without a wide text button.
static func _seal(
	hud: GameHud, icon_kind: String, caption: String, tip: String, action: Callable,
	compact_icon_only: bool = true
) -> Button:
	var button := Button.new()
	button.pressed.connect(action)
	var skin := dress(button, icon_kind, caption, tip, compact_icon_only)
	register_door(hud, button, skin.caption)
	return button


## The four readings share one cartouche seal: a click cycles them, a long press
## names the one you want (REQ-P5-03). The screen mirrors the reading back.
static func _lens_seal(hud: GameHud) -> Button:
	var seal := LensSeal.new()
	seal.name = "LensSeal"
	var skin := dress(seal, "lens", "LENS", LensSeal.TOOLTIP)
	seal.medallion = skin.medallion as TextureRect
	register_door(hud, seal, skin.caption)
	seal.cycle_requested.connect(func() -> void: hud.lens_cycle_pressed.emit())
	seal.lens_chosen.connect(func(kind: String) -> void: hud.lens_selected.emit(kind))
	hud.lens_seal = seal
	return seal


## A door the bar dresses, kept with the caption the compact fit hides. The pause
## menu mounts its own MENU crest after the bar is built, so it registers here
## too instead of the layout walking the row for a caption (REQ-P3-02).
static func register_door(hud: GameHud, button: Button, caption: Label) -> void:
	if hud == null or button == null:
		return
	hud.bar_doors.append({"button": button, "caption": caption, "wide_width": SEAL_SIZE.x})


## Paints a bar door: plaque states, a medallion and a one-word caption. Seals
## that decide their own press behaviour (the lens seal) take the same dress; an
## empty icon kind draws the bar's own vector crest, which the MENU door keeps.
## The parts travel back, so the caller keeps the caption it must hide and the
## medallion a reading repaints (REQ-P3-02).
static func dress(
	button: Button, icon_kind: String, caption: String, tip: String,
	compact_icon_only: bool = true
) -> DoorSkin:
	button.custom_minimum_size = SEAL_SIZE
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override(
		"normal", UiTheme.cartouche(Color(0.13, 0.10, 0.07, 0.58), Color(0.54, 0.43, 0.12, 0.55))
	)
	button.add_theme_stylebox_override(
		"hover", UiTheme.cartouche(Color(0.22, 0.17, 0.11, 0.88), Palette.GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed", UiTheme.cartouche(Color(0.09, 0.07, 0.05, 0.95), Palette.GOLD_PALE)
	)
	button.add_theme_stylebox_override(
		"disabled", UiTheme.cartouche(Color(0.13, 0.10, 0.07, 0.58), Color(0.54, 0.43, 0.12, 0.55))
	)
	button.add_theme_stylebox_override(
		"focus", UiTheme.cartouche(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE)
	)
	if compact_icon_only:
		button.set_meta("compact_icon_only", true)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var skin := DoorSkin.new()
	if icon_kind.is_empty():
		var crest := Icon.new("crest", 22, Palette.GOLD)
		crest.name = "Medallion"
		crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(crest)
		skin.medallion = crest
	else:
		var medallion := TextureRect.new()
		medallion.name = "Medallion"
		medallion.texture = ChromeIcons.texture(icon_kind)
		medallion.custom_minimum_size = Vector2(22, 22)
		medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		medallion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(medallion)
		skin.medallion = medallion

	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	skin.caption = label
	return skin


## Compact cartouche: command doors and status plaques keep their medallions
## (the region keeps its label, because the map's identity is context, not a
## command) and drop their caption words. Values stay visible at every width.
## The doors and plaques hand over the parts they built, so the fit never walks
## the row for a caption or a value column (REQ-P3-02).
static func apply_compact(hud: GameHud, compact: bool) -> void:
	for door: Dictionary in hud.bar_doors:
		var button: Button = door.get("button")
		if button == null or not is_instance_valid(button):
			continue
		var caption: Label = door.get("caption")
		if caption != null:
			caption.visible = not compact
		button.custom_minimum_size.x = (
			40.0 if compact else float(door.get("wide_width", SEAL_SIZE.x))
		)
	if hud.stats != null:
		hud.stats.apply_compact(compact)
