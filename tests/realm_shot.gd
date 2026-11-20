extends SceneTree
## Screenshot harness for the realm sheet's three views (excluded from coverage).
##   godot --path . -s tests/realm_shot.gd -- out=/tmp/realm.png view=economy size=1400x900 frames=40
## Run WITHOUT --headless: a SubViewport still needs a real GL context.
##
## `view` names one of economy / defence / connectivity (or `map` for the chart
## alone, which is how the region pill is checked); `sort` names the order
## chip to press (value, tree, ore, coin, wheat, hops); `size` is the plate's
## own size, so a phone shot is taken at a phone's width.

var _frames := 0
var _target := 40
var _path := "/tmp/realm_shot.png"
var _view := "economy"
var _sort := ""
var _size := Vector2i(1400, 900)
var _viewport: SubViewport = null
var _screen: Node = null
var _shot_taken := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("frames="):
			_target = int(arg.substr(7))
		elif arg.begins_with("view="):
			_view = arg.substr(5)
		elif arg.begins_with("sort="):
			_sort = arg.substr(5)
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
	if _frames == 4 and _screen != null and _view != "map":
		_screen.hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
	if _frames == 8 and _screen != null and _view != "map":
		var panel: ProvinceLedgerPanel = _screen.hud.province_ledger
		panel._on_filter(_view, false)
		if not _sort.is_empty():
			panel._on_sort(_sort)
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
	print("saved %s" % path)
