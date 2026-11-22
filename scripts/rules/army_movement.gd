class_name ArmyMovement
extends RefCounted
## Land army movement (wiki: military-armies § Movement and attacks).
## Pure rules: callers apply the result; this module never touches nodes
## (REQ-P3-03).
##
## One army marches once per turn. An army may enter any province it owns in
## its region (interior lines) and only an adjacent province it does not own
## (hostile or neutral land). The Home Army never leaves the capital.

const NO_PROVINCE: int = MapModel.NO_ID

## The walk home's own words, published on the page and printed by both surfaces
## that speak them — the dossier's hint and the refusal a home march hears
## (wiki: military-armies § Movement and attacks; DR-20261121-15). One home, so a
## crown never reads two sentences for the one rule.
const NO_OWN_LAND_REACH: String = (
	"No own land touches here — march through the provinces beside you, "
	+ "one march at a time, to reach home."
)
const NO_INTERIOR_LINES: String = (
	"No interior lines run from this ground — march through the provinces "
	+ "beside you, one march at a time, to reach home."
)
## The walk home's words when the court's seat lies on another chart: no land
## march from this shore reaches it at all, so the rule names the road that does
## — a squadron (wiki: military-armies § Movement and attacks; ships-and-naval
## § Naval transport (armies); DR-20261122-07).
const NO_OWN_LAND_REACH_OVERSEAS: String = (
	"No own land touches here, and your seat lies across the sea — no land march "
	+ "reaches it; a squadron in port must carry this host home."
)


## Legal destinations for the army's one march this turn. A host standing on
## ground its own court does not hold has no interior lines, so only the
## provinces beside it are open. Foreign land is listed but a march into it is
## refused at order time unless at war with its owner (wiki: diplomacy § War
## required for hostile actions).
static func destinations(model: MapModel, army: ArmyState) -> Array[int]:
	var result: Array[int] = []
	if not _can_act(model, army):
		return result
	if not on_own_ground(model, army):
		# Off its own ground an army keeps no interior lines: the provinces beside
		# it are the whole of its road, one march a turn (wiki: military-armies
		# § Movement and attacks; DR-20261121-15).
		result.assign(MapGeo.province_neighbors(model, army.province))
		result.sort()
		return result
	var reachable: Array[int] = land_reachable(model, army.province, army.owner)
	for province: ProvinceState in model.provinces:
		var province_id: int = province.id
		if province_id == army.province:
			continue
		if province.owner == army.owner and reachable.has(province_id):
			result.append(province_id)
	if army.province != NO_PROVINCE:
		for neighbor: int in MapGeo.province_neighbors(model, army.province):
			if not result.has(neighbor):
				result.append(neighbor)
	result.sort()
	return result


## Own provinces on the same landmass and connected through own territory.
## Interior lines are abstracted as one march, but a land army cannot cross
## open water or foreign land without transports and battles.
static func land_reachable(
	model: MapModel, province_id: int, owner: int = MapModel.NO_ID
) -> Array[int]:
	var found: Array[int] = []
	if model == null or model.province_data(province_id) == null:
		return found
	var queue: Array[int] = [province_id]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if found.has(current):
			continue
		found.append(current)
		for neighbor: int in MapGeo.province_neighbors(model, current):
			if found.has(neighbor):
				continue
			if owner != MapModel.NO_ID and model.province_owner(neighbor) != owner:
				continue
			queue.append(neighbor)
	return found


static func can_move(
	model: MapModel, army: ArmyState, province_id: int, at_war: bool = true
) -> Dictionary:
	if army == null:
		return OrderVerdict.deny("There is no army to order.")
	if army.home:
		return OrderVerdict.deny("The Home Army never leaves the capital; detach a field army first.")
	if army.moved:
		return OrderVerdict.deny("This army has already marched this turn.")
	if army.is_empty():
		return OrderVerdict.deny("An army with no regiments cannot march.")
	if model == null or model.province_data(province_id) == null:
		return OrderVerdict.deny("That is not a province.")
	if province_id == army.province:
		return OrderVerdict.deny("The army is already in that province.")
	if model.province_owner(province_id) == army.owner:
		if not on_own_ground(model, army):
			# Interior lines only run through own provinces, and a host camped on
			# another court's land (or on unclaimed wilderness) holds none: the
			# provinces beside it are its whole road home (wiki: military-armies
			# § Movement and attacks; DR-20261121-15).
			if MapGeo.province_neighbors(model, army.province).has(province_id):
				return OrderVerdict.allow()
			return OrderVerdict.deny(_off_ground_refusal(model, army))
		if land_reachable(model, army.province, army.owner).has(province_id):
			return OrderVerdict.allow()
		return OrderVerdict.deny("Own land across open water or foreign land needs a naval transport.")
	if not MapGeo.province_neighbors(model, army.province).has(province_id):
		return OrderVerdict.deny("Enemy or neutral land may only be entered from an adjacent province.")
	if not at_war and _is_foreign(model, army, province_id):
		return OrderVerdict.deny(
			"Peace holds with %s; declare war before invading."
			% FactionCatalog.name_of(model.province_owner(province_id))
		)
	return OrderVerdict.allow()


