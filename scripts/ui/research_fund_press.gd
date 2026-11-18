class_name ResearchFundPress
extends VBoxContainer
## The college's one press: a preset stepper, the press that takes every study
## the crown has under way to it in one act, and the line that prices the act
## before the crown signs (wiki: tech-tree § Research Model; DR-20261118-25).
##
## The price comes from `ResearchBatch.plan`, the same walk the sheet's heading
## totals and the Research phase spends in slot order, so the press can never
## name a spend the purse does not pay (REQ-P2-03). Presentation only: the press
## emits an intent, and the economy controller asks the rules layer (REQ-P3-03).
##
## The press stands down when it would file nothing — every study already at the
## preset — and the line says so, so a tap never loads a batch that moves no row
## (REQ-P5-05, REQ-P5-06).

signal funding_all_requested(preset: String)

const PRESS_HEIGHT: float = 38.0
const COMPACT_HEIGHT: float = 34.0
const STEP_WIDTH: float = 44.0
const COMPACT_STEP_WIDTH: float = 40.0

## The preset the press would file; the stepper walks the published order.
var _preset: String = ResearchFunding.DEFAULT
var _plan: Dictionary = {}
var _state: ResearchState = null
var _treasury: int = 0
var _boost: Dictionary = {}
var _leader: String = ""
var _compact: bool = false

var _row: HBoxContainer = null
var _down: Button = null
var _press: Button = null
var _up: Button = null
var _line: Label = null


func _init() -> void:
	add_theme_constant_override("separation", 2)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	add_child(_row)
	_down = UiRowBuilder.button("−", PRESS_HEIGHT, STEP_WIDTH, 16)
	_down.tooltip_text = "The preset below the one on the press"
	_down.pressed.connect(func() -> void: _step(-1))
	_row.add_child(_down)
	_press = UiRowBuilder.button("", PRESS_HEIGHT, 0.0, 12)
	_press.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_press.tooltip_text = "Takes every study under way to the preset on the press"
	_press.pressed.connect(func() -> void: funding_all_requested.emit(_preset))
	_row.add_child(_press)
	_up = UiRowBuilder.button("+", PRESS_HEIGHT, STEP_WIDTH, 16)
	_up.tooltip_text = "The preset above the one on the press"
	_up.pressed.connect(func() -> void: _step(1))
	_row.add_child(_up)
	_line = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	add_child(_line)
	_plan = ResearchBatch.blank()
	_paint()


## The preset the press would file.
func preset() -> String:
	return _preset


## What the press would file, as the last rendered plan reads it.
func plan() -> Dictionary:
	return _plan


## The press that files the batch (tests and tooling press it by name).
func press_button() -> Button:
	return _press


## The priced line under the press.
func line() -> Label:
	return _line


## Steps the target preset without filing anything, held at both ends of the
## published order so a stray tap never wraps Maximum round to None.
func step(direction: int) -> void:
	_set_preset(ResearchBatch.stepped(_preset, direction))


func _step(direction: int) -> void:
	step(direction)


func _set_preset(preset: String) -> void:
	if not ResearchFunding.known(preset) or preset == _preset:
		return
	_preset = preset
	_replan()
	_paint()


## Prices the press against live research state. `boost` maps tech id -> spy
## percent and `leader` the crown's leader key, the same readings the slot rows
## take, so the line's spend and RP match the headings above it (REQ-P2-03).
func render(
	state: ResearchState, treasury: int, boost: Dictionary = {}, leader: String = ""
) -> void:
	_state = state
	_treasury = treasury
	_boost = boost
	_leader = leader
	_replan()
	_paint()


## A phone trades the row's height for list room; the press keeps a thumb size.
func set_compact(compact: bool) -> void:
	_compact = compact
	var height: float = COMPACT_HEIGHT if compact else PRESS_HEIGHT
	var width: float = COMPACT_STEP_WIDTH if compact else STEP_WIDTH
	for button: Button in [_down, _press, _up]:
		button.custom_minimum_size = Vector2(button.custom_minimum_size.x, height)
		button.add_theme_font_size_override("font_size", 11 if compact else 12)
	_down.custom_minimum_size = Vector2(width, height)
	_up.custom_minimum_size = Vector2(width, height)
	_line.add_theme_font_size_override("font_size", 9 if compact else 10)
	_paint()


func _replan() -> void:
	_plan = ResearchBatch.plan(_state, _preset, _treasury, _boost, _leader)


func _paint() -> void:
	# A college with no study under way has nothing to fund: neither press nor
	# line is drawn, so the sheet names no act the crown cannot take.
	visible = int(_plan.get("count", 0)) > 0
	_press.text = "FUND ALL · %s" % ResearchFunding.label(_preset)
	_press.disabled = int(_plan.get("filed", 0)) <= 0
	var order: Array[String] = ResearchFunding.ORDER
	_down.disabled = _preset == String(order[0])
	_up.disabled = _preset == String(order[order.size() - 1])
	_press.tooltip_text = ResearchBatch.sheet_line(_plan)
	_line.text = ResearchBatch.sheet_line(_plan)
