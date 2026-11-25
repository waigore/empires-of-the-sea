class_name MapPlayLarderRecovery
extends RefCounted
## The famine order (wiki: workers-and-population § Strike workers;
## military-armies § Dismissing regiments and the docket; ships-and-naval
## § Ship muster and the breaker's yard; treasury-planner § Lock-recovery;
## issue #1433).
##
## A strike is a per-turn state: a hand left unfed stays in the pool and works
## again the moment it is fed. So a court that strikes should bend out of it —
## and the market's lock-recovery already buys the missing ration out of the
## whole purse. What a court cannot buy it must not hold: a court whose own
## fields cannot carry the mouths it feeds spends every ducat on grain, earns
## nothing (its hands turn no wheel), and strikes for ever. The measured
## campaign on seed 1500 ran 175 turns on 73 ducats with the pool at `0 / 2`.
##
## This is the order that ends it: once the pool has gone unfed for more than a
## turn, the court sheds the mouths its harvest and granary cannot carry and its
## purse cannot buy — an empty hull first, then the thinnest colours — no more
## than `SHED_PER_TURN` a close, and says what left beside the bill, harvest,
## store and purse it read (issue #1515). The shed is the
## published rules' own: a dismissed regiment returns exactly one peasant
## ([method ArmyDismiss.dismiss]), a broken-up hull the same
## ([method FleetYard.scrap]), and neither refunds anything else.
##
## The streak is noted by the court's own plan turn (`note`), so the reading is
## the phase's; the bill is `MapPlayEconomyLarder.food_demand`, the same total
## the Consumption phase eats, against the ration the court's land lands.

## Turns the pool must have gone unfed before a court sheds its force: one thin
## turn is a pantry, two is a famine (wiki: workers-and-population § Strike
## workers — the strike is per-turn, so a court that strikes twice is not merely
## short of a ration).
const STRIKE_TURNS: int = 2
## Mouths one close may shed: a court that truly cannot pay still loses its force
## a rank at a time, so one bad reading never erases a whole field army or a
## whole squadron in a single sweep (issue #1515).
const SHED_PER_TURN: int = 2
## A standard keeps one mouth: the Home Army's own standard always stands, and a
## court that sheds an army's every regiment retires it from the chart, which is
## the chart's order and not a ledger's (wiki: military-armies § Dismissing
## regiments).
const KEEP_PER_STANDARD: int = 1


## Notes the coming close's larder for this court and returns whether its pool
## would go unfed. The court's plan turn calls it every turn, fed or striking, so
## the streak that tells a thin pantry from a famine is the pass's own reading
## and never a second opinion (REQ-P2-03).
static func note(court: MapPlayEconomyCourt) -> bool:
	if court == null or court.play == null or court.play.ai == null:
		return false
	var read: Dictionary = LarderRead.reading(
		court.economy.workers,
		court.economy.stockpile,
		_mouths(court.play, court.faction),
	)
	var starving: bool = int(read.get("food_short", 0)) > 0
	court.play.ai.note_strike_streak(court.faction, starving)
	return starving


## The streak the plan turn last noted for this court: 0 when the larder covers
## every mouth, else the turns running that it would not.
static func streak(court: MapPlayEconomyCourt) -> int:
	if court == null or court.play == null or court.play.ai == null:
		return 0
	return int(court.play.ai.strike_streak.get(court.faction, 0))


