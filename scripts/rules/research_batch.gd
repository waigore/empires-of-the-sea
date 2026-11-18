class_name ResearchBatch
extends RefCounted
## The college's one press: every study the crown has under way takes one
## funding preset in a single act (wiki: tech-tree § Research Model,
## research-state). Funding is a per-slot tap — None → Low → Medium → High →
## Maximum — so a college of three studies asks up to a dozen taps of one
## decision, the last whole-realm chore the crown ledger serves a row at a time
## (REQ-P5-04).
##
## The walk is the Research phase's own: each slot is priced by
## `ResearchTurn.preview` against the treasury the slots before it leave, exactly
## as the phase spends in slot order, so the line a sheet prints and the gold
## the phase pays can never disagree (REQ-P2-03). It writes nothing; `apply`
## moves the slots through the published `ResearchState.set_funding`, so no rule,
## preset, floor or save key moves (REQ-P3-03).
##
## Pure reads over integers and catalogs, no nodes.

## A plan with nothing in it, so a sheet never has to guard the shape itself.
static func blank() -> Dictionary:
	return {
		"preset": "",
		"count": 0,
		"filed": 0,
		"kept": 0,
		"gold": 0,
		"rp": 0,
		"unpaid": 0,
		"rows": [] as Array[Dictionary],
	}


## What the press would file: the slots that stand elsewhere, the ones already
## at `preset`, and what the college then pays and earns a turn. `treasury` is
## the purse the next Research phase will spend; `boost` maps tech id -> spy
## percent and `leader_key` carries the crown's published funding multiplier, so
## the price the sheet prints is the price the phase pays (REQ-P2-03).
static func plan(
	state: ResearchState, preset: String, treasury: int,
	boost: Dictionary = {}, leader_key: String = ""
) -> Dictionary:
	var plan: Dictionary = blank()
	if state == null or not ResearchFunding.known(preset):
		return plan
	plan["preset"] = preset
	state.ensure_slots()
	var left: int = treasury
	for index in state.slots.size():
		var tech_id: String = state.tech_at(index)
		if tech_id.is_empty():
			continue
		plan["count"] = int(plan["count"]) + 1
		if state.funding_at(index) == preset:
			plan["kept"] = int(plan["kept"]) + 1
		else:
			var rows: Array[Dictionary] = plan["rows"]
			rows.append({
				"slot": index,
				"tech": tech_id,
				"name": TechCatalog.display_name(tech_id),
				"was": state.funding_at(index),
			})
			plan["filed"] = int(plan["filed"]) + 1
		var preview: Dictionary = ResearchTurn.preview(
			state, tech_id, preset, left, SpyNetworks.boost_for(boost, tech_id), leader_key
		)
		if not bool(preview["paid"]):
			plan["unpaid"] = int(plan["unpaid"]) + 1
			continue
		plan["gold"] = int(plan["gold"]) + int(preview["gold"])
		plan["rp"] = int(plan["rp"]) + int(preview["rp"])
		left -= int(preview["gold"])
	return plan


## The line under the press: what it files, what the college then spends a turn,
## and — when the purse cannot reach — how many studies wait on it. A plan that
## files nothing reads every study already at the preset, so a press that would
## spend no tap says so instead of asking for one (DR-20261118-26; REQ-P5-05).
static func sheet_line(plan: Dictionary) -> String:
	var count: int = int(plan.get("count", 0))
	if count <= 0:
		return ""
	var label: String = ResearchFunding.label(String(plan.get("preset", "")))
	var filed: int = int(plan.get("filed", 0))
	if filed <= 0:
		if count == 1:
			return "The study already stands at %s." % label
		return "Every study already stands at %s." % label
	var text: String = ""
	if count == 1:
		text = "Fund the study at %s" % label
	elif filed >= count:
		text = "Fund all %d studies at %s" % [count, label]
	else:
		text = "Fund %d of %d studies at %s" % [filed, count, label]
	var gold: int = int(plan.get("gold", 0))
	var rp: int = int(plan.get("rp", 0))
	if gold <= 0 and rp <= 0:
		text += " — the college then spends nothing a turn"
	else:
		text += " — the college then spends %s ducats & %s RP a turn" % [
			TextFormat.thousands(gold), TextFormat.thousands(rp),
		]
	var unpaid: int = int(plan.get("unpaid", 0))
	if unpaid > 0:
		text += "; %d of %d %s on the purse" % [
			unpaid, count, "waits" if unpaid == 1 else "wait",
		]
	return text + "."


## The receipt a press files: what now stands at the preset and what the college
## pays a turn, so a batch of taps is never silent (REQ-P5-05).
static func receipt(plan: Dictionary) -> String:
	var count: int = int(plan.get("count", 0))
	if count <= 0:
		return ""
	var label: String = ResearchFunding.label(String(plan.get("preset", "")))
	var gold: int = int(plan.get("gold", 0))
	var price: String = "nothing a turn" if gold <= 0 else "%s ducats a turn" % (
		TextFormat.thousands(gold)
	)
	if count == 1:
		return "The study now stands at %s — the college pays %s." % [label, price]
	return "%d studies now stand at %s — the college pays %s." % [count, label, price]


## Moves every occupied slot to `preset` and returns the rows that changed
## (slot, tech, name, was). A preset the rules do not know moves nothing.
static func apply(state: ResearchState, preset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not ResearchFunding.known(preset):
		return out
	state.ensure_slots()
	for index in state.slots.size():
		var tech_id: String = state.tech_at(index)
		var was: String = state.funding_at(index)
		if tech_id.is_empty() or was == preset:
			continue
		if not state.set_funding(index, preset):
			continue
		out.append({
			"slot": index,
			"tech": tech_id,
			"name": TechCatalog.display_name(tech_id),
			"was": was,
		})
	return out


## The preset one step below/above `preset` in the published order, held at the
## ends so a stepper never wraps past Maximum into None by a stray tap.
static func stepped(preset: String, direction: int) -> String:
	var index: int = ResearchFunding.ORDER.find(preset)
	if index < 0:
		index = ResearchFunding.ORDER.find(ResearchFunding.DEFAULT)
	return ResearchFunding.ORDER[
		clampi(index + signi(direction), 0, ResearchFunding.ORDER.size() - 1)
	]
