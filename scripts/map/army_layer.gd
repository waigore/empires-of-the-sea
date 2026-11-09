class_name ArmyLayer
extends Node2D
## Owns land army markers and applies army orders; rules come from ArmyMovement
## and ArmyCombat, this layer only animates and reports them (wiki: military-armies).

signal army_selected(army: ArmyState)
signal army_moved(army: ArmyState, result: Dictionary)

const TILE_SIZE: float = 22.0
const MARKER_RADIUS: float = 30.0
## Opening musters; the wiki fixes the Home Army's existence, not its size.
const GREAT_POWER_ROSTER: Array[String] = [
	"peasant_levies", "peasant_levies", "pikemen", "arquebusiers", "squires"
]
const MINOR_ROSTER: Array[String] = ["peasant_levies", "peasant_levies", "bowmen"]
const TRIBE_ROSTER: Array[String] = ["peasant_levies", "peasant_levies"]

var model: MapModel = null
var armies: Array[ArmyState] = []
var markers: Array[ArmyMarker] = []
var selected_army: ArmyState = null
## Abstract commanders per faction; binding to armies is per Combat phase.
var generals := GeneralRoster.new()

var _zoom: float = 1.0
## Public cursors so save/load never reaches layer privates (REQ-P3-02).
var next_army: int = 1
var next_regiment: int = 1
## Armies per region: switching maps must not move, heal or reset a muster.
var regions := MapRegionTable.new()


## Loads the region's armies (mustering Home Armies on first visit).
func spawn(p_model: MapModel) -> void:
	model = p_model
	armies = []
	selected_army = null
	_rebuild_markers()
	if model == null:
		return
	if regions.has_region(model.region_id):
		armies.assign(regions.value(model.region_id, []))
		regions.set_region(model.region_id, armies)
		_rebuild_markers()
		return
	for faction: int in model.faction_ids:
		var capital: int = MapModel.NO_ID
		for province: ProvinceState in model.provinces:
			if province.owner == faction and province.capital:
				capital = province.id
				break
		if capital < 0:
			continue
		var roster: Array[String] = []
		match FactionCatalog.type_of(faction):
			FactionCatalog.Type.GREAT_POWER:
				roster = GREAT_POWER_ROSTER.duplicate()
			FactionCatalog.Type.MINOR_NATION:
				roster = MINOR_ROSTER.duplicate()
			_:
				roster = TRIBE_ROSTER.duplicate()
		_muster(faction, capital, true, roster)
	regions.set_region(model.region_id, armies)


## Join Empire: an absorbed crown's land regiments change colours; a former Home
## Army becomes a field army so the winner keeps exactly one
## (wiki: diplomacy § GP–Minor Rules, military-armies § Home Army).
func transfer_owner(from_id: int, to_id: int) -> void:
	for raw: Variant in regions.values():
		ArmyState.hand_over(raw, from_id, to_id)
	ArmyState.hand_over(armies, from_id, to_id)
	_rebuild_markers()
	select(selected_army)


## Mints a Home Army (or recovered/field army) and registers its marker.
func _muster(owner: int, province: int, home: bool, types: Array[String]) -> ArmyState:
	var army := ArmyState.muster(
		next_army, owner, province, home, types, next_regiment
	)
	next_army += 1
	next_regiment += types.size()
	armies.append(army)
	add_marker(army)
	return army


func _rebuild_markers() -> void:
	for marker: ArmyMarker in markers:
		marker.queue_free()
	markers.clear()
	for army: ArmyState in armies:
		add_marker(army)
	place_all()


func add_marker(army: ArmyState) -> void:
	if army == null or army.is_embarked() or marker_for(army) != null:
		return
	var marker := ArmyMarker.new()
	marker.army_id = army.id
	marker.faction = army.owner
	marker.home = army.home
	marker.refresh(army.count(), army.home)
	marker.scale = Vector2.ONE * clampf(1.0 / _zoom, 0.62, 1.0)
	add_child(marker)
	markers.append(marker)
	place_all()


