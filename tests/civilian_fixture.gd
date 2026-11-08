extends RefCounted
## Synthetic civilian map shared by rules tests: two land provinces split at
## x = 3, one sea row along the bottom, resource tiles for improvements and
## prospection. Kept tiny so expectations stay readable.

const PLAYER_PROVINCE: int = 0
const RIVAL_PROVINCE: int = 1
const IRON_TILE: Vector2i = Vector2i(1, 1)
const TIMBER_TILE: Vector2i = Vector2i(0, 2)
const RIVAL_GRAIN_TILE: Vector2i = Vector2i(3, 0)
const COAST_TILE: Vector2i = Vector2i(1, 3)
const BARE_TILE: Vector2i = Vector2i(0, 0)


static func build() -> MapModel:
	var model := MapModel.new()
	model.setup(5, 5)
	var player_tiles: Array[Vector2i] = []
	var rival_tiles: Array[Vector2i] = []
	for y in 4:
		for x in 5:
			var tile := Vector2i(x, y)
			model.terrain[model.index_of(x, y)] = MapModel.Terrain.PLAINS
			if x < 3:
				model.province[model.index_of(x, y)] = PLAYER_PROVINCE
				player_tiles.append(tile)
			else:
				model.province[model.index_of(x, y)] = RIVAL_PROVINCE
				rival_tiles.append(tile)
	for x in 5:
		var sea_index: int = model.index_of(x, 4)
		model.terrain[sea_index] = MapModel.Terrain.OCEAN
		model.sea_zone[sea_index] = 0
	model.resource[model.index_of(IRON_TILE.x, IRON_TILE.y)] = 1
	model.resource[model.index_of(TIMBER_TILE.x, TIMBER_TILE.y)] = 0
	model.resource[model.index_of(RIVAL_GRAIN_TILE.x, RIVAL_GRAIN_TILE.y)] = 4
	model.provinces = [
		{
			"id": PLAYER_PROVINCE,
			"name": "Cádiz",
			"tiles": player_tiles,
			"center": Vector2(1.0, 1.5),
			"area": player_tiles.size(),
			"coastal": true,
			"port_tile": COAST_TILE,
			"owner": 0,
			"capital": true,
			"capital_tile": BARE_TILE,
			"resource": 1,
			"resource_tile": IRON_TILE,
			"population": 900,
		},
		{
			"id": RIVAL_PROVINCE,
			"name": "Coro",
			"tiles": rival_tiles,
			"center": Vector2(3.5, 1.5),
			"area": rival_tiles.size(),
			"coastal": true,
			"port_tile": Vector2i(4, 3),
			"owner": 1,
			"capital": false,
			"capital_tile": Vector2i(-1, -1),
			"resource": 4,
			"resource_tile": RIVAL_GRAIN_TILE,
			"population": 700,
		},
	]
	model.sea_zones = [
		{
			"id": 0,
			"name": "Mar Caribe",
			"tiles": [
				Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)
			],
			"center": Vector2(2.0, 4.0),
			"area": 5,
		},
	]
	return model


static func unit(type_id: String, tile: Vector2i, owner: int = 0) -> CivilianState:
	return CivilianState.create(1, owner, type_id, tile)


static func stockpile() -> Dictionary:
	return {"lumber": 40, "castIron": 40, "bronze": 10, "paper": 8, "steel": 8}


static func visibility(model: MapModel) -> VisibilityModel:
	var view := VisibilityModel.new()
	view.setup(model, 0)
	view.apply_initial()
	return view
