extends SceneTree
## Headless playtest drive: the march a crown may not order — a land move into a
## province no tile of which its chart holds (wiki: fog-and-exploration § Order
## Visibility Requirements).
##
## The opening campaign gives a crown no New World ground, so the drive reaches
## the area the way a crown does: a crew lands on a Tribe's coast (the voyage's
## own landing reveal) and a host stands on that beach. The drive then reads the
## march the rules offer, the provinces the map marks as move options, the
## order itself, and the same border for a crew — the gate the citation says one
## sentence for one rule.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_army_fog.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
## The landed host: enough regiments to be a field army, not the Home Army.
const HOST_MEN: int = 4

var _steps: PackedStringArray = PackedStringArray()
var _play: PlaySession = null
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_play.switch_region(FactionCatalog.NEW_WORLD)
	await process_frame
	var model: MapModel = _play.model
	_say("seed %s · turn %d · %s · chart %s" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(_play.player_faction),
		FactionCatalog.region_label(_play.region_index),
	])
	if model == null or model.region_id != FactionCatalog.NEW_WORLD:
		_say("the New World chart did not mount — update playtests/playtest_army_fog.gd")
		_finish()
		return
	var uncharted: int = 0
	for province: ProvinceState in model.provinces:
		if _charted_level(province.id) == VisibilityModel.Level.UNKNOWN:
			uncharted += 1
	_say("uncharted provinces on this chart: %d of %d" % [
		uncharted, model.provinces.size(),
	])
	# A crew goes ashore: the landing reveal the voyage makes charts that tile
	# and its orthogonal neighbours, and nothing else.
	var landing: Vector2i = Vector2i(-1, -1)
	var beach: int = -1
	for province: ProvinceState in model.provinces:
		if FactionCatalog.type_of(province.owner) != FactionCatalog.Type.TRIBE:
			continue
		for tile: Vector2i in province.tiles:
			if model.is_land(tile.x, tile.y):
				landing = tile
				beach = province.id
				break
		if landing.x >= 0:
			break
	if landing.x < 0:
		_say("no Tribe province to land on — the drive cannot run")
		_finish()
		return
	_play.visibility.reveal_landing(landing)
	_say("a crew landed at %s — %s is now %s" % [
		str(landing), model.province_name(beach), _level_name(_charted_level(beach)),
	])
	var dark: int = -1
	for id: int in MapGeo.province_neighbors(model, beach):
		if _charted_level(id) == VisibilityModel.Level.UNKNOWN:
			dark = id
			break
	if dark < 0:
		_say("every neighbour of the beach is charted — the drive cannot show the march")
		_finish()
		return
	_say("uncharted neighbour: %s (%s, owner %s, %d tiles, none charted)" % [
		model.province_name(dark), str(dark),
		FactionCatalog.name_of(model.province_owner(dark)),
		model.province_tiles(dark).size(),
	])
	var host: ArmyState = _seat(HOST_MEN, beach)
	_say("a %d-regiment crown host stands on the beach at %s (fixture)" % [
		host.count(), model.province_name(beach),
	])
	var offered: Array[int] = ArmyMovement.destinations(model, host, _play.visibility)
	_say("march targets the rules offer: %s" % str(offered))
	MapPlayArmies.select(_play, host)
	MapPlayArmies.refresh_options(_play, host)
	var marked: Array = _play.overlay.move_provinces
	_say("provinces the chart marks as move options: %s" % str(marked))
	_say("the uncharted province is offered: %s · marked: %s" % [
		str(offered.has(dark)), str(marked.has(dark)),
	])
	var order: Dictionary = _play.army_layer.order(host, dark, true, _play.visibility)
	_say("the crown's own order for that ground: %s\"%s\"" % [
		"ok " if bool(order.get("ok", false)) else "refused ",
		String(order.get("reason", "")),
	])
	_say("the host stands in %s (%s)" % [
		model.province_name(host.province), str(host.province),
	])
	# The same border for a crew: the one sentence the citation publishes.
	var pair: Array[Vector2i] = _adjacent_pair(beach, dark)
	if pair.is_empty():
		_say("no tile-adjacent crew pair across the border — crew reading skipped")
	else:
		var crew: CivilianState = CivilianState.create(
			900, _play.player_faction, "explorer", pair[0]
		)
		var step: Dictionary = CivilianMovement.apply_move(
			model, crew, pair[1], _play.visibility
		)
		_say("a crew ordered across the same border: %s\"%s\"" % [
			"ok " if bool(step.get("ok", false)) else "refused ",
			String(step.get("reason", "")),
		])
	_finish()


func _level_name(level: int) -> String:
	match level:
		VisibilityModel.Level.FULLY_VISIBLE:
			return "fully visible"
		VisibilityModel.Level.FOGGED:
			return "fogged"
	return "unknown"


## The highest level any tile of this province holds on the crown's chart.
func _charted_level(province_id: int) -> int:
	var model: MapModel = _play.model
	for tile: Vector2i in model.province_tiles(province_id):
		var level: int = _play.visibility.level_at(tile.x, tile.y)
		if level > VisibilityModel.Level.UNKNOWN:
			return level
	return VisibilityModel.Level.UNKNOWN


func _seat(count: int, province: int) -> ArmyState:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	var army: ArmyState = ArmyState.muster(
		_play.army_layer.next_army, _play.player_faction, province, false, types,
		_play.army_layer.next_regiment
	)
	_play.army_layer.armies.append(army)
	_play.army_layer.add_marker(army)
	return army


## A beach tile and the tile across the border: `[from, to]`, empty when the two
## provinces share no 4-neighbour edge.
func _adjacent_pair(staging: int, other: int) -> Array[Vector2i]:
	var model: MapModel = _play.model
	for tile: Vector2i in model.province_tiles(staging):
		for offset: Vector2i in [
			Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
		]:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			if model.province_at(next.x, next.y) == other:
				return [tile, next]
	return [] as Array[Vector2i]


func _say(text: String) -> void:
	_steps.append(text)
	print("playtest: %s" % text)


func _finish() -> void:
	print("playtest: %d steps" % _steps.size())
	quit(0)
