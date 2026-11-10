class_name BattleScenario
extends RefCounted
## A sandbox siege or field battle for playtesting and the Battle Simulator.
##
## The scenario builds the smallest world a Quick Battle needs — one province,
## one army a side — and then runs the **live** resolver
## [method QuickBattle.resolve_exchange], so a playtest reads exactly the rules a
## game turn reads (REQ-P2-03, REQ-P3-03). Node-free: the simulator scene is only
## a view over this module.
##
## Spec keys (all optional unless noted):
##   attacker / defender : Array[String] of regiment type ids (required)
##   fort                : 0–3 (default 0)
##   terrain             : open | hill | woods | town | marsh (default open)
##   attacker_plan       : aggressive | balanced | defensive (default balanced)
##   defender_plan       : aggressive | balanced | defensive (default defensive)
##   seed                : int (default 11)
##   attacker_medals / defender_medals : 0–4 (default 0)
##   tech                : defending court's unlocked techs (emplaced gun line)

const ATTACKER: int = 0
const DEFENDER: int = 1
const PROVINCE: int = 0
const TOWN_TILE: Vector2i = Vector2i(2, 1)


## A fresh world and army pair for one run. The caller may mutate the model
## before `fight`, but the returned report is the authoritative outcome.
static func build(spec: Dictionary) -> Dictionary:
	var model := MapModel.new()
	model.setup(6, 4)
	var tiles: Array[Vector2i] = []
	var ground: int = _ground(String(spec.get("terrain", "open")))
	for y in 3:
		for x in 6:
			var index: int = model.index_of(x, y)
			model.terrain[index] = ground
			model.province[index] = PROVINCE
			tiles.append(Vector2i(x, y))
	for x in 6:
		model.terrain[model.index_of(x, 3)] = MapModel.Terrain.OCEAN
	var province := ProvinceState.create(
		PROVINCE, "Sandbox", tiles, Vector2(2.5, 1.0), tiles.size(), DEFENDER, false
	)
	province.town_tile = TOWN_TILE
	province.fort_level = clampi(int(spec.get("fort", 0)), 0, FortRules.MAX_LEVEL)
	model.provinces = [province]
	model.faction_ids = [ATTACKER, DEFENDER]
	var defender := ArmyState.muster(
		1, DEFENDER, PROVINCE, true, _types(spec.get("defender", [])), 1
	)
	var attacker := ArmyState.muster(
		2, ATTACKER, PROVINCE, false, _types(spec.get("attacker", [])), 1000
	)
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]
	var context: Dictionary = {
		"quick_battle": true,
		"player_faction": ATTACKER,
		"battle_plan": _plan(spec.get("attacker_plan", "balanced")),
		"defender_battle_plan": _plan(spec.get("defender_plan", "defensive")),
		"seed": int(spec.get("seed", 11)),
		"tech": {DEFENDER: (spec.get("tech", {}) as Dictionary).duplicate()},
		"army_medals": {
			attacker.id: clampi(int(spec.get("attacker_medals", 0)), 0, 4),
			defender.id: clampi(int(spec.get("defender_medals", 0)), 0, 4),
		},
	}
	var terrain: String = _terrain(String(spec.get("terrain", "open")))
	context["terrain_override"] = terrain
	return {
		"model": model,
		"armies": armies,
		"province": PROVINCE,
		"attacker": ATTACKER,
		"defender": DEFENDER,
		"context": context,
	}


## Builds and resolves in one step. Returns the battle record plus the world it
## left behind, so a simulator can show the fort and province after the fight.
static func fight(spec: Dictionary) -> Dictionary:
	var scene: Dictionary = build(spec)
	var armies: Array[ArmyState] = scene["armies"]
	var report: Dictionary = QuickBattle.resolve_exchange(
		scene["model"], armies, PROVINCE, DEFENDER, ATTACKER,
		bool(spec.get("further", false)), scene["context"]
	)
	return {
		"report": report,
		"model": scene["model"],
		"armies": armies,
		"province": PROVINCE,
	}


## Every type id the shrine offers, in catalog order (the simulator's picker).
static func catalog_types() -> Array[String]:
	return RegimentCatalog.ids()


static func _types(raw: Variant) -> Array[String]:
	var types: Array[String] = []
	if raw is Array:
		for entry: Variant in raw as Array:
			var type_id: String = RegimentCatalog.normalize(String(entry))
			if RegimentCatalog.has_type(type_id):
				types.append(type_id)
	return types


static func _plan(raw: Variant) -> String:
	var plan: String = String(raw)
	return plan if QuickBattleActions.PLANS.has(plan) else "balanced"


static func _terrain(raw: String) -> String:
	return raw if SiegeLanes.TERRAIN.has(raw) else "open"


static func _ground(terrain: String) -> int:
	match _terrain(terrain):
		"hill":
			return MapModel.Terrain.HILLS
		"woods":
			return MapModel.Terrain.HARDWOOD_FOREST
		"marsh":
			return MapModel.Terrain.SWAMP
	return MapModel.Terrain.PLAINS
