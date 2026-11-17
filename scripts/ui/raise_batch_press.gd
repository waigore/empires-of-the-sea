class_name RaiseBatchPress
extends Button
## The one press a crown raise sheet adds under its chips: it names how many steps
## the view would file, arms on the first tap and files on the second, so a
## mis-tap never spends the realm's stores (REQ-P5-04; the arm of DR-20261109-01,
## DR-20261116-03). The sheet owns what to file and in what order; the press owns
## only the arm, its timeout and its words, and prints nothing a phone cannot
## read (REQ-P1-07, REQ-P5-07).

signal confirmed

## How long the arm stands before the press forgets the first tap.
const ARM_SECONDS: float = 4.0

var _count: int = 0
var _word: String = "rows"
## What the press files, as its face says it: "raise" for a raise sheet, "queue"
## for the PRODUCTION tab's runs (DR-20261116-08).
var _verb: String = "raise"
var _armed: bool = false
var _timer: Timer = null


func _init() -> void:
	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 13)
	visible = false
	pressed.connect(_on_pressed)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = ARM_SECONDS
	_timer.timeout.connect(disarm)
	add_child(_timer)


## How many steps the press would file, and the noun they are counted in. A view
## with nothing ready hides the press; any redraw spends whatever arm the player
## gave the sheet, because the face he confirmed has been re-read from the ledger
## and may no longer be the line he armed — a stale confirm one tap from spending
## is the mis-tap the arm exists to stop (REQ-P5-03, REQ-P5-04).
func set_ready(count: int, word: String) -> void:
	_count = maxi(count, 0)
	_word = word
	_armed = false
	if _timer != null:
		_timer.stop()
	visible = _count > 0
	_retitle()


## The verb the press files with, so a tab that sets runs instead of raising
## steps reads its own word on the face ("Queue all ready (3)"). Defaults to
## "raise", so every raise sheet keeps its published face (DR-20261116-08).
func set_verb(verb: String) -> void:
	_verb = verb if not verb.is_empty() else "raise"
	_retitle()


func is_armed() -> bool:
	return _armed


func arm() -> void:
	if _count == 0:
		return
	_armed = true
	if _timer != null:
		_timer.start()
	_retitle()


func disarm() -> void:
	_armed = false
	if _timer != null:
		_timer.stop()
	_retitle()


func _on_pressed() -> void:
	if not _armed:
		arm()
		return
	disarm()
	confirmed.emit()


## The count is on the face of the press, before the stores are spent: the first
## tap says what the second will do (REQ-P5-05).
func _retitle() -> void:
	text = (
		"Confirm — %s %d %s" % [_verb, _count, _word]
		if _armed
		else "%s all ready (%d)" % [_verb.capitalize(), _count]
	)
	tooltip_text = (
		"Press again to file every ready step in this view"
		if _armed
		else "File every ready step this view prints, in its order"
	)
