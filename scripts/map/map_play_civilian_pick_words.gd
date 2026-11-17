class_name MapPlayCivilianPickWords
extends RefCounted
## How one pick is worded (wiki: civilian-build-planner § Deferred seed;
## DR-20261117-06): the order's short form and the payoff the ledger that prices
## it already prints, so every surface that names the court's pick prints one
## wording (REQ-P3-02, REQ-P5-06). A reading, never an order.

## The action a march pick carries: the crew moves before it works.
const KIND_MOVE: String = "move"


## The full line a sheet prints: the short form, an optional place when the work
## is not underfoot, then the payoff where one is named. Empty for no short form.
static func line(short: String, payoff: String, where: String = "") -> String:
	if short.is_empty():
		return ""
	if payoff.is_empty():
		return "the court would %s%s" % [short, where]
	return "the court would %s%s — %s" % [short, where, payoff]


## The work's own short form: the raise it would buy, in the words the ledgers
## that sell it use, so the line can never promise a level the phase would not
## pay (REQ-P2-03).
static func short(action: String, model: MapModel, works: LandWorks, tile: Vector2i) -> String:
	var province: int = model.province_at(tile.x, tile.y)
	match action:
		"build_improvement":
			var name: String = ImprovementCatalog.base_name(
				model.resource_at(tile.x, tile.y)
			)
			return "raise the %s" % lower_first(name)
		"upgrade_town":
			return "raise the town to L%d" % CivilianWorkPlan.town_upgrade_level(model, tile)
		"build_fort":
			return "raise the %s fort" % FortRules.level_name(
				CivilianWorkPlan.fort_target(model, tile)
			).to_lower()
		"build_hospital":
			return "raise the L%d ward" % CivilianWorkPlan.hospital_target(model, tile)
		"build_road":
			return "build a road"
		"build_port":
			return "build a harbour"
		"build_rail":
			return "lay a railroad"
		"explore":
			return "survey %s" % place(model, province)
		"purchase_land":
			return "buy the deed at %s" % place(model, province)
		"counter_spy":
			return "keep the counter-espionage screen"
	return lower_first(CivilianWork.label(action))


## What the order buys, off the table that charges it: the estate's next level
## (the estates ledger's own line), the transport a road or harbour lands, the
## wall the fort stands up, the rest a ward brings, the bonus and works a town
## level opens. Empty where the sheet that sells the order already prints the
## payoff and no level is named here.
static func payoff(
	action: String,
	model: MapModel,
	works: LandWorks,
	roster: Array[CivilianState],
	owner: int,
	tech_caps: Dictionary,
	stockpile: Dictionary,
	context: Dictionary,
	blockade: Blockades,
	tile: Vector2i
) -> String:
	var province: int = model.province_at(tile.x, tile.y)
	match action:
		"build_improvement":
			var row: Dictionary = ImprovementLedger.estate_row(
				model, works, roster, stockpile, owner, tile,
				context.get("capital_tile", CivilianState.NO_TILE), tech_caps,
				blockade
			)
			return String(row.get("preview_text", ""))
		"build_road", "build_port", "build_rail":
			return CivilianWorkRows.transport_preview(action, model, tile, works, blockade)
		"build_fort":
			return WallLedger.preview_text(
				FortRules.level_at(model, province), CivilianWorkPlan.fort_target(model, tile)
			)
		"build_hospital":
			return HospitalLedger.preview_text(
				HospitalRules.level_at(model, province),
				CivilianWorkPlan.hospital_target(model, tile)
			)
		"upgrade_town":
			return TownTerms.order_line(model, tile)
	return ""


## A march the pass books when no work is legal where the crew stands: the step
## it takes, so the crown sees the ground the court is walking its crew toward.
static func move_pick(model: MapModel, move: Dictionary) -> Dictionary:
	var tile: Vector2i = move.get("tile", CivilianState.NO_TILE)
	if tile.x < 0:
		return {}
	var step: String = "march toward %s" % place(model, model.province_at(tile.x, tile.y))
	return {
		"action": KIND_MOVE,
		"tile": tile,
		"short": step,
		"line": "%s (%d, %d)" % [line(step, ""), tile.x, tile.y],
	}


## The work's first word set in running prose: `Lumber camp` -> `lumber camp`.
static func lower_first(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_lower() + text.substr(1)


static func place(model: MapModel, province: int) -> String:
	if province < 0:
		return "the wilds"
	return model.province_name(province)