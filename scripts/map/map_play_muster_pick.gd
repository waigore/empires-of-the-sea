class_name MapPlayMusterPick
extends RefCounted
## What the court's own drill yard would raise: the line the published land
## reinforcement musters at the seat today, or the gate that holds it back (wiki:
## military-armies § Home Army, ai-architecture § Land reinforcement;
## DR-20261121-03).
##
## The plan is not a second opinion: it is `MapPlayArmyMusterAi.plan`, the eleven
## readings the rival pass books its regiment from, asked for this crown's own
## ledger, purse, fleet claim and footing — so the advice and the muster cannot
## disagree (REQ-P2-03). The pattern it is saving for and the gate that blocks it
## are `AiArmyReinforce`'s own, and the gate predicates are the ones
## `RegimentEconomy.blocked_reason` reads, in that order.
##
## A reading only: nothing here raises a regiment, spends a ducat, takes a
## peasant or recalls an army, and the crown still presses her own Muster
## (REQ-P3-03, REQ-P5-06).

## The yard would raise this line today.
const KIND_MUSTER: String = "muster"
## The court stands at its target strength: no regiment is due.
const KIND_TARGET: String = "target"
## The yard means to raise a line and cannot pay for it yet.
const KIND_SAVING: String = "saving"
## A gate the planner itself names: the fields, the larder, the harvest or a hull.
const KIND_GATE: String = "gate"

## Why the yard is saving: the purse or the stores (the row's own gate order).
const WHY_PURSE: String = "purse"
const WHY_STORES: String = "stores"


## The yard's pick, as the dossier reads it: `{kind, type, why, own, target,
## line}`. Empty when the court would raise nothing this turn (no line pattern
## open, no planner, no ledger), when the dossier is not the Home Army's (the
## drill yard musters there alone), for another crown's army, or when the
## campaign is decided.
static func pick(play: PlaySession, army: ArmyState) -> Dictionary:
	if play == null or army == null or play.army_layer == null:
		return {}
	if play.diplomacy == null or not army.home:
		return {}
	if army.owner != play.player_faction or play.campaign_over():
		return {}
	var kind: String = AiControl.court_kind(play, army.owner)
	if kind == AiControl.KIND_NONE:
		return {}
	var economy: PlayerEconomy = play.ledger_for(army.owner)
	if economy == null:
		return {}
	var config: Variant = AiBind.config(
		kind, army.owner, play.map_seed, play.ensure_ai().profiles
	)
	if config == null:
		return {}
	return counsel(
		play, army.owner, config, kind, economy,
		play.army_layer.regiment_count_all(army.owner)
	)


## The yard's own answer, given a court's ledger, config and footing: the line the
## published muster would raise, the target it already stands at, the pattern it is
## saving for with its gate, or nothing. Pure: the plan and the gates read the
## state and write none of it.
static func counsel(
	play: PlaySession,
	faction: int,
	config: Variant,
	kind: String,
	economy: PlayerEconomy,
	own: int = -1
) -> Dictionary:
	if play == null or economy == null or config == null:
		return {}
	var plan: Dictionary = MapPlayArmyMusterAi.plan(play, faction, config, kind, economy)
	if plan.is_empty():
		return {}
	var target: int = int(plan.get("target", 0))
	var held: int = own if own >= 0 else play.army_layer.regiment_count_all(faction)
	var type_id: String = String(plan.get("muster", ""))
	if not type_id.is_empty():
		return _worded(KIND_MUSTER, type_id, "", held, target,
			MapPlayMusterPickWords.muster_line(type_id))
	var reasons: Array = plan.get("reasons", [])
	if reasons.has(AiArmyReinforce.REASON_TARGET):
		return _worded(KIND_TARGET, "", "", held, target,
			MapPlayMusterPickWords.target_line(held, target))
	for raw: Variant in reasons:
		var gate: String = MapPlayMusterPickWords.gate_line(String(raw))
		if not gate.is_empty():
			return _worded(KIND_GATE, "", String(raw), held, target, gate)
	# `nothing payable`: the pattern the yard means to raise, and the row that
	# stops it — the same predicates, in the same order, as the muster row's gate.
	return _saving(play, config, economy, held, target)


## The pattern the yard is saving for, worded by the gates its muster row reads
## (`RegimentEconomy.blocked_reason`'s own order: the purse, then the stores).
static func _saving(
	play: PlaySession, config: Variant, economy: PlayerEconomy, own: int, target: int
) -> Dictionary:
	if not (config is AiConfig):
		return {}
	var type_id: String = AiArmyReinforce.saving_type(config, economy)
	if type_id.is_empty():
		return {}
	var price: int = RegimentCatalog.treasury_cost(type_id)
	if economy.treasury < price:
		return _worded(KIND_SAVING, type_id, WHY_PURSE, own, target,
			MapPlayMusterPickWords.purse_line(type_id, price, economy.treasury))
	var missing: Dictionary = RegimentEconomy.missing_inputs(type_id, economy.stockpile)
	if missing.is_empty():
		return {}
	return _worded(KIND_SAVING, type_id, WHY_STORES, own, target,
		MapPlayMusterPickWords.stores_line(type_id, missing))


static func _worded(
	kind: String, type_id: String, why: String, own: int, target: int, line: String
) -> Dictionary:
	if line.is_empty():
		return {}
	return {
		"kind": kind,
		"type": type_id,
		"why": why,
		"own": own,
		"target": target,
		"line": line,
	}


## The drill yard's line: the pick's own sentence, or nothing when the court would
## raise nothing this turn.
static func line(play: PlaySession, army: ArmyState) -> String:
	return MapPlayMusterPickWords.sentence(String(pick(play, army).get("line", "")))
