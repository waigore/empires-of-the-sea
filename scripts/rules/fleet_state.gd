class_name FleetState
extends RefCounted
## One sea-going fleet's rules state (wiki: ships-and-naval).
## Pure data: no nodes, no rendering, so movement resolves headless (REQ-P3-03).
##
## Hulls are stable instance ids (`ship_<n>`); `hull_types` maps each instance id
## to its catalog type, and an unmapped hull counts as the default carrack so
## older fleet data keeps working (wiki: § Ship instances).

enum Location { AT_SEA, IN_PORT }
enum Mission { NONE, MOVE, PATROL, BLOCKADE, DEFEND, BEACHHEAD }

var id: int = -1
var owner: int = 0
var location: int = Location.AT_SEA
var sea_zone: int = MapModel.NO_ID
var province: int = MapModel.NO_ID
var moved: bool = false
## Station order for this turn (wiki: ships-and-naval § Missions and Movement).
## A mission persists until the squadron sails, docks or is reassigned; taking a
## station spends the turn's move (DR-20261109-16).
var mission: int = Mission.NONE
## Enemy province this squadron blockades, or NO_ID for every other station.
var blockade_province: int = MapModel.NO_ID
var hulls: Array[String] = []
var hull_types: Dictionary = {}
## Hull instance id -> the name it flies (wiki: naming § Ship names;
## DR-20261111-07). Kept beside the type so a hull keeps its name for the life of
## the save; ShipNames christens every hull this fleet has not named yet.
var hull_names: Dictionary = {}
## Army instance id carried aboard, or -1 (wiki: ships-and-naval § Naval
## transport; DR-20261109-08). One army per squadron; each hull carries one
## regiment.
var embarked_army: int = -1
## Civilian instance ids aboard (wiki: civilian-units § Overseas deployment;
## DR-20261109-17). One hull carries one civilian, and a squadron carrying an
## army carries none.
var embarked_civilians: Array[int] = []
## Beachhead mission (wiki: ships-and-naval § Missions and Movement): the
## hostile coastal province this squadron has marked for a landing, and the turn
## it was marked. A beachhead is ready on the following turn only and is lost
## when the squadron sails or is sunk.
var beachhead_province: int = MapModel.NO_ID
var beachhead_turn: int = -1


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


## Replaces the hull list; every hull keeps its catalog type or defaults to carrack
## and every hull Christened by the caller keeps its name (wiki: § Ship instances;
## naming § Ship names). Hulls that arrive without a name are christened here.
func set_hulls(
	p_hulls: Array[String], p_types: Dictionary = {}, p_names: Dictionary = {}
) -> void:
	hulls = p_hulls.duplicate()
	hull_types = {}
	hull_names = {}
	for hull_id: String in hulls:
		hull_types[hull_id] = ShipStats.normalize(
			String(p_types.get(hull_id, ShipStats.DEFAULT_TYPE))
		)
		var named: String = String(p_names.get(hull_id, ""))
		if not named.is_empty():
			hull_names[hull_id] = named
	ShipNames.fill(self)


static func _hulls(fleet_id: int, source: Array[String]) -> Array[String]:
	if source.is_empty():
		return ["ship_%d" % fleet_id]
	return source.duplicate()


func is_at_sea() -> bool:
	return location == Location.AT_SEA


func is_in_port() -> bool:
	return location == Location.IN_PORT


func has_beachhead() -> bool:
	return beachhead_province != MapModel.NO_ID


## Drops the landing site; a moved or sunk squadron cannot keep its beachhead.
func clear_beachhead() -> void:
	beachhead_province = MapModel.NO_ID
	beachhead_turn = -1
	if mission == Mission.BEACHHEAD:
		clear_mission()


## Stands the squadron down: a normal move or a new station replaces the order.
func clear_mission() -> void:
	mission = Mission.NONE
	blockade_province = MapModel.NO_ID


func ship_count() -> int:
	return hulls.size()


