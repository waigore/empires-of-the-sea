extends GdToolsTest
## Siege depth (wiki: siege-mechanics § Quick Battle lanes / § Gates and Sortie;
## quick-battle § Terrain / § Core actions): lane terrain, three gates and the
## breach they open, and the dedicated Sortie order.

const Fixture = preload("res://tests/army_fixture.gd")


func test_lane_terrain_follows_the_ground() -> void:
	var model := Fixture.build()
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "open", "plains without a fort")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 1), "town", "a fort rings its town")
	_set_ground(model, 2, MapModel.Terrain.HILLS)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "hill")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 2), "hill", "broken ground keeps its character")
	_set_ground(model, 2, MapModel.Terrain.HARDWOOD_FOREST)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "woods")
	_set_ground(model, 2, MapModel.Terrain.SWAMP)
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0), "marsh")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "town"), "town", "a playtest may override")


## The ground is published as `marsh` (wiki: quick-battle § Terrain;
## DR-20261110-27): a swamp province fights on marsh ground and the documented
## override is the same id the record carries — not the map's terrain enum name.
func test_the_marsh_ground_speaks_the_published_id() -> void:
	var model := Fixture.build()
	_set_ground(model, 2, MapModel.Terrain.SWAMP)

	assert_true(SiegeLanes.TERRAIN.has("marsh"), "the published id is the table key")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "marsh"), "marsh",
		"the documented playtest override is honoured")
	assert_eq(SiegeLanes.lane_terrain(model, 2, 0, "swamp"), "marsh",
		"the map enum name is not a lane id; it falls back to the province ground")
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "marsh"), 0.9, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "marsh"), 0.7, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("marsh"), 0.8, 0.001)
	assert_eq(SiegeLanes.terrain_label("marsh"), "Marsh")

	var battle: Dictionary = _fight(
		"balanced", _repeat("guards", 8), _repeat("musketeers", 6), 0, "marsh"
	)
	assert_eq(String(battle["quick"]["terrain"]), "marsh", "the record speaks the rule")
	assert_eq(String(battle["quick"]["terrain_label"]), "Marsh")
	assert_true(
		_assault_losses("marsh", 20) < _assault_losses("open", 20),
		"a charge into the marsh is blunted, not open ground"
	)


func test_terrain_scales_the_action_tables() -> void:
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "open"), 1.0, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "town"), 0.55, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("assault", "woods"), 0.6, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("volley", "woods"), 0.75, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("town"), 1.4, 0.001)
	assert_almost_eq(SiegeLanes.entrench_scale("marsh"), 0.8, 0.001)
	assert_almost_eq(SiegeLanes.terrain_scale("entrench", "town"), 1.0, 0.001, "no damage")
	assert_eq(SiegeLanes.terrain_label("hill"), "Hillside")
	assert_eq(SiegeLanes.terrain_label("unknown"), "Open field")


func test_three_gates_open_one_at_a_time() -> void:
	var gates: Dictionary = SiegeLanes.gates_for(2)
	assert_eq(int(gates["max"]), 3)
	assert_eq(int(gates["threshold"]), 7, "20 wall HP shared by three gates")
	assert_false(SiegeLanes.breached(gates))
	assert_eq(SiegeLanes.batter(gates, 6), 0, "six casualties do not open a gate")
	assert_eq(SiegeLanes.batter(gates, 1), 1, "the seventh does")
	assert_true(SiegeLanes.breached(gates))
	assert_almost_eq(SiegeLanes.breach_share(gates), 1.0 / 3.0, 0.001)
	assert_eq(SiegeLanes.batter(gates, 20), 2, "the rest fall in one blow")
	assert_eq(int(gates["broken"]), 3, "three gates and no more")
	assert_eq(SiegeLanes.batter(gates, 20), 0)
	assert_true(SiegeLanes.gates_for(0).is_empty(), "no fort, no gates")
	assert_eq(SiegeLanes.breach_threshold(0), 0)
	assert_eq(SiegeLanes.batter({}, 4), 0, "a field battle has no gate state")


func test_a_breach_sheds_the_wall_and_opens_the_behind_lane() -> void:
	var sheltered: Dictionary = _breach_strike(0)
	assert_true((sheltered["wall"] as Array).size() > 0, "the wall takes the shot")
	assert_eq(int(sheltered["gates_broken"]), 0, "one blow is not a breach")

	var opened: Dictionary = _breach_strike(1)
	assert_true(
		(opened["wall"] as Array).size() > (sheltered["wall"] as Array).size(),
		"a gate down, the wall no longer spares the garrison"
	)
	assert_true(
		(opened["behind"] as Array).size() > (sheltered["behind"] as Array).size(),
		"the attackers pour through the gate into the behind lane"
	)


