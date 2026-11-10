class_name CivilianState
extends RefCounted
## One civilian map unit (wiki: civilian-units § Relations). Pure data: no nodes,
## so movement and work resolve headless (REQ-P3-03).
##
## `status` is idle or working only; a working unit carries one active work
## order with its remaining turns. Work in progress keeps `tile` at the tile
## being worked, which is also the rendered position.

enum Status { IDLE, WORKING }

const NO_TILE: Vector2i = Vector2i(-1, -1)

var id: int = -1
var owner: int = 0
var type_id: String = CivilianCatalog.DEFAULT_TYPE
var tile: Vector2i = Vector2i.ZERO
var moved: bool = false
var status: int = Status.IDLE
var work: Dictionary = {}
## Assignment tracking (wiki: civilian-units § Relations): the tile the unit
## left for the order, and the tile the order targets while work runs.
var origin_tile: Vector2i = NO_TILE
var assigned_tile: Vector2i = NO_TILE
## Squadron carrying this civilian, or -1 while it stands on land
## (wiki: civilian-units § Overseas deployment; DR-20261109-17).
var embarked_fleet: int = -1


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


## Aboard a squadron: off the map until it goes ashore.
func is_embarked() -> bool:
	return embarked_fleet >= 0


## Leaves the land for a squadron's passenger list; boarding spends the move.
func embark_on(fleet_id: int) -> void:
	embarked_fleet = fleet_id
	tile = NO_TILE
	moved = true


## Goes ashore on the chosen tile; the caller has already spent this turn's move.
func put_ashore(tile_on_land: Vector2i) -> void:
	embarked_fleet = -1
	tile = tile_on_land
	moved = true


func work_action() -> String:
	return String(work.get("action", ""))


func work_tile() -> Vector2i:
	return Vector2i(work.get("tile", tile))


func remaining_turns() -> int:
	return int(work.get("remaining", 0))


func total_turns() -> int:
	return int(work.get("total", 0))


## Extra order parameters recorded at assignment; `build_fort` stores the level
## the project was priced and gated for.
func work_detail(key: String, fallback: int = 0) -> int:
	return int(work.get(key, fallback))


## Starts a work order; the caller has already validated it. `origin` is the
## tile the unit left for the assignment; it defaults to the target when the
## Builder works where it stands. `details` ride along in the saved work dict.
func start_work(
	action: String, target: Vector2i, duration: int, origin: Vector2i = NO_TILE,
	details: Dictionary = {}
) -> void:
	status = Status.WORKING
	tile = target
	origin_tile = origin if origin.x >= 0 else target
	assigned_tile = target
	work = {
		"action": action,
		"tile": target,
		"remaining": maxi(duration, 1),
		"total": maxi(duration, 1),
	}
	work.merge(details, true)


## Advances one turn; true when the work order completed this turn.
func advance_work() -> bool:
	if not is_working():
		return false
	work["remaining"] = maxi(remaining_turns() - 1, 0)
	return remaining_turns() == 0


func clear_work() -> void:
	status = Status.IDLE
	work = {}
	origin_tile = NO_TILE
	assigned_tile = NO_TILE


## Cancel returns the unit to the tile it left and clears assignment tracking.
func cancel_work() -> void:
	if origin_tile.x >= 0:
		tile = origin_tile
	clear_work()


## Plain data for local saves: position, move flag and the active work order.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"type_id": type_id,
		"tile": tile,
		"moved": moved,
		"status": status,
		"work": work.duplicate(true),
		"origin_tile": origin_tile,
		"assigned_tile": assigned_tile,
		"embarked_fleet": embarked_fleet,
	}


static func from_dict(data: Dictionary) -> CivilianState:
	var unit := CivilianState.create(
		int(data.get("id", -1)),
		int(data.get("owner", 0)),
		String(data.get("type_id", CivilianCatalog.DEFAULT_TYPE)),
		Vector2i(data.get("tile", Vector2i.ZERO))
	)
	unit.moved = bool(data.get("moved", false))
	unit.status = int(data.get("status", Status.IDLE))
	unit.work = data.get("work", {}).duplicate(true)
	unit.origin_tile = Vector2i(data.get("origin_tile", NO_TILE))
	unit.assigned_tile = Vector2i(data.get("assigned_tile", NO_TILE))
	unit.embarked_fleet = int(data.get("embarked_fleet", -1))
	return unit
