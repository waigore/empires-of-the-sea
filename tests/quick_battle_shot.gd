extends SceneTree
## Screenshot of the shipped Quick Battle overlay (excluded from coverage).
##   godot --path . -s tests/quick_battle_shot.gd -- out=/tmp/qb.png terrain=town fort=2
## Run WITHOUT --headless: it needs a real GL context.

var _frames := 0
var _path := "/tmp/quick_battle.png"
var _terrain := "town"
var _fort := 2
var _overlay: QuickBattleOverlay = null
var _report: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("terrain="):
			_terrain = arg.substr(8)
		elif arg.begins_with("fort="):
			_fort = int(arg.substr(5))
	_report = BattleScenario.fight({
		"attacker": ["musketeers", "musketeers", "musketeers", "guards", "culverin", "culverin"],
		"defender": ["pikemen", "pikemen", "musketeers", "culverin"],
		"fort": _fort, "terrain": _terrain, "seed": 7,
	})["report"] as Dictionary
	_overlay = QuickBattleOverlay.new()
	root.add_child(_overlay)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_overlay.show_battle(_report, "Flanders", ["England", "France"])
	if _frames == 24:
		_overlay.skip()
	if _frames == 40:
		var image: Image = root.get_texture().get_image()
		if image == null:
			print("no image")
		else:
			image.save_png(_path)
			print("saved ", _path, " ", image.get_width(), "x", image.get_height())
		return true
	return false