## A fresh defender each time: the same blow against a whole wall and against a
## wall already breached through one gate.
func _breach_strike(broken: int) -> Dictionary:
	var attacker: Array[ArmyState] = _side(["musketeers", "musketeers", "musketeers", "culverin"], 2)
	var types: Array[String] = _repeat("peasant_levies", 8)
	types.append_array(_repeat("squires", 2))
	types.append_array(_repeat("culverin", 2))
	var defender: Array[ArmyState] = _side(types, 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var gates: Dictionary = SiegeLanes.gates_for(2)
	gates["broken"] = broken
	return SiegeLanes.strike(armies, attacker, defender, 12, 20, 2, false, gates)


## A line with no fight left in it delivers no blow, so it has nothing to spend
## on the fort's battery — a spent besieger cannot grind a gun down (wiki:
## siege-mechanics § Quick Battle lanes — "the guns take the blow", and only
## what a blow delivers can reach them; DR-20261110-22 buys gun loss with the
## besieging train's weight, never with an empty blow).
func test_a_spent_line_cannot_grind_down_the_battery() -> void:
	var attacker: Array[ArmyState] = _side(_repeat("musketeers", 4), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, "open")
	state["defender"]["mods"] = {"fort": 2}
	state["attacker"]["cohesion"] = 0
	var armies: Array[ArmyState] = state["armies"]
	var guns: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)

	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", guns
	)

	assert_eq(int(entry["battery_hit"]), 0, "no blow, nothing for the guns to soak")
	assert_eq(int(entry["guns_destroyed"]), 0, "a spent line cannot silence a gun")
	assert_almost_eq(
		QuickBattleBattery.total_hp(guns), 4.0, 0.001, "the battery is untouched"
	)
	## The other side of the line: a line with fight left in it still pays the
	## guns first, so the fix does not stop a real besieger from silencing them.
	var fresh: Array[Dictionary] = QuickBattleBattery.make(2, {}, 1)
	state["attacker"]["cohesion"] = 3
	var spent: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "volley", fresh
	)
	assert_true(int(spent["battery_hit"]) > 0, "a real blow is spent on the battery")


func test_a_quick_battle_reports_its_ground_and_gates() -> void:
	var battle: Dictionary = _fight(
		"balanced", _repeat("guards", 20), _repeat("musketeers", 10), 1, "hill"
	)
	var quick: Dictionary = battle["quick"]
	assert_eq(String(quick["terrain"]), "hill")
	assert_eq(String(quick["terrain_label"]), "Hillside")
	assert_eq(int((quick["gates"] as Dictionary)["max"]), 3)
	assert_true(int((quick["gates"] as Dictionary)["damage"]) > 0, "the wall was beaten")
	assert_eq(int((quick["limits"] as Dictionary)["attacker"]), 10)
	assert_eq(String(battle["battle_mode"]), "siege")


func test_a_garrison_without_firearms_sallies_on_its_own() -> void:
	var battle: Dictionary = _fight(
		"balanced", _repeat("guards", 8), _repeat("pikemen", 6), 2, "town"
	)
	assert_true(int(battle["quick"]["sorties"]) > 0, "a pike garrison must sally to fight")
	assert_eq(String(battle["quick"]["defender_plan"]), "aggressive")


func test_the_sortie_is_a_dedicated_order() -> void:
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, true),
		["entrench", "sortie"], "a sally, not an assault on its own wall"
	)
	assert_eq(
		QuickBattleActions.actions_for("aggressive", true, false),
		["entrench", "volley", "volley"], "no wall, no gate to sally from"
	)
	assert_eq(QuickBattleActions.actions_for("aggressive"), ["maneuver", "assault"])
	assert_eq(int(QuickBattleActions.ACTION_CP["sortie"]), 2)
	assert_eq(String(QuickBattleActions.ACTION_LABEL["sortie"]), "Sortie")


func test_an_assault_into_town_is_weaker() -> void:
	var open_losses: int = _assault_losses("open")
	var town_losses: int = _assault_losses("town")
	assert_true(town_losses < open_losses, "streets and rooftops blunt a charge")


