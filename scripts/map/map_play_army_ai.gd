class_name MapPlayArmyAi
extends RefCounted
## Rival land turn: every region's stored roster is planned and applied through
## ArmyMovement, so a march this turn fights this turn (docs/ai.md). Splits run
## first so a court that has just declared war can field an army at once.


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if play.army_layer == null or play.diplomacy == null or play.world == null:
		return trace
	for region: int in play.army_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[ArmyState] = []
		roster.assign(play.army_layer.regions.value(region, []))
		if roster.is_empty():
			continue
		if not _run_region(play, model, roster, trace):
			continue
		play.army_layer.regions.set_region(region, roster)
		if play.army_layer.model != null and play.army_layer.model.region_id == region:
			_adopt_visible(play)
	return trace


## Re-reads the on-screen roster after the rules moved it; the player's selected
## standard survives the refresh when it is still in the region.
static func _adopt_visible(play: PlaySession) -> void:
	var selected: ArmyState = play.army_layer.selected_army
	play.army_layer.spawn(play.army_layer.model)
	if selected != null and play.army_layer.armies.has(selected):
		play.army_layer.select(selected)


static func _run_region(
	play: PlaySession, model: MapModel, roster: Array[ArmyState], trace: Array[Dictionary]
) -> bool:
	var changed: bool = false
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		for action: Dictionary in AiMilitaryPlanner.split_orders(
			config, play.diplomacy, model, roster
		):
			var home: ArmyState = _army_by_id(roster, int(action["army_id"]), faction)
			if home == null:
				continue
			var ids: Array[String] = []
			ids.assign(action["regiments"])
			var split: Dictionary = ArmyState.split(
				roster, home, ids, play.army_layer.next_army
			)
			if not bool(split.get("ok", false)):
				continue
			var field: ArmyState = split["army"] as ArmyState
			play.army_layer.next_army += 1
			changed = true
			trace.append({
				"faction": faction,
				"kind": AiMilitaryPlanner.KIND_SPLIT,
				"army": field.id,
				"province": field.province,
			})
		var plan: Dictionary = AiMilitaryPlanner.march_orders(
			config, play.diplomacy, model, roster
		)
		for order: Dictionary in plan["orders"]:
			var army: ArmyState = _army_by_id(roster, int(order["army_id"]), faction)
			if army == null:
				continue
			var province: int = int(order["province"])
			var march: Dictionary = ArmyMovement.apply_move(model, army, province, true)
			if not bool(march.get("ok", false)):
				continue
			changed = true
			trace.append({
				"faction": faction,
				"kind": AiMilitaryPlanner.KIND_MARCH,
				"army": army.id,
				"province": province,
				"attacked": bool(march.get("attacked", false)),
			})
			_report_march(play, model, faction, province)
	return changed


## Critical state changes are never silent: a rival entering the human's land
## gets a toast; battles and captures already report through the battle line.
static func _report_march(
	play: PlaySession, model: MapModel, faction: int, province: int
) -> void:
	if play.hud == null or model.province_owner(province) != play.player_faction:
		return
	play.hud.toast(
		"%s's army marches into %s"
		% [FactionCatalog.name_of(faction), model.province_name(province)]
	)


static func _army_by_id(armies: Array[ArmyState], army_id: int, owner: int) -> ArmyState:
	for army: ArmyState in armies:
		if army != null and army.id == army_id and army.owner == owner:
			return army
	return null
