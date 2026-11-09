class_name MapPlayCivilianVoyage
extends RefCounted
## The fleet dossier's passenger block and its intents (DR-20261109-17):
## colonists aboard, idle civilians to take on, coasts to put them ashore, and
## the home squadron's sortie. Rules live in CivilianVoyage and FleetSortie.


## Dossier data: {"count", "note", "embark", "land", "sortie"}.
static func crew(play: PlaySession, fleet: FleetState) -> Dictionary:
	var data: Dictionary = {
		"count": 0, "note": "", "embark": [], "land": [], "sortie": [],
	}
	if fleet == null or fleet.owner != play.player_faction:
		return data
	var aboard: Array[CivilianState] = _aboard(play, fleet)
	data["count"] = aboard.size()
	data["note"] = _note(aboard)
	if (
		fleet.is_in_port()
		and not fleet.moved
		and fleet.embarked_army < 0
		and fleet.civilian_count() < CivilianVoyage.capacity(fleet)
	):
		for unit: CivilianState in play.civilian_layer.units:
			if unit == null or unit.owner != play.player_faction:
				continue
			if not bool(CivilianVoyage.can_embark(play.model, unit, fleet)["ok"]):
				continue
			var row: Dictionary = {"id": unit.id, "name": unit.display_name()}
			data["embark"].append(row)
	if not aboard.is_empty():
		var provinces: Array[int] = []
		for unit: CivilianState in aboard:
			for province: int in CivilianVoyage.landing_provinces(
				play.model, unit, fleet
			):
				if not provinces.has(province):
					provinces.append(province)
		provinces.sort()
		for province: int in provinces:
			var row: Dictionary = {
				"province": province,
				"name": play.model.province_name(province),
			}
			data["land"].append(row)
	for zone: int in FleetSortie.zones(play.model, fleet):
		if not bool(FleetSortie.can_sortie(play.model, fleet, zone)["ok"]):
			continue
		var row: Dictionary = {"zone": zone, "name": play.model.sea_zone_name(zone)}
		data["sortie"].append(row)
	return data


## Routes a crew intent; true when this block claimed the action.
static func on_action(play: PlaySession, action: String) -> bool:
	if play.campaign_over():
		return false
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return false
	if action.begins_with("crew:embark:"):
		embark(play, fleet, int(action.trim_prefix("crew:embark:")))
		return true
	if action.begins_with("crew:land:"):
		land(play, fleet, int(action.trim_prefix("crew:land:")))
		return true
	if action.begins_with("sortie:"):
		sortie(play, fleet, int(action.trim_prefix("sortie:")))
		return true
	return false


## Takes one idle civilian aboard the selected squadron.
static func embark(play: PlaySession, fleet: FleetState, unit_id: int) -> void:
	var unit: CivilianState = CivilianVoyageMap.by_id(play.civilian_layer, unit_id)
	var result: Dictionary = CivilianVoyage.embark(play.model, unit, fleet)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The civilian cannot board.")))
		return
	CivilianVoyageMap.hide(play.civilian_layer, unit)
	play.hud.toast(
		"The %s boards at %s"
		% [unit.display_name(), play.model.province_name(fleet.province)]
	)
	_refresh(play, fleet)


## Puts the first passenger able to take the chosen coast ashore. A landing
## reveals the tile and its orthogonal neighbours (fog-and-exploration § New
## World arrival).
static func land(play: PlaySession, fleet: FleetState, province_id: int) -> void:
	var unit: CivilianState = null
	var tile: Vector2i = CivilianState.NO_TILE
	for candidate: CivilianState in _aboard(play, fleet):
		tile = CivilianVoyage.landing_tile_in(
			play.model, candidate, fleet, province_id
		)
		if tile.x >= 0:
			unit = candidate
			break
	if unit == null:
		play.hud.toast("No colonist aboard can land on that coast.")
		return
	var result: Dictionary = CivilianVoyage.disembark(play.model, unit, fleet, tile)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The civilian cannot land.")))
		return
	CivilianVoyageMap.show_ashore(play.civilian_layer, unit)
	_reveal(play, tile)
	var place: String = play.model.province_name(province_id)
	play.hud.toast("The %s goes ashore at %s" % [unit.display_name(), place])
	_refresh(play, fleet)


## The home squadron puts to sea; the layer reveals the zone and reopens the
## dossier through its own move signal (wiki: ships-and-naval § Home Fleet).
static func sortie(play: PlaySession, fleet: FleetState, zone: int) -> void:
	var result: Dictionary = play.ship_layer.sortie(fleet, zone)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The squadron cannot sail.")))


## Passengers carried by this squadron, in instance-id order.
static func _aboard(
	play: PlaySession, fleet: FleetState
) -> Array[CivilianState]:
	var aboard: Array[CivilianState] = []
	for unit_id: int in fleet.embarked_civilians:
		var unit: CivilianState = CivilianVoyageMap.by_id(
			play.civilian_layer, unit_id
		)
		if unit != null:
			aboard.append(unit)
	return aboard


static func _note(aboard: Array[CivilianState]) -> String:
	if aboard.is_empty():
		return "No colonists aboard."
	var names: PackedStringArray = PackedStringArray()
	for unit: CivilianState in aboard:
		names.append(unit.display_name())
	return "%d aboard: %s" % [aboard.size(), " · ".join(names)]


static func _reveal(play: PlaySession, tile: Vector2i) -> void:
	if play.visibility == null or tile.x < 0:
		return
	var changed: Array = play.visibility.reveal_landing(tile)
	if not changed.is_empty():
		play.overlay.sync_visibility(play.visibility, changed)


static func _refresh(play: PlaySession, fleet: FleetState) -> void:
	MapPlayFleets.show_dossier(play, fleet)
	MapPlayFleets.refresh_options(play, fleet)
