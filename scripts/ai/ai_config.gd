class_name AiConfig
extends RefCounted
## One AI Great Power's read-only config for the whole run (wiki: ai-architecture,
## ai-profile-overrides). Composes a leader personality, a hidden agenda and a
## blessed parameter profile; planners read thresholds only through `parameter`.

var faction: int = -1
var game_seed: int = 0
var profile: String = AiProfile.NORMAL
var leader: String = ""
var personality: Dictionary = {}
var agenda: String = ""
var agenda_traits: Dictionary = {}


static func build(
	faction_id: int,
	seed_value: int,
	profile_id: String = AiProfile.NORMAL,
	agenda_id: String = ""
) -> AiConfig:
	var config := AiConfig.new()
	config.faction = faction_id
	config.game_seed = seed_value
	config.profile = profile_id if AiProfile.has(profile_id) else AiProfile.NORMAL
	config.leader = AiPersonality.leader_for(faction_id)
	config.personality = AiPersonality.resolve(config.leader)
	config.agenda = agenda_id if not agenda_id.is_empty() else AiAgenda.assign(seed_value, faction_id)
	config.agenda_traits = AiAgenda.resolve(config.agenda)
	return config


## Profile override → registry default for one behaviour knob.
func parameter(key: String) -> int:
	return AiParameterRegistry.resolve(key, AiProfile.overrides(profile))


## Relation ceiling above which this court will not declare war: the registry
## default shifted by personality and agenda (warmonger 70, peacemaker 30).
func war_relation_ceiling() -> int:
	var ceiling: int = parameter("diplomacy.war_relation_ceiling")
	ceiling += int(personality.get("war_gate", 0))
	ceiling += int(agenda_traits.get("war_gate", 0))
	return clampi(ceiling, 0, 100)


## War-desire shift from personality and agenda.
func war_bias() -> int:
	return int(personality.get("war_bias", 0)) + int(agenda_traits.get("war_bias", 0))


## Domain weight vector (economy / military / diplomacy / research).
func weights() -> Dictionary:
	return personality.get("weights", AiPersonality.NEUTRAL["weights"])
