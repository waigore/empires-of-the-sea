class_name FactionCatalog
extends RefCounted
## Faction roster and capabilities (wiki: factions, game-setup).
## Pure data: rules, world generation, UI and tests read the same table, so the
## three faction types never drift apart between systems (REQ-P2-01, REQ-P3-03).

enum Type { GREAT_POWER, MINOR_NATION, TRIBE }

const OLD_WORLD: int = 0
const NEW_WORLD: int = 1
const PLAYER_FACTION: int = 0

const REGION_KEYS: Array[String] = ["old_world", "new_world"]
const REGION_LABELS: Array[String] = ["Old World", "New World"]

const COLOR_UNCLAIMED := Color(0.235, 0.184, 0.129)

## Six Great Powers (default count, wiki: game-setup configurable values).
## Ownership colours: GDD 09 defaults (wiki: naming § Default map colour id).
## United Provinces uses the GDD `netherlands` slot.
const GREAT_POWERS: Array[Dictionary] = [
	{
		"id": 0,
		"name": "Spain",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(220, 180, 60),
	},
	{
		"id": 1,
		"name": "England",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(180, 80, 80),
	},
	{
		"id": 2,
		"name": "France",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(80, 140, 200),
	},
	{
		"id": 3,
		"name": "Portugal",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(90, 160, 90),
	},
	{
		"id": 4,
		"name": "United Provinces",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(220, 140, 100),
	},
	{
		"id": 5,
		"name": "Sweden",
		"type": Type.GREAT_POWER,
		"region": OLD_WORLD,
		"color": Color8(100, 120, 200),
	},
]

## Three Minor Nations (default count): Old World only, no orders, no navy.
const MINOR_NATIONS: Array[Dictionary] = [
	{
		"id": 6,
		"name": "Genoa",
		"type": Type.MINOR_NATION,
		"region": OLD_WORLD,
		"color": Color(0.620, 0.361, 0.263),
	},
	{
		"id": 7,
		"name": "Venice",
		"type": Type.MINOR_NATION,
		"region": OLD_WORLD,
		"color": Color(0.549, 0.278, 0.380),
	},
	{
		"id": 8,
		"name": "Denmark",
		"type": Type.MINOR_NATION,
		"region": OLD_WORLD,
		"color": Color(0.451, 0.420, 0.298),
	},
]

## Ten Tribes (default count): New World only, primitive military, no orders.
const TRIBES: Array[Dictionary] = [
	{
		"id": 9,
		"name": "Aztec",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.553, 0.204, 0.176),
	},
	{
		"id": 10,
		"name": "Tlaxcala",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.620, 0.427, 0.161),
	},
	{
		"id": 11,
		"name": "Maya",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.251, 0.451, 0.322),
	},
	{
		"id": 12,
		"name": "Inca",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.620, 0.341, 0.200),
	},
	{
		"id": 13,
		"name": "Muisca",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.353, 0.420, 0.518),
	},
	{
		"id": 14,
		"name": "Taíno",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.239, 0.443, 0.451),
	},
	{
		"id": 15,
		"name": "Mapuche",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.420, 0.376, 0.239),
	},
	{
		"id": 16,
		"name": "Guaraní",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.522, 0.302, 0.361),
	},
	{
		"id": 17,
		"name": "Pueblo",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.600, 0.502, 0.278),
	},
	{
		"id": 18,
		"name": "Carib",
		"type": Type.TRIBE,
		"region": NEW_WORLD,
		"color": Color(0.302, 0.302, 0.380),
	},
]

static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	return GREAT_POWERS + MINOR_NATIONS + TRIBES


static func count() -> int:
	return GREAT_POWERS.size() + MINOR_NATIONS.size() + TRIBES.size()


static func get_faction(id: int) -> Dictionary:
	return _index().get(id, {})


static func has_faction(id: int) -> bool:
	return _index().has(id)


static func name_of(id: int) -> String:
	var faction: Dictionary = get_faction(id)
	if faction.is_empty():
		return "Unclaimed"
	return String(faction["name"])


## Display names indexed by faction id (despatches and panels look names up by id).
static func names() -> Array[String]:
	var result: Array[String] = []
	for faction: Dictionary in all():
		result.append(String(faction["name"]))
	return result


static func color_of(id: int) -> Color:
	var faction: Dictionary = get_faction(id)
	if faction.is_empty():
		return COLOR_UNCLAIMED
	return faction["color"]


static func type_of(id: int) -> int:
	var faction: Dictionary = get_faction(id)
	if faction.is_empty():
		return -1
	return int(faction["type"])


static func region_of(id: int) -> int:
	var faction: Dictionary = get_faction(id)
	if faction.is_empty():
		return -1
	return int(faction["region"])


static func type_ids(type: int) -> Array[int]:
	var ids: Array[int] = []
	for faction: Dictionary in all():
		if int(faction["type"]) == type:
			ids.append(int(faction["id"]))
	return ids


static func great_power_ids() -> Array[int]:
	return type_ids(Type.GREAT_POWER)


static func minor_ids() -> Array[int]:
	return type_ids(Type.MINOR_NATION)


static func tribe_ids() -> Array[int]:
	return type_ids(Type.TRIBE)


static func ids_in_region(region: int) -> Array[int]:
	var ids: Array[int] = []
	for faction: Dictionary in all():
		if int(faction["region"]) == region:
			ids.append(int(faction["id"]))
	return ids


## Great Powers may own provinces in both regions; Minors are Old World only and
## Tribes New World only (wiki: factions).
static func can_own_region(id: int, region: int) -> bool:
	var type: int = type_of(id)
	if type < 0:
		return false
	if type == Type.GREAT_POWER:
		return true
	return region_of(id) == region


static func can_win(id: int) -> bool:
	return type_of(id) == Type.GREAT_POWER


static func submits_orders(id: int) -> bool:
	return type_of(id) == Type.GREAT_POWER


static func has_navy(id: int) -> bool:
	return type_of(id) == Type.GREAT_POWER


## Only Minor Nations track the strongest Great Power's regiment era; Tribes stay
## at level 1 (wiki: factions § Minor military parity).
static func has_military_parity(id: int) -> bool:
	return type_of(id) == Type.MINOR_NATION


static func type_label(type: int) -> String:
	match type:
		Type.GREAT_POWER:
			return "Great Power"
		Type.MINOR_NATION:
			return "Minor Nation"
		Type.TRIBE:
			return "Tribe"
		_:
			return "Unclaimed"


static func region_label(region: int) -> String:
	if region < 0 or region >= REGION_LABELS.size():
		return "Uncharted"
	return REGION_LABELS[region]


static func region_key(region: int) -> String:
	if region < 0 or region >= REGION_KEYS.size():
		return "unknown"
	return REGION_KEYS[region]


static func _index() -> Dictionary:
	if _by_id.is_empty():
		for faction: Dictionary in all():
			_by_id[int(faction["id"])] = faction
	return _by_id
