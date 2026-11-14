class_name MainlineAiParameterArmy
extends RefCounted
## Land-reinforcement AI knobs (wiki: ai-parameter-registry § Land reinforcement;
## DR-20261111-04).
##
## The registry holds one catalog; the army group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `MainlineAiParameterRegistry.entries()`
## appends this group after the market group so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "army.regiment_target",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 40,
		"default": 8,
	},
	{
		"key": "army.war_extra",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 4,
	},
	{
		"key": "army.min_treasury",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 50000,
		# Climb probe (ai-bench): lower floor so the live crown can muster more
		# often under bench pressure (was 1000).
		"default": 400,
	},
	{
		"key": "army.min_peasants",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 3,
	},
]