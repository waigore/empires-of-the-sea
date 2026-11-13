extends SceneTree
## Probe: which riches tiles each Great Power owns, and whether it works them.

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = 1500
	screen.map_width = 40
	screen.map_height = 30
	screen.observer_mode = true
	screen.infinite_mode = true
	root.add_child(screen)
	for _i in 8:
		await process_frame
	var play: PlaySession = screen.play
	var world: WorldMap = play.world
	for faction: int in FactionCatalog.great_power_ids():
		var riches: Array[String] = []
		for region: int in world.region_ids():
			var model: MapModel = world.region(region)
			for province: ProvinceState in model.provinces:
				if province.owner != faction:
					continue
				for tile: Vector2i in province.tiles:
					var res: int = model.resource_at(tile.x, tile.y)
					if res == MapModel.NO_ID:
						continue
					var id: String = ImprovementCatalog.commodity(res)
					if CommodityCatalog.RICHES.has(id):
						riches.append("%s@%s" % [id, province.name])
		print("RICHES %-18s %s" % [FactionCatalog.name_of(faction), riches])
	quit()
