class_name CapitalLoss
extends RefCounted
## Capital loss, reassignment and a crown's fall (wiki:
## capital-and-connectivity §§ Capital loss and reassignment, Great Power fall,
## Minor Nation and Tribe terminal fall). Pure rules over the world map: no
## nodes, so the pass runs headless (REQ-P3-03).
##
## A seat is the province whose `capital_of` names the crown. When another
## faction owns that province, the court relocates inside its original region
## or falls. Reassignment keeps the province's own works; it only moves the
## seat, the capital tile and (for Great Powers) the town development of 4.
## Falling courts transfer every province to the conqueror of their seat and
## report themselves so the map layer can disband their armies and fleets.

const NO_ID: int = MapModel.NO_ID
const NO_TILE: Vector2i = CapitalChoice.NO_TILE


## Resolves every lost seat once, in ascending faction id so the same board
## always yields the same result. Returns one record per crown that lost its
## seat; the caller applies the visible consequences (toasts, force removal).
static func resolve(world: WorldMap) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if world == null:
		return changes
	for faction: int in _lost_crowns(world):
		var seat: ProvinceState = _seat_of(world, faction)
		if seat == null or seat.owner < 0:
			continue
		var model: MapModel = _model_of(world, seat)
		if model == null:
			continue
		var conqueror: int = seat.owner
		var kind: int = FactionCatalog.type_of(faction)
		var fallen: bool = _falls(model, faction, kind)
		var capital: Dictionary = {} if fallen else _reassign(model, faction, kind)
		if not fallen and capital.is_empty():
			fallen = true
		if fallen:
			_transfer_all(world, faction, conqueror)
		_clear_seat(seat)
		changes.append({
			"faction": faction,
			"region": model.region_id,
			"lost_province": seat.id,
			"conqueror": conqueror,
			"reassigned": not fallen,
			"capital_province": int(capital.get("province_id", NO_ID)),
			"capital_tile": capital.get("tile", NO_TILE),
			"fallen": fallen,
		})
	# Stale seats (an absorbed crown's old town, a captured capital) never
	# keep a capital marker that belongs to another owner.
	_clear_stale(world)
	return changes


## Crowns whose seat province is now owned by someone else, ascending.
static func _lost_crowns(world: WorldMap) -> Array[int]:
	var ids: Array[int] = []
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.capital_of == NO_ID or province.owner == province.capital_of:
				continue
			if not ids.has(province.capital_of):
				ids.append(province.capital_of)
	ids.sort()
	return ids


## The lost seat of one crown. A crown has exactly one; lowest province wins if
## malformed data ever carries two.
static func _seat_of(world: WorldMap, faction: int) -> ProvinceState:
	var found: ProvinceState = null
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.capital_of != faction or province.owner == faction:
				continue
			if found == null or province.id < found.id:
				found = province
	return found


static func _model_of(world: WorldMap, province: ProvinceState) -> MapModel:
	for model: MapModel in world.regions:
		if model.get_province(province.id) == province:
			return model
	return null


## Retires a crown's seat when Join Empire absorbs it: absorption is not a fall,
## so the loss pass must not report it (wiki: diplomacy § Join Empire).
static func retire_seat(world: WorldMap, faction: int) -> void:
	if world == null:
		return
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.capital_of == faction:
				_clear_seat(province)


## Great Powers keep a court only while they hold a sea-bound province in the
## original capital region; Minors and Tribes need any province there
## (wiki: § Great Power fall, § Minor Nation and Tribe terminal fall).
static func _falls(model: MapModel, faction: int, kind: int) -> bool:
	var owned: Array[int] = CapitalChoice.owned_provinces(model, faction)
	if kind != FactionCatalog.Type.GREAT_POWER:
		return owned.is_empty()
	for province_id: int in owned:
		if CapitalChoice.is_sea_bound(model, province_id):
			return false
	return true


## Moves the seat to the lowest owned province that can seat the court: a
## sea-bound province first (preferring a province that already has a port),
## then inland as the wiki allows. No ports, roads or terrain are added.
static func _reassign(model: MapModel, faction: int, kind: int) -> Dictionary:
	var coast: Array[int] = []
	var inland: Array[int] = []
	for province_id: int in CapitalChoice.owned_provinces(model, faction):
		if CapitalChoice.is_sea_bound(model, province_id):
			coast.append(province_id)
		else:
			inland.append(province_id)
	var ordered: Array[int] = []
	ordered.append_array(coast)
	ordered.append_array(inland)
	for province_id: int in ordered:
		var tile: Vector2i = CapitalChoice.choose_tile(model, province_id, kind)
		if tile == NO_TILE:
			continue
		var province: ProvinceState = model.get_province(province_id)
		if province == null:
			continue
		province.capital = true
		province.capital_of = faction
		province.capital_tile = tile
		if kind == FactionCatalog.Type.GREAT_POWER:
			province.town_development = CapitalChoice.CAPITAL_TOWN_DEVELOPMENT
		return {"province_id": province_id, "tile": tile}
	return {}


## Every holding changes colours with the fallen court; the province keeps its
## works and owner-side tiles, only `owner` changes (wiki: § Great Power fall).
static func _transfer_all(world: WorldMap, faction: int, conqueror: int) -> int:
	var transferred: int = 0
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			province.owner = conqueror
			province.capital = false
			province.capital_of = NO_ID
			province.capital_tile = NO_TILE
			transferred += 1
	return transferred


static func _clear_seat(province: ProvinceState) -> void:
	province.capital = false
	province.capital_of = NO_ID
	province.capital_tile = NO_TILE


## A capital marker must belong to the province's present owner. This also
## retires the old seat of a crown absorbed by Join Empire.
static func _clear_stale(world: WorldMap) -> void:
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if not province.capital:
				continue
			if province.capital_of == province.owner and province.owner != NO_ID:
				continue
			province.capital = false
			province.capital_of = NO_ID
			province.capital_tile = NO_TILE
