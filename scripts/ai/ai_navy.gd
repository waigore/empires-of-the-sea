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


## True when the court is rebuilding its navy: at war and outmatched at sea. The
## same reading `navy.build` is priced on (issue #491 T5).
static func due(at_war: bool, own_warships: int, hostile_warships: int) -> bool:
	if not at_war:
		return false
	return own_warships <= 0 or hostile_warships > own_warships


## Cheapest warship this court's techs open, ignoring its purse: the hull a
## saving court is saving for. Empty when its techs open none.
static func saving_type(economy: PlayerEconomy) -> String:
	if economy == null:
		return ""
	var cheapest: String = ""
	for raw: Variant in ShipEconomy.ENTRIES.keys():
		var type_id: String = String(raw)
		if not ShipStats.is_warship(type_id):
			continue
		if not ShipEconomy.buildable(type_id, economy.tech_unlocked):
			continue
		if cheapest.is_empty() or (
			ShipEconomy.treasury_cost(type_id) < ShipEconomy.treasury_cost(cheapest)
		):
			cheapest = type_id
	return cheapest


## The treasury row of that hull, or 0 when the court's techs open no warship.
static func price(economy: PlayerEconomy) -> int:
	var type_id: String = saving_type(economy)
	return 0 if type_id.is_empty() else ShipEconomy.treasury_cost(type_id)


## The purse a court must hold before it lays the hull it is saving for: the
## yard takes the whole treasury row in one payment (wiki: ships-and-naval
## § Ship build economy). 0 when no hull is due or none is open to it.
static func chest(
	at_war: bool, own_warships: int, hostile_warships: int, economy: PlayerEconomy
) -> int:
	if not due(at_war, own_warships, hostile_warships):
		return 0
	return price(economy)
