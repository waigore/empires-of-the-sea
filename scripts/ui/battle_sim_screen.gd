class_name BattleSimScreen
extends Control
## Visual Battle Simulator: a playtesting instrument over the live Quick Battle
## rules. The setup rail hands a spec to [BattleScenario], which runs the same
## resolver a game turn runs; this screen only paints the record it gets back
## (REQ-P2-03, REQ-P3-03). Launch:
##   tools/run.sh scenes/battle_sim.tscn

const NAMES: Array[String] = ["The Attack", "The Garrison"]

var _setup: BattleSimSetup = null
var _field: QuickBattleField = null
var _header: Label = null
var _status: Label = null
var _log: Label = null
var _readout: Label = null
var _round_buttons: HBoxContainer = null
var _result: Dictionary = {}
var _cursor: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.05, 0.04)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	_setup = BattleSimSetup.new()
	row.add_child(_setup)
	_setup.run_requested.connect(_fight)
	_setup.step_requested.connect(_step)
	_setup.reset_requested.connect(_reset)
	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 6)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(centre)
	_build_centre(centre)
	row.add_child(_build_log_panel())


func _build_centre(column: VBoxContainer) -> void:
	_header = _label("", 15, Palette.GOLD_PALE)
	column.add_child(_header)
	_field = QuickBattleField.new()
	_field.custom_minimum_size = Vector2(0, 220)
	_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_field)
	_status = _label("Ready — set the ground, the fort and the men, then Fight.", 12, Palette.TEXT)
	column.add_child(_status)
	_round_buttons = HBoxContainer.new()
	_round_buttons.add_theme_constant_override("separation", 6)
	column.add_child(_round_buttons)
	for index in QuickBattle.MAX_ROUNDS:
		var button := Button.new()
		button.text = "Round %s" % QuickBattleCopy.roman(index + 1)
		button.pressed.connect(_show_round.bind(index))
		button.disabled = true
		_round_buttons.add_child(button)
	var aftermath := Button.new()
	aftermath.text = "Aftermath"
	aftermath.pressed.connect(_show_aftermath)
	aftermath.disabled = true
	_round_buttons.add_child(aftermath)


func _build_log_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.09, 0.07, 0.05, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(10, 8, 10, 8))
	)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	column.add_child(_label("DESPATCHES", 13, Palette.GOLD))
	_readout = _label("", 11, Palette.TEXT_DIM)
	column.add_child(_readout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_log = _label("", 12, Palette.TEXT)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)
	return panel


# --- intents -----------------------------------------------------------------


func _fight() -> void:
	_run()
	_show_aftermath()


func _step() -> void:
	if _result.is_empty():
		_run()
		_show_round(0)
		return
	_cursor += 1
	if _cursor >= _rounds().size():
		## Stepping past the aftermath starts the plate over, so a playtester can
		## walk the same record again without re-resolving it.
		_show_round(0)
		return
	_show_round(_cursor)


func _reset() -> void:
	_result = {}
	_cursor = 0
	_log.text = ""
	_status.text = "Reset — set the ground, the fort and the men, then Fight."
	_header.text = "No battle yet"
	_field.set_battle({})
	_field.attacker_count = 0
	_field.defender_count = 0
	_field.queue_redraw()
	_set_round_buttons(false)
	_readout.text = ""


## Resolves the current setup through BattleScenario and writes the full
## despatch. Returns false when the setup produced no usable battle.
func _run() -> bool:
	_result = BattleScenario.fight(_setup.spec())
	var report: Dictionary = _result["report"]
	_cursor = 0
	## The plate reads the record once: ground, wall and gates come from it.
	_field.set_battle(report)
	var quick: Dictionary = report["quick"] as Dictionary
	_header.text = "%s vs %s — %s · %s" % [
		NAMES[0], NAMES[1], FortRules.describe(int(report.get("fort_level", 0))),
		String(quick.get("terrain_label", "Open field")),
	]
	_readout.text = _rules_text(report)
	_log.text = _despatch(report)
	_set_round_buttons(true)
	_status_for_round(report, 0)
	return true


func _status_for_round(report: Dictionary, index: int) -> void:
	var rounds: Array = _rounds()
	if index < 0 or index >= rounds.size():
		_status.text = "No rounds were fought."
		return
	var entry: Dictionary = rounds[index] as Dictionary
	_status.text = "Round %s — %d attackers, %d defenders, %d guns, %d of 3 gates breached." % [
		QuickBattleCopy.roman(index + 1),
		int(entry.get("attacker_count", 0)), int(entry.get("defender_count", 0)),
		int(entry.get("guns", 0)), int(entry.get("gates", 0)),
	]


