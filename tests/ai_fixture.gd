extends RefCounted
## Shared fixtures for the AI suites: hand-built worlds and planner contexts.
## Provinces are stubs (id/owner/resource only) because the AI reads ownership,
## region membership and resource ids — never terrain (REQ-P3-03).


## One Old World region with `owners.size()` provinces, one per entry.
static func world(owners: Array[int], resources: Dictionary = {}) -> WorldMap:
	var model := MapModel.new()
	model.setup(maxi(owners.size(), 1), 1)
	for index in owners.size():
		var tiles: Array[Vector2i] = [Vector2i(index, 0)]
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			tiles,
			Vector2(float(index), 0.0),
			1,
			owners[index],
			false
		)
		if resources.has(index):
			province.resource = int(resources[index])
			province.resource_tile = Vector2i(index, 0)
		model.provinces.append(province)
	var world_map := WorldMap.new()
	world_map.add_region(model)
	return world_map


## Planner context with absolute power scores (and optional unit counts).
static func context(power: Dictionary, regiments: Dictionary = {}, ships: Dictionary = {}) -> Dictionary:
	return {"power": power, "regiments": regiments, "ships": ships}


## One Old World region of land provinces wired into the tile grid, so
## adjacency, ownership and army placement work (military-planner suites).
## `capitals` maps a province index to true to give that province the seat flag.
static func land_world(owners: Array[int], capitals: Dictionary = {}) -> WorldMap:
	var model := MapModel.new()
	model.setup(maxi(owners.size(), 1), 3)
	model.terrain.fill(MapModel.Terrain.PLAINS)
	for index in owners.size():
		var tile := Vector2i(index, 1)
		model.province[model.index_of(tile.x, tile.y)] = index
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			[tile] as Array[Vector2i],
			Vector2(float(index), 1.0),
			1,
			owners[index],
			capitals.has(index)
		)
		if capitals.has(index):
			province.capital_tile = tile
		model.provinces.append(province)
		if not model.faction_ids.has(owners[index]):
			model.faction_ids.append(owners[index])
	var world_map := WorldMap.new()
	world_map.add_region(model)
	return world_map
