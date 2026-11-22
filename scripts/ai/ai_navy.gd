class_name AiNavy
extends RefCounted
## The rival's fleet claim: the hull a court means to lay and the chest it saves
## for it (wiki: ai-architecture § Naval policy, treasury-planner § Priority;
## issue #484, #500).
##
## A court at war with no fighting hull, or with fewer than the courts it fights,
## means to lay one down. The yard's treasury row is the chest that claim holds
## back: the money goal reserves it, the muster spends only what stands above it,
## and `navy.build` claims it in the ledger — so a rival that never had a fleet,
## or lost one, can actually reach the slip (issue #484).
##
## Pure: the counts, the ledger and the tech table in, a price out (REQ-P2-03,
## REQ-P3-03).


## True when the court is rebuilding its navy: no fighting hull left (peace or
## war — a lost last sloop must still be replaced), or at war and outmatched at
## sea. The same reading `navy.build` is priced on (issue #491 T5, #484).
static func due(at_war: bool, own_warships: int, hostile_warships: int) -> bool:
	if own_warships <= 0:
		return true
	if not at_war:
		return false
	return hostile_warships > own_warships


## Cheapest warship this court means to lay, ignoring its purse: a type its
## techs already open or that it already flies, else the cheapest warship in
## the frozen catalog so the chest and the cloth are reserved while the court
## studies the unlock (issue #484). Empty only when the catalog has no warship.
## `flown` is the court's current hull types (ShipEconomy.types_flown).
static func saving_type(economy: PlayerEconomy, flown: Array = []) -> String:
	if economy == null:
		return ""
	var open: String = _cheapest_warship(economy.tech_unlocked, true, flown)
	if not open.is_empty():
		return open
	return _cheapest_warship({}, false, [])


## The next tech on the path that opens [method saving_type] when the court
## cannot yet lay it — the research "door" a due navy walks first, the way a
## Tribe chain pins its next stage (DR-20261114-05 / #484). Walks prerequisites
## so a shut Navigation first studies Superior Hull Design. Empty when a
## warship is already open (tech or already flown).
static func unlock_tech(economy: PlayerEconomy, flown: Array = []) -> String:
	var type_id: String = saving_type(economy, flown)
	if type_id.is_empty() or economy == null:
		return ""
	if ShipEconomy.buildable(type_id, economy.tech_unlocked, flown):
		return ""
	var goal: String = String(ShipEconomy.TECH.get(type_id, ""))
	if goal.is_empty():
		return ""
	return _next_tech_door(goal, economy.tech_unlocked)


## First locked tech on the path to `goal`: a missing prerequisite, else the
## goal itself once its prerequisites are open.
static func _next_tech_door(goal: String, unlocked: Dictionary) -> String:
	if bool(unlocked.get(goal, false)):
		return ""
	for raw: Variant in TechCatalog.prerequisites(goal):
		var need: String = String(raw)
		if bool(unlocked.get(need, false)):
			continue
		var prior: String = _next_tech_door(need, unlocked)
		return prior if not prior.is_empty() else need
	return goal


## The treasury row of that hull, or 0 when the catalog has no warship.
static func price(economy: PlayerEconomy, flown: Array = []) -> int:
	var type_id: String = saving_type(economy, flown)
	return 0 if type_id.is_empty() else ShipEconomy.treasury_cost(type_id)


