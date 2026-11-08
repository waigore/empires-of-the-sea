class_name SaveCodec
extends RefCounted
## Converts a live PlaySession to plain built-in data and back (REQ-P3-03).
## Saves rebuild the deterministic world from its seed and then lay the mutable
## state on top, so a load never keeps a reference to the previous game.

## Bump when the on-disk shape changes incompatibly.
const VERSION: int = 1

const MAX_MAP_SIDE: int = 512
const MIN_MAP_SIDE: int = 32

# --- capture -----------------------------------------------------------------


static func capture(play: PlaySession) -> Dictionary:
	if play == null or play.world == null:
		return {}
	return {
		"version": VERSION,
		"game_version": GameVersion.as_string(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"session": _capture_session(play),
		"regions": _capture_regions(play.world),
		"visibility": _capture_visibility(play),
		"economy": _capture_economy(play),
		"market": play.economy.market.to_dict() if play.economy != null else {},
		"diplomacy": _capture_diplomacy(play.diplomacy),
		"ai": play.ai.to_dict() if play.ai != null else {},
		"civilians": SaveLayers.capture_civilians(play.civilian_layer),
		"fleets": SaveLayers.capture_fleets(play.ship_layer),
		"armies": SaveLayers.capture_armies(play.army_layer),
		"generals": play.army_layer.generals.to_dict() if play.army_layer != null else {},
	}


static func _capture_session(play: PlaySession) -> Dictionary:
	return {
		"map_seed": play.map_seed,
		"map_width": play.map_width,
		"map_height": play.map_height,
		"player_faction": play.player_faction,
		"region_index": play.region_index,
		"turn": play.turn,
		"prestige": play.prestige,
		"income": play.income,
		"capital_province": play.capital_province,
		"capital_tile": play.capital_tile,
		"feeding": play.feeding.duplicate(),
		"charted": play.charted_provinces.keys(),
		"bootstrapped": play.bootstrapped_regions.keys(),
	}


static func _capture_regions(world: WorldMap) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for model: MapModel in world.regions:
		var provinces: Array[Dictionary] = []
		for province: ProvinceState in model.provinces:
			var province_entry: Dictionary = {
				"id": province.id,
				"owner": province.owner,
				"capital": province.capital,
				"town_development": province.town_development,
				"resource": province.resource,
				"resource_tile": province.resource_tile,
				"population": province.population,
				"road_paths": province.road_paths.duplicate(true),
			}
			provinces.append(province_entry)
		var region_entry: Dictionary = {
			"width": model.width,
			"height": model.height,
			"provinces": provinces,
			"resources": model.resource.duplicate(),
		}
		regions.append(region_entry)
	return regions


static func _capture_visibility(play: PlaySession) -> Dictionary:
	var by_region: Dictionary = {}
	for raw: Variant in play.visibility_by_region.keys():
		var visibility: VisibilityModel = play.visibility_by_region[raw]
		if visibility != null:
			by_region[int(raw)] = visibility.to_dict()
	return {"by_region": by_region}


static func _capture_economy(play: PlaySession) -> Dictionary:
	if play.economy == null or play.economy.economy == null:
		return {}
	return play.economy.economy.snapshot()


# --- validation --------------------------------------------------------------


static func is_valid(data: Dictionary) -> bool:
	if data.is_empty() or int(data.get("version", -1)) != VERSION:
		return false
	var session: Variant = data.get("session", {})
	if typeof(session) != TYPE_DICTIONARY:
		return false
	var width: int = int(session.get("map_width", 0))
	var height: int = int(session.get("map_height", 0))
	if width < MIN_MAP_SIDE or height < MIN_MAP_SIDE:
		return false
	if width > MAX_MAP_SIDE or height > MAX_MAP_SIDE:
		return false
	var regions: Variant = data.get("regions", [])
	if typeof(regions) != TYPE_ARRAY or regions.is_empty():
		return false
	return FactionCatalog.can_win(int(session.get("player_faction", -1)))


## Short slot description for the save browser.
static func summary(data: Dictionary) -> Dictionary:
	var session: Dictionary = data.get("session", {})
	var faction: int = int(session.get("player_faction", FactionCatalog.PLAYER_FACTION))
	return {
		"turn": int(session.get("turn", 1)),
		"nation": FactionCatalog.name_of(faction),
		"seed": int(session.get("map_seed", 0)),
		"region": FactionCatalog.region_label(int(session.get("region_index", 0))),
		"saved_at": String(data.get("saved_at", "")),
	}


# --- restore -----------------------------------------------------------------


## Rebuilds the world and the session's mutable state before the screen loads
## its first region. The caller then builds the HUD and calls the two economy
## and diplomacy restorers (they need the freshly created nodes).
static func restore(play: PlaySession, data: Dictionary) -> bool:
	if play == null or not is_valid(data):
		return false
	var session: Dictionary = data.get("session", {})
	play.player_faction = _faction(session)
	play.map_seed = int(session.get("map_seed", 1500))
	play.map_width = int(session.get("map_width", 128))
	play.map_height = int(session.get("map_height", 84))
	play.turn = maxi(int(session.get("turn", 1)), 1)
	play.prestige = int(session.get("prestige", 0))
	play.income = int(session.get("income", 0))
	play.capital_province = int(session.get("capital_province", -1))
	play.capital_tile = _vector(session.get("capital_tile", CapitalChoice.NO_TILE))
	play.feeding = _fraction_dictionary(session.get("feeding", {}))
	play.charted_provinces = _flag_dictionary(session.get("charted", []))
	play.bootstrapped_regions = _flag_dictionary(session.get("bootstrapped", []))

	var world: WorldMap = MapGenerator.new().generate_world(
		play.map_seed, play.map_width, play.map_height
	)
	if not _apply_regions(world, data.get("regions", [])):
		return false
	play.world = world
	play.region_index = clampi(int(session.get("region_index", 0)), 0, world.region_count() - 1)

	SaveLayers.restore_civilians(play.civilian_layer, data.get("civilians", {}))
	SaveLayers.restore_fleets(play.ship_layer, data.get("fleets", {}))
	SaveLayers.restore_armies(play.army_layer, data.get("armies", {}))
	if play.army_layer != null:
		play.army_layer.generals = GeneralRoster.from_dict(
			_dictionary(data.get("generals", {}))
		)
	_restore_visibility(play, data.get("visibility", {}))
	return true


static func _apply_regions(world: WorldMap, regions: Variant) -> bool:
	if typeof(regions) != TYPE_ARRAY or regions.size() != world.region_count():
		return false
	for index in world.region_count():
		var entry: Variant = regions[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var model: MapModel = world.region(index)
		var data: Dictionary = entry
		if int(data.get("width", 0)) != model.width or int(data.get("height", 0)) != model.height:
			return false
		var provinces: Array = data.get("provinces", [])
		if provinces.size() != model.provinces.size():
			return false
		for raw: Variant in provinces:
			if typeof(raw) != TYPE_DICTIONARY:
				return false
			if not _apply_province(model, raw):
				return false
		if not _apply_resources(model, data.get("resources", PackedInt32Array())):
			return false
	return true


static func _apply_province(model: MapModel, data: Dictionary) -> bool:
	var province: ProvinceState = model.get_province(int(data.get("id", -1)))
	if province == null:
		return false
	province.owner = int(data.get("owner", MapModel.NO_ID))
	province.capital = bool(data.get("capital", false))
	province.town_development = int(data.get("town_development", 0))
	province.resource = int(data.get("resource", MapModel.NO_ID))
	province.resource_tile = _vector(data.get("resource_tile", Vector2i(-1, -1)))
	province.population = int(data.get("population", 0))
	var paths: Variant = data.get("road_paths", [])
	if typeof(paths) != TYPE_ARRAY:
		return false
	province.road_paths = paths.duplicate(true)
	return true


static func _apply_resources(model: MapModel, raw: Variant) -> bool:
	var wanted: int = model.width * model.height
	if typeof(raw) == TYPE_PACKED_INT32_ARRAY:
		var packed: PackedInt32Array = raw
		if packed.size() != wanted:
			return false
		model.resource = packed
		return true
	if typeof(raw) != TYPE_ARRAY or raw.size() != wanted:
		return false
	for index in wanted:
		model.resource[index] = int(raw[index])
	return true


static func _restore_visibility(play: PlaySession, data: Variant) -> void:
	play.visibility_by_region.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var by_region: Dictionary = data.get("by_region", {})
	for raw: Variant in by_region.keys():
		var region: int = int(raw)
		var model: MapModel = play.world.region(region)
		var entry: Variant = by_region[raw]
		if model == null or typeof(entry) != TYPE_DICTIONARY:
			continue
		var visibility := VisibilityModel.new()
		visibility.setup(model, play.player_faction)
		if visibility.apply_dict(entry):
			play.visibility_by_region[region] = visibility


## The economy node exists only after the HUD is built.
static func restore_economy(play: PlaySession, data: Dictionary) -> void:
	if play == null or play.economy == null:
		return
	var snapshot: Variant = data.get("economy", {})
	if typeof(snapshot) == TYPE_DICTIONARY and not snapshot.is_empty():
		play.economy.economy.apply_snapshot(snapshot)
	var market: Variant = data.get("market", {})
	if typeof(market) == TYPE_DICTIONARY and not market.is_empty():
		play.economy.market = WorldMarket.from_dict(market)
	# Legacy saves carried no general pools; rebuild the court from the persisted
	# tech floors rather than leaving it without commanders (wiki:
	# military-generals § Persistence and load reconciliation).
	if play.army_layer != null and play.economy.economy != null:
		play.army_layer.sync_generals(play.player_faction, play.economy.economy.tech_unlocked)


static func restore_diplomacy(play: PlaySession, data: Dictionary) -> void:
	var snapshot: Variant = data.get("diplomacy", {})
	if typeof(snapshot) == TYPE_DICTIONARY and not snapshot.is_empty():
		play.diplomacy = _diplomacy_from(snapshot)
	var ai: Dictionary = _dictionary(data.get("ai", {}))
	if not ai.is_empty():
		play.ai = AiState.from_dict(ai)


# --- diplomacy ---------------------------------------------------------------


static func _capture_diplomacy(state: DiplomacyState) -> Dictionary:
	if state == null:
		return {}
	var records: Dictionary = {}
	for key: String in state.relations.keys():
		var record: DiplomacyRelation = state.relations[key]
		if record != null:
			records[key] = record.to_dict()
	return {
		"turn": state.turn,
		"relations": records,
		"overtures": state.overtures.duplicate(),
		"subsidies": state.subsidies.duplicate(),
		"colonies": state.colonies.duplicate(),
		"events": state.events.duplicate(true),
		"modified": state._modified.duplicate(),
		"order_counts": state._order_counts.duplicate(),
	}


static func _diplomacy_from(data: Dictionary) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.turn = int(data.get("turn", 0))
	var records: Dictionary = data.get("relations", {})
	for key: Variant in records.keys():
		var entry: Variant = records[key]
		if typeof(entry) == TYPE_DICTIONARY:
			state.relations[String(key)] = DiplomacyRelation.from_dict(entry)
	state.overtures = data.get("overtures", {}).duplicate()
	state.subsidies = data.get("subsidies", {}).duplicate()
	state.colonies = data.get("colonies", {}).duplicate()
	state.events.clear()
	for event: Variant in data.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			state.events.append(event.duplicate(true))
	state._modified = data.get("modified", {}).duplicate()
	state._order_counts = data.get("order_counts", {}).duplicate()
	return state


# --- helpers -----------------------------------------------------------------


static func _faction(session: Dictionary) -> int:
	var faction: int = int(session.get("player_faction", FactionCatalog.PLAYER_FACTION))
	return faction if FactionCatalog.can_win(faction) else FactionCatalog.PLAYER_FACTION


static func _flag_dictionary(keys: Variant) -> Dictionary:
	var flags: Dictionary = {}
	if typeof(keys) != TYPE_ARRAY:
		return flags
	var list: Array = keys
	for raw: Variant in list:
		flags[int(raw)] = true
	return flags


## Faction -> fraction, tolerating string keys from an older text save.
static func _fraction_dictionary(raw: Variant) -> Dictionary:
	var values: Dictionary = {}
	var stored: Dictionary = _dictionary(raw)
	for key: Variant in stored.keys():
		var value: Variant = stored[key]
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			values[int(key)] = float(value)
	return values


static func _dictionary(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}


## Accepts the two vector shapes a save may carry (Vector2i or [x, y]).
static func _vector(raw: Variant) -> Vector2i:
	match typeof(raw):
		TYPE_VECTOR2I:
			return Vector2i(raw)
		TYPE_VECTOR2:
			return Vector2i(raw)
		TYPE_ARRAY:
			var pair: Array = raw
			if pair.size() == 2:
				return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i(-1, -1)
