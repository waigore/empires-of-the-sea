class_name NavalPlate
extends Control
## The sea's despatch: a painted stretch of water, both colours' hulls standing
## on it as their own medallions, and the engagement told in four beats — the
## meeting, the maths, the losses, what the sea decided (wiki: ships-and-naval
## § Naval Combat Resolution). Presentation only: every number and name is read
## from the resolver's record through [NavalDispatch] (REQ-P2-03). Skippable on
## one tap so the report never holds the court (REQ-P5-06).

signal finished

const BEAT_SECONDS: float = 0.95
const LOG_LINES: int = 3
const SEA_ART: String = "res://assets/art/battle/sea_open.jpg"
const MEDALLION_MIN: float = 22.0
const MEDALLION_MAX: float = 36.0

var battle: Dictionary = {}
var zone_name: String = ""
var faction_names: Array = []

var _panel: PanelContainer = null
var _headline: Label = null
var _atk_name: Label = null
var _def_name: Label = null
var _atk_bar: ProgressBar = null
var _def_bar: ProgressBar = null
var _log: VBoxContainer = null
var _outcome: Label = null
var _continue: Button = null
var _skip: Button = null
var _tween: Tween = null
var _shown: bool = false
var _finished: bool = false
var _beats_shown: int = 0
## The sea band's two lines of hulls, attacker then defender (tests read them).
var _rows: Array[HBoxContainer] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_build()
	visible = false


## Opens the plate on one engagement, as the land plate opens on its battle.
func show_engagement(p_battle: Dictionary, p_zone: String, p_names: Array) -> void:
	battle = p_battle
	zone_name = p_zone
	faction_names = p_names
	_shown = true
	_finished = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_reset()
	_populate()
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.18)
	_play()


func is_shown() -> bool:
	return _shown


## One tap tells the whole despatch (REQ-P5-06).
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not _finished:
		_finish()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.74)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.08, 0.08, 0.07, 0.97), Palette.GOLD, 2, 6, Vector4(16, 12, 16, 12))
	)
	margin.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_build_header(column)
	_build_sea(column)
	_build_bars(column)
	_build_log(column)
	_build_footer(column)


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	header.add_child(_label("A DESPATCH FROM THE SEA", 22, Palette.GOLD_PALE))
	_headline = _label("", 14, Palette.TEXT)
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_headline)
	_skip = Button.new()
	_skip.text = "Skip"
	_skip.tooltip_text = "Tell the whole despatch at once"
	_skip.pressed.connect(skip)
	header.add_child(_skip)


## The painted water with one line per colour standing on the band below the
## painting's horizon; each line is its own name followed by a medallion per
## type and the number that flew (REQ-P1-08).
func _build_sea(column: VBoxContainer) -> void:
	var sea := Control.new()
	sea.custom_minimum_size = Vector2(0, 132)
	sea.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sea.size_flags_stretch_ratio = 3.0
	sea.clip_contents = true
	column.add_child(sea)
	var art := TextureRect.new()
	if ResourceLoader.exists(SEA_ART):
		art.texture = load(SEA_ART)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sea.add_child(art)
	var band := MarginContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		band.add_theme_constant_override("margin_" + edge, 8)
	sea.add_child(band)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.alignment = BoxContainer.ALIGNMENT_END
	band.add_child(lines)
	for _side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		lines.add_child(row)
		_rows.append(row)


func _build_bars(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_atk_name = _label("", 13, Palette.TEXT)
	_atk_name.custom_minimum_size = Vector2(140, 0)
	_atk_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_atk_name)
	_atk_bar = _bar()
	row.add_child(_atk_bar)
	_def_bar = _bar()
	_def_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	row.add_child(_def_bar)
	_def_name = _label("", 13, Palette.TEXT)
	_def_name.custom_minimum_size = Vector2(140, 0)
	_def_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_def_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_def_name)


func _build_log(column: VBoxContainer) -> void:
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)


func _build_footer(column: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_outcome = _label("", 20, Palette.GOLD_PALE)
	_outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_outcome)
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.custom_minimum_size = Vector2(140, 0)
	_continue.pressed.connect(_on_continue)
	_continue.visible = false
	footer.add_child(_continue)


func _populate() -> void:
	_headline.text = NavalDispatch.headline(battle, zone_name, faction_names)
	var index: int = 0
	for side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		if index < _rows.size():
			_fill_row(_rows[index], side)
		index += 1
		var owner: int = _owner(side)
		var who: Label = _atk_name if side == NavalDispatch.ATTACKER else _def_name
		var bar: ProgressBar = _atk_bar if side == NavalDispatch.ATTACKER else _def_bar
		who.text = "%s · %s" % [
			NavalDispatch.name_of(faction_names, owner), _hull_text(side)
		]
		who.add_theme_color_override("font_color", Palette.faction_color(owner))
		bar.max_value = maxi(NavalDispatch.strength(battle, side), 1)
		bar.value = bar.max_value
		bar.add_theme_stylebox_override(
			"fill", UiTheme.box(Palette.faction_color(owner), Palette.faction_color(owner).lightened(0.25),
			1, 3, Vector4.ZERO)
		)