## Validates, then moves every regiment with the army. `attacked` reports that
## the destination belongs to another faction.
static func apply_move(
	model: MapModel, army: ArmyState, province_id: int, at_war: bool = true
) -> Dictionary:
	var check: Dictionary = can_move(model, army, province_id, at_war)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": String(check.get("reason", "")), "attacked": false}
	var attacked: bool = model.province_owner(province_id) != army.owner
	army.province = province_id
	army.moved = true
	return {"ok": true, "reason": "", "attacked": attacked}


## True when the army stands on land its own court holds. An army camped on
## another court's ground — a beaten host left where it fought — has no interior
## lines to use, so only the provinces beside it are open (wiki: military-armies
## § Movement and attacks).
static func on_own_ground(model: MapModel, army: ArmyState) -> bool:
	if model == null or army == null or army.province == NO_PROVINCE:
		return false
	return model.province_owner(army.province) == army.owner


## True when no own province is one march away: the army stands on ground it does
## not hold and every province beside it belongs to someone else. The road home
## is then a walk through foreign ground, and the dossier says so (wiki:
## military-armies § Movement and attacks).
static func stranded(model: MapModel, army: ArmyState) -> bool:
	if not _can_act(model, army) or on_own_ground(model, army):
		return false
	for province: int in destinations(model, army):
		if model.province_owner(province) == army.owner:
			return false
	return true


## What a host standing off its own ground hears when it is ordered to own land
## it cannot reach in one march. The wiki's own sentence when no own land touches;
## the interior-lines word when own land does, so the refusal never claims a
## border the map shows (wiki: military-armies § Movement and attacks).
static func _off_ground_refusal(model: MapModel, army: ArmyState) -> String:
	if stranded(model, army):
		return walk_home_words(model, army)
	return NO_INTERIOR_LINES


## The walk home's one sentence for this host: the rule's own words on the seat's
## own chart, and the sea's words when the court's seat lies on another chart, so
## no shore ever promises a land march home that cannot exist (wiki: military-
## armies § Movement and attacks; ships-and-naval § Naval transport (armies);
## DR-20261122-07).
static func walk_home_words(model: MapModel, army: ArmyState) -> String:
	if seat_elsewhere(model, army):
		return NO_OWN_LAND_REACH_OVERSEAS
	return NO_OWN_LAND_REACH


## True when the army stands on a chart that holds no seat of its court while the
## court keeps that seat on another chart — an overseas holding, where no land
## march reaches home (DR-20261122-07). A chart that holds the seat, and a court
## the catalogue gives no chart at all, read false, so the land words stand.
static func seat_elsewhere(model: MapModel, army: ArmyState) -> bool:
	if model == null or army == null:
		return false
	if capital_province_on(model, army.owner) != NO_PROVINCE:
		return false
	var home: int = FactionCatalog.region_of(army.owner)
	return home >= 0 and home != model.region_id


## The court's own seat on this chart, read without touching the session: the
## province it owns here that carries the capital (wiki: capital-and-connectivity
## § Capital; world-model-identity — ids never cross charts).
static func capital_province_on(model: MapModel, faction: int) -> int:
	if model == null:
		return NO_PROVINCE
	return WorldBootstrap.capital_province(model, faction)


## Land held by another faction; unowned wilderness is not an invasion.
static func _is_foreign(model: MapModel, army: ArmyState, province_id: int) -> bool:
	var owner: int = model.province_owner(province_id)
	return owner != MapModel.NO_ID and owner != army.owner


static func begin_turn(armies: Array[ArmyState], model: MapModel = null) -> void:
	for army: ArmyState in armies:
		if army != null:
			army.moved = false
			# Field depots replace part of the battle's wear each turn; a
			# province hospital sets a faster tempo, and an army's own train
			# carries the field's tempo wherever it stands — the better of the
			# two, never both (wiki: combat § Strength; DR-20261110-19,
			# DR-20261111-12, DR-20261112-07).
			var share: float = HospitalTrain.army_rest_share(
				model, army.province, army.field_hospital
			)
			RegimentCondition.rest(army, share)


static func _can_act(model: MapModel, army: ArmyState) -> bool:
	return (
		model != null
		and army != null
		and not army.home
		and not army.moved
		and not army.is_empty()
		and army.province != NO_PROVINCE
	)
