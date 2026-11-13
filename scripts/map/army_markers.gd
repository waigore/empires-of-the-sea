class_name ArmyMarkers
extends RefCounted
## Marker bookkeeping for one region's army roster: mint one [ArmyMarker] per
## army, stack standards that share a province, and drop markers that left the
## field. ArmyLayer keeps orders, battles and signals; this helper owns the
## node lifecycle so the layer stays under the soft size bar (REQ-P3-01,
## REQ-P3-03). The layer adds every minted node to itself.

const TILE_SIZE: float = 22.0
const MARKER_RADIUS: float = 30.0

var model: MapModel = null
var markers: Array[ArmyMarker] = []
var zoom: float = 1.0


## Mints a marker for a land army; embarked armies leave no standard.
func make(army: ArmyState) -> ArmyMarker:
	if army == null or army.is_embarked() or find(army.id) != null:
		return null
	var marker := ArmyMarker.new()
	marker.army_id = army.id
	marker.faction = army.owner
	marker.home = army.home
	marker.refresh(army.count(), army.home)
	marker.scale = Vector2.ONE * clampf(1.0 / zoom, 0.62, 1.0)
	markers.append(marker)
	return marker


## Frees every marker.
func clear() -> void:
	for marker: ArmyMarker in markers:
		marker.queue_free()
	markers.clear()


## Drops one marker from the book and frees its node.
func remove(marker: ArmyMarker) -> void:
	if marker == null:
		return
	markers.erase(marker)
	marker.queue_free()


## Marker for an army id, or null when that muster has no standard.
func find(army_id: int) -> ArmyMarker:
	for marker: ArmyMarker in markers:
		if is_instance_valid(marker) and marker.army_id == army_id:
			return marker
	return null


func find_army(army: ArmyState) -> ArmyMarker:
	if army == null:
		return null
	return find(army.id)


## Stacks armies sharing a province in a short row so each standard is legible.
func place_all(armies: Array[ArmyState]) -> void:
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
		var base: Vector2 = province_position(province)
		var span: float = 22.0
		for index in group.size():
			var marker: ArmyMarker = find_army(group[index])
			if marker == null:
				continue
			marker.position = base + Vector2((float(index) - float(group.size() - 1) * 0.5) * span, 0)
			marker.refresh(group[index].count(), group[index].home)


func province_position(province_id: int) -> Vector2:
	var data: ProvinceState = model.province_data(province_id) if model != null else null
	if data == null:
		return Vector2.ZERO
	return data.center * TILE_SIZE


func set_zoom(value: float) -> void:
	zoom = maxf(value, 0.001)
	for marker: ArmyMarker in markers:
		if is_instance_valid(marker):
			marker.scale = Vector2.ONE * clampf(1.0 / zoom, 0.62, 1.0)


## Closest visible standard to a world tap within the marker radius.
func nearest(armies: Array[ArmyState], world_position: Vector2) -> ArmyState:
	var best: ArmyState = null
	var best_distance: float = minf(MARKER_RADIUS / maxf(zoom, 0.001), TILE_SIZE * 1.1)
	for army: ArmyState in armies:
		var marker: ArmyMarker = find_army(army)
		if marker == null or not marker.visible:
			continue
		var distance: float = marker.position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = army
	return best


## Drops standards for armies that left the field and refreshes the rest;
## returns markers still on the book so the layer can raise missing ones.
func prune(armies: Array[ArmyState]) -> void:
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


## Re-reads one army's count onto its marker after a muster or recruit.
func refresh(army: ArmyState) -> void:
	var marker: ArmyMarker = find_army(army)
	if marker == null:
		return
	marker.refresh(army.count(), army.home)
	marker.visible = true


## Fog hides rival standards until their province is fully visible.
func sync_visibility(
	armies: Array[ArmyState], visibility: VisibilityModel, player_faction: int
) -> void:
	for army: ArmyState in armies:
		var marker: ArmyMarker = find_army(army)
		if marker == null:
			continue
		if army.is_embarked():
			marker.visible = false
			continue
		if army.owner == player_faction or visibility == null:
			marker.visible = army.count() > 0
			continue
		var data: ProvinceState = model.province_data(army.province) if model != null else null
		var tile: Vector2i = (
			data.tiles[0] if data != null and not data.tiles.is_empty() else Vector2i(-1, -1)
		)
		marker.visible = (
			army.count() > 0
			and tile.x >= 0
			and visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE
		)
