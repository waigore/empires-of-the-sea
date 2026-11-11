class_name FleetHomeMerge
extends RefCounted
## Which squadron is a crown's home fleet, the one-tap order that folds a
## squadron moored at the seat into it, and the absorption a docking squadron
## gets (wiki: ships-and-naval § Home Fleet — membership and state).
## Pure rules: callers own markers, toasts and army placement (REQ-P3-03).


## The crown's home fleet in one roster: the oldest squadron in port at its
## seat. A transitional save that parks two there keeps the oldest as home, so
## the yard, the holds and the dossier all read one squadron.
static func home_fleet(
	model: MapModel, roster: Array[FleetState], owner: int
) -> FleetState:
	var home: FleetState = null
	for fleet: FleetState in roster:
		if fleet == null or fleet.owner != owner:
			continue
		if not NavalMovement.is_home_fleet(model, fleet):
			continue
		if home == null or fleet.id < home.id:
			home = fleet
	return home


## The squadron a merge folds into: the oldest other squadron moored at the same
## seat, so a docking squadron always finds the home fleet beside her (and never
## herself).
static func merge_target(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> FleetState:
	if model == null or fleet == null or not fleet.is_in_port():
		return null
	var target: FleetState = null
	for other: FleetState in roster:
		if other == null or other == fleet or other.owner != fleet.owner:
			continue
		if other.province != fleet.province:
			continue
		if not NavalMovement.is_home_fleet(model, other):
			continue
		if target == null or other.id < target.id:
			target = other
	return target


## Verdict for "join the home fleet": the squadron must be moored at its own
## capital, carry hulls, and have another squadron there to join. Nothing is
## destroyed or spent, so the order stays one tap (DR-20261109-01).
static func can_join(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Dictionary:
	if model == null or fleet == null:
		return _deny("There is no squadron to join.")
	if not fleet.is_in_port():
		return _deny("Sail the squadron into your capital port first.")
	if not NavalMovement.is_home_fleet(model, fleet):
		return _deny("Only a squadron moored at your own capital can join the home fleet.")
	if not fleet.is_afloat():
		return _deny("A slip with no hulls has nothing to join.")
	if merge_target(model, roster, fleet) == null:
		return _deny("She is the only squadron at your capital — launch or dock another first.")
	return {"ok": true, "reason": ""}


## Folds a moored squadron into the home fleet: every hull, name and passenger
## keeps, and the emptied sea-going squadron leaves the roster. Returns the home
## fleet, how many hulls joined and an army the home squadron could not keep
## aboard (-1 when none).
static func join(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Dictionary:
	var check: Dictionary = can_join(model, roster, fleet)
	if not bool(check.get("ok", false)):
		return _refused(String(check.get("reason", "")))
	return absorb(model, roster, fleet)


## The merge a squadron docking at its own capital gets (wiki: ships-and-naval
## § Home Fleet). A squadron already alone at the seat has nothing to join.
static func absorb(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Dictionary:
	if model == null or fleet == null:
		return _refused("")
	if not NavalMovement.is_home_fleet(model, fleet):
		return _refused("")
	var target: FleetState = merge_target(model, roster, fleet)
	if target == null:
		return _refused("")
	var hulls: int = fleet.ship_count()
	var displaced: int = target.merge_from(fleet)
	roster.erase(fleet)
	return {"ok": true, "fleet": target, "hulls": hulls, "displaced": displaced, "reason": ""}


## One squadron per capital port: every extra squadron parked at the seat folds
## into the home fleet. Transitional saves and a court hand-over can leave two,
## so the pass is idempotent and reports what it absorbed.
static func settle(
	model: MapModel, roster: Array[FleetState], owner: int
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var home: FleetState = home_fleet(model, roster, owner)
	if home == null:
		return reports
	var strays: Array[FleetState] = []
	for fleet: FleetState in roster:
		if fleet == null or fleet == home or fleet.owner != owner:
			continue
		if NavalMovement.is_home_fleet(model, fleet):
			strays.append(fleet)
	for stray: FleetState in strays:
		var merged: Dictionary = absorb(model, roster, stray)
		if not bool(merged.get("ok", false)):
			continue
		reports.append({
			"owner": owner,
			"fleet": stray.id,
			"into": home.id,
			"hulls": int(merged["hulls"]),
			"displaced": int(merged["displaced"]),
			"seat": home.province,
		})
	return reports


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "fleet": null, "hulls": 0, "displaced": -1, "reason": reason}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
