class_name GameMenuDoor
extends RefCounted
## The pause menu's MENU seal and its parking bookkeeping: full-screen ledgers
## (estates card, civilian roster, muster roll) hide the seal while they are up,
## because the seal rides a higher canvas layer than the HUD and would cut
## through their frame. GameMenu owns the button; this helper owns the state, so
## the menu layer answers the seal's visibility instead of every panel walking
## the tree for a node path (REQ-P3-02).

## The seal's crest, mounted on the cartouche's first slot (or the corner of a
## standalone pause page); null until GameMenu mounts it.
var crest: Button = null

## A ledger holds the seal while it is up.
var _parked: bool = false
## The observer seals the door for the whole running screen (REQ-P5-02).
var _sealed: bool = false


func mount(p_crest: Button) -> void:
	crest = p_crest
	_apply()


## Hides the seal while a ledger owns the map.
func park() -> void:
	_parked = true
	_apply()


## Releases one ledger's hold; an observer's seal outlives it.
func release() -> void:
	if _sealed:
		return
	_parked = false
	_apply()


## True while a ledger holds the seal, or the observer sealed it.
func is_parked() -> bool:
	return _parked


func is_sealed() -> bool:
	return _sealed


## The observer owns no pause door at all: its seal stays hidden for good.
func seal() -> void:
	_parked = true
	_sealed = true
	_apply()


func _apply() -> void:
	if crest != null and is_instance_valid(crest):
		crest.visible = not _parked


## One full-screen ledger's hold: its private "parked" flag mirrors the parking,
## so a close without an open never releases another ledger's or the observer's
## frame — the three ledgers share this one park/release rule (REQ-P3-01).
static func set_held(door: GameMenuDoor, held: bool, mine: bool) -> bool:
	if door == null:
		return mine
	if held:
		if mine:
			door.release()
		return false
	if door.is_parked():
		return mine
	door.park()
	return true
