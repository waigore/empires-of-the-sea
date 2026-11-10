extends SceneTree
## Screenshot harness for the Battle Simulator plate (excluded from coverage).
##   godot --path . -s tests/battle_sim_shot.gd -- out=/tmp/sim.png terrain=0 fort=2 round=3
## Run WITHOUT --headless: it needs a real GL context.

var _frames := 0
var _target := 60
var _path := "/tmp/battle_sim.png"
var _terrain := 0
var _fort := 2
var _round := 3
var _screen: Node = null
var _shot := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("frames="):
			_target = int(arg.substr(7))
		elif arg.begins_with("terrain="):
			_terrain = int(arg.substr(8))
		elif arg.begins_with("fort="):
			_fort = int(arg.substr(5))
		elif arg.begins_with("round="):
			_round = int(arg.substr(6))
	var scene: PackedScene = load("res://scenes/battle_sim.tscn")
	_screen = scene.instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4 and _screen != null:
		_screen._setup._terrain.selected = _terrain
		_screen._setup._fort.selected = _fort
		_screen._fight()
		if _round >= 0:
			_screen._show_round(_round)
	if _frames == _target and not _shot:
		_shot = true
		var image: Image = root.get_texture().get_image()
		if image == null:
			print("no image")
		else:
			image.save_png(_path)
			print("saved ", _path, " ", image.get_width(), "x", image.get_height())
		return true
	return false
