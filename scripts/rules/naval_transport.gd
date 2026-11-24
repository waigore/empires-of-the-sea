class_name NavalTransport
extends RefCounted
## Army embarkation and landing (wiki: ships-and-naval § Naval transport;
## DR-20261109-08). Pure rules: callers apply the result, this module never
## touches nodes (REQ-P3-03).
##
## A squadron in port takes one field army aboard; each hull carries one
## regiment. The fleet may then sail and land the army on an owned coast that
## borders its sea zone. A hostile shore needs a Beachhead marked on the turn
## before (wiki: ships-and-naval § Missions and Movement). What a deck can hold,
## and what drowns when the sea takes a hull, is [NavalDeck]'s count.

const NO_ID: int = MapModel.NO_ID


## A field army in the fleet's port may board when the hulls can hold it.
static func can_embark(model: MapModel, army: ArmyState, fleet: FleetState) -> Dictionary:
	if army == null:
		return OrderVerdict.deny("There is no army to embark.")
	if fleet == null:
		return OrderVerdict.deny("No fleet waits in this port.")
	if army.owner != fleet.owner:
		return OrderVerdict.deny("Own colours only.")
	if army.home:
		return OrderVerdict.deny("The Home Army never leaves the capital; detach a field army first.")
	if army.is_empty():
		return OrderVerdict.deny("An army with no regiments cannot embark.")
	if army.is_embarked():
		return OrderVerdict.deny("The army is already aboard a fleet.")
	if army.moved:
		return OrderVerdict.deny("This army has already marched this turn.")
	if not fleet.is_in_port():
		return OrderVerdict.deny("The fleet must be in port to take troops aboard.")
	if fleet.province != army.province:
		return OrderVerdict.deny("The fleet is not in this port.")
	if fleet.moved:
		return OrderVerdict.deny("This fleet has already sailed this turn.")
	if fleet.embarked_army >= 0:
		return OrderVerdict.deny("The fleet already carries an army.")
	if fleet.carries_civilians():
		return OrderVerdict.deny("The squadron is carrying colonists; land them before taking troops aboard.")
	if army.count() > NavalDeck.capacity(fleet):
		var room: int = NavalDeck.capacity(fleet)
		var men: int = army.count()
		# One hull holds one regiment: the deck names both counts, and a host of
		# one reads the singular (REQ-P1-07; the press prints these words as its
		# own caption, DR-20261124-14).
		return OrderVerdict.deny(
			"The squadron has %d hull%s and cannot carry %d regiment%s."
			% [room, "" if room == 1 else "s", men, "" if men == 1 else "s"]
		)
	if model == null or model.province_data(army.province) == null:
		return OrderVerdict.deny("That is not a province.")
	return OrderVerdict.allow()


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
	return OrderVerdict.allow()


## Owned coastal provinces the fleet could land troops on right now; a ready
## beachhead adds the hostile coast it marked (wiki: ships-and-naval § Missions
## and Movement, § Naval transport).
static func landing_provinces(
	model: MapModel,
	fleet: FleetState,
	turn: int = 0,
	hostile: Callable = Callable()
) -> Array[int]:
	var provinces: Array[int] = []
	if model == null or fleet == null:
		return provinces
	if fleet.is_in_port():
		if model.province_owner(fleet.province) == fleet.owner:
			provinces.append(fleet.province)
		return provinces
	provinces = NavalMovement.owned_provinces_by_zone(model, fleet.sea_zone, fleet.owner)
	if beachhead_allows(model, fleet, fleet.beachhead_province, turn, hostile):
		provinces.append(fleet.beachhead_province)
		provinces.sort()
	return provinces


