class_name MapPlayCivilianPick
extends RefCounted
## What the court's own civilian planner would have each idle crew do next: the
## pick the published work modules score, worded by [MapPlayCivilianPickWords]
## from the ledgers that price the work it would take (wiki:
## civilian-build-planner § Deferred seed; DR-20261117-06). A reading, never an
## order — nothing is assigned, reserved or spent, and the pass runs on this
## crown's own purse, chart and studies, so the crown reads the decision its own
## AI seat would take (REQ-P2-03, REQ-P3-03).
##
## The pass itself is `MapPlayCivilianAi.plan_all`, the call the economy turn
## already makes for a court, read here one crew at a time. Every pick carries
## the order's own words (`line`) and a short form (`short`), so the surfaces
## that name it print one wording (REQ-P3-02, REQ-P5-06).

## The action a march pick carries: the crew moves before it works.
const KIND_MOVE: String = MapPlayCivilianPickWords.KIND_MOVE


## unit id -> {"action", "tile", "line", "short"} for every idle crew the pass
## would put to work. Empty when the session has no ledger, no planner, or the
## roster already has its orders.
static func picks(play: PlaySession, faction: int) -> Dictionary:
	var result: Dictionary = {}
	if play == null or play.civilian_layer == null:
		return result
	var economy: PlayerEconomy = play.ledger_for(faction)
	if economy == null:
		return result
	var kind: String = AiControl.court_kind(play, faction)
	if kind == AiControl.KIND_NONE:
		return result
	var config: Variant = AiBind.config(kind, faction, play.map_seed)
	var overseas: Dictionary = MapPlayEconomyAi._overseas(play, faction, economy)
	# The crown's own purse, with no reserve held back: a pick the crown could
	# not press today is no advice at all. A works floor below zero keeps both
	# purses on the standing treasury (wiki: economy-planner § Reservations).
	var stockpile: Dictionary = economy.stockpile
	var blockade: Blockades = MapPlayBlockades.crown(play)
	for entry: Dictionary in MapPlayCivilianAi.plan_all(
		play, faction, economy, config, overseas, stockpile, 0, -1
	):
		_words(entry, faction, stockpile, blockade, result)
	return result


## One region's plan, folded into the crown's picks: the work first, then the
## marches of the crews no work was legal for.
static func _words(
	entry: Dictionary,
	faction: int,
	stockpile: Dictionary,
	blockade: Blockades,
	result: Dictionary
) -> void:
	var model: MapModel = entry.get("model", null)
	var works: LandWorks = entry.get("works", null)
	var plan: Dictionary = entry.get("plan", {})
	if model == null or works == null or plan.is_empty():
		return
	var roster: Array[CivilianState] = []
	roster.assign(entry.get("roster", []))
	var tech_caps: Dictionary = entry.get("tech_caps", {})
	var context: Dictionary = entry.get("context", {})
	for raw: Variant in plan.get("orders", []):
		var order: Dictionary = raw
		var pick: Dictionary = _order_pick(
			model, works, roster, faction, tech_caps, stockpile, context, blockade,
			order
		)
		if not pick.is_empty():
			result[int(order.get("unit_id", -1))] = pick
	for raw: Variant in plan.get("moves", []):
		var move: Dictionary = raw
		var pick: Dictionary = MapPlayCivilianPickWords.move_pick(model, move)
		if not pick.is_empty():
			result[int(move.get("unit_id", -1))] = pick


## The work the pass books for one crew, in the order's own words: the raise it
## would buy, priced off the ledger that sells it (REQ-P2-03).
static func _order_pick(
	model: MapModel,
	works: LandWorks,
	roster: Array[CivilianState],
	faction: int,
	tech_caps: Dictionary,
	stockpile: Dictionary,
	context: Dictionary,
	blockade: Blockades,
	order: Dictionary
) -> Dictionary:
	var action: String = String(order.get("action", ""))
	var tile: Vector2i = order.get("tile", CivilianState.NO_TILE)
	if action.is_empty() or tile.x < 0:
		return {}
	var step: String = MapPlayCivilianPickWords.short(action, model, works, tile)
	return {
		"action": action,
		"tile": tile,
		"short": step,
		"line": MapPlayCivilianPickWords.line(
			step,
			MapPlayCivilianPickWords.payoff(
				action, model, works, roster, faction, tech_caps, stockpile,
				context, blockade, tile
			)
		),
	}


## A march, worded where the words live: kept as the sheet's own entry point.
static func _move_pick(model: MapModel, move: Dictionary) -> Dictionary:
	return MapPlayCivilianPickWords.move_pick(model, move)