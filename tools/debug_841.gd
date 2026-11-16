extends SceneTree
## Throwaway probe (issue #841): runs a headless campaign and prints, per turn,
## each court's techs, merchants and deeds, so the deed path can be read while
## it is being opened. Not committed.

const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")

var _turns: int = 60
var _seed: int = 1500
var _size: int = 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--turns="):
			_turns = int(arg.split("=")[1])
		elif arg.begins_with("--seed="):
			_seed = int(arg.split("=")[1])
	var entry: Dictionary = GameConfig.SIZES[_size]
	var screen: MapScreen = SCENE.instantiate()
	screen.map_seed = _seed
	screen.map_width = int(entry["width"])
	screen.map_height = int(entry["height"])
	screen.observer_mode = true
	MapPlayTurn.view_live = false
	screen.infinite_mode = true
	root.add_child(screen)
	for _frame in 3:
		await process_frame
	var play: PlaySession = screen.play
	play.ai_mode = AiControl.FULL
	var panel := screen.get_node_or_null("AiObserver") as AiObserverPanel
	if panel != null:
		panel.running = false
	while not play.campaign_over() and play.turn <= _turns:
		MapPlayTurn.end_turn(play)
		await process_frame
		var line: String = "t%d" % play.turn
		for faction: int in FactionCatalog.great_power_ids():
			var economy: PlayerEconomy = play.ledger_for(faction)
			var crews: int = 0
			for unit: CivilianState in play.civilian_layer.units:
				if unit.owner == faction and unit.type_id == "merchant":
					crews += 1
			var model: MapModel = play.world.region(WorldMap.OLD_WORLD)
			var view: VisibilityModel = MapPlayCourtFog.view_for(play, faction, WorldMap.OLD_WORLD)
			var deed: Dictionary = AiMerchantWork.openable_deed(
				model, faction, {"diplomacy": play.diplomacy, "visibility": view}
			)
			var roster: Array = CivilianMuster.roster(play, WorldMap.OLD_WORLD)
			var counts: Dictionary = {}
			for unit: CivilianState in roster:
				if unit.owner == faction:
					counts[unit.type_id] = int(counts.get(unit.type_id, 0)) + 1
			var seller: int = int(deed.get("seller", -1))
			var stage: String = play.diplomacy.overture(faction, seller) if seller >= 0 else "-"
			line += " | %s $%d c=%d d=%d deed=%s/%d emb=%s %s" % [
				FactionCatalog.name_of(faction).substr(0, 3), economy.treasury, crews,
				MapPlayObserver.deeds_held(play, faction),
				str(seller), int(deed.get("price", 0)), stage, str(counts)
			]
		print(line)
	print("FINAL turn %d result %s" % [play.turn, MapPlayObserver.snapshot(play)["result"]])
	quit(0)