## The hull the yard would lay down today, or the gate that refuses it: the
## strongest warship the court's techs open (or it already flies) whose treasury
## row, material row and one free peasant the yard can pay. `type_id` empty means
## the yard refuses, and `reason` is the gate's own words for the cheapest hull
## the court's techs open — the one its chest is saved toward. The ledger, the
## cargo pass and the turn trace read this one gate, so a funded claim and the
## yard's refusal can never disagree (issue #1126).
static func laying(economy: PlayerEconomy, flown: Array = []) -> Dictionary:
	if economy == null:
		return {"type_id": "", "reason": "There is no court to pay for her."}
	var best: String = ""
	var best_strength: float = 0.0
	var refusal: String = ""
	var peasants: int = economy.available_peasants()
	for raw: Variant in ShipEconomy.ENTRIES.keys():
		var type_id: String = String(raw)
		if not ShipStats.is_warship(type_id):
			continue
		var reason: String = ShipEconomy.blocked_reason(
			type_id, economy.treasury, economy.stockpile, peasants,
			economy.tech_unlocked, flown
		)
		if not reason.is_empty():
			# The cheapest hull the techs open is the one the chest is saved
			# toward, so its refusal is the gate the court is waiting on.
			if refusal.is_empty() and ShipEconomy.buildable(
				type_id, economy.tech_unlocked, flown
			):
				refusal = reason
			continue
		var strength: float = ShipStats.strength(type_id)
		if best.is_empty() or strength > best_strength:
			best = type_id
			best_strength = strength
	if not best.is_empty():
		return {"type_id": best, "reason": ""}
	return {
		"type_id": "",
		"reason": refusal if not refusal.is_empty() else "no warship its techs open",
	}


## The hand the yard keeps for the hull the court's chest is banking for: one
## peasant while that chest is due and the material row is already in store
## (issue #1126). The economy's hire gate reads it beside the muster's, so the
## court neither trains its last peasant away from the slip nor fills a chest it
## cannot crew (wiki: ships-and-naval § Ship muster — one peasant leaves the
## pool at launch).
static func hands(economy: PlayerEconomy, flown: Array, chest: int) -> int:
	if chest <= 0 or economy == null:
		return 0
	# The chest in hand is the moment the hand matters: a court still filling
	# its chest trains as published, so the reserve costs no labour on the way.
	if economy.treasury < chest:
		return 0
	var type_id: String = saving_type(economy, flown)
	if type_id.is_empty():
		return 0
	if not ShipEconomy.buildable(type_id, economy.tech_unlocked, flown):
		return 0
	if not ShipEconomy.missing_inputs(type_id, economy.stockpile).is_empty():
		return 0
	return ShipEconomy.WORKER_COST


## Cheapest warship by treasury cost. When `must_buildable` is set, only types
## the court's techs open or that it already flies; otherwise every catalog
## warship is a candidate.
static func _cheapest_warship(
	unlocked: Dictionary, must_buildable: bool, flown: Array = []
) -> String:
	var cheapest: String = ""
	for raw: Variant in ShipEconomy.ENTRIES.keys():
		var type_id: String = String(raw)
		if not ShipStats.is_warship(type_id):
			continue
		if must_buildable and not ShipEconomy.buildable(type_id, unlocked, flown):
			continue
		if cheapest.is_empty() or (
			ShipEconomy.treasury_cost(type_id) < ShipEconomy.treasury_cost(cheapest)
		):
			cheapest = type_id
	return cheapest


## The material row of that hull — the cloth and lumber the yard wants beside the
## chest. The fleet claim holds this row back the way the army holds its muster's
## (`AiArmyReinforce.muster_reserve`), so a court that saves 5,500 ducats does not
## sell the last fabric it needs to lay the hull (issue #484).
static func saving_row(economy: PlayerEconomy, flown: Array = []) -> Dictionary:
	var type_id: String = saving_type(economy, flown)
	if type_id.is_empty():
		return {}
	return ShipEconomy.build_inputs(type_id)


## The material row that claim holds, or empty when no hull is due. The economy
## reserves it beside the muster's, so the cloth is not sold while the chest
## fills (issue #484).
static func due_row(
	at_war: bool,
	own_warships: int,
	hostile_warships: int,
	economy: PlayerEconomy,
	flown: Array = []
) -> Dictionary:
	if not due(at_war, own_warships, hostile_warships):
		return {}
	return saving_row(economy, flown)


