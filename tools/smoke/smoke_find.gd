extends RefCounted
## The smoke's chart lookups: where the crown's units stand and which tiles a
## work order may start on. Every read goes through the same model the map draws,
## so a lookup never asserts anything — the step that asked prints the assert.
##
## No `class_name`: the steps preload this file (tools/e2e_smoke.gd).


## First civilian of this type the crown owns, anywhere on the chart.
static func civilian_of(screen: MapScreen, type_id: String) -> CivilianState:
	for unit: CivilianState in screen.civilian_layer.units:
		if unit != null and unit.type_id == type_id and unit.owner == MapScreen.PLAYER_FACTION:
			return unit
	return null


## First idle civilian of the crown standing in this province.
static func idle_civilian(screen: MapScreen, province_id: int) -> CivilianState:
	for unit: CivilianState in screen.civilian_layer.units:
		if unit == null or unit.owner != MapScreen.PLAYER_FACTION:
			continue
		if unit.is_embarked() or unit.is_working():
			continue
		if screen.model.province_at(unit.tile.x, unit.tile.y) == province_id:
			return unit
	return null


static func player_ship_at_sea(screen: MapScreen) -> Ship:
	for ship: Ship in screen.ship_layer.ships:
		var fleet: FleetState = screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	return null


static func home_army(screen: MapScreen) -> ArmyState:
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == MapScreen.PLAYER_FACTION and army.is_home_army():
			return army
	return null


static func inland_province(screen: MapScreen) -> int:
	for province: ProvinceState in screen.model.provinces:
		if not province.coastal and province.area > 30:
			return province.id
	if screen.model.provinces.is_empty():
		return -1
	return int(screen.model.provinces[0].id)


static func uncharted_land_tile(screen: MapScreen) -> Vector2i:
	if screen.visibility == null:
		return Vector2i(-1, -1)
	for province: ProvinceState in screen.model.provinces:
		if screen.visibility.is_province_fully_visible(int(province.id)):
			continue
		# Exploring a Minor/Tribe province needs a Consulate (wiki:
		# civilian-units § Work Order Summary, Refs #3753 R4).
		if (
			province.owner != MapScreen.PLAYER_FACTION
			and FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER
		):
			continue
		if province.tiles.is_empty():
			continue
		return province.tiles[0]
	return Vector2i(-1, -1)


static func mineral_tile(screen: MapScreen) -> Vector2i:
	for province: ProvinceState in screen.model.provinces:
		# Explorer work in a Minor/Tribe province needs a Consulate, so the
		# smoke needs a tile the crown may actually work on turn one (wiki:
		# civilian-units § Work Order Summary, Refs #3753 R4).
		if (
			province.owner != MapScreen.PLAYER_FACTION
			and FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER
		):
			continue
		for tile: Vector2i in province.tiles:
			# A survey target: charted prospectable ground this crown has not
			# read yet (wiki: fog-and-exploration § Prospecting;
			# DR-20261111-26).
			if MineralSurvey.can_prospect(
				screen.model, screen.land_works, MapScreen.PLAYER_FACTION, tile,
				screen.visibility
			):
				return tile
	return Vector2i(-1, -1)


static func owned_resource_tile(
	screen: MapScreen, avoid: Vector2i = Vector2i(-1, -1)
) -> Vector2i:
	var fallback: Vector2i = Vector2i(-1, -1)
	for province: ProvinceState in screen.model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if tile == avoid:
				continue
			var resource: int = screen.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if screen.land_works.improvement_at(screen.model, tile) > 0:
				continue
			if not ImprovementCatalog.needs_prospecting(resource):
				return tile
			if fallback.x < 0:
				fallback = tile
	return fallback


static func owned_roadable_tile(screen: MapScreen, avoid: Array[Vector2i]) -> Vector2i:
	for province: ProvinceState in screen.model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if avoid.has(tile):
				continue
			if screen.land_works.transport_at(screen.model, tile) >= LandWorks.TRANSPORT_ROAD:
				continue
			return tile
	return Vector2i(-1, -1)


static func options_has(options: Array[Dictionary], action: String) -> bool:
	for option: Dictionary in options:
		if String(option.get("action", "")) == action:
			return true
	return false


## Runs one world-market clearing pass for the human ledger, as the turn does.
static func clear_market(screen: MapScreen) -> void:
	var cargo: Dictionary = screen.economy.trade_cargo()
	MarketClearing.clear(
		screen.economy.market,
		screen.play.world,
		{screen.player_faction: screen.economy.economy},
		{screen.player_faction: int(cargo.get("clear_free", cargo.get("free", 0)))},
		{"diplomacy": screen.play.diplomacy}
	)


## True when at least one rival court put a tech into a research slot, proving
## the economy adapter wired AiResearchPlanner (DR-20261109-20).
static func rival_research_started(screen: MapScreen) -> bool:
	if screen.play.ai == null:
		return false
	for faction: int in FactionCatalog.great_power_ids():
		if faction == screen.play.player_faction:
			continue
		var rival: PlayerEconomy = screen.play.ai.economy_for(faction)
		for slot in rival.research.slots.size():
			if not rival.research.tech_at(slot).is_empty():
				return true
	return false
