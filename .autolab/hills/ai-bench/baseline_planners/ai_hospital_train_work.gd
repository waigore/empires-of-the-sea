class_name MainlineAiHospitalTrainWork
extends RefCounted
## Rival surgeon policy for field hospital trains (wiki: combat § Regiment
## condition; DR-20261112-07 the crown's train, DR-20261112-08 the rival's).
##
## A court at war brings its surgeons along: a worn field army on its own ground
## pitches a train, so wounds mend in the field instead of a march home. Every
## candidate runs the same `HospitalTrain.check` the crown's dossier runs, so the
## planner can never buy tents the rules would refuse, and it spends nothing —
## the map adapter pays (REQ-P2-03, REQ-P3-03).
##
## Pure rules: state in, one army out.

## A field army below this share of its paper strength is worth tents. The
## policy's own bar, not a rule: the train's tempo is `HospitalTrain.REST_SHARE`
## whatever the court's soldiers are owed.
const WORN_SHARE: float = 0.80
## The court keeps a working stock for its yards: it pays only when the
## stockpile covers the price twice over, so a train never eats the last of the
## timber a Builder is waiting on.
const STOCK_MULTIPLE: int = 2


## The army this court should shelter this turn, or null. Tents go to the
## wornest field army that stands where the ground heals worse than the train,
## on the court's own land, with the tech and materials to pay for it.
static func best_army(
	model: MapModel,
	roster: Array[ArmyState],
	owner: int,
	economy: PlayerEconomy,
	at_war: bool
) -> ArmyState:
	if model == null or economy == null or not at_war:
		return null
	if not _keeps_stock(economy):
		return null
	var best: ArmyState = null
	for army: ArmyState in roster:
		if army == null or army.owner != owner:
			continue
		if army.home or army.field_hospital or army.is_embarked() or army.is_empty():
			continue
		if army.province == MapModel.NO_ID or model.province_data(army.province) == null:
			continue
		## A province ward as good as the train would leave the tents idle.
		if HospitalRules.rest_share_at(model, army.province) >= HospitalTrain.REST_SHARE:
			continue
		if worn(army) >= WORN_SHARE:
			continue
		if not bool(
			HospitalTrain.check(
				model, army, economy.tech_unlocked, economy.stockpile
			).get("ok", false)
		):
			continue
		best = _wornest(best, army)
	return best


## The army's average condition as a share of its paper strength (1.0 = fresh).
static func worn(army: ArmyState) -> float:
	if army == null or army.is_empty():
		return 1.0
	var total: float = 0.0
	for regiment_id: String in army.regiments:
		total += float(army.condition_of(regiment_id)["fraction"])
	return total / float(army.regiments.size())


## Has the court's stockpile to spare after the price? Read off the same cost
## table the dossier prints.
static func _keeps_stock(economy: PlayerEconomy) -> bool:
	var cost: Dictionary = HospitalTrain.cost()
	for commodity: String in cost.keys():
		var need: int = int(cost[commodity]) * STOCK_MULTIPLE
		if economy.quantity(commodity) < need:
			return false
	return true


## Wornest first, then the lowest army id — one stable answer for a given roster.
static func _wornest(best: ArmyState, candidate: ArmyState) -> ArmyState:
	if best == null:
		return candidate
	var left: float = worn(candidate)
	var right: float = worn(best)
	if not is_equal_approx(left, right):
		return candidate if left < right else best
	return candidate if candidate.id < best.id else best