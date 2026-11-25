extends SceneTree
## Headless re-play of the defect this pass fixed: the province dossier's **Build
## road** and **Lay railroad** presses offered an open press the work order then
## refused — an empty larder, or a tile another crew already held.
##   godot --headless --path . --script res://playtests/playtest_work_press_gates.gd
##
## A reading only: this drive opens the real map screen, empties the crown's
## purse, opens the dossier on its own province and prints what the two presses
## say. It files no order and moves no crew.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"

var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		quit(1)
		return
	_play = _screen.play
	print("playtest: seed %s — %s, turn %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn
	])
	# An empty larder is the gate the press used to miss.
	var stock: Dictionary = _play.stockpile()
	for commodity: String in ["lumber", "castIron", "steel"]:
		if stock.has(commodity) or commodity != "steel":
			stock[commodity] = 0
	print("playtest: purse %s" % str(stock))
	_open_a_province()
	quit(0)


## Opens the dossier on each owned province until one offers a press, and prints
## what the two presses say there.
func _open_a_province() -> void:
	var model: MapModel = _play.model
	for province: ProvinceState in model.provinces:
		if model.province_owner(province.id) != _play.player_faction:
			continue
		MapPlayInput.select_province(_play, province.id, Vector2.ZERO)
		var panel: ProvincePanel = _play.hud._panel
		if panel == null:
			print("playtest: no dossier on this screen")
			return
		var resources: ProvinceResources = panel._resources
		var rail: ProvinceRailBlock = panel._rail
		if resources.lines().is_empty() and rail.rows().is_empty():
			continue
		print("playtest: province %d — %d estate row(s), %d rail row(s)" % [
			province.id, resources.lines().size(), rail.rows().size()
		])
		for row: Dictionary in resources.lines():
			var tile: Vector2i = row["tile"]
			var plan: Dictionary = resources.road_plan(tile)
			if not bool(plan.get("needed", false)):
				continue
			print("playtest:   estate (%d, %d) — price %s · %d turn(s)" % [
				tile.x, tile.y,
				CivilianWorkPlan.cost_text(plan.get("cost", {})),
				int(plan.get("turns", 0)),
			])
			print("playtest:     note: %s" % resources.road_note(tile))
		print("playtest: rail block visible=%s" % rail.visible)
		for rail_row: Dictionary in rail.rows():
			var rail_tile: Vector2i = rail_row["tile"]
			print("playtest:   rail (%d, %d) — note: %s" % [
				rail_tile.x, rail_tile.y, rail.rail_note(rail_tile)
			])
		print("playtest: the crown's purse: %s" % str(_play.stockpile()))
		# The same live chart: a real cut estate — a developed estate off the
		# crown network, the state issue #671's Build road exists for — read with
		# the crown's own stores, then with a purse that can pay.
		var cut: Vector2i = _cut_estate(province)
		if cut.x >= 0:
			print("playtest: estate (%d, %d) cut off the crown:" % [cut.x, cut.y])
			var broke: Dictionary = RoadWorks.plan(
				model, _play.land_works, _play.civilian_layer.units,
				_play.player_faction, _play.capital_tile, cut, {},
				_play.stockpile()
			)
			print("playtest:   empty purse  — needed=%s reason '%s'" % [
				bool(broke.get("needed", false)), String(broke.get("reason", ""))
			])
			var rich: Dictionary = RoadWorks.plan(
				model, _play.land_works, _play.civilian_layer.units,
				_play.player_faction, _play.capital_tile, cut, {},
				{"lumber": 9, "castIron": 9}
			)
			print("playtest:   able purse   — reason '%s', %s · %d turn(s)" % [
				String(rich.get("reason", "")),
				CivilianWorkPlan.cost_text(rich.get("cost", {})),
				int(rich.get("turns", 0)),
			])
	print("playtest: no owned province offers a work press")


## The first owned resource tile in `province` that reaches the crown when
## developed and stops reaching it when its road goes: the state the press is
## raised for. Returns (-1, -1) when the province holds none.
func _cut_estate(province: ProvinceState) -> Vector2i:
	var model: MapModel = _play.model
	for tile: Vector2i in province.tiles:
		if _play.land_works.improvement_at(model, tile) > 0:
			continue
		var level: int = _play.land_works.transport_at(model, tile)
		_play.land_works.set_improvement(model, tile, 1)
		_play.land_works.set_transport(model, tile, 0)
		var plan: Dictionary = RoadWorks.plan(
			model, _play.land_works, _play.civilian_layer.units,
			_play.player_faction, _play.capital_tile, tile
		)
		_play.land_works.set_improvement(model, tile, 0)
		_play.land_works.set_transport(model, tile, level)
		if bool(plan.get("needed", false)):
			_play.land_works.set_improvement(model, tile, 1)
			_play.land_works.set_transport(model, tile, 0)
			return tile
	return Vector2i(-1, -1)
