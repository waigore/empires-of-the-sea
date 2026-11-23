class_name AiParameterArmy
extends RefCounted
## Land-reinforcement AI knobs (wiki: ai-parameter-registry § Land reinforcement;
## DR-20261111-04).
##
## The registry holds one catalog; the army group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `AiParameterRegistry.entries()`
## appends this group after the market group so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "army.regiment_target",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 40,
		# Reachable peacetime target so the live crown musters instead of saving
		# forever under bench pressure (issue #603; was 8).
		"default": 5,
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
		# often under bench pressure (was 1000; 400 still left the chest
		# unreachable beside estate feedstock — #910).
		"default": 200,
	},
	{
		"key": "army.min_peasants",
		"category": "army",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		# Issue #1314 retune companion: with every Old World province behind a
		# wall, a court must be able to arm up past the 51-strength storm
		# threshold. The old floor of 3 spare hands permanently blocked the levy
		# when the pool sat at 3, so the court armed nothing and banked forever;
		# floor 1 lets the levy draw one hand while the fields keep the rest.
		# The floor names the hands the levy may draw (issue #1355): the gate
		# reads the pool as it stands, the levy's own hand included.
		"default": 1,
	},
]
