class_name MainlineAiParameterMarket
extends RefCounted
## World-market AI knobs (wiki: ai-parameter-registry § Market).
##
## The registry holds one catalog; the market group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `MainlineAiParameterRegistry.entries()`
## appends this group last so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "market.sell_reserve",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 200,
		"default": 20,
	},
	{
		"key": "market.max_offer_types",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 3,
	},
	{
		"key": "market.max_offer_units",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 200,
		"default": 10,
	},
	{
		"key": "market.max_bid_types",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 20,
		"default": 3,
	},
	{
		"key": "market.max_bid_units",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 200,
		"default": 5,
	},
	{
		"key": "market.min_treasury",
		"category": "market",
		"type": TYPE_INT,
		"min": 0,
		"max": 50000,
		"default": 500,
	},
]