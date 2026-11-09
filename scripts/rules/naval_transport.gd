class_name NavalTransport
extends RefCounted
## Army embarkation and landing (wiki: ships-and-naval § Naval transport;
## DR-20261109-08). Pure rules: callers apply the result, this module never
## touches nodes (REQ-P3-03).
##
## A squadron in port takes one field army aboard; each hull carries one
## regiment. The fleet may then sail and land the army on an owned coast that
## borders its sea zone. A hostile landing still needs a beachhead, so this
## slice moves troops between friendly shores only.

const NO_ID: int = MapModel.NO_ID


## Regiments the squadron can carry: one per hull.
static func capacity(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	return fleet.ship_count()


## A field army in the fleet's port may board when the hulls can hold it.
static func can_embark(model: MapModel, army: ArmyState, fleet: FleetState) -> Dictionary:
	if army == null:
		return _deny("There is no army to embark.")
	if fleet == null:
		return _deny("No fleet waits in this port.")
	if army.owner != fleet.owner:
		return _deny("Own colours only.")
	if army.home:
		return _deny("The Home Army never leaves the capital; detach a field army first.")
	if army.is_empty():
		return _deny("An army with no regiments cannot embark.")
	if army.is_embarked():
		return _deny("The army is already aboard a fleet.")
	if army.moved:
		return _deny("This army has already marched this turn.")
	if not fleet.is_in_port():
		return _deny("The fleet must be in port to take troops aboard.")
	if fleet.province != army.province:
		return _deny("The fleet is not in this port.")
	if fleet.moved:
		return _deny("This fleet has already sailed this turn.")
	if fleet.embarked_army >= 0:
		return _deny("The fleet already carries an army.")
	if army.count() > capacity(fleet):
		return _deny(
			"The squadron has %d hulls and cannot carry %d regiments."
			% [capacity(fleet), army.count()]
		)
	if model == null or model.province_data(army.province) == null:
		return _deny("That is not a province.")
	return _allow()


## Boards the army: it leaves the land, spends its march, and the fleet carries
## its instance id until it lands.
static func embark(model: MapModel, army: ArmyState, fleet: FleetState) -> Dictionary:
	var check: Dictionary = can_embark(model, army, fleet)
	if not bool(check.get("ok", false)):
		return check
	army.embarked_fleet = fleet.id
	army.province = NO_ID
	army.moved = true
	fleet.embarked_army = army.id
	return _allow()


## Owned coastal provinces the fleet could land troops on right now.
static func landing_provinces(model: MapModel, fleet: FleetState) -> Array[int]:
	var provinces: Array[int] = []
	if model == null or fleet == null:
		return provinces
	if fleet.is_in_port():
		if model.province_owner(fleet.province) == fleet.owner:
			provinces.append(fleet.province)
		return provinces
	return NavalMovement.owned_provinces_by_zone(model, fleet.sea_zone, fleet.owner)


## The army may land on its owner's coast: the port province when docked, or a
## province bordering the fleet's sea zone. Hostile shores need a beachhead.
static func can_disembark(
	model: MapModel, army: ArmyState, fleet: FleetState, province_id: int
) -> Dictionary:
	if army == null or fleet == null:
		return _deny("No army is aboard this fleet.")
	if army.embarked_fleet != fleet.id or fleet.embarked_army != army.id:
		return _deny("No army is aboard this fleet.")
	if model == null or model.province_data(province_id) == null:
		return _deny("That is not a province.")
	if model.province_owner(province_id) != army.owner:
		return _deny("Troops can only land on your own coast; a hostile landing needs a beachhead.")
	if fleet.is_in_port():
		if province_id != fleet.province:
			return _deny("The fleet is in port at %s." % model.province_name(fleet.province))
		return _allow()
	if not NavalMovement.owned_provinces_by_zone(model, fleet.sea_zone, army.owner).has(province_id):
		return _deny("That coast does not border the fleet's sea zone.")
	return _allow()


## Lands the army on the chosen owned province; it has spent this turn's march.
static func disembark(
	model: MapModel, army: ArmyState, fleet: FleetState, province_id: int
) -> Dictionary:
	var check: Dictionary = can_disembark(model, army, fleet, province_id)
	if not bool(check.get("ok", false)):
		return check
	army.province = province_id
	army.embarked_fleet = -1
	army.moved = true
	fleet.embarked_army = -1
	return _allow()


## Breaking up a hull must not leave more regiments aboard than hulls afloat.
static func can_scrap(fleet: FleetState, army: ArmyState) -> Dictionary:
	if fleet == null or fleet.embarked_army < 0:
		return _allow()
	if army == null:
		return _deny("The troops aboard cannot be accounted for.")
	if fleet.ship_count() - 1 < army.count():
		return _deny(
			"The squadron cannot break up a hull while it carries %d regiments."
			% army.count()
		)
	return _allow()


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
