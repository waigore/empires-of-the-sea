class_name RaiseBatchPress
extends Button
## The one press a crown raise sheet adds under its chips: it names how many steps
## the view would file, arms on the first tap and files on the second, so a
## mis-tap never spends the realm's stores (REQ-P5-04; the arm of DR-20261109-01,
## DR-20261116-03). The sheet owns what to file and in what order; the press owns
## only its words, and ArmGuard owns the arm and its window, and prints nothing a
## phone cannot read (REQ-P1-07, REQ-P5-07).
##
## The armed face names the line the press will file, not the view it stands in
## (wiki: civilian-units § One press files what the realm can raise;
## DR-20261118-21). A crown with five ready towns and one idle Builder reads
## `Raise all ready (5)` above a line that carries one, so the second tap says
## `Confirm — raise 1 of 5 towns`: the count a crown confirms is the count the
## walk pays for. A view in which nothing is payable arms nothing, and its
## disabled face sends the reader to the line for the reason.

signal confirmed

## How long the arm stands before the press forgets the first tap.
const ARM_SECONDS: float = 4.0
## The press's one key: the guard's arm stands for this batch and no other.
const KEY: String = "batch"

## The ready steps the view prints.
var _count: int = 0
## How many of them the line under the press carries — what the second tap files.
var _carries: int = 0
var _word: String = "rows"
## What the press files, as its face says it: "raise" for a raise sheet, "queue"
## for the PRODUCTION tab's runs (DR-20261116-08).
var _verb: String = "raise"
## The arm, its window and its expiry: a mis-tap never spends the stores.
var _arm: ArmGuard = null


func _init() -> void:
	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 13)
	visible = false
	pressed.connect(_on_pressed)
	_arm = ArmGuard.new()
	_arm.expired.connect(_retitle)
	add_child(_arm, false, Node.INTERNAL_MODE_BACK)


## How many steps the press would file, and the noun they are counted in. `carries`
## is how many of them the sheet's line pays for — the walk the second tap files,
## which stops where the rules refuse — and a negative value means the line
## carries every ready step (the sheet reads no plan, so its view is its line).
## A view with nothing ready hides the press; a view whose line carries nothing
## stands it disabled, because no tap could file an order. Any redraw spends
## whatever arm the player gave the sheet, because the face he confirmed has been
## re-read from the ledger and may no longer be the line he armed — a stale
## confirm one tap from spending is the mis-tap the arm exists to stop
## (REQ-P5-03, REQ-P5-04).
func set_ready(count: int, word: String, carries: int = -1) -> void:
	_count = maxi(count, 0)
	_carries = _count if carries < 0 else clampi(carries, 0, _count)
	_word = word
	_arm.clear()
	visible = _count > 0
	disabled = _count > 0 and _carries <= 0
	_retitle()


## How many steps the press's face names as its line: what the second tap files.
func carries() -> int:
	return _carries


## The verb the press files with, so a tab that sets runs instead of raising
## steps reads its own word on the face ("Queue all ready (3)"). Defaults to
## "raise", so every raise sheet keeps its published face (DR-20261116-08).
func set_verb(verb: String) -> void:
	_verb = verb if not verb.is_empty() else "raise"
	_retitle()


func is_armed() -> bool:
	return _arm.holds(KEY)


func arm() -> void:
	if _carries <= 0:
		return
	_arm.arm(KEY, ARM_SECONDS)
	_retitle()


func disarm() -> void:
	_arm.clear()
	_retitle()


func _on_pressed() -> void:
	if not is_armed():
		arm()
		return
	disarm()
	confirmed.emit()


## The count is on the face of the press, before the stores are spent: the first
## tap says what the second will do (REQ-P5-05). The armed face names the line the
## walk pays for, and says so as a share of the view when the two differ
## (DR-20261118-21).
func _retitle() -> void:
	if is_armed():
		text = (
			"Confirm — %s %d of %d %s" % [_verb, _carries, _count, _word]
			if _carries < _count
			else "Confirm — %s %d %s" % [_verb, _carries, _word]
		)
		tooltip_text = (
			"Press again to file the %d the line under this press carries" % _carries
			if _carries < _count
			else "Press again to file every ready step in this view"
		)
		return
	text = "%s all ready (%d)" % [_verb.capitalize(), _count]
	if _carries <= 0 and _count > 0:
		tooltip_text = "Nothing in this view can be ordered — the line under this press says what waits"
		return
	tooltip_text = (
		"File the %d of %d ready steps the line under this press carries" % [_carries, _count]
		if _carries < _count
		else "File every ready step this view prints, in its order"
	)