## Stacks armies sharing a province in a short row so each standard is legible.
func place_all() -> void:
	var groups: Dictionary = {}
	for army: ArmyState in armies:
		if army == null or army.is_embarked():
			continue
		var group: Array[ArmyState] = []
		group.assign(groups.get(army.province, []))
		group.append(army)
		groups[army.province] = group
	for province: int in groups.keys():
		var group: Array[ArmyState] = []
		group.assign(groups[province])
		group.sort_custom(func(a: ArmyState, b: ArmyState) -> bool: return a.id < b.id)
		var base: Vector2 = _province_position(province)
		var span: float = 22.0
		for index in group.size():
			var marker: ArmyMarker = marker_for(group[index])
			if marker == null:
				continue
			marker.position = base + Vector2((float(index) - float(group.size() - 1) * 0.5) * span, 0)
			marker.refresh(group[index].count(), group[index].home)


func _province_position(province_id: int) -> Vector2:
	var data: ProvinceState = model.province_data(province_id) if model != null else null
	if data == null:
		return Vector2.ZERO
	return data.center * TILE_SIZE


func marker_for(army: ArmyState) -> ArmyMarker:
	if army == null or not is_instance_valid(self):
		return null
	for marker: ArmyMarker in markers:
		if is_instance_valid(marker) and marker.army_id == army.id:
			return marker
	return null


func set_zoom(value: float) -> void:
	_zoom = maxf(value, 0.001)
	for marker: ArmyMarker in markers:
		if is_instance_valid(marker):
			marker.scale = Vector2.ONE * clampf(1.0 / _zoom, 0.62, 1.0)


func select(army: ArmyState) -> void:
	if selected_army != null:
		var previous: ArmyMarker = marker_for(selected_army)
		if previous != null:
			previous.set_selected(false)
	selected_army = army
	if army != null:
		var marker: ArmyMarker = marker_for(army)
		if marker != null:
			marker.set_selected(true)
	army_selected.emit(army)


func deselect() -> void:
	if selected_army == null:
		return
	select(null)


## Closest visible standard to a world tap within the marker radius.
func army_at(world_position: Vector2) -> ArmyState:
	var best: ArmyState = null
	var best_distance: float = minf(MARKER_RADIUS / maxf(_zoom, 0.001), TILE_SIZE * 1.1)
	for army: ArmyState in armies:
		var marker: ArmyMarker = marker_for(army)
		if marker == null or not marker.visible:
			continue
		var distance: float = marker.position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = army
	return best


## Applies a march through the rules, then animates the standard.
func order(army: ArmyState, province_id: int, at_war: bool = true) -> Dictionary:
	var result: Dictionary = ArmyMovement.apply_move(model, army, province_id, at_war)
	if not bool(result.get("ok", false)):
		return result
	var marker: ArmyMarker = marker_for(army)
	if marker != null:
		var tween: Tween = create_tween()
		tween.tween_property(marker, "position", _province_position(army.province), 0.38).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(place_all)
	army_moved.emit(army, result)
	return result


## Detaches regiment instances into a new field army (wiki: military-armies).
func split(army: ArmyState, regiment_ids: Array[String]) -> Dictionary:
	var result: Dictionary = ArmyState.split(armies, army, regiment_ids, next_army)
	if not bool(result.get("ok", false)):
		return result
	next_army += 1
	prune_markers()
	var created: ArmyState = result["army"] as ArmyState
	add_marker(created)
	place_all()
	return result


## Combines the selected army with friendly armies in its province. The Home
## Army wins the merge target when it is in the group (wiki: military-armies).
func combine(army: ArmyState) -> Dictionary:
	if army == null:
		return {"ok": false, "reason": "There is no army to combine."}
	var selected: Array[ArmyState] = [army]
	for other: ArmyState in armies:
		if other != army and other.province == army.province and other.owner == army.owner:
			selected.append(other)
	var before: Array[ArmyState] = selected.duplicate()
	var result: Dictionary = ArmyState.combine(armies, selected)
	if not bool(result.get("ok", false)):
		return result
	for old: ArmyState in before:
		if armies.has(old):
			continue
		var marker: ArmyMarker = marker_for(old)
		if marker != null:
			markers.erase(marker)
			marker.queue_free()
	place_all()
	return result


func armies_in(province_id: int, owner: int) -> Array[ArmyState]:
	return ArmyCombat.armies_of(armies, province_id, owner)


