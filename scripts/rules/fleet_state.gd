class_name FleetState
extends RefCounted
## One sea-going fleet's rules state (wiki: ships-and-naval).
## Pure data: no nodes, no rendering, so movement resolves headless (REQ-P3-03).
##
## Hulls are stable instance ids (`ship_<n>`); `hull_types` maps each instance id
## to its catalog type, and an unmapped hull counts as the default carrack so
## older fleet data keeps working (wiki: § Ship instances).

enum Location { AT_SEA, IN_PORT }

var id: int = -1
var owner: int = 0
var location: int = Location.AT_SEA
var sea_zone: int = MapModel.NO_ID
var province: int = MapModel.NO_ID
var moved: bool = false
var hulls: Array[String] = []
var hull_types: Dictionary = {}


static func at_sea(
	p_id: int,
	p_owner: int,
	p_zone: int,
	p_hulls: Array[String] = [],
	p_types: Dictionary = {}
) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = p_id
	fleet.owner = p_owner
	fleet.location = Location.AT_SEA
	fleet.sea_zone = p_zone
	fleet.set_hulls(_hulls(p_id, p_hulls), p_types)
	return fleet


static func in_port(
	p_id: int,
	p_owner: int,
	p_province: int,
	p_hulls: Array[String] = [],
	p_types: Dictionary = {}
) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = p_id
	fleet.owner = p_owner
	fleet.location = Location.IN_PORT
	fleet.province = p_province
	fleet.set_hulls(_hulls(p_id, p_hulls), p_types)
	return fleet


## A yard slip: an in-port squadron with no hulls yet, filled by its first
## launch (wiki: ships-and-naval § Ship muster; DR-20261109-01).
static func empty_in_port(p_id: int, p_owner: int, p_province: int) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = p_id
	fleet.owner = p_owner
	fleet.location = Location.IN_PORT
	fleet.province = p_province
	return fleet


## Replaces the hull list; every hull keeps its catalog type or defaults to carrack.
func set_hulls(p_hulls: Array[String], p_types: Dictionary = {}) -> void:
	hulls = p_hulls.duplicate()
	hull_types = {}
	for hull_id: String in hulls:
		hull_types[hull_id] = ShipStats.normalize(
			String(p_types.get(hull_id, ShipStats.DEFAULT_TYPE))
		)


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


func is_afloat() -> bool:
	return not hulls.is_empty()


func type_of(hull_id: String) -> String:
	return ShipStats.normalize(String(hull_types.get(hull_id, ShipStats.DEFAULT_TYPE)))


func add_hull(hull_id: String, type_id: String = ShipStats.DEFAULT_TYPE) -> void:
	if hulls.has(hull_id):
		return
	hulls.append(hull_id)
	hull_types[hull_id] = ShipStats.normalize(type_id)


func remove_hull(hull_id: String) -> bool:
	var index: int = hulls.find(hull_id)
	if index < 0:
		return false
	hulls.remove_at(index)
	hull_types.erase(hull_id)
	return true


func count_of_type(type_id: String) -> int:
	var wanted: String = ShipStats.normalize(type_id)
	var total: int = 0
	for hull_id: String in hulls:
		if type_of(hull_id) == wanted:
			total += 1
	return total


## "2 Carrack · 1 Sloop" for the fleet dossier.
func hull_summary() -> String:
	var counts: Dictionary = {}
	for hull_id: String in hulls:
		var type_id: String = type_of(hull_id)
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for type_id: String in counts.keys():
		parts.append("%d %s" % [int(counts[type_id]), ShipStats.display_name(type_id)])
	return " · ".join(parts)


## Plain data for local saves: location, orders and every hull instance.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"location": location,
		"sea_zone": sea_zone,
		"province": province,
		"moved": moved,
		"hulls": hulls.duplicate(),
		"hull_types": hull_types.duplicate(),
	}


static func from_dict(data: Dictionary) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = int(data.get("id", -1))
	fleet.owner = int(data.get("owner", 0))
	fleet.location = int(data.get("location", Location.AT_SEA))
	fleet.sea_zone = int(data.get("sea_zone", MapModel.NO_ID))
	fleet.province = int(data.get("province", MapModel.NO_ID))
	fleet.moved = bool(data.get("moved", false))
	var names: Array[String] = []
	for raw: Variant in data.get("hulls", []):
		names.append(String(raw))
	fleet.set_hulls(names, data.get("hull_types", {}))
	return fleet
