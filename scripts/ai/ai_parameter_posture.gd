class_name AiParameterPosture
extends RefCounted
## Posture modifier knobs (wiki: ai-parameter-registry, phase-planner-architecture;
## issue #491 T4). Per-mille, so 1000 is "no change". The registry holds one
## catalog; this group lives here so the registry module stays under the size
## cap, exactly like the market, army, cargo and diplomacy groups.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "posture.war_boost",
		"category": "posture",
		"type": TYPE_INT,
		"min": 500,
		"max": 3000,
		"default": 1500,
	},
	{
		"key": "posture.war_expansion",
		"category": "posture",
		"type": TYPE_INT,
		"min": 100,
		"max": 1500,
		"default": 600,
	},
	{
		"key": "posture.fronts_expansion",
		"category": "posture",
		"type": TYPE_INT,
		"min": 100,
		"max": 1500,
		"default": 400,
	},
	{
		"key": "posture.weight_step",
		"category": "posture",
		"type": TYPE_INT,
		"min": 0,
		"max": 500,
		"default": 150,
	},
	{
		"key": "posture.floor",
		"category": "posture",
		"type": TYPE_INT,
		"min": 100,
		"max": 1000,
		"default": 200,
	},
]
