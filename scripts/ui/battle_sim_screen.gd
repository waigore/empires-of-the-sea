class_name BattleSimScreen
extends Control
## Visual Battle Simulator: a playtesting instrument over the live Quick Battle
## rules. Setup rail, layout chrome, despatch copy and round playback each own a
## module; this screen only wires intents to [BattleScenario] and paints the
## record it gets back (REQ-P2-03, REQ-P3-01, REQ-P3-03). Launch:
##   tools/run.sh scenes/battle_sim.tscn

const NAMES: Array[String] = ["The Attack", "The Garrison"]
## The province the sandbox fights over, named wherever a plate names one.
const SANDBOX: String = "the sandbox"
## The instrument stacks on a screen too narrow for three columns — the rail on
## top, the plate, then the despatches — and scrolls rather than clipping, so a
## phone or a tablet reads the whole sandbox (REQ-P1-05, REQ-P5-07).
const STACK_BELOW: float = 900.0
const RAIL_MIN: float = 240.0
const LOG_MIN: float = 180.0
const FIELD_MIN: float = 160.0

var _setup: BattleSimSetup = null
var _field: QuickBattleField = null
var _header: Label = null
var _status: Label = null
var _log: Label = null
var _readout: Label = null
## The round doors wrap rather than widen the plate, so a handset can still
## step the record (REQ-P1-05).
var _round_buttons: HFlowContainer = null
var _result: Dictionary = {}
var _cursor: int = 0
var _margin: MarginContainer = null
## The column the three panels ride: an HBox on a wide screen, a scrolling VBox
## on a handset.
var _row: Container = null
var _centre: VBoxContainer = null
var _log_panel: PanelContainer = null
var _stacked: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.05, 0.04)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 12)
	add_child(_margin)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_margin.add_child(_row)
	_setup = BattleSimSetup.new()
	_row.add_child(_setup)
	_setup.run_requested.connect(_fight)
	_setup.step_requested.connect(_step)
	_setup.reset_requested.connect(_reset)
	_centre = VBoxContainer.new()
	_centre.add_theme_constant_override("separation", 6)
	_centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_centre)
	var centre: Dictionary = BattleSimLayout.build_centre(_centre)
	_header = centre["header"] as Label
	_field = centre["field"] as QuickBattleField
	_status = centre["status"] as Label
	_round_buttons = centre["round_buttons"] as HFlowContainer
	for index in QuickBattle.MAX_ROUNDS:
		(_round_buttons.get_child(index) as Button).pressed.connect(_show_round.bind(index))
	(_round_buttons.get_child(QuickBattle.MAX_ROUNDS) as Button).pressed.connect(_show_aftermath)
	var log_bits: Dictionary = BattleSimLayout.build_log_panel()
	_log_panel = log_bits["panel"] as PanelContainer
	_readout = log_bits["readout"] as Label
	_log = log_bits["log"] as Label
	_row.add_child(_log_panel)
	resized.connect(_relayout)
	_relayout()


## One column on a handset, three on a desktop: the panels are re-seated rather
## than rebuilt, so a resize never loses the setup or the record.
func _relayout() -> void:
	if size.x <= 1.0:
		return
	var stacked: bool = size.x < STACK_BELOW
	if stacked != _stacked:
		_stacked = stacked
		_row = BattleSimLayout.restack(
			_margin, _row, _stacked, [_setup, _centre, _log_panel]
		)
	BattleSimLayout.apply_stack(
		_setup, _field, _log_panel, _stacked, RAIL_MIN, LOG_MIN, FIELD_MIN
	)


# --- intents -----------------------------------------------------------------


func _fight() -> void:
	if _run():
		_show_aftermath()


func _step() -> void:
	if _result.is_empty():
		if _run():
			_show_round(0)
		return
	if _cursor + 1 < _rounds().size():
		_show_round(_cursor + 1)
		return
	if _cursor < _rounds().size():
		## Stepping on from the last round shows the aftermath, so the outcome is
		## the walk's own end and not a second button's secret (REQ-P2-03).
		_show_aftermath()
		return
	## Stepping past the aftermath starts the plate over, so a playtester can
	## walk the same record again without re-resolving it.
	_show_round(0)


func _reset() -> void:
	_result = {}
	_cursor = 0
	_log.text = ""
	_status.text = "Reset — set the ground, the fort and the men, then Fight."
	_header.text = "No battle yet"
	BattleSimPlayback.reset_field(_field)
	BattleSimPlayback.set_round_buttons(_round_buttons, false, 0)
	_readout.text = ""


## Resolves the current setup through BattleScenario and writes the full
## despatch. Returns false when the rail fields no men on a side: the sandbox
## fights the army it shows, and says which side is empty rather than inventing
## one (REQ-P2-03).
func _run() -> bool:
	var spec: Dictionary = _setup.spec()
	var empty: String = BattleSimDespatch.empty_side(spec, NAMES)
	if not empty.is_empty():
		_status.text = "%s fields no men — give a slot a count." % empty
		return false
	_result = BattleScenario.fight(spec)
	var report: Dictionary = _result["report"]
	_cursor = 0
	## The plate reads the record once: ground, wall and gates come from it.
	_field.set_battle(report)
	_header.text = BattleSimDespatch.header(report, NAMES)
	_readout.text = BattleSimDespatch.rules_text(report)
	_log.text = BattleSimDespatch.full(report, NAMES, SANDBOX)
	BattleSimPlayback.set_round_buttons(_round_buttons, true, _rounds().size())
	_status.text = BattleSimDespatch.status_for_round(report, 0)
	return true


# --- presentation ------------------------------------------------------------


func _show_round(index: int) -> void:
	if _result.is_empty():
		return
	var report: Dictionary = _result["report"]
	var painted: Dictionary = BattleSimPlayback.show_round(_field, report, index, NAMES)
	if not bool(painted.get("ok", false)):
		_show_aftermath()
		return
	_cursor = int(painted["cursor"])
	_status.text = String(painted["status"])


func _show_aftermath() -> void:
	if _result.is_empty():
		return
	var painted: Dictionary = BattleSimPlayback.show_aftermath(
		_field, _result["report"] as Dictionary, SANDBOX, NAMES
	)
	_cursor = int(painted["cursor"])
	_status.text = String(painted["status"])


func _rounds() -> Array:
	return BattleSimDespatch.rounds_of(_result.get("report", {}) as Dictionary)
