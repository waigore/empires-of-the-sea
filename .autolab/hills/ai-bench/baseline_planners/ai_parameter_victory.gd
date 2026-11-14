class_name MainlineAiParameterVictory
extends RefCounted
## Victory-pressure knobs (wiki: ai-parameter-registry, ai-architecture
## § Notable strategic policies; DR-20261114-04). Per-mille except the muster
## extra, which is whole regiments. The registry holds one catalog; this group
## lives here so the registry module stays under the size cap, exactly like the
## market, army, cargo, posture and diplomacy groups.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "victory.pressure_start",
		"category": "victory",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 500,
	},
	{
		"key": "victory.pressure_regiments",
		"category": "victory",
		"type": TYPE_INT,
		"min": 0,
		"max": 6,
		"default": 2,
	},
	{
		"key": "victory.pressure_boost",
		"category": "victory",
		"type": TYPE_INT,
		"min": 1000,
		"max": 2000,
		"default": 1250,
	},
]