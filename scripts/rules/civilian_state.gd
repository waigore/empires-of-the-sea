class_name CivilianState
extends RefCounted
## One civilian map unit (wiki: civilian-units § Relations). Pure data: no nodes,
## so movement and work resolve headless (REQ-P3-03).
##
## `status` is idle or working only; a working unit carries one active work
## order with its remaining turns. Work in progress keeps `tile` at the tile
## being worked, which is also the rendered position.

enum Status { IDLE, WORKING }

var id: int = -1
var owner: int = 0
var type_id: String = CivilianCatalog.DEFAULT_TYPE
var tile: Vector2i = Vector2i.ZERO
var moved: bool = false
var status: int = Status.IDLE
var work: Dictionary = {}


static func create(
	p_id: int, p_owner: int, p_type_id: String, p_tile: Vector2i
) -> CivilianState:
	var unit := CivilianState.new()
	unit.id = p_id
	unit.owner = p_owner
	unit.type_id = CivilianCatalog.normalize(p_type_id)
	unit.tile = p_tile
	return unit


func display_name() -> String:
	return CivilianCatalog.display_name(type_id)


func is_working() -> bool:
	return status == Status.WORKING and not work.is_empty()


func is_idle() -> bool:
	return not is_working()


func work_action() -> String:
	return String(work.get("action", ""))


func work_tile() -> Vector2i:
	return Vector2i(work.get("tile", tile))


func remaining_turns() -> int:
	return int(work.get("remaining", 0))


func total_turns() -> int:
	return int(work.get("total", 0))


## Starts a work order; the caller has already validated it.
func start_work(action: String, target: Vector2i, duration: int) -> void:
	status = Status.WORKING
	tile = target
	work = {
		"action": action,
		"tile": target,
		"remaining": maxi(duration, 1),
		"total": maxi(duration, 1),
	}


## Advances one turn; true when the work order completed this turn.
func advance_work() -> bool:
	if not is_working():
		return false
	work["remaining"] = maxi(remaining_turns() - 1, 0)
	return remaining_turns() == 0


func clear_work() -> void:
	status = Status.IDLE
	work = {}


## Cancel returns the unit to idle on the tile it was working.
func cancel_work() -> void:
	clear_work()
