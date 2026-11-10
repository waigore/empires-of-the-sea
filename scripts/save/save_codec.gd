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
		"regions": SaveWorld.capture(play.world),
		"visibility": SaveWorld.capture_visibility(play),
		"economy": _capture_economy(play),
		"market": play.economy.market.to_dict() if play.economy != null else {},
		"diplomacy": SaveCourt.capture_diplomacy(play.diplomacy),
		"ai": play.ai.to_dict() if play.ai != null else {},
		"victory": SaveCourt.capture_victory(play.victory),
		"defeat": SaveDefeat.capture(play.defeat),
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
		"income": play.income,
		"capital_province": play.capital_province,
		"capital_tile": play.capital_tile,
		"feeding": play.feeding.duplicate(),
		"charted": play.charted_provinces.keys(),
		"bootstrapped": play.bootstrapped_regions.keys(),
		"leaders": play.leaders.duplicate(),
		"infinite_mode": play.infinite_mode,
		"advanced_start": play.advanced_start,
		"difficulty": play.difficulty,
		"campaign_halted": play.campaign_halted,
	}


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
##
## `reuse` lets a caller hand over an already generated world (a MapScreen
## preset) so a load does not regenerate it. Generation is the single most
## expensive step under coverage; the saved ownership, resources and deeds are
## still applied on top. The world is only reused when its region sizes match
## the save; seed identity cannot be checked (WorldMap stores no seed), so
## callers must pass a world generated for the save's seed — tests pass their
## shared fixture.
static func restore(play: PlaySession, data: Dictionary, reuse: WorldMap = null) -> bool:
	if play == null or not is_valid(data):
		return false
	var session: Dictionary = data.get("session", {})
	play.player_faction = _faction(session)
	play.map_seed = int(session.get("map_seed", 1500))
	play.map_width = int(session.get("map_width", 128))
	play.map_height = int(session.get("map_height", 84))
	play.turn = maxi(int(session.get("turn", 1)), 1)
	play.income = int(session.get("income", 0))
	play.capital_province = int(session.get("capital_province", -1))
	play.capital_tile = _vector(session.get("capital_tile", CapitalChoice.NO_TILE))
	play.feeding = _fraction_dictionary(session.get("feeding", {}))
	play.charted_provinces = _flag_dictionary(session.get("charted", []))
	play.bootstrapped_regions = _flag_dictionary(session.get("bootstrapped", []))
	play.leaders = LeaderCatalog.from_saved(session.get("leaders", {}))
	play.infinite_mode = bool(session.get("infinite_mode", false))
	play.advanced_start = AdvancedStart.normalize(
		String(session.get("advanced_start", AdvancedStart.NONE))
	)
	play.difficulty = Difficulty.normalize(
		String(session.get("difficulty", Difficulty.DEFAULT))
	)
	play.campaign_halted = bool(session.get("campaign_halted", false))
	# A decided campaign must come back decided or the load would reopen sealed turns.
	play.victory = SaveCourt.victory_from(data.get("victory", {}))
	play.defeat = SaveDefeat.from_dict(data.get("defeat", {}), play.player_faction)

	var world: WorldMap = SaveWorld.reusable(reuse, play.map_width, play.map_height)
	if world == null:
		world = MapGenerator.new().generate_world(
			play.map_seed, play.map_width, play.map_height
		)
	if not SaveWorld.apply(world, data.get("regions", [])):
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
	SaveWorld.restore_visibility(play, data.get("visibility", {}))
	return true


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
	SaveCourt.restore_diplomacy(play, data)


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
