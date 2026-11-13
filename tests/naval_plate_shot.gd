extends SceneTree
## Screenshot of the shipped sea's despatch plate (excluded from coverage).
##   godot --path . -s tests/naval_plate_shot.gd -- out=/tmp/sea.png w=532 h=600
## Run WITHOUT --headless: it needs a real GL context.

var _frames := 0
var _path := "/tmp/naval_plate.png"
var _plate: NavalPlate = null
var _w := 900.0
var _h := 600.0
var _battle: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("w="):
			_w = float(arg.substr(2))
		elif arg.begins_with("h="):
			_h = float(arg.substr(2))
	_battle = {
		"attacker": 0,
		"defender": 1,
		"attacker_strength": 182.0,
		"defender_strength": 121.0,
		"attacker_before": 6,
		"defender_before": 4,
		"attacker_hulls": ["galleon", "galleon", "galleon", "galleon", "sloop", "sloop"],
		"defender_hulls": ["carrack", "carrack", "carrack", "carrack"],
		"attacker_lost": ["ship_9"],
		"attacker_lost_names": ["San Juan"],
		"defender_lost": ["a", "b", "c", "d"],
		"defender_lost_names": ["Trinidad", "Concepcion"],
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"retreat": {},
	}
	_plate = NavalPlate.new()
	root.add_child(_plate)
	root.size = Vector2i(int(_w), int(_h))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_plate.show_engagement(_battle, "Mar Caribe", ["España", "England"])
	if _frames == 24:
		_plate.skip()
	if _frames == 40:
		var image: Image = root.get_texture().get_image()
		if image == null:
			print("no image")
		else:
			image.save_png(_path)
			print("saved ", _path, " ", image.get_width(), "x", image.get_height())
		return true
	return false
