class_name AiParameterCargo
extends RefCounted
## Cargo-route AI knobs (wiki: ai-parameter-registry § Cargo).
##
## The registry holds one catalog; the cargo group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `AiParameterRegistry.entries()`
## appends this group after the market group so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "cargo.trade_holds",
		"category": "cargo",
		"type": TYPE_INT,
		"min": 0,
		"max": 60,
		"default": 4,
	},
	{
		"key": "cargo.max_routes",
		"category": "cargo",
		"type": TYPE_INT,
		"min": 0,
		"max": 10,
		"default": 2,
	},
	{
		"key": "cargo.min_launch_shortfall",
		"category": "cargo",
		"type": TYPE_INT,
		"min": 0,
		"max": 60,
		"default": 4,
	},
	{
		"key": "cargo.min_treasury",
		"category": "cargo",
		"type": TYPE_INT,
		"min": 0,
		"max": 50000,
		"default": 1500,
	},
]
