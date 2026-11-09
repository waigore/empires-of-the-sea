class_name AiParameterRegistry
extends RefCounted
## Machine-readable AI behaviour knobs (wiki: ai-parameter-registry).
##
## Planners never hardcode a weight or threshold: they read it through
## `resolve(key, overrides)`, so a blessed profile or an inline override changes
## behaviour without touching planner code (REQ-P2-01, REQ-P3-03).
## Pure data: no nodes, no autoloads, safe to drive from tests.

## Key catalog. `min`/`max` bound the legal range; `default` is the registry
## value used when no profile overrides the key.
const PARAMETERS: Array[Dictionary] = [
	{
		"key": "diplomacy.war_desire_base",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 50,
	},
	{
		"key": "diplomacy.war_declare_min_desire",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 51,
	},
	{
		"key": "diplomacy.war_relation_ceiling",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 50,
	},
	{
		"key": "diplomacy.war_cooldown_turns",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 4,
	},
	{
		"key": "diplomacy.overture_cooldown_turns",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 2,
	},
	{
		"key": "diplomacy.power_province_weight",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 10,
	},
	{
		"key": "diplomacy.power_regiment_weight",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 1,
	},
	{
		"key": "diplomacy.power_ship_weight",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 5,
	},
	{
		"key": "military.attack_margin_pct",
		"category": "military",
		"type": TYPE_INT,
		"min": 100,
		"max": 300,
		"default": 110,
	},
	{
		"key": "military.capital_weight",
		"category": "military",
		"type": TYPE_INT,
		"min": 0,
		"max": 5000,
		"default": 1000,
	},
	{
		"key": "military.resource_weight",
		"category": "military",
		"type": TYPE_INT,
		"min": 0,
		"max": 2000,
		"default": 200,
	},
	{
		"key": "military.fort_weight",
		"category": "military",
		"type": TYPE_INT,
		"min": 0,
		"max": 2000,
		"default": 120,
	},
	{
		"key": "military.defence_weight",
		"category": "military",
		"type": TYPE_INT,
		"min": 0,
		"max": 5000,
		"default": 500,
	},
	{
		"key": "military.stage_distance_weight",
		"category": "military",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 1,
	},
]

static var _by_key: Dictionary = {}


static func entries() -> Array[Dictionary]:
	return PARAMETERS


static func keys() -> Array[String]:
	var result: Array[String] = []
	for parameter: Dictionary in PARAMETERS:
		result.append(String(parameter["key"]))
	return result


static func has(key: String) -> bool:
	return not entry(key).is_empty()


static func entry(key: String) -> Dictionary:
	if _by_key.is_empty():
		for parameter: Dictionary in PARAMETERS:
			_by_key[String(parameter["key"])] = parameter
	return _by_key.get(key, {})


static func default_of(key: String, fallback: int = 0) -> int:
	var found: Dictionary = entry(key)
	if found.is_empty():
		return fallback
	return int(found["default"])


static func in_bounds(key: String, value: int) -> bool:
	var found: Dictionary = entry(key)
	if found.is_empty():
		return false
	return value >= int(found["min"]) and value <= int(found["max"])


## Profile override when present and in bounds, else the registry default.
## Unknown keys resolve to 0 so a typo is loud in the trace instead of silent.
static func resolve(key: String, overrides: Dictionary = {}) -> int:
	var found: Dictionary = entry(key)
	if found.is_empty():
		return 0
	if overrides.has(key):
		var value: Variant = overrides[key]
		if _is_int(value) and in_bounds(key, int(value)):
			return int(value)
	return int(found["default"])


## Rejects unknown keys and out-of-range or non-integer values at load time.
static func validate(overrides: Dictionary) -> Dictionary:
	var rejected: Array[String] = []
	for raw: Variant in overrides.keys():
		var key: String = String(raw)
		var found: Dictionary = entry(key)
		var value: Variant = overrides[raw]
		if found.is_empty() or not _is_int(value) or not in_bounds(key, int(value)):
			rejected.append(key)
	rejected.sort()
	return {"ok": rejected.is_empty(), "rejected": rejected}


static func _is_int(value: Variant) -> bool:
	var kind: int = typeof(value)
	if kind == TYPE_INT:
		return true
	if kind == TYPE_FLOAT:
		return is_equal_approx(float(value), roundf(float(value)))
	return false