## Files the famine order when the strike has run past a thin turn: sheds the
## mouths this court's harvest and granary cannot carry and its purse cannot buy,
## a rank at a time, and returns the receipt
## `{ok, regiments, hulls, peasants, lines, bill, harvest, store, purse}`. Reads
## and spends nothing while the larder is feeding its hands — the common case.
##
## The market's lock-recovery buys first (wiki: treasury-planner § Modes;
## DR-20261124-09): a court whose store covers the bill, or whose purse can buy
## the rest at the market's price, sheds nothing. Only the gap left after both
## is shed, and never more than `SHED_PER_TURN` mouths in one close, so a thin
## turn cannot wipe an army (issue #1515).
static func shed(court: MapPlayEconomyCourt) -> Dictionary:
	var receipt: Dictionary = {
		"ok": false, "regiments": 0, "hulls": 0, "peasants": 0, "lines": [],
		"bill": 0, "harvest": 0, "store": 0, "purse": 0,
	}
	if court == null or court.play == null or court.economy == null:
		return receipt
	if streak(court) < STRIKE_TURNS:
		return receipt
	# The bill the phase eats against what the larder already holds and what the
	# turn's own land lands: a court buys grain out of the whole purse before it
	# sheds (treasury-planner § Lock-recovery), so only the mouths nothing can
	# pay for go.
	var bill: int = MapPlayEconomyLarder.food_demand(
		court.play, court.faction, court.economy
	)
	var harvest: int = EconomyConsumption.food_available(
		court.overseas.get("extraction", {}) as Dictionary
	)
	var store: int = EconomyConsumption.food_available(court.economy.stockpile)
	var purse: int = court.economy.treasury
	receipt["bill"] = bill
	receipt["harvest"] = harvest
	receipt["store"] = store
	receipt["purse"] = purse
	var gap: int = bill - harvest - store
	if gap <= 0:
		return receipt
	gap -= _rations_the_purse_buys(court, gap)
	if gap <= 0:
		return receipt
	var lines: Array[String] = []
	lines.append(_reading_line(bill, harvest, store, purse))
	# The ration a returned peasant eats back: the mouth the shed hands the pool.
	var ration: int = WorkerPool.FOOD_PER_WORKER[WorkerPool.Tier.PEASANT]
	var shed_mouths: int = 0
	while gap > 0 and shed_mouths < SHED_PER_TURN:
		var hull: Dictionary = _weakest_hull(court)
		if not hull.is_empty() and _break_up(court, hull):
			receipt["hulls"] = int(receipt["hulls"]) + 1
			receipt["peasants"] = int(receipt["peasants"]) + 1
			shed_mouths += 1
			gap -= maxi(ShipEconomy.FOOD_UPKEEP_PER_SHIP - ration, 0)
			continue
		var colours: Dictionary = _thinnest_colours(court)
		if colours.is_empty():
			break
		var army: ArmyState = colours["army"] as ArmyState
		var regiment: String = String(colours["regiment"])
		var upkeep: int = RegimentCatalog.food_upkeep(army.type_of(regiment))
		if not _dismiss(court, army, regiment):
			break
		receipt["regiments"] = int(receipt["regiments"]) + 1
		receipt["peasants"] = int(receipt["peasants"]) + 1
		shed_mouths += 1
		gap -= maxi(upkeep - ration, 0)
	receipt["ok"] = int(receipt["peasants"]) > 0
	if int(receipt["hulls"]) > 0:
		lines.append(_broken_line(int(receipt["hulls"])))
	if int(receipt["regiments"]) > 0:
		lines.append(_dismissed_line(int(receipt["regiments"])))
	receipt["lines"] = lines
	return receipt


## The rations this court's purse can buy in the market for `gap` mouths: the
## cheapest food the market sells it, at the price the buy would clear at
## (wiki: treasury-planner § Lock-recovery). A court with no market to buy from
## buys nothing, so the count is 0 and the whole gap is shed.
static func _rations_the_purse_buys(
	court: MapPlayEconomyCourt, gap: int
) -> int:
	if court.market == null or court.economy == null or gap <= 0:
		return 0
	var unit: int = 0
	for id: String in CommodityCatalog.FOOD:
		var price: int = court.market.buy_price(id, court.faction)
		if price <= 0:
			continue
		if unit == 0 or price < unit:
			unit = price
	if unit <= 0:
		return 0
	return mini(gap, int(court.economy.treasury) / unit)


## "Larder: bill 22 · harvest 15 · store 22 · purse 85" — the exact reading the
## shed acted on, so a future shed is auditable in the turn log (issue #1515).
static func _reading_line(
	bill: int, harvest: int, store: int, purse: int
) -> String:
	return "Larder: bill %d · harvest %d · store %d · purse %d" % [
		bill, harvest, store, purse,
	]


## The mouths the phase feeds before the pool: the army, the navy and the wards,
## the same appetites `MapPlayEconomyLarder.food_demand` bills.
static func _mouths(play: PlaySession, faction: int) -> Dictionary:
	return {
		"army": MapPlayEconomyLarder.army_food(play, faction),
		"ships": MapPlayCourt.ships(play, faction),
		"wards": HospitalRules.demand_list(play.world, faction),
	}


