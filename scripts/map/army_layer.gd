class_name ArmyLayer
extends Node2D
## Owns land army markers and applies army orders; rules come from ArmyMovement
## and ArmyCombat, this layer only animates and reports them. Marker nodes live
## in ArmyMarkers, opening musters in ArmyMuster; ArmyTurnPass resolves the
## turn's battles; ArmyMusterOps owns split, dismiss, combine and recruit
## (REQ-P3-01; wiki: military-armies).

signal army_selected(army: ArmyState)
signal army_moved(army: ArmyState, result: Dictionary)

var model: MapModel = null
var armies: Array[ArmyState] = []
var selected_army: ArmyState = null
## Crown whose eyes are on this map: only her own standards paint the busy loop
## of an order (issue #1198). A chart that names no viewer reads every muster as
## the crown's own, which is what rules fixtures expect.
var viewer_faction: int = -1
## Abstract commanders per faction; binding to armies is per Combat phase.
var generals := GeneralRoster.new()

var _markers := ArmyMarkers.new()
var _muster := ArmyMuster.new()
## Public cursors so save/load never reaches layer privates (REQ-P3-02).
var next_army: int = 1
var next_regiment: int = 1
## Armies per region: switching maps must not move, heal or reset a muster.
var regions := MapRegionTable.new()

## Markers the shown region draws (view handles for taps and transport).
var markers: Array[ArmyMarker]:
	get:
		return _markers.markers


## Loads the region's armies (mustering Home Armies on first visit).
func spawn(p_model: MapModel) -> void:
	model = p_model
	_markers.model = model
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
	_muster.next_army = next_army
	_muster.next_regiment = next_regiment
	armies = _muster.build(model)
	next_army = _muster.next_army
	next_regiment = _muster.next_regiment
	for army: ArmyState in armies:
		add_marker(army)
	regions.set_region(model.region_id, armies)


## Join Empire: an absorbed crown's land regiments change colours; a former Home
## Army becomes a field army so the winner keeps exactly one
## (wiki: diplomacy § GP–Minor Rules, military-armies § Home Army). A fall
## (`MapModel.NO_ID`) retires them. Every stored roster is handed over in place
## and written back, since a retirement rewrites the list a region holds.
func transfer_owner(from_id: int, to_id: int) -> void:
	for region: int in regions.region_ids():
		var stored: Array[ArmyState] = []
		stored.assign(regions.value(region, []))
		ArmyRoster.hand_over(stored, from_id, to_id)
		regions.set_region(region, stored)
	ArmyRoster.hand_over(armies, from_id, to_id)
	_rebuild_markers()
	select(selected_army)


func _rebuild_markers() -> void:
	_markers.clear()
	for army: ArmyState in armies:
		add_marker(army)
	place_all()


func add_marker(army: ArmyState) -> void:
	var marker: ArmyMarker = _markers.make(army)
	if marker == null:
		return
	add_child(marker)
	place_all()


## Stacks armies sharing a province in a short row so each standard is legible.
func place_all() -> void:
	_markers.place_all(armies)


func marker_for(army: ArmyState) -> ArmyMarker:
	if not is_instance_valid(self):
		return null
	return _markers.find_army(army)


## Drops one standard from the book (embark, merge sink, transport).
func remove_marker(army: ArmyState) -> void:
	var marker: ArmyMarker = marker_for(army)
	if marker != null:
		_markers.remove(marker)
		place_all()


## Re-reads one army's strength onto its marker after muster surgery.
func refresh_marker(army: ArmyState) -> void:
	_markers.refresh(army)


func set_zoom(value: float) -> void:
	_markers.set_zoom(value)


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
	return _markers.nearest(armies, world_position)


## Applies a march through the rules, then animates the standard. `visibility` is
## the crown's own chart: a march onto ground it has never charted is refused at
## the rules' gate (wiki: fog-and-exploration § Order Visibility Requirements).
func order(
	army: ArmyState,
	province_id: int,
	at_war: bool = true,
	visibility: VisibilityModel = null
) -> Dictionary:
	var result: Dictionary = ArmyMovement.apply_move(
		model, army, province_id, at_war, visibility
	)
	if not bool(result.get("ok", false)):
		return result
	var marker: ArmyMarker = marker_for(army)
	if marker != null:
		var target: Vector2 = _markers.province_position(army.province)
		# The march loop runs only for the crown's own standard, and only while
		# it travels: an idle or a rival banner stays as it was (issue #1198).
		var marching: bool = viewer_faction < 0 or army.owner == viewer_faction
		if marching:
			marker.set_order(OrderMotion.Order.MOVE, target - marker.position)
		var tween: Tween = create_tween()
		tween.tween_property(marker, "position", target, 0.38).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
		# The standard is looked up by id at the end of the march: a marker the
		# chart dropped mid-step (a merge, a retirement) is simply gone.
		var army_id: int = army.id
		tween.tween_callback(func() -> void:
			var settled: ArmyMarker = _markers.find(army_id)
			if settled != null:
				settled.set_order(OrderMotion.Order.NONE)
			place_all()
		)
	army_moved.emit(army, result)
	return result


func armies_in(province_id: int, owner: int) -> Array[ArmyState]:
	return ArmyForce.armies_of(armies, province_id, owner)


## Grows a Great Power's general pool to its tech-gated cap (wiki:
## military-generals § Count and tech-gated cap).
func sync_generals(owner: int, tech_unlocked: Dictionary) -> void:
	if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
		generals.sync(owner, tech_unlocked)


## Commander block for the dossier: each general by name and medals, then what a
## medal buys in the field; empty for Minor Nations and Tribes.
func command_text(army: ArmyState) -> String:
	if army == null or FactionCatalog.type_of(army.owner) != FactionCatalog.Type.GREAT_POWER:
		return ""
	return generals.line(army.owner)


## Drops the standard of an army that left the field and raises one for an army
## the map never drew: the combat pass can mint a garrison the layer never saw
## (wiki: combat § Garrison recovery), and an army without a standard cannot be
## seen, tapped or ordered.
func prune_markers() -> void:
	_markers.prune(armies)
	if selected_army != null and not armies.has(selected_army):
		selected_army = null
		army_selected.emit(null)
	place_all()
	for army: ArmyState in armies:
		add_marker(army)


## Regiments for one faction across every region: the HUD counts them all.
func regiment_count_all(owner: int) -> int:
	return ArmyRoster.count_all(regions, owner)


func food_upkeep_all(owner: int) -> int:
	return ArmyRoster.food_upkeep_all(regions, owner)


## Fog hides rival standards until their province is fully visible.
func sync_visibility(visibility: VisibilityModel, player_faction: int) -> void:
	_markers.sync_visibility(armies, visibility, player_faction)
