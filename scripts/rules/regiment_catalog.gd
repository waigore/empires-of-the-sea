class_name RegimentCatalog
extends RefCounted
## Land regiment roster (wiki: military-units § Regiment Table).
## Pure data: stats, category, era and the canonical treasury build cost.
## Training costs beyond cash (materials, workers) are deferred until the
## regiment-economy config exists, so nothing here invents stockpile inputs.

enum Category {
	LIGHT_INFANTRY,
	REGULAR_INFANTRY,
	HEAVY_INFANTRY,
	BOWMEN,
	LIGHT_CAVALRY,
	SPEAR_CAVALRY,
	HEAVY_CAVALRY,
	LIGHT_ARTILLERY,
	HEAVY_ARTILLERY,
}

const DEFAULT_TYPE: String = "peasant_levies"

const ROWS: Array[Dictionary] = [
	{"id": "peasant_levies", "name": "Peasant Levies", "fpn": 0, "fpm": 3, "rng": 1, "def": 3, "mvr": 3, "category": Category.LIGHT_INFANTRY, "era": 1, "cost": 2000},
	{"id": "pikemen", "name": "Pikemen", "fpn": 0, "fpm": 5, "rng": 1, "def": 5, "mvr": 3, "category": Category.REGULAR_INFANTRY, "era": 1, "cost": 4000},
	{"id": "arquebusiers", "name": "Arquebusiers", "fpn": 5, "fpm": 1, "rng": 3, "def": 3, "mvr": 2, "category": Category.HEAVY_INFANTRY, "era": 1, "cost": 5000},
	{"id": "bowmen", "name": "Bowmen", "fpn": 3, "fpm": 1, "rng": 4, "def": 2, "mvr": 3, "category": Category.BOWMEN, "era": 1, "cost": 3000},
	{"id": "squires", "name": "Squires", "fpn": 0, "fpm": 4, "rng": 1, "def": 4, "mvr": 6, "category": Category.LIGHT_CAVALRY, "era": 1, "cost": 6000},
	{"id": "knights", "name": "Knights", "fpn": 0, "fpm": 6, "rng": 1, "def": 6, "mvr": 4, "category": Category.SPEAR_CAVALRY, "era": 1, "cost": 8000},
	{"id": "culverin", "name": "Culverin", "fpn": 8, "fpm": 1, "rng": 5, "def": 2, "mvr": 2, "category": Category.HEAVY_ARTILLERY, "era": 1, "cost": 8000},
	{"id": "calivermen", "name": "Calivermen", "fpn": 3, "fpm": 2, "rng": 5, "def": 5, "mvr": 4, "category": Category.LIGHT_INFANTRY, "era": 2, "cost": 7000},
	{"id": "halberdiers", "name": "Halberdiers", "fpn": 0, "fpm": 7, "rng": 1, "def": 6, "mvr": 4, "category": Category.REGULAR_INFANTRY, "era": 2, "cost": 7000},
	{"id": "musketeers", "name": "Musketeers", "fpn": 7, "fpm": 2, "rng": 4, "def": 4, "mvr": 3, "category": Category.HEAVY_INFANTRY, "era": 2, "cost": 8000},
	{"id": "cossacks", "name": "Cossacks", "fpn": 0, "fpm": 5, "rng": 1, "def": 5, "mvr": 8, "category": Category.LIGHT_CAVALRY, "era": 2, "cost": 9000},
	{"id": "lancers", "name": "Lancers", "fpn": 0, "fpm": 8, "rng": 1, "def": 5, "mvr": 6, "category": Category.SPEAR_CAVALRY, "era": 2, "cost": 10000},
	{"id": "harquebusiers", "name": "Harquebusiers", "fpn": 2, "fpm": 6, "rng": 3, "def": 5, "mvr": 6, "category": Category.HEAVY_CAVALRY, "era": 2, "cost": 11000},
	{"id": "horse_artillery", "name": "Horse Artillery", "fpn": 5, "fpm": 2, "rng": 7, "def": 2, "mvr": 3, "category": Category.LIGHT_ARTILLERY, "era": 2, "cost": 11000},
	{"id": "royal_artillery", "name": "Royal Artillery", "fpn": 9, "fpm": 2, "rng": 8, "def": 2, "mvr": 2, "category": Category.HEAVY_ARTILLERY, "era": 2, "cost": 12000},
	{"id": "skirmishers", "name": "Skirmishers", "fpn": 4, "fpm": 3, "rng": 5, "def": 6, "mvr": 6, "category": Category.LIGHT_INFANTRY, "era": 3, "cost": 9000},
	{"id": "regulars", "name": "Regulars", "fpn": 7, "fpm": 7, "rng": 5, "def": 5, "mvr": 4, "category": Category.REGULAR_INFANTRY, "era": 3, "cost": 11000},
	{"id": "grenadiers", "name": "Grenadiers", "fpn": 10, "fpm": 8, "rng": 5, "def": 5, "mvr": 4, "category": Category.HEAVY_INFANTRY, "era": 3, "cost": 13000},
	{"id": "hussars", "name": "Hussars", "fpn": 2, "fpm": 8, "rng": 3, "def": 6, "mvr": 11, "category": Category.LIGHT_CAVALRY, "era": 3, "cost": 13000},
	{"id": "cuirassiers", "name": "Cuirassiers", "fpn": 5, "fpm": 13, "rng": 3, "def": 5, "mvr": 9, "category": Category.HEAVY_CAVALRY, "era": 3, "cost": 15000},
	{"id": "light_artillery", "name": "Light Artillery", "fpn": 8, "fpm": 3, "rng": 9, "def": 3, "mvr": 4, "category": Category.LIGHT_ARTILLERY, "era": 3, "cost": 14000},
	{"id": "heavy_artillery", "name": "Heavy Artillery", "fpn": 13, "fpm": 2, "rng": 10, "def": 2, "mvr": 3, "category": Category.HEAVY_ARTILLERY, "era": 3, "cost": 16000},
	{"id": "sharpshooters", "name": "Sharpshooters", "fpn": 5, "fpm": 4, "rng": 7, "def": 7, "mvr": 7, "category": Category.LIGHT_INFANTRY, "era": 4, "cost": 12000},
	{"id": "rifle_infantry", "name": "Rifle Infantry", "fpn": 9, "fpm": 9, "rng": 6, "def": 6, "mvr": 4, "category": Category.REGULAR_INFANTRY, "era": 4, "cost": 14000},
	{"id": "guards", "name": "Guards", "fpn": 12, "fpm": 10, "rng": 6, "def": 6, "mvr": 4, "category": Category.HEAVY_INFANTRY, "era": 4, "cost": 18000},
	{"id": "scouts", "name": "Scouts", "fpn": 5, "fpm": 11, "rng": 5, "def": 6, "mvr": 11, "category": Category.LIGHT_CAVALRY, "era": 4, "cost": 15000},
	{"id": "carbine_cavalry", "name": "Carbine Cavalry", "fpn": 7, "fpm": 17, "rng": 5, "def": 5, "mvr": 9, "category": Category.HEAVY_CAVALRY, "era": 4, "cost": 18000},
	{"id": "field_artillery", "name": "Field Artillery", "fpn": 10, "fpm": 3, "rng": 11, "def": 4, "mvr": 5, "category": Category.LIGHT_ARTILLERY, "era": 4, "cost": 18000},
	{"id": "siege_guns", "name": "Siege Guns", "fpn": 17, "fpm": 2, "rng": 12, "def": 3, "mvr": 3, "category": Category.HEAVY_ARTILLERY, "era": 4, "cost": 22000},
]