## One colour's line on the water: its name, then a medallion per hull type.
func _fill_row(row: HBoxContainer, side: String) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var owner: int = _owner(side)
	row.add_child(_label(NavalDispatch.name_of(faction_names, owner), 13,
		Palette.faction_color(owner)))
	for group: Dictionary in NavalDispatch.groups(battle, side):
		row.add_child(_medal_chip(String(group["type"]), int(group["count"])))
	if row.get_child_count() == 1:
		row.add_child(_label("%d hulls" % NavalDispatch.hull_count(battle, side), 12,
			Palette.TEXT_DIM))


## The two lines of hulls the sea band is drawing, for tests and tooling.
func side_lines() -> Array[HBoxContainer]:
	return _rows


## "6 hulls — 4 Galleon and 2 Sloop", or just "4 Carrack" when she flew one type.
func _hull_text(side: String) -> String:
	var groups: String = NavalDispatch.groups_text(battle, side)
	var count: int = NavalDispatch.hull_count(battle, side)
	if groups.is_empty():
		return "%d %s" % [count, "hull" if count == 1 else "hulls"]
	if NavalDispatch.groups(battle, side).size() == 1:
		return groups
	return "%d hulls — %s" % [count, groups]


## A hull type's medallion and how many of her flew; art is the catalogue's own
## (ShipArt), so a Frigate never reads as a Fluyte (REQ-P1-08).
func _medal_chip(type_id: String, count: int) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	var size: float = clampf((_panel.size.x if _panel != null else 0.0) / 18.0,
		MEDALLION_MIN, MEDALLION_MAX)
	chip.tooltip_text = "%d %s" % [count, ShipStats.display_name(type_id)]
	var tex: Texture2D = ShipArt.medallion(type_id)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.custom_minimum_size = Vector2(size, size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
	var tally := _label("×%d" % count, 12, Palette.TEXT)
	tally.custom_minimum_size = Vector2(0, size)
	tally.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(tally)
	return chip


func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	_beats_shown = 0
	_outcome.text = ""
	_continue.visible = false
	_skip.visible = true


## The despatch is read one beat at a time, then the verdict stamps down.
func _play() -> void:
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	if beats.is_empty():
		_finish()
		return
	_tween = create_tween()
	for index in beats.size():
		_tween.tween_callback(_add_beat.bind(index))
		_tween.tween_interval(BEAT_SECONDS)
	_tween.tween_callback(_finish)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	while _beats_shown < beats.size():
		_add_beat(_beats_shown)
	_set_survivors()
	_outcome.text = NavalDispatch.outcome_text(battle, zone_name, faction_names)
	var settled: bool = int(battle.get("outcome", NavalCombat.Outcome.STALEMATE)) \
		!= NavalCombat.Outcome.STALEMATE
	_outcome.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if settled else Color(0.86, 0.60, 0.52)
	)
	_outcome.pivot_offset = _outcome.size * 0.5
	_outcome.scale = Vector2(0.7, 0.7)
	_skip.visible = false
	_continue.visible = true
	var stamp: Tween = create_tween()
	stamp.tween_property(_outcome, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)


## The bars keep the hulls each colour carried out: the beaten side's are gone
## unless she slipped away, and a retreat takes every hull she still had.
func _set_survivors() -> void:
	var fled: bool = bool((battle.get("retreat", {}) as Dictionary).get("success", false))
	for side: String in [NavalDispatch.ATTACKER, NavalDispatch.DEFENDER]:
		var before: int = NavalDispatch.hull_count(battle, side)
		var lost: int = (battle.get(side + "_lost", []) as Array).size()
		var bar: ProgressBar = _atk_bar if side == NavalDispatch.ATTACKER else _def_bar
		bar.max_value = maxi(before, 1)
		bar.value = before if fled and lost == 0 else maxi(before - lost, 0)


func _on_continue() -> void:
	_shown = false
	visible = false
	finished.emit()


func _add_beat(index: int) -> void:
	var beats: Array[String] = NavalDispatch.beats(battle, zone_name, faction_names)
	if index < 0 or index >= beats.size() or index < _beats_shown:
		return
	_beats_shown = index + 1
	var line := _label(beats[index], 12, Palette.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(line)
	while _log.get_child_count() > LOG_LINES:
		var oldest: Node = _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()


func _owner(side: String) -> int:
	return int(battle.get(side, 0))


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override(
		"background",
		UiTheme.box(Color(0.17, 0.14, 0.10), Palette.INK_LINE, 1, 3, Vector4(0, 0, 0, 0))
	)
	return bar
