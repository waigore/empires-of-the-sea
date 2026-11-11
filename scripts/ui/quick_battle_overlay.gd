class_name QuickBattleOverlay
extends Control
## The Quick Battle plate: a bright animated field, round-by-round despatches and
## a decisive outcome stamp. Presentation only — it replays the report the rules
## resolver produced and never changes it (REQ-P2-03). Despatch copy lives in
## [QuickBattleCopy]. Skippable with one tap so the juice stays non-modal
## (REQ-P5-06, REQ-P3-01).

signal finished

const ROUND_SECONDS: float = 1.15
const LOG_LINES: int = 3

var battle: Dictionary = {}
var province_name: String = ""
var faction_names: Array = []

var field: QuickBattleField = null
var _panel: PanelContainer = null
var _title: Label = null
var _province: Label = null
var _round_label: Label = null
var _outcome: Label = null
var _atk_name: Label = null
var _def_name: Label = null
var _atk_bar: ProgressBar = null
var _def_bar: ProgressBar = null
var _plan_label: Label = null
var _log: VBoxContainer = null
var _continue: Button = null
var _skip: Button = null
var _pips: Array[Label] = []
var _tween: Tween = null
var _shown: bool = false
var _finished: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_build()
	visible = false


func show_battle(p_battle: Dictionary, p_province: String, p_names: Array) -> void:
	battle = p_battle
	province_name = p_province
	faction_names = p_names
	_shown = true
	_finished = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_reset()
	field.set_battle(battle)
	_populate()
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.18)
	_play()


func is_shown() -> bool:
	return _shown


func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _finished:
		return
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if not rounds.is_empty():
		_enter_round(rounds.size() - 1)
	_finish()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.04, 0.03, 0.74)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.09, 0.07, 0.05, 0.97), Palette.GOLD, 2, 6, Vector4(16, 12, 16, 12))
	)
	margin.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_build_header(column)
	_build_field(column)
	_build_bars(column)
	_build_log(column)
	_build_footer(column)


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_title = _label("QUICK BATTLE", 24, Palette.GOLD_PALE)
	header.add_child(_title)
	_province = _label("", 16, Palette.TEXT)
	_province.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_province)
	_round_label = _label("", 13, Palette.GOLD)
	header.add_child(_round_label)
	_skip = Button.new()
	_skip.text = "Skip"
	_skip.tooltip_text = "Skip the animation"
	_skip.pressed.connect(skip)
	header.add_child(_skip)


func _build_field(column: VBoxContainer) -> void:
	field = QuickBattleField.new()
	field.custom_minimum_size = Vector2(0, 140)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.size_flags_stretch_ratio = 3.0
	column.add_child(field)


func _build_bars(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_atk_name = _label("", 13, Palette.TEXT)
	_atk_name.custom_minimum_size = Vector2(120, 0)
	row.add_child(_atk_name)
	_atk_bar = _bar(Palette.CRIMSON)
	row.add_child(_atk_bar)
	_def_name = _label("", 13, Palette.TEXT)
	_def_name.custom_minimum_size = Vector2(120, 0)
	_def_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_def_bar = _bar(Palette.NAVY)
	row.add_child(_def_bar)
	row.add_child(_def_name)
	_def_bar.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	column.add_child(pips)
	pips.add_child(_label("ROUNDS", 11, Palette.TEXT_DIM))
	for index in 3:
		var pip := _label(QuickBattleCopy.roman(index + 1), 13, Palette.TEXT_DIM)
		_pips.append(pip)
		pips.add_child(pip)
	_plan_label = _label("", 11, Palette.TEXT_DIM)
	_plan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pips.add_child(_plan_label)


func _build_log(column: VBoxContainer) -> void:
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)


func _build_footer(column: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_outcome = _label("", 22, Palette.GOLD_PALE)
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
	var attacker: int = int(battle.get("attacker", 0))
	var defender: int = int(battle.get("defender", 1))
	_province.text = province_name
	_atk_name.text = QuickBattleCopy.faction(attacker, faction_names)
	_def_name.text = QuickBattleCopy.faction(defender, faction_names)
	_atk_name.add_theme_color_override("font_color", Palette.faction_color(attacker))
	_def_name.add_theme_color_override("font_color", Palette.faction_color(defender))
	var atk_color: Color = Palette.faction_color(attacker)
	var def_color: Color = Palette.faction_color(defender)
	_atk_bar.add_theme_stylebox_override(
		"fill", UiTheme.box(atk_color, atk_color.lightened(0.25), 1, 3, Vector4.ZERO)
	)
	_def_bar.add_theme_stylebox_override(
		"fill", UiTheme.box(def_color, def_color.lightened(0.25), 1, 3, Vector4.ZERO)
	)
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_plan_label.text = QuickBattleCopy.plan_text(battle)
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1))
	)
	_round_label.text = ""


func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	for pip: Label in _pips:
		pip.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_outcome.text = ""
	_continue.visible = false
	_skip.visible = true


func _play() -> void:
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if rounds.is_empty():
		_finish()
		return
	_tween = create_tween()
	for index in rounds.size():
		_tween.tween_callback(_enter_round.bind(index))
		_tween.tween_interval(ROUND_SECONDS)
	_tween.tween_callback(_finish)


