class_name MainlineAiConfig
extends RefCounted
## One AI Great Power's read-only config for the whole run (wiki: ai-architecture,
## ai-profile-overrides). Composes a leader personality, a hidden agenda and a
## blessed parameter profile; planners read thresholds only through `parameter`.

var faction: int = -1
var game_seed: int = 0
var profile: String = MainlineAiProfile.NORMAL
var leader: String = ""
var personality: Dictionary = {}
var agenda: String = ""
var agenda_traits: Dictionary = {}


static func build(
	faction_id: int,
	seed_value: int,
	profile_id: String = MainlineAiProfile.NORMAL,
	agenda_id: String = ""
) -> MainlineAiConfig:
	var config := MainlineAiConfig.new()
	config.faction = faction_id
	config.game_seed = seed_value
	config.profile = profile_id if MainlineAiProfile.has(profile_id) else MainlineAiProfile.NORMAL
	config.leader = MainlineAiPersonality.leader_for(faction_id)
	config.personality = MainlineAiPersonality.resolve(config.leader)
	config.agenda = agenda_id if not agenda_id.is_empty() else MainlineAiAgenda.assign(seed_value, faction_id)
	config.agenda_traits = MainlineAiAgenda.resolve(config.agenda)
	return config


## Profile override → registry default for one behaviour knob.
func parameter(key: String) -> int:
	return MainlineAiParameterRegistry.resolve(key, MainlineAiProfile.overrides(profile))


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


## Shifts the desire a court needs before it keeps a war going: the planner
## raises its peace bar by this much (wiki: hidden-agendas; DR-20261111-27).
func peace_bias() -> int:
	return int(agenda_traits.get("peace_bias", 0))


## War desire against a court this one is formally allied to. Only an agenda
## that signs treaties to break them carries it.
func betray_bias() -> int:
	return int(agenda_traits.get("betray_bias", 0))


## War desire against a human crown that has pulled ahead of this court.
func rival_bias() -> int:
	return int(agenda_traits.get("rival_bias", 0))


## Appetite for trade pacts and subsidies: negative keeps the court to itself.
func trade_bias() -> int:
	return int(agenda_traits.get("trade_bias", 0))


## Research funding steps above the registry default; a court catching up pays
## one step higher.
func research_bias() -> int:
	return int(agenda_traits.get("research_bias", 0))


## Domain weight vector (economy / military / diplomacy / research).
func weights() -> Dictionary:
	return personality.get("weights", MainlineAiPersonality.NEUTRAL["weights"])