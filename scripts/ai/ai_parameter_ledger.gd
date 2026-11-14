class_name AiParameterLedger
extends RefCounted
## Deferred-aim escalation knobs (wiki: ai-parameter-registry; issue #603).
##
## The registry holds one catalog; the ledger group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `AiParameterRegistry.entries()`
## appends this group after the base catalog so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "ledger.escalate_turns",
		"category": "ledger",
		"type": TYPE_INT,
		"min": 1,
		"max": 60,
		"default": 10,
	},
	{
		"key": "ledger.blocked_turns",
		"category": "ledger",
		"type": TYPE_INT,
		"min": 2,
		"max": 200,
		"default": 40,
	},
]
