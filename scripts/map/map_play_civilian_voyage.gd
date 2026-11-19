class_name MapPlayCivilianVoyage
extends RefCounted
## The fleet dossier's passenger block and its intents (DR-20261109-17):
## colonists aboard, idle civilians to take on, coasts to put them ashore, and
## the home squadron's sortie. Rules live in CivilianVoyage and FleetSortie.
##
## A landing is a **tile** and a **crew** (wiki: civilian-units § Landing;
## DR-20261118-19): the block groups the legal grounds by the crew kind that can
## take them and by the coast they stand on, so the press names both what it
## lands and where. Two crews of one kind read one line, because which of them
## steps off is no choice the crown can tell apart.


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
		# The landing rule names a tile; the crew's kind is what the crown picks
		# between, so the block reads one line per crew kind per coast and the
		# grounds behind it (wiki: civilian-units § Landing).
		var by_coast: Dictionary = _grounds(play, fleet, aboard)
		for type_id: String in _aboard_types(aboard):
			for province: int in _provinces_of(by_coast, type_id):
				var row: Dictionary = by_coast["%d|%s" % [province, type_id]]
				var tiles: Array[Vector2i] = row["tiles"]
				var grounds: Array[Dictionary] = [] as Array[Dictionary]
				for tile: Vector2i in tiles:
					grounds.append({
						"x": tile.x, "y": tile.y,
						"ground": _ground_label(play, tile),
					})
				var entry: Dictionary = {
					"province": province,
					"name": play.model.province_name(province),
					"crew": type_id,
					"crew_name": CivilianCatalog.display_name(type_id),
					"tiles": grounds,
				}
				var seat: Dictionary = _seat(play, fleet, province, tiles)
				if not seat.is_empty():
					entry["seat"] = seat
				data["land"].append(entry)
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
			land(
				play, fleet, Vector2i(int(pick[0]), int(pick[1])),
				String(pick[2]) if pick.size() >= 3 else ""
			)
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
## sheet pressed; `crew_type` is the kind of crew the press named, so the crown's
## choice between a Builder and an Explorer is the one it read. A caller that
## names only the ground or only the coast (a script, the smoke flow) lands the
## first able crew, which is the published convenience. A landing reveals the
## tile and its orthogonal neighbours (fog-and-exploration § New World arrival).
static func land(
	play: PlaySession, fleet: FleetState, ground: Variant, crew_type: String = ""
) -> void:
	var province_id: int = CivilianVoyage.NO_ID
	var tile: Vector2i = CivilianState.NO_TILE
	if ground is Vector2i:
		tile = ground as Vector2i
	else:
		province_id = int(ground)
	var unit: CivilianState = null
	for candidate: CivilianState in _aboard(play, fleet):
		if not crew_type.is_empty() and candidate.type_id != crew_type:
			continue
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
		var where: String = "that ground" if ground is Vector2i else "that coast"
		if crew_type.is_empty():
			play.hud.toast("No colonist aboard can land on %s." % where)
		else:
			play.hud.toast(
				"The %s aboard cannot land on %s."
				% [CivilianCatalog.display_name(crew_type), where]
			)
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


## Legal landing grounds of this squadron, grouped by the crew kind that can take
## them and by the coast they stand on. Two crews of one kind read one line: the
## crown cannot tell those two apart, and one ground is listed once.
static func _grounds(
	play: PlaySession, fleet: FleetState, aboard: Array[CivilianState]
) -> Dictionary:
	var by_coast: Dictionary = {}
	for unit: CivilianState in aboard:
		for tile: Vector2i in CivilianVoyage.landing_tiles(play.model, unit, fleet):
			var province: int = play.model.province_at(tile.x, tile.y)
			if province == CivilianVoyage.NO_ID:
				continue
			var key: String = "%d|%s" % [province, unit.type_id]
			if not by_coast.has(key):
				by_coast[key] = {
					"province": province, "crew": unit.type_id,
					"tiles": [] as Array[Vector2i],
				}
			var grounds: Array = by_coast[key]["tiles"]
			if not grounds.has(tile):
				grounds.append(tile)
	return by_coast


## Crew kinds aboard, in the order they are read (two Builders read once).
static func _aboard_types(aboard: Array[CivilianState]) -> Array[String]:
	var types: Array[String] = [] as Array[String]
	for unit: CivilianState in aboard:
		if not types.has(unit.type_id):
			types.append(unit.type_id)
	return types


## Coasts this crew kind can land on, lowest id first.
static func _provinces_of(by_coast: Dictionary, type_id: String) -> Array[int]:
	var provinces: Array[int] = [] as Array[int]
	for key: String in by_coast.keys():
		if String(by_coast[key]["crew"]) != type_id:
			continue
		provinces.append(int(by_coast[key]["province"]))
	provinces.sort()
	return provinces


## What the crown can read of a ground: the terrain once the chart has reached
## it, and the commodity an estate there would work — never a mineral no Explorer
## has prospected, and nothing at all of an uncharted tile (wiki:
## fog-and-exploration § Prospect-Required Resources, § What a landing reveals).
static func _ground_label(play: PlaySession, tile: Vector2i) -> String:
	if play.model == null or not play.model.is_land(tile.x, tile.y):
		return ""
	var level: int = VisibilityModel.Level.FULLY_VISIBLE
	if play.visibility != null:
		level = play.visibility.level_at(tile.x, tile.y)
	if level < VisibilityModel.Level.FOGGED:
		return ""
	var terrain: String = String(MapModel.TERRAIN_LABELS.get(
		play.model.terrain_at(tile.x, tile.y), ""
	))
	var resource: int = play.model.resource_at(tile.x, tile.y)
	if resource < 0 or not ImprovementCatalog.known(resource):
		return terrain
	if level < VisibilityModel.Level.FULLY_VISIBLE:
		return terrain
	if (
		ImprovementCatalog.needs_prospecting(resource)
		and (
			play.land_works == null
			or not play.land_works.is_prospected(play.player_faction, play.model, tile)
		)
	):
		return terrain
	var commodity: String = ImprovementCatalog.commodity(resource)
	if commodity.is_empty():
		return terrain
	if terrain.is_empty():
		return ImprovementCatalog.commodity_label(commodity)
	return "%s · %s" % [terrain, ImprovementCatalog.commodity_label(commodity)]


## The crown's own seat on this coast: the province's town site (its seat on a
## chart that predates town assignment), when the squadron is docked there and
## that ground is one this crew kind may take. A crown that only wants the crew
## ashore at home reads one press instead of the coast's whole list (wiki:
## civilian-units § Landing).
static func _seat(
	play: PlaySession, fleet: FleetState, province: int, tiles: Array[Vector2i]
) -> Dictionary:
	if not fleet.is_in_port() or province != fleet.province:
		return {}
	var data: ProvinceState = play.model.province_data(province)
	if data == null:
		return {}
	var seat: Vector2i = data.town_site()
	if seat.x < 0 or not tiles.has(seat):
		return {}
	return {"x": seat.x, "y": seat.y, "ground": _ground_label(play, seat)}


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