func _enter_round(index: int) -> void:
	var rounds: Array = (battle.get("quick", {}) as Dictionary).get("rounds", []) as Array
	if index < 0 or index >= rounds.size():
		return
	var round: Dictionary = rounds[index] as Dictionary
	field.set_round(
		index,
		int(round.get("attacker_count", 0)),
		int(round.get("defender_count", 0)),
		int(round.get("guns", 0)),
		round.get("attacker_health", []) as Array,
		round.get("defender_health", []) as Array,
		int(round.get("gates", 0))
	)
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(round.get("attacker_count", 0)), int(round.get("defender_count", 0)),
		float(round.get("attacker_strength", 1.0)),
		float(round.get("defender_strength", 1.0))
	)
	_round_label.text = "ROUND %s" % QuickBattleCopy.roman(index + 1)
	if index < _pips.size():
		_pips[index].add_theme_color_override("font_color", Palette.GOLD_PALE)
	for action: Dictionary in round.get("actions", []):
		_add_log(QuickBattleCopy.action_line(action, battle, faction_names))
		_show_hits(action)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_round_label.text = "AFTERMATH"
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var atk_left: int = int(quick.get("attacker_left", 0))
	var def_left: int = int(quick.get("defender_left", 0))
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		atk_left, def_left,
		_average(battle.get("attacker_health", []) as Array, atk_left),
		_average(battle.get("defender_health", []) as Array, def_left)
	)
	var outcome: int = int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE))
	field.set_outcome(outcome)
	# The final field carries the aftermath, not another round's animation.
	field.attacker_count = atk_left
	field.defender_count = def_left
	field.guns = int(quick.get("guns_left", 0))
	field.attacker_health = battle.get("attacker_health", []) as Array
	field.defender_health = battle.get("defender_health", []) as Array
	field.queue_redraw()
	_outcome.text = QuickBattleCopy.outcome_text(
		outcome, battle, province_name, faction_names
	)
	# Ground, the line, walls and named dead: told, never silently written back
	# (REQ-P5-05).
	var lines: Array[String] = [
		QuickBattleCopy.terrain_line(battle),
		QuickBattleCopy.line_line(battle, faction_names),
		QuickBattleCopy.loss_line(battle, faction_names),
		QuickBattleCopy.health_line(battle, faction_names),
		QuickBattleCopy.chevron_line(battle, faction_names),
		QuickBattleCopy.siege_line(battle),
	]
	for text: String in lines:
		if not text.is_empty():
			_add_log(text)
	var won: bool = QuickBattleCopy.player_won(outcome, battle)
	_outcome.add_theme_color_override(
		"font_color", Palette.GOLD_PALE if won else Color(0.86, 0.60, 0.52)
	)
	_outcome.pivot_offset = _outcome.size * 0.5
	_outcome.scale = Vector2(0.7, 0.7)
	_skip.visible = false
	_continue.visible = true
	var stamp: Tween = create_tween()
	stamp.tween_property(_outcome, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK)


func _on_continue() -> void:
	_shown = false
	visible = false
	finished.emit()


func _add_log(text: String) -> void:
	var line := _label(text, 12, Palette.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(line)
	while _log.get_child_count() > LOG_LINES:
		var oldest: Node = _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()


func _set_bars(
	atk_start: int, def_start: int, atk: int, def_now: int,
	atk_fraction: float = 1.0, def_fraction: float = 1.0
) -> void:
	_atk_bar.max_value = maxi(atk_start, 1)
	_atk_bar.value = atk
	_def_bar.max_value = maxi(def_start, 1)
	_def_bar.value = def_now
	_atk_name.text = "%s  %d · %d%%" % [
		QuickBattleCopy.faction(int(battle.get("attacker", 0)), faction_names), atk,
		roundi(atk_fraction * 100.0)
	]
	_def_name.text = "%d · %d%%  %s" % [
		def_now, roundi(def_fraction * 100.0),
		QuickBattleCopy.faction(int(battle.get("defender", 1)), faction_names)
	]


## Floats the damage an action dealt (and took) over the side it struck.
func _show_hits(action: Dictionary) -> void:
	var actor: int = int(action.get("side", -1))
	var acting: String = "attacker" if actor == int(battle.get("attacker", 0)) else "defender"
	var hurt: String = "defender" if acting == "attacker" else "attacker"
	var hits: Array = action.get("hits", []) as Array
	if not hits.is_empty():
		field.add_hits(hurt, hits, Palette.faction_color(int(battle.get(hurt, 0))))
	var own: Array = action.get("own_hits", []) as Array
	if not own.is_empty():
		field.add_hits(acting, own, Palette.faction_color(actor))


## Mean health of a side; a side left with no regiments reads zero, one whose
## record predates condition tracking reads full.
func _average(entries: Array, count: int) -> float:
	if entries.is_empty():
		return 1.0 if count > 0 else 0.0
	var total: float = 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("fraction", 1.0))
	return total / float(entries.size())


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override(
		"background", UiTheme.box(Color(0.17, 0.14, 0.10), Palette.INK_LINE, 1, 3, Vector4(0, 0, 0, 0))
	)
	bar.add_theme_stylebox_override(
		"fill", UiTheme.box(color, color.lightened(0.25), 1, 3, Vector4(0, 0, 0, 0))
	)
	return bar
