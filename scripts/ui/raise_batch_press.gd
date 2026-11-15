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
## with nothing ready hides the press and forgets any arm (REQ-P5-03).
func set_ready(count: int, word: String) -> void:
	_count = maxi(count, 0)
	_word = word
	if _count == 0:
		_armed = false
		if _timer != null:
			_timer.stop()
	visible = _count > 0
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
		"Confirm — raise %d %s" % [_count, _word]
		if _armed
		else "Raise all ready (%d)" % _count
	)
	tooltip_text = (
		"Press again to file every ready step in this view"
		if _armed
		else "File every ready step this view prints, in its order"
	)
