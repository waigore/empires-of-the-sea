class_name AiProfile
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
		"civilian.work_per_staff": 8,
	},
}


## The names the setup screen and any sheet print for a profile id.
const LABELS: Dictionary = {
	NORMAL: "Normal",
	AGGRESSIVE: "Aggressive",
	ECONOMIC: "Economic",
}

## What each profile does, in the words the new-game screen shows. Qualitative
## on purpose: the figures live in BLESSED and in the registry, and the test
## holds the words to the shift each profile actually makes.
const HINTS: Dictionary = {
	NORMAL: "The registry's own thresholds, with no shift.",
	AGGRESSIVE: "Declares war on warmer neighbours, and sooner.",
	ECONOMIC: "Banks more, raises more works, and keeps more crews about them.",
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
	var raw: Dictionary = BLESSED.get(_known(id), {})
	if not AiParameterRegistry.validate(raw).get("ok", false):
		return {}
	return raw


## The name a sheet prints for a profile id ("Aggressive").
static func label(id: String) -> String:
	return String(LABELS.get(_known(id), LABELS[NORMAL]))


## The one line a sheet prints under the name: what the profile shifts.
static func hint(id: String) -> String:
	return String(HINTS.get(_known(id), HINTS[NORMAL]))


## The profile one crown was bound to at creation. A crown the map does not
## name, or a name the catalog does not bless, plans as the neutral profile. A
## map read back from a save may key its crowns as strings, so both forms are
## read (wiki: ai-profile-overrides § Resolution).
static func bound(profiles: Dictionary, faction: int) -> String:
	if profiles.has(faction):
		return _known(String(profiles[faction]))
	return _known(String(profiles.get(str(faction), NORMAL)))


## Every Great Power -> profile id, the neutral profile where none was bound.
## The binding is fixed for the run, so this is the roster a save carries.
static func roster(profiles: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		result[faction] = bound(profiles, faction)
	return result


## Rehydrates a saved Faction -> profile map: a crown the save does not name
## plans as the neutral profile, and an id the catalog does not bless is
## dropped so a stale save cannot invent a temperament (wiki:
## ai-profile-overrides; REQ-P2-03).
static func from_saved(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return roster()
	return roster(raw as Dictionary)


## One crown's config for a run: the leader personality and fixed agenda
## `AiConfig.build` composes, over the temperament the new-game screen bound to
## it. Surfaces that plan for a rival call this, so none can forget the profile
## the run was created with (wiki: ai-profile-overrides § Resolution).
static func config(faction: int, game_seed: int, profiles: Dictionary) -> AiConfig:
	return AiConfig.build(faction, game_seed, bound(profiles, faction))


## The blessed id a raw name resolves to; unknown names read as neutral.
static func _known(id: String) -> String:
	var key: String = id.strip_edges().to_lower()
	return key if BLESSED.has(key) else NORMAL


static func resolve(key: String, id: String = NORMAL) -> int:
	return AiParameterRegistry.resolve(key, overrides(id))


## Validation result for a profile id or an inline parameter map.
static func validate(id: String) -> Dictionary:
	if not has(id):
		return {"ok": false, "rejected": [id]}
	return AiParameterRegistry.validate(overrides(id))