## The purse a court must hold before it lays the hull it is saving for: the
## yard takes the whole treasury row in one payment (wiki: ships-and-naval
## § Ship build economy). 0 when no hull is due, when the unlock is still shut
## (the research door must be able to pay a slot — issue #484), or when the
## catalog has no warship.
##
## `yard_yields` is the deferred-aim escalation reading for `navy.build`
## (#603): true when the court has stalled on the yard past `escalate_turns`
## while a regiment is due **and it already holds that regiment's chest**. The
## yard then stands down, so the chest it never fills stops holding the purse
## the muster needs to buy its material row — the same re-route the war chest
## already takes (`AiIncome.reserve`). The shortfall shrinking resumes it.
static func chest(
	at_war: bool,
	own_warships: int,
	hostile_warships: int,
	economy: PlayerEconomy,
	flown: Array = [],
	yard_yields: bool = false
) -> int:
	if not due(at_war, own_warships, hostile_warships):
		return 0
	if not unlock_tech(economy, flown).is_empty():
		return 0
	if yard_yields:
		return 0
	return price(economy, flown)


## The home hull a food-gated court breaks up, or `{}` while the fleet earns its
## keep (issue #1233). A court whose muster is food-gated — the harvest cannot
## carry one more ration — frees the rations an idle home fleet eats: its two
## per hull (`ShipEconomy.food_upkeep_per_ship`) leave the larder's `wanted`, and
## the broken hull's own peasant returns to the pool the levy needs. The hull is
## the lowest id of the seat's squadron (the yard's own order). A fleet that has
## sailed this turn is not idle: the war used it, so the hull stays. A muster
## that is not food-gated, a hull that carries a regiment or colonist, a court
## with no reading of its larder and a caller with no seat all keep the hull.
## Pure: state in, one reading out.
static func idle_hull(
	config: AiConfig, economy: PlayerEconomy, fleets: Array, seat: int, slack: int
) -> Dictionary:
	if config == null or economy == null:
		return {}
	# The `-2` sentinel is no reading of the larder: no gate, no break-up.
	if slack < -1:
		return {}
	# The gate the muster reads (`AiArmyReinforce.plan`'s own words): the
	# harvest, not the pantry, so the court frees the rations its land cannot
	# carry. The store gate stays: a starving court breaks the hull too — its
	# own men strike for food before the muster waits.
	if slack > 0:
		return {}
	if seat < 0 or fleets_sailing(fleets, config.faction):
		return {}
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != config.faction:
			continue
		if not fleet.is_in_port() or fleet.province != seat:
			continue
		if fleet.embarked_army >= 0 or not fleet.embarked_civilians.is_empty():
			continue
		if fleet.mission != FleetState.Mission.NONE:
			continue
		var hull_id: String = _idle_hull_id(fleet)
		if not hull_id.is_empty():
			return {
				"fleet_id": fleet.id,
				"hull": hull_id,
				"type_id": fleet.type_of(hull_id),
				"rations": ShipEconomy.food_upkeep_per_ship(fleet.type_of(hull_id)),
			}
	return {}


## True while any squadron this court owns has sailed this turn: a fleet in
## motion is not idle — the break-up reads the larder only when the war's own
## hulls stay home (wiki: ai-architecture § Naval policy).
static func fleets_sailing(fleets: Array, faction: int) -> bool:
	for fleet: FleetState in fleets:
		if fleet != null and fleet.owner == faction and fleet.moved:
			return true
	return false


## The lowest-id hull of one squadron — the yard's own order — that the fleet
## can spare: one hull keeps her, because a break-up that retires the court's
## whole idle fleet strands her own name in one turn (`NavalDeck.can_scrap`
## refuses a hull her passengers need). A pair reads its cheaper first.
static func _idle_hull_id(fleet: FleetState) -> String:
	if fleet.hulls.size() < 2:
		return ""
	var aboard: int = fleet.civilian_count()
	if fleet.embarked_army >= 0:
		aboard += 1
	if fleet.ship_count() - 1 < aboard:
		return ""
	return fleet.hulls[0]