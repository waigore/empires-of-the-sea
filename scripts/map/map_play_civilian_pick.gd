class_name MapPlayCivilianPick
extends RefCounted
## What the court's own civilian planner would have each idle crew do next: the
## pick the published work modules score, worded by the ledgers that price the
## work it would take (wiki: civilian-build-planner § Deferred seed;
## DR-20261117-06). A reading, never an order — nothing is assigned, reserved or
## spent, and the pass runs on this crown's own purse, chart and studies, so the
## crown reads the decision its own AI seat would take (REQ-P2-03, REQ-P3-03).
##
## The pass itself is `MapPlayCivilianAi.plan_all`, the call the economy turn
## already makes for a court, read here one crew at a time. Every pick carries
## the order's own words (`line`) and a short form (`short`), so the surfaces
## that name it print one wording (REQ-P3-02, REQ-P5-06).

## The action a march pick carries: the crew moves before it works.
const KIND_MOVE: String = "move"


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
		var pick: Dictionary = _move_pick(model, move)
		if not pick.is_empty():
			result[int(move.get("unit_id", -1))] = pick


## The work the pass books for one crew, in the order's own words: the raise it
## would buy, priced off the ledger that sells it, so the line can never promise
## a level the phase would not pay (REQ-P2-03).
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
	var province: int = model.province_at(tile.x, tile.y)
	var words: Dictionary = _wording(action, model, works, tile, province)
	var payoff: String = _payoff(
		action, model, works, roster, faction, tech_caps, stockpile, context,
		blockade, tile, province
	)
	# The work is not always underfoot: a Builder raises an estate anywhere on
	# crown land, an Engineer lays a road ahead of the crew. The sheet the line
	# sits on presses the crew's own tile, so the line names the ground it means
	# — the same words the march pick uses, and the tile the chart rings.
	var where: String = ""
	var crew: CivilianState = CivilianMuster.unit_by_id(roster, int(order.get("unit_id", -1)))
	if crew != null and crew.tile != tile:
		where = " at %s (%d, %d)" % [_place(model, province), tile.x, tile.y]
	words["line"] = (
		"the court would %s%s" % [String(words["short"]), where]
		if payoff.is_empty()
		else "the court would %s%s — %s" % [String(words["short"]), where, payoff]
	)
	words["action"] = action
	words["tile"] = tile
	return words


## A march the pass books when no work is legal where the crew stands: the step
## it takes, so the crown sees the ground the court is walking its crew toward.
static func _move_pick(model: MapModel, move: Dictionary) -> Dictionary:
	var tile: Vector2i = move.get("tile", CivilianState.NO_TILE)
	if tile.x < 0:
		return {}
	var place: String = _place(model, model.province_at(tile.x, tile.y))
	return {
		"action": KIND_MOVE,
		"tile": tile,
		"short": "march toward %s" % place,
		"line": "the court would march toward %s (%d, %d)" % [place, tile.x, tile.y],
	}


## The step's own short form, one branch per work kind the pass books.
static func _wording(
	action: String, model: MapModel, works: LandWorks, tile: Vector2i, province: int
) -> Dictionary:
	match action:
		"build_improvement":
			var name: String = ImprovementCatalog.base_name(
				model.resource_at(tile.x, tile.y)
			)
			return {"short": "raise the %s" % _lower_first(name)}
		"upgrade_town":
			return {
				"short": "raise the town to L%d" % CivilianWorkPlan.town_upgrade_level(
					model, tile
				)
			}
		"build_fort":
			return {
				"short": "raise the %s fort" % FortRules.level_name(
					CivilianWorkPlan.fort_target(model, tile)
				).to_lower()
			}
		"build_hospital":
			return {
				"short": "raise the L%d ward" % CivilianWorkPlan.hospital_target(model, tile)
			}
		"build_road":
			return {"short": "build a road"}
		"build_port":
			return {"short": "build a harbour"}
		"build_rail":
			return {"short": "lay a railroad"}
		"explore":
			return {"short": "survey %s" % _place(model, province)}
		"purchase_land":
			return {"short": "buy the deed at %s" % _place(model, province)}
		"counter_spy":
			return {"short": "keep the counter-espionage screen"}
		_:
			return {"short": _lower_first(CivilianWork.label(action))}


## What the order buys, off the table that charges it: the estate's next level
## (the estates ledger's own line), the transport a road or harbour lands, the
## wall the fort stands up, the rest a ward brings. Empty where the sheet that
## sells the order already prints the payoff and no level is named here.
static func _payoff(
	action: String,
	model: MapModel,
	works: LandWorks,
	roster: Array[CivilianState],
	faction: int,
	tech_caps: Dictionary,
	stockpile: Dictionary,
	context: Dictionary,
	blockade: Blockades,
	tile: Vector2i,
	province: int
) -> String:
	match action:
		"build_improvement":
			var row: Dictionary = ImprovementLedger.estate_row(
				model, works, roster, stockpile, faction, tile,
				context.get("capital_tile", CivilianState.NO_TILE), tech_caps,
				blockade
			)
			return String(row.get("preview_text", ""))
		"build_road", "build_port", "build_rail":
			return CivilianWorkPlan.transport_preview(action, model, tile, works)
		"build_fort":
			return WallLedger.preview_text(
				FortRules.level_at(model, province), CivilianWorkPlan.fort_target(model, tile)
			)
		"build_hospital":
			return HospitalLedger.preview_text(
				HospitalRules.level_at(model, province),
				CivilianWorkPlan.hospital_target(model, tile)
			)
	return ""


## The work's first word set in running prose: `Lumber camp` -> `lumber camp`.
static func _lower_first(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_lower() + text.substr(1)


static func _place(model: MapModel, province: int) -> String:
	if province < 0:
		return "the wilds"
	return model.province_name(province)