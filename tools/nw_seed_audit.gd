extends SceneTree
## Evidence probe for issue #1520: the eight-seed New World audit, printed for
## the wiki evidence page. Run:
##   godot --headless --path . --script res://tools/nw_seed_audit.gd

const SEEDS: Array[int] = [160, 1, 42, 777, 1500, 2024, 31415, 99991]
const WIDTH: int = 84
const HEIGHT: int = 58


func _init() -> void:
	var crops_total: int = 0
	var riches_total: int = 0
	print("seed   land  forest  hardwood  open30  ore40  crops  riches  barren")
	for seed_value: int in SEEDS:
		var model: MapModel = MapGenerator.new().generate_ground(
			seed_value, FactionCatalog.NEW_WORLD, WIDTH, HEIGHT
		)
		var row: Dictionary = _rows(model)
		crops_total += int(row["crops"])
		riches_total += int(row["riches"])
		print("%5d %5d  %6.1f%%  %6.1f%%  %5.1f%%  %4.1f%%  %5d  %6d  %6d" % [
			seed_value, int(row["land"]), float(row["forest"]) * 100.0,
			float(row["hardwood"]) * 100.0, float(row["open"]) * 100.0,
			float(row["ore"]) * 100.0, int(row["crops"]), int(row["riches"]),
			int(row["barren"]),
		])
	var count: float = float(SEEDS.size())
	print("mean   %20s  %5d cash-crop tiles, %d rich tiles" % [
		"", int(round(float(crops_total) / count)), int(round(float(riches_total) / count)),
	])
	quit()


func _rows(model: MapModel) -> Dictionary:
	var table: Array[Dictionary] = MapGenerator.resource_table()
	var land: int = 0
	var forest: int = 0
	var hardwood: int = 0
	var open_rows: int = 0
	var ore: int = 0
	var crops: int = 0
	var riches: int = 0
	var money: Dictionary = {}
	for y in model.height:
		for x in model.width:
			var terrain: int = model.terrain_at(x, y)
			if terrain == MapModel.Terrain.OCEAN or terrain == MapModel.Terrain.SHALLOW:
				continue
			land += 1
			var wooded: bool = terrain == MapModel.Terrain.HARDWOOD_FOREST \
				or terrain == MapModel.Terrain.SCRUB_FOREST
			if wooded:
				forest += 1
				if terrain == MapModel.Terrain.HARDWOOD_FOREST:
					hardwood += 1
				continue
			var index: int = model.resource_at(x, y)
			if index == MapModel.NO_ID:
				continue
			open_rows += 1
			var commodity: String = String(table[index].get("commodity", ""))
			if String(table[index].get("scope", "both")) == "both":
				ore += 1
			if ResourceGround.MONEY_CROPS.has(commodity):
				crops += 1
			elif CommodityCatalog.is_riches(commodity):
				riches += 1
			else:
				continue
			var province: int = model.province_at(x, y)
			money[province] = int(money.get(province, 0)) + 1
	var barren: int = 0
	for province: ProvinceState in model.provinces:
		if int(money.get(province.id, 0)) < ResourceGround.PROVINCE_MONEY_FLOOR:
			barren += 1
	return {
		"land": land,
		"forest": float(forest) / float(maxi(land, 1)),
		"hardwood": float(hardwood) / float(maxi(forest, 1)),
		"open": float(open_rows) / float(maxi(land, 1)),
		"ore": float(ore) / float(maxi(open_rows, 1)),
		"crops": crops,
		"riches": riches,
		"barren": barren,
	}