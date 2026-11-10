class_name MapPlayFocus
extends RefCounted
## Top-bar force plaques double as a "where are my pieces?" control: each press
## selects the next own squadron or army in the region on screen and brings it
## under the camera. Presentation only — selection still flows through the
## normal map helpers, so dossiers and move overlays stay in one place
## (REQ-P1-05).

const KIND_FLEET := "fleet"
const KIND_ARMY := "army"


static func bind(play: PlaySession) -> void:
	if play == null or play.hud == null:
		return
	play.hud.fleet_status_pressed.connect(func() -> void: focus_next(play, KIND_FLEET))
	play.hud.army_status_pressed.connect(func() -> void: focus_next(play, KIND_ARMY))


static func focus_next(play: PlaySession, kind: String) -> void:
	match kind:
		KIND_FLEET:
			_next_fleet(play)
		KIND_ARMY:
			_next_army(play)


static func _next_fleet(play: PlaySession) -> void:
	var ships: Array[Ship] = []
	for ship: Ship in play.ship_layer.ships:
		if ship.faction == play.player_faction:
			ships.append(ship)
	if ships.is_empty():
		play.hud.toast("No squadron in this region")
		return
	var next: Ship = _pick(ships, play.ship_layer.selected()) as Ship
	play.ship_layer.select(next)
	play.camera.focus_on(next.position, maxf(play.camera.target_zoom, 1.0))


static func _next_army(play: PlaySession) -> void:
	var armies: Array[ArmyState] = []
	for army: ArmyState in play.army_layer.armies:
		if army.owner != play.player_faction:
			continue
		if play.army_layer.marker_for(army) == null:
			continue
		armies.append(army)
	if armies.is_empty():
		play.hud.toast("No army in this region")
		return
	var next: ArmyState = _pick(armies, play.army_layer.selected_army) as ArmyState
	play.army_layer.select(next)
	var marker: ArmyMarker = play.army_layer.marker_for(next)
	if marker != null:
		play.camera.focus_on(marker.position, maxf(play.camera.target_zoom, 1.0))


## The next item after the current one, wrapping; an unknown current selection
## starts the cycle at the first item.
static func _pick(items: Array, current: Variant) -> Variant:
	var index: int = items.find(current)
	return items[(index + 1) % items.size()]
