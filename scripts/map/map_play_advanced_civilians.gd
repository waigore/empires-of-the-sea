class_name MapPlayAdvancedCivilians
extends RefCounted
## Tops every crown's civilian roster to the advanced-start tier totals at its
## own capital (and across its Old World land when the capital is full). Session
## wiring only — catalog counts live on AdvancedStart (REQ-P3-01).


## Tops every crown's civilian roster up to the tier totals at its own capital.
static func apply(play: PlaySession, tier: String) -> void:
	var model: MapModel = play.world.region(0)
	if model == null:
		return
	var roster: Array = _roster(play)
	var works: LandWorks = play.civilian_layer.works_regions.value(0, null)
	var taken: Dictionary = _taken_tiles(model, roster)
	var totals: Dictionary = AdvancedStart.civilians(tier)
	for faction: int in model.faction_ids:
		if FactionCatalog.type_of(faction) != FactionCatalog.Type.GREAT_POWER:
			continue
		var provinces: Array[ProvinceState] = _muster_provinces(model, faction)
		if provinces.is_empty():
			continue
		for province: ProvinceState in provinces:
			taken[province.capital_tile] = true
			if works != null:
				for tile: Vector2i in province.tiles:
					if works.improvement_at(model, tile) > 0:
						taken[tile] = true
		for type_id: Variant in totals.keys():
			var want: int = int(totals[type_id])
			var have: int = _count_type(roster, faction, String(type_id))
			for _index in maxi(want - have, 0):
				var tile: Vector2i = _free_tile(model, provinces, taken)
				if tile.x < 0:
					break
				taken[tile] = true
				roster.append(_new_civilian(play, faction, String(type_id), tile))


static func _new_civilian(
	play: PlaySession, faction: int, type_id: String, tile: Vector2i
) -> CivilianState:
	var unit: CivilianState = CivilianState.create(
		play.civilian_layer.next_id, faction, type_id, tile
	)
	play.civilian_layer.next_id += 1
	return unit


static func _roster(play: PlaySession) -> Array:
	var list: Array = play.civilian_layer.regions.value(0, [])
	play.civilian_layer.regions.set_region(0, list)
	return list


static func _taken_tiles(model: MapModel, roster: Array) -> Dictionary:
	var taken: Dictionary = {}
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and not unit.is_embarked():
			taken[unit.tile] = true
	return taken


static func _count_type(roster: Array, owner: int, type_id: String) -> int:
	var count: int = 0
	for raw: Variant in roster:
		var unit: CivilianState = raw as CivilianState
		if unit != null and unit.owner == owner and unit.type_id == type_id:
			count += 1
	return count


## The crown's own land, seat first then the rest of its provinces in id order:
## a tier roster larger than the capital can hold musters across the realm.
static func _muster_provinces(model: MapModel, faction: int) -> Array[ProvinceState]:
	var provinces: Array[ProvinceState] = []
	var seat: ProvinceState = _capital(model, faction)
	if seat != null:
		provinces.append(seat)
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province != seat:
			provinces.append(province)
	return provinces


static func _free_tile(
	model: MapModel, provinces: Array[ProvinceState], taken: Dictionary
) -> Vector2i:
	for province: ProvinceState in provinces:
		for tile: Vector2i in province.tiles:
			if tile == province.capital_tile or taken.has(tile):
				continue
			if model.is_land(tile.x, tile.y):
				return tile
	return Vector2i(-1, -1)


static func _capital(model: MapModel, faction: int) -> ProvinceState:
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province
	return null
