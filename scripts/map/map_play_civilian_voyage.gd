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
		# The landing rule names a tile; the dossier groups the legal grounds by
		# the coast they stand on, so the crown reads one line per coast and the
		# grounds behind it (wiki: civilian-units § Landing).
		var by_coast: Dictionary = _grounds(play, fleet, aboard)
		var coasts: Array[int] = [] as Array[int]
		for province: int in by_coast.keys():
			coasts.append(province)
		coasts.sort()
		for province: int in coasts:
			var grounds: Array[Dictionary] = [] as Array[Dictionary]
			for tile: Vector2i in by_coast[province]:
				grounds.append({"x": tile.x, "y": tile.y})
			data["land"].append({
				"province": province,
				"name": play.model.province_name(province),
				"tiles": grounds,
			})
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
		var pick: PackedStringArray = action.trim_prefix("crew:land:").split(":")
		if pick.size() >= 2:
			land(play, fleet, Vector2i(int(pick[0]), int(pick[1])))
		else:
			land(play, fleet, int(pick[0]))
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


## Puts a passenger ashore on the ground the crown named. `tile` is the tile the
## sheet pressed; a caller that names only the coast (a script, the smoke flow)
## passes the province and lands on the first legal ground it reads. A landing
## reveals the tile and its orthogonal neighbours (fog-and-exploration § New
## World arrival).
static func land(play: PlaySession, fleet: FleetState, ground: Variant) -> void:
	var province_id: int = CivilianVoyage.NO_ID
	var tile: Vector2i = CivilianState.NO_TILE
	if ground is Vector2i:
		tile = ground as Vector2i
	else:
		province_id = int(ground)
	var unit: CivilianState = null
	for candidate: CivilianState in _aboard(play, fleet):
		if tile.x >= 0:
			if bool(CivilianVoyage.can_disembark(play.model, candidate, fleet, tile)["ok"]):
				unit = candidate
				break
			continue
		tile = CivilianVoyage.landing_tile_in(play.model, candidate, fleet, province_id)
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
	var place: String = play.model.province_name(play.model.province_at(tile.x, tile.y))
	play.hud.toast(
		"The %s goes ashore at %s (%d, %d)"
		% [unit.display_name(), place, tile.x, tile.y]
	)
	_refresh(play, fleet)


## The home squadron puts to sea; the layer reveals the zone and reopens the
## dossier through its own move signal (wiki: ships-and-naval § Home Fleet).
static func sortie(play: PlaySession, fleet: FleetState, zone: int) -> void:
	var result: Dictionary = play.ship_layer.sortie(fleet, zone)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "The squadron cannot sail.")))


## Legal landing grounds of this squadron, grouped by the coast they stand on and
## deduplicated across passengers: two colonists aboard read one row per ground,
## not one per passenger.
static func _grounds(
	play: PlaySession, fleet: FleetState, aboard: Array[CivilianState]
) -> Dictionary:
	var by_coast: Dictionary = {}
	for unit: CivilianState in aboard:
		for tile: Vector2i in CivilianVoyage.landing_tiles(play.model, unit, fleet):
			var province: int = play.model.province_at(tile.x, tile.y)
			if province == CivilianVoyage.NO_ID:
				continue
			if not by_coast.has(province):
				by_coast[province] = []
			var grounds: Array = by_coast[province]
			if not grounds.has(tile):
				grounds.append(tile)
	return by_coast


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
