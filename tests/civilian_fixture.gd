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
	var player := ProvinceState.create(
		PLAYER_PROVINCE, "Cádiz", player_tiles, Vector2(1.0, 1.5), player_tiles.size(), 0, true
	)
	player.coastal = true
	player.port_tile = COAST_TILE
	player.capital_tile = BARE_TILE
	player.resource = 1
	player.resource_tile = IRON_TILE
	player.population = 900
	var rival := ProvinceState.create(
		RIVAL_PROVINCE, "Coro", rival_tiles, Vector2(3.5, 1.5), rival_tiles.size(), 1, false
	)
	rival.coastal = true
	rival.port_tile = Vector2i(4, 3)
	rival.resource = 4
	rival.resource_tile = RIVAL_GRAIN_TILE
	rival.population = 700
	model.provinces = [player, rival]
	var sea_tiles: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)
	]
	model.sea_zones = [
		SeaZoneState.create(0, "Mar Caribe", sea_tiles, Vector2(2.0, 4.0), 5)
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
