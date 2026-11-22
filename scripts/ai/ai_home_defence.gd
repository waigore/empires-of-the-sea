class_name AiHomeDefence
extends RefCounted
## Reads the land war as home defence (issue #1259): the seat's own province held
## by the invader, the seat gone to the invader, or hostile ground on the court's
## own frontier. Then the land war is on the court's soil, and a host marching
## toward it outranks the foreign adventure the staging branch would price.
## Pure reads: state in, answer out.


## Two hostile provinces on the court's frontier read as land already lost.
const LOST_FRONTIER: int = 2


## True when the land war stands on the court's own soil: the seat's province
## held by the invader, the seat gone — `capital_province` reads only held
## ground, so a taken capital reads NO_ID — or hostile ground on its frontier.
static func active(model: MapModel, owner: int, hostile: Dictionary) -> bool:
	var seat: int = WorldBootstrap.capital_province(model, owner)
	if seat == MapModel.NO_ID:
		return _capital_taken(model, owner, hostile)
	if model.province_owner(seat) != owner:
		return true
	return _provinces_lost(model, owner, hostile) >= LOST_FRONTIER


## A lost seat: a hostile-held capital province touching the court's own land.
static func _capital_taken(
	model: MapModel, owner: int, hostile: Dictionary
) -> bool:
	for province: ProvinceState in model.provinces:
		if not province.capital or not hostile.has(province.owner):
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			if model.province_owner(neighbor) == owner:
				return true
	return false


## Hostile ground on the court's own frontier: every one of these provinces was
## its own ground until the invader took it. Zero when the war is abroad.
static func _provinces_lost(
	model: MapModel, owner: int, hostile: Dictionary
) -> int:
	var lost: int = 0
	for province: ProvinceState in model.provinces:
		if province.owner == owner or not hostile.has(province.owner):
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			if model.province_owner(neighbor) == owner:
				lost += 1
				break
	return lost


## Two destinations priced the same: meeting a hostile host already standing on
## the court's own ground is the lost land itself, so it outranks a storm onto
## the invader's frontier; otherwise the lower province id wins.
static func outranks(
	model: MapModel, army: ArmyState, province: int, kind: String, best: Dictionary
) -> bool:
	var meet: bool = kind == "defend" and model.province_owner(province) == army.owner
	var best_meet: bool = String(best["kind"]) == "defend" \
		and model.province_owner(int(best["province"])) == army.owner
	if meet != best_meet:
		return meet
	return province < int(best["province"])
