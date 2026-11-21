class_name MapPlayProductionPick
extends RefCounted
## What the court's own manufacture would run this phase: the runs the published
## economy pass books for the crown's workshop, and — when it books none — why
## not (wiki: stockpiles-and-production § Production Flow; economy-planner
## § Playable slice; DR-20261121-07).
##
## The reading is not a second opinion: it is `AiEconomyPlanner.production_orders`
## — the call `MapPlayEconomyCourt.plan_turn` books every court's manufacture
## from — asked with the crown's own ledger, its best town, and the chest rows
## the muster and the hull claim, read through `MapPlayEconomyCourt.chest_rows`
## so the plan and the pass cannot price two different chests (issue #484, #878).
##
## A reading only: nothing here sets a run, spends an input or a hand, and the
## crown still presses her own steppers (REQ-P3-03, REQ-P5-06).

## The plan books runs: the phase would set this many, of these outputs.
const KIND_RUN: String = "run"
## No run is booked because every store already meets the court's reserve target.
const KIND_DONE: String = "done"
## No run is booked because no row fits the idle hands the fields have left.
const KIND_HANDS: String = "hands"
## No run is booked although rows are short: the stores or the benches hold them.
const KIND_STORES: String = "stores"

## The most outputs one line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 4

const DONE_LINE: String = (
	"the court would run nothing this phase — its stores already meet the "
	+ "reserve it keeps"
)
const HANDS_LINE: String = (
	"the court would run nothing this phase — too few hands stand idle in the "
	+ "fields"
)
const STORES_LINE: String = (
	"the court would run nothing this phase — its stores and benches hold every "
	+ "row back"
)


## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession) -> String:
	return sentence(String(pick(play).get("line", "")))


## `text` as a printed sentence: "the court would run …" → "The court would run …".
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The ledger's pick as the PRODUCTION tab prints it: `{kind, runs, line}`, where
## `runs` maps recipe id to the units the plan books. Empty when the session runs
## no planner for the crown, an observer session, a decided campaign, or a crown
## with no ledger.
static func pick(play: PlaySession) -> Dictionary:
	if play == null or play.world == null or play.campaign_over():
		return {}
	if play.observer_mode:
		return {}
	var faction: int = play.player_faction
	var economy: PlayerEconomy = play.ledger_for(faction)
	if economy == null:
		return {}
	var kind: String = AiControl.court_kind(play, faction)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(
		kind, faction, play.map_seed, play.ensure_ai().profiles
	)
	if not (config is AiConfig):
		return {}
	return of(economy, plan_for(play, faction, kind, config, economy))


## The plan the court's own economy pass books for its manufacture: the published
## `production_orders` over the crown's ledger and best town, with the chest rows
## the pass reads for the same court (REQ-P2-03).
static func plan_for(
	play: PlaySession, faction: int, kind: String, config: Variant,
	economy: PlayerEconomy
) -> Dictionary:
	var at_war: bool = MapPlayCourt.at_war(play, faction)
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	var chest: Dictionary = MapPlayEconomyCourt.chest_rows(
		play, faction, kind, config, economy, at_war,
		MapPlayCourt.regiments(play, faction),
		MapPlayCourt.warships(play, faction),
		MapPlayCourt.navy_chest(play, faction),
		int(pressure.get("extra_regiments", 0))
	)
	return AiBindEconomy.production_orders(
		kind, config, economy, TownIndustry.best_level(play.world, faction),
		chest.get("held", {}) as Dictionary
	)


## The pick, worded off plan data alone: the runs the plan books in the catalogue
## order the page prints them, or the gate that leaves every row out. Pure — a
## sheet and its suite drive it without a session.
static func of(economy: PlayerEconomy, plan: Dictionary) -> Dictionary:
	if economy == null or plan.is_empty():
		return {}
	var runs: Dictionary = {}
	var outputs: Dictionary = {}
	for raw: Variant in plan.get("assignments", []):
		var assignment: Dictionary = raw
		var recipe: String = String(assignment.get("recipe", ""))
		var units: int = int(assignment.get("units", 0))
		if recipe.is_empty() or units <= 0:
			continue
		runs[recipe] = units
		var output: String = ProductionRecipes.output(recipe)
		outputs[output] = int(outputs.get(output, 0)) + units
	if not runs.is_empty():
		return {"kind": KIND_RUN, "runs": runs, "line": run_line(outputs)}
	# The plan books nothing: the plan's own figures say which gate left the rows
	# out — no deficit at all, no hand to start a row, or the stores and benches.
	var candidates: Array = plan.get("candidates", [])
	if candidates.is_empty():
		return {}
	var short_rows: int = 0
	var cheapest: int = 1 << 30
	for raw: Variant in candidates:
		var entry: Dictionary = raw as Dictionary
		if int(entry.get("deficit", 0)) <= 0:
			continue
		short_rows += 1
		cheapest = mini(
			cheapest, ProductionRecipes.labour(String(entry.get("recipe", "")))
		)
	if short_rows == 0:
		return {"kind": KIND_DONE, "runs": {}, "line": DONE_LINE}
	if economy.workers.labour() < cheapest:
		return {"kind": KIND_HANDS, "runs": {}, "line": HANDS_LINE}
	return {"kind": KIND_STORES, "runs": {}, "line": STORES_LINE}


## "the court would run Lumber ×2 and Cast Iron ×1 this phase". The outputs come
## in the catalogue's own order — the order the page prints its rows in — so the
## clause reads down the sheet it answers, and beyond four it counts the rest.
static func run_line(outputs: Dictionary) -> String:
	var named: Array[String] = []
	var hidden: int = 0
	for output: String in CommodityCatalog.MANUFACTURED:
		if not outputs.has(output):
			continue
		if named.size() >= NAMED_LIMIT:
			hidden += int(outputs[output])
			continue
		named.append("%s ×%d" % [CommodityCatalog.label(output), int(outputs[output])])
	if named.is_empty():
		return ""
	var joined: String = ", ".join(named) if hidden > 0 else _join(named)
	if hidden > 0:
		joined += " and %d more" % hidden
	return "the court would run %s this phase" % joined


## A list read the way prose reads it: "A", "A and B", "A, B and C".
static func _join(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]
