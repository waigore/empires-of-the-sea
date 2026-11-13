extends SceneTree
## Screenshot harness for the ledger's WORKERS tab (excluded from coverage).
##   xvfb-run -s "-screen 0 1400x900x24" \
##     godot --path . -s tests/ledger_shot.gd -- out=/tmp/ledger.png size=1280x720 frames=40
## Run WITHOUT --headless: a SubViewport still needs a real GL context.

const TAB_WORKERS: int = 2

var _frames := 0
var _target := 40
var _path := "/tmp/ledger_shot.png"
var _size := Vector2i(1280, 720)
var _viewport: SubViewport = null
var _screen: Node = null
var _shot_taken := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("frames="):
			_target = int(arg.substr(7))
		elif arg.begins_with("size="):
			_apply_size(arg.substr(5))
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var scene: PackedScene = load("res://scenes/map_screen.tscn")
	_screen = scene.instantiate()
	_viewport.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4 and _screen != null:
		_screen.economy.open_panel()
		var panel: EconomyPanel = _screen.hud.panels.economy_panel
		panel.select_tab(TAB_WORKERS)
	if _frames == _target and not _shot_taken:
		_shot_taken = true
		_save(_path)
		return true
	return false


func _apply_size(text: String) -> void:
	var parts: PackedStringArray = text.split("x")
	if parts.size() != 2:
		return
	_size = Vector2i(int(parts[0]), int(parts[1]))


func _save(path: String) -> void:
	var image: Image = _viewport.get_texture().get_image()
	if image == null:
		print("no image")
		return
	image.save_png(path)
	print("saved ", path, " ", image.get_size())
