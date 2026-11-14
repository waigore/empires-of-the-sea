class_name AiParameterDiplomacy
extends RefCounted
## War-memory knobs (wiki: ai-parameter-registry, diplomacy § Cooldowns;
## issue #475). The registry holds one catalog; this group lives here so the
## registry module stays under the architecture size cap, exactly like the
## market and army groups.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "diplomacy.war_weariness",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 10,
		"default": 1,
	},
	{
		"key": "diplomacy.war_weariness_grace",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 40,
		"default": 12,
	},
	{
		"key": "diplomacy.truce_turns",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 60,
		"default": 30,
	},
	{
		"key": "diplomacy.truce_fought_turns",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 40,
		"default": 6,
	},
	{
		"key": "diplomacy.truce_penalty",
		"category": "diplomacy",
		"type": TYPE_INT,
		"min": 0,
		"max": 100,
		"default": 40,
	},
]
