class_name ArmGuard
extends Timer
## One destructive press's confirm window, kept in one place: the first tap arms
## a key, the second spends it, and the clock stands it down on its own
## (wiki: military-armies § Dismissing regiments; DR-20261109-01).
##
## Dossiers that shed colours, break up a hull or raise a batch all ask once. The
## key, the window and the expiry are this node's, so no sheet carries its own
## copy of the state machine (REQ-P3-01, REQ-P3-02). A guard lives beside the
## presses it serves: the owner adds it as a child and answers `expired` with the
## repaint or retitle its own face needs.

## The armed key ran out of time: the owner repaints the face it had armed.
signal expired

## The published window: a crown has five seconds to confirm a destructive press
## (DR-20261109-01).
const SECONDS: float = 5.0

var _key: String = ""


func _init() -> void:
	one_shot = true
	wait_time = SECONDS
	timeout.connect(_on_timeout)


## The key the guard is holding, or "" when no order is armed.
func key() -> String:
	return _key


## Whether `key` is the one armed: the face a press paints before a confirm.
func holds(key: String) -> bool:
	return not key.is_empty() and _key == key


## First tap: arms `key` for `seconds`. A guard built outside the tree (a test
## sheet) keeps the arm and takes no clock; the press still asks once.
func arm(key: String, seconds: float = SECONDS) -> void:
	if key.is_empty():
		return
	_key = key
	wait_time = seconds if seconds > 0.0 else SECONDS
	if is_inside_tree():
		start()


## Spends the arm when `key` is the one held: the second tap's yes. A tap on any
## other key asks first, so a mis-tap never files an order.
func spend(key: String) -> bool:
	if not holds(key):
		return false
	clear()
	return true


## Stands the arm down without spending it: a repaint, a closed drawer, an
## expired window. The owner prints its own resting face.
func clear() -> void:
	_key = ""
	if not is_stopped():
		stop()


func _on_timeout() -> void:
	if _key.is_empty():
		return
	_key = ""
	expired.emit()
