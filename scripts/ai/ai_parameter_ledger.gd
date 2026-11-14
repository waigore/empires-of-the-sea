class_name AiParameterLedger
extends RefCounted
## Deferred-aim escalation knobs (wiki: ai-parameter-registry
## § Deferred-aim escalation; DR-20261114-14).
##
## The registry holds one catalog; this group lives apart so the registry
## module stays under the architecture size cap. Keys, ranges and defaults are
## published on the wiki page exactly as they appear here, and
## `AiParameterRegistry.entries()` appends this group after the victory group.

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
