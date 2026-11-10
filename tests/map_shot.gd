extends SceneTree
## Screenshot harness for the map screen (excluded from coverage).
##   godot --path . -s tests/map_shot.gd -- out=/tmp/map.png frames=90 zoom=2
## Run WITHOUT --headless: it needs a real GL context.

var _frames := 0
var _target := 90
var _path := "/tmp/map_shot.png"
var _zoom := 0.0
var _diplomacy := false
var _army := false
var _select := -1
var _warp := 0
var _lens := false
var _political := false
var _war := false
var _gazette := false
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
		elif arg.begins_with("army="):
			_army = arg.substr(5) == "1"
		elif arg.begins_with("select="):
			_select = int(arg.substr(7))
		elif arg.begins_with("warp="):
			_warp = int(arg.substr(5))
		elif arg.begins_with("lens="):
			_lens = arg.substr(5) == "1"
		elif arg.begins_with("political="):
			_political = arg.substr(10) == "1"
		elif arg.begins_with("war="):
			_war = arg.substr(4) == "1"
		elif arg.begins_with("gazette="):
			_gazette = arg.substr(8) == "1"
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
	if _frames == 4 and _warp > 0 and _screen != null:
		_warp_shot()
	if _frames == 4 and _army and _screen != null:
		MapPlayArmies.open_muster(_screen.play)
	if _frames == 4 and _lens and _screen != null:
		MapPlayInput.set_lens(_screen.play, true)
	if _frames == 4 and _political and _screen != null:
		MapPlayInput.set_diplomacy_lens(_screen.play, true)
	if _frames == 4 and _war and _screen != null:
		_sample_war()
	if _frames == 4 and _gazette and _screen != null:
		_sample_gazette()
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


## Files a sample sheet and raises the plate, so a screenshot shows the Gazette
## in the same brass-and-parchment chrome as the rest of the shell.
func _sample_gazette() -> void:
	var play: PlaySession = _screen.play
	MapPlayGazette.ensure(play)
	var province: String = play.model.province_name(int(play.model.provinces[0].id))
	var records: Array[Dictionary] = [
		{
			"class": Gazette.Class.WORLD,
			"kind": "warDeclared",
			"who": "England",
			"whom": "France",
		},
		{
			"class": Gazette.Class.COURT,
			"kind": "battleCapture",
			"place": province,
			"whom": "France",
			"count": 3,
			"self_act": true,
		},
		{
			"class": Gazette.Class.COURT,
			"kind": "techFinished",
			"label": "Crop Rotation",
			"self_act": true,
		},
		{
			"class": Gazette.Class.COURT,
			"kind": "richesRendered",
			"amount": 1250,
		},
		{
			"class": Gazette.Class.INTEREST,
			"kind": "allianceFormed",
			"who": "England",
			"whom": "France",
		},
	]
	var items: Array[Dictionary] = []
	for rec: Dictionary in records:
		var text: String = GazetteCopy.line(rec)
		if text.is_empty():
			continue
		items.append({"class": int(rec["class"]), "kind": String(rec["kind"]), "text": text})
	var sheet: Dictionary = {"turn": play.turn, "items": items}
	play.gazette.append(sheet)
	MapPlayGazette.show(play, sheet)


## Declares war on one neighbour and allies with another, so a screenshot shows
## the red and green bands without a campaign.
func _sample_war() -> void:
	var play: PlaySession = _screen.play
	var owners: Array[int] = []
	for province: ProvinceState in play.model.provinces:
		if province.owner == MapModel.NO_ID or province.owner == play.player_faction:
			continue
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER:
			continue
		if not owners.has(province.owner):
			owners.append(province.owner)
	if owners.is_empty():
		return
	DiplomacyRules.declare_war(play.diplomacy, play.player_faction, owners[0], false)
	if owners.size() > 1:
		var record: DiplomacyRelation = play.diplomacy.ensure_relation(
			play.player_faction, owners[1], play.turn
		)
		record.set_score(80.0)
		DiplomacyRules.form_alliance(
			play.diplomacy, play.player_faction, owners[1], DiplomacyRules.DECISION_ACCEPT
		)
	MapPlaySetup.build_diplomacy_lens(play)
	MapPlayInput.set_diplomacy_lens(play, true)


## warp=1 selects a player squadron in the Old World passage; warp=2 crosses it.
func _warp_shot() -> void:
	var play: PlaySession = _screen.play
	var zone: int = play.world.warp_zones(FactionCatalog.OLD_WORLD)[0]
	for ship: Ship in _screen.ship_layer.ships:
		var fleet: FleetState = _screen.ship_layer.fleet_of(ship)
		if fleet == null or fleet.owner != FactionCatalog.PLAYER_FACTION:
			continue
		if not fleet.is_at_sea():
			continue
		fleet.sea_zone = zone
		fleet.province = MapModel.NO_ID
		_screen.ship_layer.select(ship)
		if _warp == 2:
			MapPlayFleets.try_order(play, play.model.sea_zone_data(zone).tiles[0])
		_screen.camera.focus_on(
			play.model.sea_zone_center(fleet.sea_zone) * PlaySession.TILE_SIZE, 1.4, true
		)
		return
