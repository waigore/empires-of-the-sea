extends RefCounted
## Synthetic map shared by rules tests: two coastal provinces, two adjacent sea
## zones, one owned harbour each. Kept tiny so expectations stay readable.


static func build() -> MapModel:
	var model := MapModel.new()
	model.setup(7, 3)
	_fill_land(model, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], 0)
	_fill_land(model, [Vector2i(5, 0), Vector2i(5, 1)], 1)
	# Neutral land keeps the two coasts apart.
	for tile: Vector2i in [Vector2i(3, 0), Vector2i(4, 0)]:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
	for tile: Vector2i in [
		Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 0
	for tile: Vector2i in [
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2),
	]:
		model.sea_zone[model.index_of(tile.x, tile.y)] = 1
	var cadiz_tiles: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var coro_tiles: Array[Vector2i] = [Vector2i(5, 0), Vector2i(5, 1)]
	var cadiz := ProvinceState.create(0, "Cádiz", cadiz_tiles, Vector2(0.5, 0.5), 3, 0, true)
	cadiz.port_tile = Vector2i(1, 0)
	var coro := ProvinceState.create(1, "Coro", coro_tiles, Vector2(5.0, 0.5), 2, 1, false)
	coro.port_tile = Vector2i(5, 1)
	model.provinces = [cadiz, coro]
	var caribbean: Array[Vector2i] = [
		Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	]
	var gulf: Array[Vector2i] = [
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2),
	]
	model.sea_zones = [
		SeaZoneState.create(0, "Mar Caribe", caribbean, Vector2(1.5, 1.5), 6),
		SeaZoneState.create(1, "Golfo de México", gulf, Vector2(4.0, 1.5), 5),
	]
	return model


static func _fill_land(model: MapModel, tiles: Array, province_id: int) -> void:
	for tile: Vector2i in tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = MapModel.Terrain.PLAINS
		model.province[model.index_of(tile.x, tile.y)] = province_id
