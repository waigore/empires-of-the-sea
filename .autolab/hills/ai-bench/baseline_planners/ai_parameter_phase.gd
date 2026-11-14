class_name MainlineAiParameterPhase
extends RefCounted
## War-footing AI knobs (wiki: ai-parameter-registry § Posture;
## phase-planner-architecture § Playable slice).
##
## The registry holds one catalog; the phase group lives here so the registry
## module stays under the size cap. Keys, ranges and defaults are published on
## the wiki page exactly as they appear here, and `MainlineAiParameterRegistry.entries()`
## appends this group after the cargo group so the catalog order never changes.

const PARAMETERS: Array[Dictionary] = [
	{
		"key": "phase.overstretch_fronts",
		"category": "phase",
		"type": TYPE_INT,
		"min": 1,
		"max": 6,
		"default": 2,
	},
]