static func ids() -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in ROWS:
		result.append(String(row["id"]))
	return result


static func normalize(type_id: String) -> String:
	return type_id if has_type(type_id) else DEFAULT_TYPE


static func has_type(type_id: String) -> bool:
	return not row(type_id).is_empty()


static func row(type_id: String) -> Dictionary:
	for entry: Dictionary in ROWS:
		if String(entry["id"]) == type_id:
			return entry
	return {}


static func display_name(type_id: String) -> String:
	var data: Dictionary = row(type_id)
	return String(data.get("name", "Regiment"))


static func stat(type_id: String, key: String, fallback: int = 0) -> int:
	return int(row(type_id).get(key, fallback))


static func category(type_id: String) -> int:
	return int(row(type_id).get("category", Category.LIGHT_INFANTRY))


static func category_name(type_id: String) -> String:
	match category(type_id):
		Category.LIGHT_INFANTRY:
			return "Light infantry"
		Category.REGULAR_INFANTRY:
			return "Regular infantry"
		Category.HEAVY_INFANTRY:
			return "Heavy infantry"
		Category.BOWMEN:
			return "Bowmen"
		Category.LIGHT_CAVALRY:
			return "Light cavalry"
		Category.SPEAR_CAVALRY:
			return "Spear cavalry"
		Category.HEAVY_CAVALRY:
			return "Heavy cavalry"
		Category.LIGHT_ARTILLERY:
			return "Light artillery"
		Category.HEAVY_ARTILLERY:
			return "Heavy artillery"
	return "Regiment"