func is_afloat() -> bool:
	return not hulls.is_empty()


func civilian_count() -> int:
	return embarked_civilians.size()


func carries_civilians() -> bool:
	return not embarked_civilians.is_empty()


func has_civilian(unit_id: int) -> bool:
	return embarked_civilians.has(unit_id)


func add_civilian(unit_id: int) -> void:
	if unit_id < 0 or embarked_civilians.has(unit_id):
		return
	embarked_civilians.append(unit_id)


func remove_civilian(unit_id: int) -> bool:
	var index: int = embarked_civilians.find(unit_id)
	if index < 0:
		return false
	embarked_civilians.remove_at(index)
	return true


func type_of(hull_id: String) -> String:
	return ShipStats.normalize(String(hull_types.get(hull_id, ShipStats.DEFAULT_TYPE)))


func add_hull(hull_id: String, type_id: String = ShipStats.DEFAULT_TYPE) -> void:
	if hulls.has(hull_id):
		return
	hulls.append(hull_id)
	hull_types[hull_id] = ShipStats.normalize(type_id)
	hull_names[hull_id] = ShipNames.christen(self, hull_id)


func remove_hull(hull_id: String) -> bool:
	var index: int = hulls.find(hull_id)
	if index < 0:
		return false
	hulls.remove_at(index)
	hull_types.erase(hull_id)
	hull_names.erase(hull_id)
	return true


## Absorbs another fleet's hulls and passengers in order, preserving instance
## ids and types. A duplicate id stays with the receiving fleet (wiki:
## ships-and-naval § Ship instances — combine appends, never duplicates).
## One army per squadron, so when both already carry one the source army is
## returned for the caller to land at the port rather than lost in the merge.
func merge_from(source: FleetState) -> int:
	if source == null:
		return -1
	for hull_id: String in source.hulls:
		if hulls.has(hull_id):
			continue
		hulls.append(hull_id)
		hull_types[hull_id] = source.type_of(hull_id)
		hull_names[hull_id] = ShipNames.of(source, hull_id)
	for unit_id: int in source.embarked_civilians:
		add_civilian(unit_id)
	source.embarked_civilians.clear()
	if source.embarked_army < 0:
		return -1
	var displaced: int = -1
	if embarked_army < 0:
		embarked_army = source.embarked_army
	else:
		displaced = source.embarked_army
	source.embarked_army = -1
	return displaced


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
		"mission": mission,
		"blockade_province": blockade_province,
		"hulls": hulls.duplicate(),
		"hull_types": hull_types.duplicate(),
		"hull_names": hull_names.duplicate(),
		"embarked_army": embarked_army,
		"embarked_civilians": embarked_civilians.duplicate(),
		"beachhead_province": beachhead_province,
		"beachhead_turn": beachhead_turn,
	}


static func from_dict(data: Dictionary) -> FleetState:
	var fleet := FleetState.new()
	fleet.id = int(data.get("id", -1))
	fleet.owner = int(data.get("owner", 0))
	fleet.location = int(data.get("location", Location.AT_SEA))
	fleet.sea_zone = int(data.get("sea_zone", MapModel.NO_ID))
	fleet.province = int(data.get("province", MapModel.NO_ID))
	fleet.moved = bool(data.get("moved", false))
	fleet.mission = int(data.get("mission", Mission.NONE))
	fleet.blockade_province = int(data.get("blockade_province", MapModel.NO_ID))
	fleet.embarked_army = int(data.get("embarked_army", -1))
	for raw: Variant in data.get("embarked_civilians", []):
		fleet.embarked_civilians.append(int(raw))
	fleet.beachhead_province = int(data.get("beachhead_province", MapModel.NO_ID))
	fleet.beachhead_turn = int(data.get("beachhead_turn", -1))
	var names: Array[String] = []
	for raw: Variant in data.get("hulls", []):
		names.append(String(raw))
	fleet.set_hulls(names, data.get("hull_types", {}), data.get("hull_names", {}))
	return fleet
