class_name MainlineAiProfile
extends RefCounted
## Blessed AI parameter profiles (wiki: ai-parameter-registry § Seed profiles,
## ai-profile-overrides). A profile is a validated map of registry key -> value;
## missing keys inherit the registry default. Bind one profile per AI slot for
## the whole run, so observers and difficulty flavours only vary data.

const NORMAL: String = "normal"
const AGGRESSIVE: String = "aggressive"
const ECONOMIC: String = "economic"

## Seed profiles. Values are registry keys so the catalog stays the contract.
const BLESSED: Dictionary = {
	NORMAL: {},
	AGGRESSIVE: {
		"diplomacy.war_relation_ceiling": 70,
		"diplomacy.war_declare_min_desire": 45,
	},
	ECONOMIC: {
		"diplomacy.war_relation_ceiling": 35,
		"diplomacy.war_declare_min_desire": 65,
		"economy.reserve_target": 30,
		"civilian.improvement_weight": 60,
		"civilian.max_civilians": 7,
	},
}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in BLESSED.keys():
		result.append(id)
	result.sort()
	return result


static func has(id: String) -> bool:
	return BLESSED.has(id)


## Overrides for a profile id; unknown ids fall back to the neutral profile.
static func overrides(id: String) -> Dictionary:
	var raw: Dictionary = BLESSED.get(id, {})
	if not MainlineAiParameterRegistry.validate(raw).get("ok", false):
		return {}
	return raw


static func resolve(key: String, id: String = NORMAL) -> int:
	return MainlineAiParameterRegistry.resolve(key, overrides(id))


## Validation result for a profile id or an inline parameter map.
static func validate(id: String) -> Dictionary:
	if not has(id):
		return {"ok": false, "rejected": [id]}
	return MainlineAiParameterRegistry.validate(overrides(id))