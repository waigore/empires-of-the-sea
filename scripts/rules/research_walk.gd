class_name ResearchWalk
extends RefCounted
## The Research phase's priced walk, in one home: every occupied slot is priced
## in slot order against the purse the slots before it leave, and a study that
## lands this turn opens its own to the slots after it (wiki: tech-tree §
## Research Model; DR-20261118-26).
##
## The college ledger's slot rows and heading, and the one press's line, all read
## this walk, so the gold a sheet prints and the gold the phase pays can never
## disagree (REQ-P2-03). It writes nothing: the walk runs over a copy of the
## state, and only `ResearchTurn.resolve` moves the crown's own slots.
##
## Pure reads over integers and catalogs, no nodes (REQ-P3-03).

## A walk with nothing in it, so a sheet never guards the shape itself.
static func blank() -> Dictionary:
	return {
		"slots": [] as Array[Dictionary],
		"gold": 0,
		"rp": 0,
		"unpaid": 0,
		"occupied": 0,
		"floor": 0,
	}


## One priced row per slot index, in phase order. `treasury` is the purse the
## next Research phase will spend; `boost` maps tech id -> spy percent and
## `leader_key` carries the crown's published funding multiplier, so the price a
## sheet prints is the price the phase pays (REQ-P2-03).
##
## `preset` forces every slot to that funding when the rules know it, the way the
## one press would file it; an empty or unknown preset reads each slot's own
## preset, the way the slots stand now. An idle slot still gets its row, so a
## caller can paint the slots by index.
static func run(
	state: ResearchState, treasury: int, preset: String = "",
	boost: Dictionary = {}, leader_key: String = ""
) -> Dictionary:
	var walk: Dictionary = blank()
	if state == null:
		return walk
	state.ensure_slots()
	var forced: bool = ResearchFunding.known(preset)
	var sim: ResearchState = state.copy()
	var left: int = treasury
	walk["floor"] = state.treasury_floor()
	var rows: Array[Dictionary] = walk["slots"]
	for index in state.slots.size():
		var funding: String = preset if forced else state.funding_at(index)
		var row: Dictionary = _price(
			sim, index, state.tech_at(index), funding, left, boost, leader_key
		)
		rows.append(row)
		if String(row["tech"]).is_empty():
			continue
		walk["occupied"] = int(walk["occupied"]) + 1
		if not bool(row["paid"]):
			walk["unpaid"] = int(walk["unpaid"]) + 1
			continue
		walk["gold"] = int(walk["gold"]) + int(row["gold"])
		walk["rp"] = int(walk["rp"]) + int(row["rp"])
		left -= int(row["gold"])
		# The phase's own completion: the study this slot pays for lands before
		# the next slot is priced, so the copy carries the unlock with it.
		_settle(sim, String(row["tech"]), int(row["rp"]))
	return walk


## What one slot would pay and earn at `treasury`, as a sheet draws it. The
## figures are `ResearchTurn.preview`'s, so a row, a heading and the phase read
## one rule (REQ-P2-03).
static func _price(
	sim: ResearchState, index: int, tech_id: String, funding: String,
	treasury: int, boost: Dictionary, leader_key: String
) -> Dictionary:
	var preview: Dictionary = ResearchTurn.preview(
		sim, tech_id, funding, treasury, SpyNetworks.boost_for(boost, tech_id), leader_key
	)
	return {
		"slot": index,
		"tech": tech_id,
		"funding": funding,
		"gold": int(preview["gold"]),
		"rp": int(preview["rp"]),
		"boost": int(preview["boost"]),
		"paid": bool(preview["paid"]),
		"cost": int(preview["cost"]),
		"progress": int(preview["progress"]),
	}


## Lands one study in the walk when the slot it holds earns its cost this turn,
## so the slots after it are priced against what it opened — the phase unlocks
## in slot order, and the rows must read the same turn.
static func _settle(sim: ResearchState, tech_id: String, rp: int) -> void:
	var cost: int = TechCatalog.cost(tech_id)
	if cost > 0 and sim.add_progress(tech_id, rp) >= cost:
		sim.unlock(tech_id)