func test_entrenching_is_surer_in_cover() -> void:
	var open_guard: float = _entrench_guard("open")
	var town_guard: float = _entrench_guard("town")
	assert_almost_eq(open_guard, 0.45, 0.001)
	assert_almost_eq(town_guard, 0.63, 0.001)
	assert_true(town_guard > open_guard)


func test_a_sortie_in_the_open_costs_the_garrison_dear() -> void:
	## Enough pike that a quality assault leaves men to pay the sally's own cost
	## (main's FPN/FPM blow no longer treats a thin garrison as a head count).
	var battle: Dictionary = _fight(
		"aggressive", _repeat("guards", 8), _repeat("pikemen", 16), 1, "town"
	)
	var sortie: Dictionary = {}
	for round: Dictionary in battle["quick"]["rounds"]:
		for action: Dictionary in round["actions"]:
			if bool(action["sortie"]):
				sortie = action
	assert_true(not sortie.is_empty(), "the plate records the sally")
	assert_true(int(sortie["defender_lost"]) > 0, "the sally costs its own men")
	assert_eq(String(sortie["label"]), "Sortie")


# --- fixtures ----------------------------------------------------------------


func _fight(
	plan: String, attacker: Array[String], defender: Array[String], fort: int,
	terrain: String
) -> Dictionary:
	var model := Fixture.build()
	model.province_data(2).fort_level = fort
	_set_ground(model, 2, _ground(terrain))
	var defender_army := Fixture.army(1, 1, 2, defender, true)
	var attacker_army := Fixture.army(2, 0, 2, attacker)
	attacker_army.moved = true
	var armies: Array[ArmyState] = [defender_army, attacker_army]
	var context: Dictionary = {
		"quick_battle": true, "player_faction": 0,
		"battle_plan": plan, "seed": 11, "terrain_override": terrain,
	}
	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, context)
	return reports[0]


func _assault_losses(terrain: String, count: int = 6) -> int:
	## Peer-quality lines so the blow stays in the terrain band instead of
	## wiping both open and town (quality weight from main's Quick Battle).
	var attacker: Array[ArmyState] = _side(_repeat("pikemen", count), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", count), 1)
	var armies: Array[ArmyState] = _joined(attacker, defender)
	var state: Dictionary = _state(attacker, defender, terrain)
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "attacker", "defender", "assault", [] as Array[Dictionary]
	)
	return int(entry["defender_lost"])


func _entrench_guard(terrain: String) -> float:
	var attacker: Array[ArmyState] = _side(_repeat("guards", 4), 2)
	var defender: Array[ArmyState] = _side(_repeat("pikemen", 4), 1)
	var state: Dictionary = _state(attacker, defender, terrain)
	var armies: Array[ArmyState] = state["armies"]
	var entry: Dictionary = QuickBattleActions.resolve(
		armies, state, "defender", "attacker", "entrench", [] as Array[Dictionary]
	)
	return float(entry["guard"])


func _state(
	attacker: Array[ArmyState], defender: Array[ArmyState], terrain: String
) -> Dictionary:
	var state: Dictionary = {
		"attacker": {
			"side": attacker, "owner": 2, "limit": 10, "mods": {},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "balanced", "exposed": false,
		},
		"defender": {
			"side": defender, "owner": 1, "limit": 10, "mods": {"fort": 0},
			"cohesion": 3, "guard": 0.0, "lost": [] as Array[String],
			"plan": "defensive", "exposed": false,
		},
		"terrain": terrain,
		"gates": {},
	}
	## One list so the resolver can find both sides' regiments by instance id.
	state["armies"] = _joined(attacker, defender)
	return state


func _side(types: Array[String], owner: int) -> Array[ArmyState]:
	var side: Array[ArmyState] = []
	side.append(Fixture.army(10 + owner, owner, 2, types, true))
	return side


func _joined(first: Array[ArmyState], second: Array[ArmyState]) -> Array[ArmyState]:
	var all: Array[ArmyState] = []
	all.append_array(first)
	all.append_array(second)
	return all


func _set_ground(model: MapModel, province: int, terrain: int) -> void:
	var data: ProvinceState = model.province_data(province)
	for tile: Vector2i in data.tiles:
		model.terrain[model.index_of(tile.x, tile.y)] = terrain


func _ground(terrain: String) -> int:
	match terrain:
		"hill":
			return MapModel.Terrain.HILLS
		"woods":
			return MapModel.Terrain.HARDWOOD_FOREST
		"marsh":
			return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS


func _repeat(type_id: String, count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append(type_id)
	return types
