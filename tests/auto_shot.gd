extends SceneTree
## Screenshot harness for Auto mode's chrome (excluded from coverage):
##   godot --path . -s tests/auto_shot.gd -- out=/tmp/auto.png size=1440x900
## Run WITHOUT --headless: it needs a real GL context.

var _path := "/tmp/auto_shot.png"
var _size := Vector2i(1440, 900)
var _confirm := false
var _turns := 2
var _frames := 0
var _screen: MapScreen = null
var _viewport: SubViewport = null
var _shot_taken := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_path = arg.substr(4)
		elif arg.begins_with("size="):
			var parts: PackedStringArray = arg.substr(5).split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("confirm="):
			_confirm = arg.substr(8) == "1"
		elif arg.begins_with("turns="):
			_turns = int(arg.substr(6))
	_run.call_deferred()


func _run() -> void:
	# A SubViewport of the exact size under test: the OS window on a HiDPI host
	# reports a logical size of its own, and the shot must read the phone's.
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_viewport)
	var scene: PackedScene = load("res://scenes/map_screen.tscn")
	_screen = scene.instantiate()
	_screen.map_seed = 1500
	_screen.map_width = int(GameConfig.SIZES[1]["width"])
	_screen.map_height = int(GameConfig.SIZES[1]["height"])
	_screen.infinite_mode = true
	_viewport.add_child(_screen)
	await process_frame
	await process_frame
	var play: PlaySession = _screen.play
	MapPlayAuto.arm(play)
	_close_turn(play)
	for _turn in _turns:
		_drain(play)
		await process_frame
	# The turn's news sheet covers the chart; the shot reads the plaque instead.
	if _screen.hud.gazette_plate != null and _screen.hud.gazette_plate.is_open():
		_screen.hud.gazette_plate.close()
	if _screen.hud.gazette_plate != null:
		_screen.hud.gazette_plate.visible = false
	_screen.game_menu.close()
	if _screen.hud.panels != null:
		DiplomacyHud.hide(_screen.hud.panels)
	if _confirm:
		_screen.hud.auto_bar._on_toggle_pressed()
	# The driver's own clock would keep playing while the shot is taken.
	play.auto_speed = 0
	await process_frame


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90 or _shot_taken:
		if _shot_taken and _frames > 100:
			return true
		return false
	_shot_taken = true
	var image: Image = _viewport.get_texture().get_image()
	image.save_png(_path)
	print("auto_shot: %s · turn %d · seat %s · plaque %s · view %s" % [
		_path, _screen.play.turn, _screen.play.auto_active,
		_screen.hud.auto_bar.toggle.get_global_rect(), _screen.hud.size,
	])
	return false


func _close_turn(play: PlaySession) -> void:
	MapPlayTurn.end_turn(play)
	var guard := 0
	while play.turn_suspended and guard < 6:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_offer(play, false)
		else:
			play.turn_suspended = false


func _drain(play: PlaySession) -> void:
	var guard := 0
	MapPlayAuto.tick(play)
	while play.auto_book != null and guard < 60:
		MapPlayAuto.tick(play)
		guard += 1