## The weakest hull the court may break up: the least tooth afloat, in a
## squadron that keeps one hull and carries no troops or colonists — a deck
## under a charge is not a mouth to shed (wiki: ships-and-naval § Naval
## transport). Empty when every squadron is down to its last hull or carrying.
static func _weakest_hull(court: MapPlayEconomyCourt) -> Dictionary:
	var best: Dictionary = {}
	var best_strength: float = 0.0
	for fleet: FleetState in _fleets(court.play):
		if fleet.owner != court.faction:
			continue
		if fleet.embarked_army >= 0 or fleet.civilian_count() > 0:
			continue
		if fleet.ship_count() <= KEEP_PER_STANDARD:
			continue
		for hull_id: String in fleet.hulls:
			var strength: float = ShipStats.strength(fleet.type_of(hull_id))
			if not best.is_empty() and strength >= best_strength:
				continue
			best = {"fleet": fleet, "hull": hull_id}
			best_strength = strength
	return best


## The thinnest colours the court may dismiss: the mouth that buys the least
## strength for the ration it eats, from an army that keeps one regiment.
## Returns `{army, regiment}` or an empty row.
static func _thinnest_colours(court: MapPlayEconomyCourt) -> Dictionary:
	var best: Dictionary = {}
	var best_ratio: float = 0.0
	for army: ArmyState in _armies(court.play):
		if army.owner != court.faction:
			continue
		if army.regiments.size() <= KEEP_PER_STANDARD:
			continue
		for regiment_id: String in army.regiments:
			var type_id: String = army.type_of(regiment_id)
			var upkeep: int = RegimentCatalog.food_upkeep(type_id)
			var ratio: float = float(RegimentCatalog.strength(type_id)) / float(
				maxi(upkeep, 1)
			)
			if not best.is_empty() and ratio >= best_ratio:
				continue
			best = {"army": army, "regiment": regiment_id}
			best_ratio = ratio
	return best


## Breaks one hull up, and repaints the chart when it shows her: a squadron on
## the other chart keeps her markers until the court looks at it
## (map-topology § two regions).
static func _break_up(court: MapPlayEconomyCourt, key: Dictionary) -> bool:
	var fleet: FleetState = key["fleet"] as FleetState
	var result: Dictionary = FleetYard.scrap(court.economy, fleet, String(key["hull"]))
	if not bool(result.get("ok", false)):
		return false
	if court.play.ship_layer != null and court.play.ship_layer.fleets.has(fleet):
		court.play.ship_layer.markers.hulls(fleet)
	return true


## Dismisses one regiment from `army`, and returns whether it left.
static func _dismiss(
	court: MapPlayEconomyCourt, army: ArmyState, regiment_id: String
) -> bool:
	var ids: Array[String] = [regiment_id]
	var result: Dictionary = ArmyDismiss.dismiss(court.economy, army, ids)
	if not bool(result.get("ok", false)):
		return false
	if court.play.army_layer != null and court.play.army_layer.armies.has(army):
		court.play.army_layer.refresh_marker(army)
	return true


## Every army of the crown's, on both charts: the chart on screen answers from
## its live roster, the other from the roster it stored.
static func _armies(play: PlaySession) -> Array[ArmyState]:
	var out: Array[ArmyState] = []
	if play == null or play.army_layer == null:
		return out
	for region in play.world.region_count():
		for army: ArmyState in MapPlayCourt.visible_armies(play, region):
			if not out.has(army):
				out.append(army)
	return out


## Every squadron of the crown's, on both charts, read the way `_armies` reads
## the standards.
static func _fleets(play: PlaySession) -> Array[FleetState]:
	var out: Array[FleetState] = []
	if play == null or play.ship_layer == null:
		return out
	for region in play.world.region_count():
		var roster: Array[FleetState] = []
		if play.ship_layer.model != null and play.ship_layer.model.region_id == region:
			roster.assign(play.ship_layer.fleets)
		else:
			roster = MapPlayCourt.region_fleets(play, region)
		for fleet: FleetState in roster:
			if not out.has(fleet):
				out.append(fleet)
	return out


## "Breaks up 2 hulls — 2 peasants return to the pool"
static func _broken_line(hulls: int) -> String:
	return "Breaks up %d hull%s — %d peasants return to the pool" % [
		hulls, "" if hulls == 1 else "s", hulls,
	]


## "Dismisses 3 regiments — 3 peasants return to the fields"
static func _dismissed_line(regiments: int) -> String:
	return "Dismisses %d regiment%s — %d peasants return to the fields" % [
		regiments, "" if regiments == 1 else "s", regiments,
	]