# --- presentation ------------------------------------------------------------


func _show_round(index: int) -> void:
	if _result.is_empty():
		_run()
	var report: Dictionary = _result["report"]
	var rounds: Array = _rounds()
	if index < 0 or index >= rounds.size():
		_show_aftermath()
		return
	_cursor = index
	var entry: Dictionary = rounds[index] as Dictionary
	_field.set_round(
		index, int(entry.get("attacker_count", 0)), int(entry.get("defender_count", 0)),
		int(entry.get("guns", 0)), entry.get("attacker_health", []) as Array,
		entry.get("defender_health", []) as Array, int(entry.get("gates", 0))
	)
	_status_for_round(report, index)


func _show_aftermath() -> void:
	if _result.is_empty():
		return
	var report: Dictionary = _result["report"]
	var quick: Dictionary = report["quick"] as Dictionary
	_field.attacker_count = int(quick.get("attacker_left", 0))
	_field.defender_count = int(quick.get("defender_left", 0))
	_field.guns = int(quick.get("guns_left", 0))
	_field.gates_broken = int(quick.get("breaches", 0))
	_field.attacker_health = report.get("attacker_health", []) as Array
	_field.defender_health = report.get("defender_health", []) as Array
	_field.round_index = 3
	_field.set_outcome(int(report.get("outcome", 0)))
	_status.text = QuickBattleCopy.outcome_text(
		int(report.get("outcome", 0)), report, "the sandbox", NAMES
	)
	_cursor = _rounds().size()


func _set_round_buttons(enabled: bool) -> void:
	for child: Node in _round_buttons.get_children():
		(child as Button).disabled = not enabled


## Every action's despatch plus the aftermath lines the game plate prints.
func _despatch(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for round: Dictionary in _rounds():
		lines.append("— ROUND %s —" % QuickBattleCopy.roman(int(round.get("round", 1))))
		for action: Dictionary in round.get("actions", []) as Array:
			lines.append(QuickBattleCopy.action_line(action, report, NAMES))
	var tail: PackedStringArray = PackedStringArray()
	for text: String in [
		QuickBattleCopy.terrain_line(report),
		QuickBattleCopy.siege_line(report),
		QuickBattleCopy.loss_line(report, NAMES),
		QuickBattleCopy.health_line(report, NAMES),
		QuickBattleCopy.chevron_line(report, NAMES),
	]:
		if not text.is_empty():
			tail.append(text)
	if not tail.is_empty():
		lines.append("— AFTERMATH —")
		lines.append_array(tail)
	lines.append("— OUTCOME —")
	lines.append(QuickBattleCopy.outcome_text(
		int(report.get("outcome", 0)), report, "the sandbox", NAMES
	))
	return "\n".join(lines)


## The numbers behind the plate: what the ground, the wall and the gates do.
func _rules_text(report: Dictionary) -> String:
	var quick: Dictionary = report["quick"] as Dictionary
	var terrain: String = String(quick.get("terrain", "open"))
	var limits: Dictionary = quick.get("limits", {}) as Dictionary
	var text: String = "Deployment %d / %d a side · 3 CP a round\n" % [
		int(limits.get("attacker", ArmyModifiers.BASE_DEPLOYMENT)),
		int(limits.get("defender", ArmyModifiers.BASE_DEPLOYMENT)),
	]
	text += "Ground %s — volley ×%.2f, assault ×%.2f, entrench ×%.2f\n" % [
		SiegeLanes.terrain_label(terrain), SiegeLanes.terrain_scale("volley", terrain),
		SiegeLanes.terrain_scale("assault", terrain), SiegeLanes.entrench_scale(terrain),
	]
	var level: int = int(report.get("fort_level", 0))
	if level > 0:
		text += "Walls spare %d%% · %d guns\n" % [
			roundi(FortRules.damage_reduction(level) * 100.0), int(quick.get("guns_start", 0)),
		]
		text += "3 gates · one breaches every %d wall casualties\n" % SiegeLanes.breach_threshold(level)
		text += "Lanes: %d wall, %d behind\n" % [
			int((quick.get("lanes", {}) as Dictionary).get("wall", 0)),
			int((quick.get("lanes", {}) as Dictionary).get("behind", 0)),
		]
		text += "Gates breached: %d of 3" % int(quick.get("breaches", 0))
	return text


func _rounds() -> Array:
	return ((_result.get("report", {}) as Dictionary).get("quick", {}) as Dictionary).get(
		"rounds", []
	) as Array


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.serif())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
