class_name ArmyMuster
extends RefCounted
## Builds one region's opening Home Armies: who owns each capital and which
## regiment types it musters. ArmyLayer keeps markers, orders and battles;
## this pure mustering step stays free of nodes (REQ-P3-03) and small enough
## to test on its own (REQ-P3-01).

## Opening musters; the wiki fixes the Home Army's existence, not its size.
const GREAT_POWER_ROSTER: Array[String] = [
	"peasant_levies", "peasant_levies", "pikemen", "arquebusiers", "squires"
]
const MINOR_ROSTER: Array[String] = ["peasant_levies", "peasant_levies", "bowmen"]
const TRIBE_ROSTER: Array[String] = ["peasant_levies", "peasant_levies"]

## Regiment and army ids stay unique for the life of the save; the layer hands
## its cursors in and takes the advanced values back.
var next_army: int = 1
var next_regiment: int = 1


## Musters a Home Army (or recovered/field army) and advances the id cursors.
func mint(owner: int, province: int, home: bool, types: Array[String]) -> ArmyState:
	var army := ArmyState.muster(
		next_army, owner, province, home, types, next_regiment
	)
	next_army += 1
	next_regiment += types.size()
	return army


## Opening Home Army at every capital on first visit to a region.
func build(model: MapModel) -> Array[ArmyState]:
	var armies: Array[ArmyState] = []
	if model == null:
		return armies
	for faction: int in model.faction_ids:
		var capital: int = MapModel.NO_ID
		for province: ProvinceState in model.provinces:
			if province.owner == faction and province.capital:
				capital = province.id
				break
		if capital < 0:
			continue
		armies.append(mint(faction, capital, true, roster_for(faction)))
	return armies


static func roster_for(faction: int) -> Array[String]:
	match FactionCatalog.type_of(faction):
		FactionCatalog.Type.GREAT_POWER:
			return GREAT_POWER_ROSTER.duplicate()
		FactionCatalog.Type.MINOR_NATION:
			return MINOR_ROSTER.duplicate()
		_:
			return TRIBE_ROSTER.duplicate()
