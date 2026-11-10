extends SceneTree
## Isolated screenshot of the Quick Battle plate (excluded from coverage).
##   godot --path . -s tests/battle_field_shot.gd -- terrain=open fort=2 gates=1 out=/tmp/f.png
## Run WITHOUT --headless: it needs a real GL context.

const W := 532.0
const H := 600.0

var _frames := 0
var _path := "/tmp/battle_field.png"
var _terrain := "open"
var _fort := 2
var _gates := 1
var _atk := 8
var _def := 7
var _guns := 2
var _round := 2
var _w := W
var _h := H
var _field: QuickBattleField = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("terrain="):
			_terrain = arg.substr(8)
		elif arg.begins_with("fort="):
			_fort = int(arg.substr(5))
		elif arg.begins_with("gates="):
			_gates = int(arg.substr(6))
		elif arg.begins_with("atk="):
			_atk = int(arg.substr(4))
		elif arg.begins_with("def="):
			_def = int(arg.substr(4))
		elif arg.begins_with("guns="):
			_guns = int(arg.substr(5))
		elif arg.begins_with("round="):
			_round = int(arg.substr(6))
		elif arg.begins_with("w="):
			_w = float(arg.substr(2))
		elif arg.begins_with("h="):
			_h = float(arg.substr(2))
	_field = QuickBattleField.new()
	_field.position = Vector2.ZERO
	_field.size = Vector2(_w, _h)
	_field.custom_minimum_size = Vector2(_w, _h)
	root.add_child(_field)
	_field.terrain = _terrain
	_field.fort_level = _fort
	_field.gates_broken = _gates
	_field.attacker_count = _atk
	_field.defender_count = _def
	_field.attacker_start = 10
	_field.defender_start = 10
	_field.guns = _guns
	_field.round_index = _round
	_field.attacker_health = [{"fraction": 0.9, "medals": 0}, {"fraction": 0.6, "medals": 1}]
	_field.defender_health = [{"fraction": 0.4, "medals": 2}]


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		_save(_path)
	if _frames == 180:
		_save(_path.get_basename() + "_b.png")
		return true
	return false


func _save(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("no image")
		return
	image = image.get_region(Rect2i(0, 0, int(_w), int(_h)))
	image.save_png(path)
	print("saved ", path, " ", image.get_width(), "x", image.get_height())
