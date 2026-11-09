class_name QuickBattleOverlay
extends Control
## The Quick Battle plate: a bright animated field, round-by-round despatches and
## a decisive outcome stamp. Presentation only — it replays the report the rules
## resolver produced and never changes it (REQ-P2-03). Skippable with one tap so
## the juice stays non-modal (REQ-P5-06).

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
	row.add_child(_def_name)
	_def_bar = _bar(Palette.NAVY)
	row.add_child(_def_bar)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	column.add_child(pips)
	pips.add_child(_label("ROUNDS", 11, Palette.TEXT_DIM))
	for index in 3:
		var pip := _label(_roman(index + 1), 13, Palette.TEXT_DIM)
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
	_atk_name.text = _faction(attacker)
	_def_name.text = _faction(defender)
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
	_plan_label.text = "Plan: %s" % String(quick.get("plan", "balanced")).capitalize()
	if int(quick.get("guns_start", 0)) > 0:
		_plan_label.text += " · %d guns" % int(quick.get("guns_start", 0))
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
		int(round.get("guns", 0))
	)
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(round.get("attacker_count", 0)), int(round.get("defender_count", 0))
	)
	_round_label.text = "ROUND %s" % _roman(index + 1)
	if index < _pips.size():
		_pips[index].add_theme_color_override("font_color", Palette.GOLD_PALE)
	for action: Dictionary in round.get("actions", []):
		_add_log(_action_line(action))


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_round_label.text = "AFTERMATH"
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	_set_bars(
		int(quick.get("attacker_start", 1)), int(quick.get("defender_start", 1)),
		int(quick.get("attacker_left", 0)), int(quick.get("defender_left", 0))
	)
	var outcome: int = int(battle.get("outcome", ArmyCombat.Outcome.STALEMATE))
	field.set_outcome(outcome)
	_outcome.text = _outcome_text(outcome)
	var won: bool = _player_won(outcome)
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


func _action_line(action: Dictionary) -> String:
	var owner: int = int(action.get("side", 0))
	var label: String = String(action.get("label", "Action"))
	var text: String = "%s — %s" % [_faction(owner), label]
	var lost: int = int(action.get("attacker_lost", 0))
	if String(action.get("action", "")) == "battery":
		lost = int(action.get("attacker_lost", 0))
	elif owner == int(battle.get("defender", -1)):
		lost = int(action.get("defender_lost", 0))
	if lost > 0:
		text += " · %d lost" % lost
	var guns: int = int(action.get("guns_destroyed", 0))
	if guns > 0:
		text += " · %d gun%s silenced" % [guns, "" if guns == 1 else "s"]
	return text


func _add_log(text: String) -> void:
	var line := _label(text, 12, Palette.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(line)
	while _log.get_child_count() > LOG_LINES:
		var oldest: Node = _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()


func _set_bars(atk_start: int, def_start: int, atk: int, def_now: int) -> void:
	_atk_bar.max_value = maxi(atk_start, 1)
	_atk_bar.value = atk
	_def_bar.max_value = maxi(def_start, 1)
	_def_bar.value = def_now
	_atk_name.text = "%s  %d" % [_faction(int(battle.get("attacker", 0))), atk]
	_def_name.text = "%d  %s" % [def_now, _faction(int(battle.get("defender", 1)))]


func _outcome_text(outcome: int) -> String:
	var attacker: String = _faction(int(battle.get("attacker", 0)))
	var defender: String = _faction(int(battle.get("defender", 1)))
	match outcome:
		ArmyCombat.Outcome.ATTACKER_VICTORY:
			return "%s takes %s" % [attacker, province_name]
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			return "%s holds the field — %s keeps %s" % [attacker, defender, province_name]
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			return "%s holds %s" % [defender, province_name]
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			return "Mutual ruin — both sides are broken"
		ArmyCombat.Outcome.CAPTURE:
			return "%s occupies %s unopposed" % [attacker, province_name]
	return "%s and %s stand off" % [attacker, defender]


func _player_won(outcome: int) -> bool:
	var player: int = int(battle.get("player_faction", -1))
	var winner: int = -1
	if outcome in [
		ArmyCombat.Outcome.ATTACKER_VICTORY,
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
		ArmyCombat.Outcome.CAPTURE,
	]:
		winner = int(battle.get("attacker", -1))
	elif outcome == ArmyCombat.Outcome.DEFENDER_VICTORY:
		winner = int(battle.get("defender", -1))
	return player >= 0 and winner == player


func _faction(owner: int) -> String:
	if owner < 0 or owner >= faction_names.size():
		return "An unknown flag"
	return String(faction_names[owner])


func _roman(value: int) -> String:
	var numerals: Array[String] = ["I", "II", "III", "IV", "V"]
	return numerals[clampi(value - 1, 0, numerals.size() - 1)]


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