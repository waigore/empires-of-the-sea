class_name AiParameterCivilian
extends RefCounted
## Civilian-staff AI knobs (wiki: ai-parameter-registry § Civilian staff;
## DR-20261115-01).
##
## The registry holds one catalog; the civilian group lives here so the
## registry module stays under the architecture size cap. Keys, ranges and
## defaults are published on the wiki page exactly as they appear here, and
## `AiParameterRegistry.entries()` appends this group after the ledger group.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "civilian.work_per_staff",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 2,
		"max": 100,
		# The staff a court trains is the work it can see, not a cap: each type's
		# desired count is one plus its queued work divided by this, so the
		# college scales with the land it holds and the charting, mining and
		# roads still ahead (DR-20261115-01). Replaces civilian.max_civilians.
		"default": 10,
	},
	{
		"key": "civilian.explorer_target",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 10,
		# Explorers the college keeps over the work queue: one sails the colony
		# voyage, the rest survey and prospect the crown's own land — the mines
		# that pay for the army (DR-20261115-01). Was a hard-coded 1.
		"default": 3,
	},
	{
		"key": "civilian.engineer_target",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 10,
		# Engineers the college keeps: roads raise the transport a mine yields
		# through, ports feed the imports (DR-20261115-01). Was 1.
		"default": 2,
	},
	{
		"key": "civilian.need_target",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 200,
		"default": 20,
	},
	{
		"key": "civilian.improvement_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 40,
	},
	{
		"key": "civilian.prospect_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 60,
	},
	{
		"key": "civilian.merchant_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 75,
	},
	{
		"key": "civilian.road_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 50,
	},
	{
		"key": "civilian.port_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 45,
	},
	{
		"key": "civilian.fort_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 30,
	},
	{
		"key": "civilian.spy_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 70,
	},
	{
		"key": "civilian.town_road_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 55,
	},
	{
		"key": "civilian.hospital_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 30,
	},
	{
		"key": "civilian.town_upgrade_weight",
		"category": "civilian",
		"type": TYPE_INT,
		"min": 0,
		"max": 1000,
		"default": 45,
	},
]
