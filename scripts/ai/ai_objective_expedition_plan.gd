class_name AiObjectiveExpeditionPlan
extends RefCounted
## The expedition the court's hulls and Explorer serve, and the Tribe chain
## that turns a charted Tribe into a colony (docs/ai.md; issue #491 T2, #476,
## #602). Pure: readings in, objectives out (REQ-P2-03).

## The expedition's children: the hull and the Explorer it must have, and a
## voyage already afloat, which outranks every new aim of the same court.
const W_HULL: int = 60
const W_EXPLORER: int = 60
const W_VOYAGE: int = 75
## The envoy chain that turns a charted Tribe into a colony: the next step of the
## chain, priced at its published cost and the court's one order (wiki:
## diplomacy § GP–Tribe Rules; DR-20261114-02).
const W_TRIBE_COLONY: int = 55


## The expedition: one parent with the children that actually make it sail — the
## hull kept off the cargo routes, the Explorer mustering for the next train
## slot, the order that opens the peace window at war, and the voyage already
## afloat as a protected claim (issue #491 T2, #476).
##
## The parent carries no cost of its own: the allocator funds the children, and
## the gate that musters the Explorer reads `expedition.hull` rather than
## looking for a squadron a second time. A child that cannot be had is blocked
## with its reason, and a funded parent whose children are deferred prints the
## shortfall (e.g. `expedition.hull 0/1`).
static func expedition(readings: Dictionary, at_war: bool) -> AiObjective:
	if not bool(readings.get("colony_target", false)):
		return null
	var parent := AiObjective.create(
		"colonise.new_world", "expansion", AiObjectivesPlan.W_PROVINCES_NEW, {}
	)
	var afloat: bool = bool(readings.get("voyage_afloat", false))
	var abroad: bool = bool(readings.get("voyage_abroad", false))
	# A colonist ashore where the crown owns no land neither founds a province
	# nor boards again (docking needs a crown port), so no voyage can be sailed:
	# the aim says why instead of funding a sailing it cannot order (issue #602).
	# The Explorer is not idle — the civilian planner keeps it on the far shore's
	# chart — but the expedition is over, not under way.
	if bool(readings.get("voyage_stranded", false)):
		return parent.block("the Explorer is ashore with no crown land")
	parent.with_child(_hull(readings))
	parent.with_child(_explorer(readings))
	if at_war:
		# The court's one order is already claimed by `peace.window`; the voyage
		# needs that window funded, not a second order of its own.
		parent.needs("peace.window")
	if afloat or abroad:
		# Already under way — at sea or landed on the far shore: no new hull or
		# colonist, but the voyage outranks opening a second one.
		parent.with_child(AiObjective.create("expedition.voyage", "expansion", W_VOYAGE, {}))
	return parent


## The hull off the cargo routes, or the reason there is none: no harbour, or a
## long wait for an idle one — the fleet is committed elsewhere (issue #603).
static func _hull(readings: Dictionary) -> AiObjective:
	var hull := AiObjective.create("expedition.hull", "naval", W_HULL, {"hull": 1})
	if not bool(readings.get("harbour", false)):
		hull.block("no harbour")
		return hull
	var hull_stall: int = int(
		(readings.get("blockings", {}) as Dictionary).get("expedition.hull", 0)
	)
	if hull_stall > 0:
		hull.block("no idle hull %d turns" % hull_stall)
	return hull


## The Explorer for the next train slot, blocked while it is neither under way
## nor free.
static func _explorer(readings: Dictionary) -> AiObjective:
	var explorer := AiObjective.create(
		"expedition.explorer", "civilian", W_EXPLORER, {"civilian": 1}
	)
	var under_way: bool = bool(readings.get("voyage_afloat", false)) \
		or bool(readings.get("voyage_abroad", false))
	if not under_way and not bool(readings.get("explorer_ready", false)):
		explorer.block("no Explorer free")
	return explorer


## The colony the court is buying: the next envoy step toward the Tribe it has
## charted, priced at the published stage cost and the court's one order. The
## aim is only a reading — `AiTribeColony` is what the diplomacy planner weighs —
## so the trace explains a rival's colonial diplomacy even on the turn it spends
## the order elsewhere (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
static func tribe_chain(readings: Dictionary) -> AiObjective:
	var target: int = int(readings.get("tribe_target", -1))
	if target < 0:
		# A footing that holds the slot shut still names the aim it closed, so
		# the trace reads why the court is buying no colony this turn instead of
		# the row simply vanishing (DR-20261116-11, REQ-P5-05).
		var closed: String = String(readings.get("tribe_closed", ""))
		if closed.is_empty():
			return null
		return AiObjective.create(
			"colonise.tribe_chain", "expansion", W_TRIBE_COLONY
		).block(closed)
	# The aim is only a reading, priced on the next step's published cost; the
	# diplomacy planner is what actually spends the order (DR-20261114-02).
	return AiObjective.create(
		"colonise.tribe_chain", "expansion", W_TRIBE_COLONY,
		{"treasury": int(readings.get("tribe_stage_cost", 0)), "orders": 1}
	)