## Musters one regiment into the faction's Home Army, keeping the marker in step.
func recruit(owner: int, type_id: String, economy: PlayerEconomy) -> Dictionary:
	var home: ArmyState = ArmyTraining.home_army(armies, owner)
	if home == null:
		return {
			"ok": false,
			"reason": "The Home Army musters at your capital.",
			"type": "",
			"regiment": "",
		}
	var unit_id: String = "unit_%d" % next_regiment
	var result: Dictionary = ArmyTraining.recruit(economy, home, type_id, unit_id)
	if not bool(result.get("ok", false)):
		return result
	next_regiment += 1
	var marker: ArmyMarker = marker_for(home)
	if marker != null:
		marker.refresh(home.count(), home.home)
		marker.visible = true
	place_all()
	return result


## Grows a Great Power's general pool to its tech-gated cap (wiki:
## military-generals § Count and tech-gated cap).
func sync_generals(owner: int, tech_unlocked: Dictionary) -> void:
	if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
		generals.sync(owner, tech_unlocked)


## Commander line for the dossier; empty for Minor Nations and Tribes.
func command_text(army: ArmyState) -> String:
	if army == null or FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
		return ""
	return generals.summary(army.owner)


func begin_turn() -> void:
	for raw: Variant in regions.values():
		var stored: Array[ArmyState] = []
		stored.assign(raw)
		ArmyMovement.begin_turn(stored)


## Resolves land battles in every region: a battle must not wait for the player
## to open that map (wiki: map-topology § two regions); `context["hostile"]` is
## the court's war query so peace never spills blood.
func resolve_battles(world: WorldMap, context: Dictionary = {}) -> Array[Dictionary]:
	var by_region: Dictionary = {}
	for index in world.region_count():
		var region_armies: Array[ArmyState] = []
		if model != null and index == model.region_id:
			region_armies = armies
		else:
			region_armies.assign(regions.value(index, []))
		by_region[index] = region_armies
	var all: Array[Dictionary] = ArmyBattles.resolve_region_turn(world, by_region, generals, context)
	for index in world.region_count():
		var region_armies: Array[ArmyState] = []
		region_armies.assign(by_region.get(index, []))
		regions.set_region(index, region_armies)
		if model != null and index == model.region_id and region_armies != armies:
			armies = region_armies
			prune_markers()
	return all


func prune_markers() -> void:
	var kept: Array[ArmyMarker] = []
	for marker: ArmyMarker in markers:
		var army: ArmyState = null
		for candidate: ArmyState in armies:
			if candidate != null and candidate.id == marker.army_id:
				army = candidate
				break
		if army == null:
			marker.queue_free()
			continue
		marker.refresh(army.count(), army.home)
		kept.append(marker)
	markers = kept
	if selected_army != null and not armies.has(selected_army):
		selected_army = null
		army_selected.emit(null)
	place_all()


## Regiments for one faction across every region: the HUD counts them all.
func regiment_count_all(owner: int) -> int:
	var total: int = 0
	for raw: Variant in regions.values():
		var stored: Array[ArmyState] = []
		stored.assign(raw)
		total += ArmyState.count_of(stored, owner)
	return total


func food_upkeep_all(owner: int) -> int:
	var total: int = 0
	for raw: Variant in regions.values():
		var stored: Array[ArmyState] = []
		stored.assign(raw)
		total += ArmyState.food_upkeep_of(stored, owner)
	return total


## Fog hides rival standards until their province is fully visible.
func sync_visibility(visibility: VisibilityModel, player_faction: int) -> void:
	for army: ArmyState in armies:
		var marker: ArmyMarker = marker_for(army)
		if marker == null:
			continue
		if army.is_embarked():
			marker.visible = false
			continue
		if army.owner == player_faction or visibility == null:
			marker.visible = army.count() > 0
			continue
		var data: ProvinceState = model.province_data(army.province)
		var tile: Vector2i = (
			data.tiles[0] if data != null and not data.tiles.is_empty() else Vector2i(-1, -1)
		)
		marker.visible = (
			army.count() > 0
			and tile.x >= 0
			and visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE
		)