## Dossier line for one regiment: its stats and the food it eats (wiki:
## military-units § Regiment Table, military-generals § Regiment Economy).
static func detail_line(type_id: String) -> String:
	return "%s · FPN %d · FPM %d · RNG %d · DEF %d · MVR %d · %d food" % [
		category_name(type_id),
		stat(type_id, "fpn"),
		stat(type_id, "fpm"),
		stat(type_id, "rng"),
		stat(type_id, "def"),
		stat(type_id, "mvr"),
		food_upkeep(type_id),
	]


## "3 Guards · 2 Pikemen" — deterministic by display name, empty when nothing.
static func detail_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var type_ids: Array[String] = []
	for type_id: Variant in counts.keys():
		type_ids.append(String(type_id))
	type_ids.sort_custom(func(a: String, b: String) -> bool:
		return display_name(a) < display_name(b)
	)
	for type_id: String in type_ids:
		var count: int = int(counts[type_id])
		if count <= 0:
			continue
		var name: String = display_name(type_id)
		parts.append(name if count == 1 else "%d %s" % [count, name])
	return " · ".join(parts)


static func era(type_id: String) -> int:
	return int(row(type_id).get("era", 1))


static func treasury_cost(type_id: String) -> int:
	return int(row(type_id).get("cost", 0))


## Auto-resolve strength basis: FPN + FPM (wiki: combat § Strength).
static func strength(type_id: String) -> int:
	return stat(type_id, "fpn") + stat(type_id, "fpm")


static func is_cavalry(type_id: String) -> bool:
	return category(type_id) in [
		Category.LIGHT_CAVALRY, Category.SPEAR_CAVALRY, Category.HEAVY_CAVALRY
	]


static func is_artillery(type_id: String) -> bool:
	return category(type_id) in [Category.LIGHT_ARTILLERY, Category.HEAVY_ARTILLERY]


## Infantry-eligible means neither cavalry nor artillery (wiki: combat §
## Garrison recovery type).
static func is_infantry(type_id: String) -> bool:
	return not is_cavalry(type_id) and not is_artillery(type_id)


## Program-level food upkeep (wiki: military-generals § Regiment Economy).
## The wiki fixes cavalry at 3 and says light/early units eat less; these
## 1-3 values are the code-side config until a ruleset loader exists.
static func food_upkeep(type_id: String) -> int:
	var tier: int = category(type_id)
	match tier:
		Category.LIGHT_INFANTRY, Category.BOWMEN:
			return 2 if era(type_id) >= 3 else 1
		Category.REGULAR_INFANTRY:
			return 2
		Category.HEAVY_INFANTRY:
			return 3 if era(type_id) >= 4 else 2
		_:
			return 3


## Most advanced infantry type for a military era: highest FPN + FPM, ties by
## lexicographically smallest id, fallback peasant levies (wiki: combat §
## Garrison recovery type).
static func garrison_type_for(p_era: int) -> String:
	var best: String = ""
	var best_strength: int = -1
	for type_id: String in ids():
		if era(type_id) != p_era or not is_infantry(type_id):
			continue
		var value: int = strength(type_id)
		if value > best_strength or (value == best_strength and type_id < best):
			best = type_id
			best_strength = value
	return best if best != "" else DEFAULT_TYPE
