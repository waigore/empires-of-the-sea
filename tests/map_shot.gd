extends SceneTree
## Screenshot harness for the map screen (excluded from coverage).
##   godot --path . -s tests/map_shot.gd -- out=/tmp/map.png frames=90 zoom=2
## Run WITHOUT --headless: it needs a real GL context.

var _frames := 0
var _target := 90
var _path := "/tmp/map_shot.png"
var _zoom := 0.0
var _diplomacy := false
var _select := -1
var _shot_taken := false
var _shot2_taken := false
var _screen: Node = null
var _window_ms := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("frames="):
			_target = int(arg.substr(7))
		elif arg.begins_with("zoom="):
			_zoom = float(arg.substr(5))
		elif arg.begins_with("diplomacy="):
			_diplomacy = arg.substr(10) == "1"
		elif arg.begins_with("select="):
			_select = int(arg.substr(7))
	var scene: PackedScene = load("res://scenes/map_screen.tscn")
	_screen = scene.instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4 and _zoom > 0.0 and _screen != null:
		_screen.camera.zoom = Vector2.ONE * _zoom
	if _frames == 4 and _diplomacy and _screen != null:
		_screen.play.diplomacy.apply_delta(0, 1, 22.0, "courtSample")
		MapPlayDiplomacy.open(_screen.play)
		if _select >= 0:
			_screen.hud.panels.diplomacy_panel.select_faction(_select)
	if _frames == _target and not _shot_taken:
		_shot_taken = true
		_save(_path)
		_window_ms = Time.get_ticks_msec()
	if _frames == _target + 150 and not _shot2_taken:
		_shot2_taken = true
		_save(_path.get_basename() + "_b.png")
		var elapsed: float = float(Time.get_ticks_msec() - _window_ms) / 1000.0
		print("steady: 150 frames in %.2fs → %.1f fps" % [elapsed, 150.0 / maxf(elapsed, 0.001)])
		return true
	return false


func _save(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("no image")
		return
	image.save_png(path)
	print("saved ", path, " ", image.get_width(), "x", image.get_height())