## Hostile coastal provinces this squadron could mark for a landing: adjacent to
## its sea zone, owned by a crown it is at war with (wiki: ships-and-naval
## § Missions and Movement).
static func hostile_coasts(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> Array[int]:
	var coasts: Array[int] = []
	if model == null or fleet == null or not fleet.is_at_sea():
		return coasts
	for province_id: int in NavalMovement.provinces_by_zone(model, fleet.sea_zone):
		var owner: int = model.province_owner(province_id)
		if owner == MapModel.NO_ID or owner == fleet.owner:
			continue
		if not Hostility.between(hostile, fleet.owner, owner):
			continue
		coasts.append(province_id)
	return coasts


## Validates the Beachhead mission without mutating the fleet.
static func can_establish_beachhead(
	model: MapModel,
	fleet: FleetState,
	province_id: int,
	turn: int = 0,
	hostile: Callable = Callable()
) -> Dictionary:
	if fleet == null or model == null:
		return OrderVerdict.deny("No squadron can take that station.")
	if not fleet.is_at_sea():
		return OrderVerdict.deny("The squadron must be at sea to mark a beachhead.")
	if not fleet.is_afloat():
		return OrderVerdict.deny("A squadron with no hulls cannot land troops.")
	if fleet.moved:
		return OrderVerdict.deny("This fleet has already moved or taken a mission this turn.")
	if model.province_data(province_id) == null:
		return OrderVerdict.deny("That is not a province.")
	var owner: int = model.province_owner(province_id)
	if owner == fleet.owner:
		return OrderVerdict.deny("A beachhead is only needed on a hostile coast.")
	if owner == MapModel.NO_ID:
		return OrderVerdict.deny("That coast belongs to no crown.")
	if not Hostility.between(hostile, fleet.owner, owner):
		return OrderVerdict.deny("A beachhead needs a declared war with %s." % FactionCatalog.name_of(owner))
	if not NavalMovement.provinces_by_zone(model, fleet.sea_zone).has(province_id):
		return OrderVerdict.deny("That coast does not border the fleet's sea zone.")
	return OrderVerdict.allow()


## Marks the landing site; the squadron spends this turn's move or mission and
## may land troops from the following turn (wiki: ships-and-naval).
static func establish_beachhead(
	model: MapModel,
	fleet: FleetState,
	province_id: int,
	turn: int,
	hostile: Callable = Callable()
) -> Dictionary:
	var check: Dictionary = can_establish_beachhead(
		model, fleet, province_id, turn, hostile
	)
	if not bool(check.get("ok", false)):
		return check
	fleet.beachhead_province = province_id
	fleet.beachhead_turn = turn
	fleet.mission = FleetState.Mission.BEACHHEAD
	fleet.moved = true
	return {
		"ok": true,
		"reason": "",
		"province": province_id,
		"name": model.province_name(province_id),
	}


## The landing site is usable on the turn after it was marked, and only while the
## squadron holds its station (wiki: ships-and-naval § Missions and Movement).
static func beachhead_ready(fleet: FleetState, turn: int) -> bool:
	if fleet == null or not fleet.is_at_sea() or not fleet.has_beachhead():
		return false
	return turn == fleet.beachhead_turn + 1


## True when this fleet's ready beachhead opens `province_id` to a landing.
static func beachhead_allows(
	model: MapModel,
	fleet: FleetState,
	province_id: int,
	turn: int = 0,
	hostile: Callable = Callable()
) -> bool:
	if model == null or fleet == null or province_id < 0:
		return false
	if fleet.beachhead_province != province_id or not beachhead_ready(fleet, turn):
		return false
	return beachhead_target_valid(model, fleet, hostile)


## True while the marked coast is still a hostile shore this squadron could
## land on: a province that changes hands or a war that ends leaves the marker
## without a landing (wiki: ships-and-naval § Missions and Movement).
static func beachhead_target_valid(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> bool:
	if model == null or fleet == null or not fleet.has_beachhead():
		return false
	var province_id: int = fleet.beachhead_province
	if not NavalMovement.provinces_by_zone(model, fleet.sea_zone).has(province_id):
		return false
	var owner: int = model.province_owner(province_id)
	if owner == MapModel.NO_ID or owner == fleet.owner:
		return false
	return Hostility.between(hostile, fleet.owner, owner)


## Expires every beachhead whose one full turn has run; called at end of turn.
static func expire_beachheads(fleets: Array[FleetState], turn: int) -> void:
	for fleet: FleetState in fleets:
		if fleet == null or not fleet.has_beachhead():
			continue
		if turn >= fleet.beachhead_turn + 1:
			fleet.clear_beachhead()


## The army may land on its owner's coast: the port province when docked, or a
## province bordering the fleet's sea zone. A hostile shore needs a ready
## beachhead (wiki: ships-and-naval § Missions and Movement). The squadron's own
## roster names the troops it carries; the army's back-pointer may lag a
## renumbered or merged squadron, so it is not the gate.
static func can_disembark(
	model: MapModel,
	army: ArmyState,
	fleet: FleetState,
	province_id: int,
	turn: int = 0,
	hostile: Callable = Callable()
) -> Dictionary:
	if army == null or fleet == null:
		return OrderVerdict.deny("No army is aboard this fleet.")
	if fleet.embarked_army != army.id:
		return OrderVerdict.deny("No army is aboard this fleet.")
	if model == null or model.province_data(province_id) == null:
		return OrderVerdict.deny("That is not a province.")
	if model.province_owner(province_id) != army.owner:
		if not beachhead_allows(model, fleet, province_id, turn, hostile):
			# A marked site that is not open yet names its own wait: the court is
			# not asked to find a beachhead it already holds (wiki: ships-and-naval
			# § Missions and Movement).
			if fleet.beachhead_province == province_id and fleet.has_beachhead():
				if not beachhead_ready(fleet, turn):
					return OrderVerdict.deny(
						"The beachhead at %s opens next turn."
						% model.province_name(province_id)
					)
				# Open by the clock but no longer a hostile shore (it changed
				# hands or the war ended): waiting never opens it, so the refusal
				# names the loss instead of promising a turn that never comes.
				return OrderVerdict.deny(
					"The beachhead at %s has lapsed — that shore is no longer an enemy's."
					% model.province_name(province_id)
				)
			return OrderVerdict.deny("Troops can only land on your own coast; a hostile landing needs a beachhead.")
		return OrderVerdict.allow()
	if fleet.is_in_port():
		if province_id != fleet.province:
			return OrderVerdict.deny("The fleet is in port at %s." % model.province_name(fleet.province))
		return OrderVerdict.allow()
	if not NavalMovement.owned_provinces_by_zone(model, fleet.sea_zone, army.owner).has(province_id):
		return OrderVerdict.deny("That coast does not border the fleet's sea zone.")
	return OrderVerdict.allow()


## Lands the army on the chosen coast; it has spent this turn's march. A hostile
## landing consumes the beachhead it used.
static func disembark(
	model: MapModel,
	army: ArmyState,
	fleet: FleetState,
	province_id: int,
	turn: int = 0,
	hostile: Callable = Callable()
) -> Dictionary:
	var check: Dictionary = can_disembark(
		model, army, fleet, province_id, turn, hostile
	)
	if not bool(check.get("ok", false)):
		return check
	var invaded: bool = model.province_owner(province_id) != army.owner
	army.province = province_id
	army.embarked_fleet = -1
	army.moved = true
	fleet.embarked_army = -1
	if invaded:
		fleet.clear_beachhead()
	return OrderVerdict.allow()
