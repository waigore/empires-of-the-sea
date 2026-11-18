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
		# A war chest that has not closed for one more turn re-routes so income
		# can lead before provinces fall (issue #603; ai-bench seed 1500). Was
		# 10, then 1 — and 1 never let a fill run: a bank that is progressing
		# restarts the stall at one on every new-low turn, so the bar answered
		# the fill's own progress and no chest ever closed. Two turns: a
		# genuine standing-still still answers fast, a filling bank never
		# does (issue #995).
		"default": 2,
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
