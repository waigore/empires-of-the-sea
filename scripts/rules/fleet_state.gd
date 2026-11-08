class_name FleetState
extends RefCounted
## One sea-going fleet's rules state (wiki: ships-and-naval).
## Pure data: no nodes, no rendering, so movement resolves headless (REQ-P3-03).

enum Location { AT_SEA, IN_PORT }

var id: int = -1
var owner: int = 0
var location: int = Location.AT_SEA
var sea_zone: int = MapModel.NO_ID
var province: int = MapModel.NO_ID
var moved: bool = false
var hulls: Array[String] = []


static func at_sea(
	p_id: int, p_owner: int, p_zone: int, p_hulls: Array[String] = []
) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = p_id
	fleet.owner = p_owner
	fleet.location = Location.AT_SEA
	fleet.sea_zone = p_zone
	fleet.hulls = _hulls(p_id, p_hulls)
	return fleet


static func in_port(
	p_id: int, p_owner: int, p_province: int, p_hulls: Array[String] = []
) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = p_id
	fleet.owner = p_owner
	fleet.location = Location.IN_PORT
	fleet.province = p_province
	fleet.hulls = _hulls(p_id, p_hulls)
	return fleet


static func _hulls(fleet_id: int, source: Array[String]) -> Array[String]:
	if source.is_empty():
		return ["ship_%d" % fleet_id]
	return source.duplicate()


func is_at_sea() -> bool:
	return location == Location.AT_SEA


func is_in_port() -> bool:
	return location == Location.IN_PORT


func ship_count() -> int:
	return hulls.size()
