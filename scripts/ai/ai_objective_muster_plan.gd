class_name AiObjectiveMusterPlan
extends RefCounted
## The army's aims: the seat held and the line regiment the court saves for
## (docs/ai.md; issue #491 T1, #807, #1143). Pure: readings in, objectives out
## (REQ-P2-03).
##
## The two utilities live beside the aims that read them: a seat worth little at
## peace and a line that outranks it at war are one reading.

const W_DEFEND: int = 90
const W_DEFEND_PEACE: int = 25
## The line's own weight, and the increment a war adds to it, so a warring court
## funds the line ahead of the same line at peace.
const W_MUSTER: int = AiObjectivesPlan.W_MUSTER
const W_MUSTER_WAR: int = AiObjectivesPlan.W_MUSTER_WAR


## The seat held: at war every court keeps a regiment home, at peace it is a
## standing aim worth little next to growth. While a line is due the guard
## claims nothing — the muster's regiment *is* the Home Army, and a phantom
## slot claim at 90 held the muster's own claim shut every warring turn
## (issue #807, the #474 clause-1 un-latch; evidence/issue-766).
static func defend(readings: Dictionary, at_war: bool) -> AiObjective:
	var due: bool = bool(readings.get("muster_due", false))
	var cost: Dictionary = {"regiment": 1} if at_war and not due else {}
	var utility: int = W_DEFEND if at_war else W_DEFEND_PEACE
	return AiObjective.create("defend.seat", "military", utility, cost)


## A line regiment while the court stands under its target. The treasury entry
## is the war chest it must leave behind (AiArmyReinforce.muster_floor), which
## T3 turns into a shared claim (#498). Null at target with nothing to say.
static func muster(readings: Dictionary, at_war: bool) -> AiObjective:
	if not bool(readings.get("muster_due", false)):
		return _closed_line(readings)
	return _line(readings, at_war)


## The line the court stands under its target for: its cost, the utility the
## footing lifts, and the stall the escalation has counted (#603).
static func _line(readings: Dictionary, at_war: bool) -> AiObjective:
	var utility: int = W_MUSTER + (W_MUSTER_WAR if at_war else 0)
	# The purse it must leave behind: the planner refuses a muster short of
	# that cloth (#474), so a row priced on the purse alone would read `funded`
	# for a regiment the court cannot raise — and clear the very stall the
	# escalation counts (#603). The pattern's own material row stays on
	# `reserve.muster` (the ranked claim the market keeps stocked): pricing it
	# here too deferred the whole aim for want of cloth a banked court cannot
	# buy — the line starved thirty turns with a full purse (issue #1143) —
	# while the muster's own gate still refuses a raise the stores cannot pay.
	var cost: Dictionary = {
		"regiment": 1, "labour": 1, "treasury": int(readings.get("muster_floor", 0)),
	}
	var line := AiObjective.create("muster.line", "military", utility, cost)
	# The escalation's explicit terminal reading (#603): a muster that has been
	# deferred past the blocked bar with its shortfall standing still names it,
	# instead of another silent deferred row. The reserve re-route stays the
	# escalation's acting lever; this row only says so in the trace.
	var blocked_turns: int = int(
		(readings.get("blockings", {}) as Dictionary).get("muster.line", 0)
	)
	if blocked_turns > 0:
		line.block("muster out of reach %d turns" % blocked_turns)
	return line


## No line is due. `muster_due` is the court's own saving flag: a court at
## target stays quiet, while one whose row the muster's own gate closed still
## prints the aim — blocked with the gate's words — instead of vanishing beside
## the navy chest, so the starvation cannot hide in a silent absence
## (issue #1143).
static func _closed_line(readings: Dictionary) -> AiObjective:
	var gate: String = String(readings.get("muster_gate", ""))
	if gate.is_empty():
		return null
	return AiObjective.create(
		"muster.line", "military", W_MUSTER, {}
	).block(gate)


## The army's aims in the ledger's order: the seat, then the line it saves for.
static func build(readings: Dictionary, at_war: bool) -> Array[AiObjective]:
	var objectives: Array[AiObjective] = []
	objectives.append(defend(readings, at_war))
	var line: AiObjective = muster(readings, at_war)
	if line != null:
		objectives.append(line)
	return objectives
