extends RefCounted
## Shared small maps for integration suites. Cached once per Godot worker so
## coverage runs do not regenerate a world per test method (gd-tools clones a
## fresh suite instance each time; underscore fields are not copied from
## before_all).

const SEED: int = 1500
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
## Single-region generator / canvas fixtures.
const WIDTH: int = 48
const HEIGHT: int = 32
## Two-region world used by MapScreen integration + world setup. The province
## target clamps to its 24/20 floor long before this size, so it keeps the same
## rosters (60 Old World / 30 New World provinces, 8 sea zones and passages, 6
## crowned capitals) while painting far fewer tiles per mounted screen. Two
## floors hold it here: sides stay at or above `SaveCodec.MIN_MAP_SIDE` (32) or
## a slot written from this world would not validate, and a crown needs ~16 free
## land tiles for the turn-100 advanced-start civilians (44x34 leaves the
## tightest crown 32).
##
## The height is 34, not 32, because `generate_world` regenerates with a bumped
## seed while a region fails `unfair_split` (wiki: game-setup § Tribe assignment
## regen-until-pass) and this seed's Old World splits unfairly two rows short.
## A world that passes on its first attempt costs a suite one generation instead
## of two (~2.7 s → ~1.1 s per worker before coverage instrumentation), paid by
## ~30 mounted suites. Re-probe before shrinking this again.
const WORLD_WIDTH: int = 44
const WORLD_HEIGHT: int = 34

static var _world: WorldMap = null
static var _region: MapModel = null


static func world() -> WorldMap:
	if _world == null:
		_world = MapGenerator.new().generate_world(SEED, WORLD_WIDTH, WORLD_HEIGHT)
	return _world


static func region() -> MapModel:
	if _region == null:
		_region = MapGenerator.new().generate(SEED, WIDTH, HEIGHT)
	return _region


static func inland_province(model: MapModel) -> int:
	for province: ProvinceState in model.provinces:
		if not province.coastal and province.area > 30:
			return province.id
	return int(model.provinces[0].id)


static func foreign_province(model: MapModel) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			return province.id
	return MapModel.NO_ID


static func owned_resource_tile(model: MapModel, works: LandWorks) -> Vector2i:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) < 0:
				continue
			if works.improvement_at(model, tile) > 0:
				continue
			return tile
	return Vector2i(-1, -1)


static func coastal_land_of(model: MapModel, zone_id: int) -> Vector2i:
	for tile: Vector2i in model.sea_zone_data(zone_id).tiles:
		for offset: Vector2i in CivilianMovement.NEIGHBORS:
			var nx: int = tile.x + offset.x
			var ny: int = tile.y + offset.y
			if model.is_land(nx, ny):
				return Vector2i(nx, ny)
	return Vector2i(-1, -1)


static func fleet_at_sea(fleets: Array, owner: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet.owner == owner and fleet.is_at_sea():
			return fleet
	return null


## Answers any rival proposal so a suite that only asserts the turn's outcome
## is not held by the court gate (wiki: diplomacy § Court proposals).
static func settle(play: PlaySession) -> void:
	while DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapCourtOrders.apply(
			play, DiplomacyProposals.KIND_REFUSE, play.player_faction, ""
		)


## Ownership, seats and tile deeds of the shared world as it was generated.
## Suites that hand provinces to a crown or buy deeds call this once, then
## `restore(world, snapshot)` in `before_each`/`after_each`, so the shared map
## stays a fresh world without paying for generation per case.
static func snapshot(world: WorldMap) -> Array:
	var rows: Array = []
	for region: MapModel in world.regions:
		rows.append(region.ownership.to_dict())
		var provinces: Array = []
		for province: ProvinceState in region.provinces:
			provinces.append([province, province.owner, province.capital])
		rows.append(provinces)
	return rows


static func restore(world: WorldMap, snapshot: Array) -> void:
	if world == null or snapshot.is_empty():
		return
	for index in world.region_count():
		var region: MapModel = world.region(index)
		region.ownership.apply_dict(snapshot[index * 2])
		for row: Array in snapshot[index * 2 + 1]:
			var province: ProvinceState = row[0]
			province.owner = int(row[1])
			province.capital = bool(row[2])


## --- one mount per suite -------------------------------------------------------
## Coverage charges ~0.5 s to mount MapScreen and ~0.15 s to re-seat the same
## screen from a pristine save, so a suite whose cases only need a fresh session
## should share one mount. `test_save_codec` proved the in-place load path; the
## helpers below keep that path in one place:
##   before_all:  screen = attach_screen(self); pristine = suite_capture(screen)
##   before_each: restore(world(), saved); suite_reset(screen, pristine)
##   after_all:   screen.free()
## The screen's own node state (selection, sheets, lenses, news) is dropped by the
## reset; anything a case leaves on a node that is not re-read here must be
## cleared by the suite itself.

## The suite's opening state, captured once from the mounted screen.
static func suite_capture(screen: MapScreen) -> Dictionary:
	if screen == null or screen.play == null:
		return {}
	return SaveCodec.capture(screen.play)


## Re-seats a shared screen on its pristine save without remounting it. Applies
## the same in-place load path the pause menu's load uses, then re-reads the
## layers, HUD and lenses a case may have moved.
static func suite_reset(
	screen: MapScreen, pristine: Dictionary, world: WorldMap = null
) -> void:
	if screen == null or not is_instance_valid(screen) or pristine.is_empty():
		return
	var play: PlaySession = screen.play
	if play == null:
		return
	# The view's chart is the session's until the save rewrites it.
	var shown: int = play.region_index
	_reset_view(screen)
	if world == null:
		world = play.world
	# A restore hands the session the arrays it reads (a fog grid is assigned,
	# not copied), so a case that charts a tile would edit the pristine save and
	# every later case would start from that chart. Reset from a copy.
	var data: Dictionary = pristine.duplicate(true)
	if not SaveCodec.restore(play, data, world):
		return
	# Economy always founds on the Old World; restore there, then return.
	var target: int = play.region_index
	play.region_index = 0
	play.model = play.world.region(0)
	SaveCodec.restore_economy(play, data)
	play.diplomacy = DiplomacyState.new()
	# A pristine save taken before any AI turn carries no ledgers, and a restore
	# leaves the live ones alone; drop them so the case starts where the mount
	# did, with rivals founded only when a turn first needs them.
	play.ai = null
	SaveCodec.restore_diplomacy(play, data)
	play.diplomacy.human_faction = play.human_faction_id()
	play.turn_suspended = false
	if shown != target:
		# A case left the view on the other chart: only a swap repaints, and it
		# rebuilds every layer on the way, so the cheap path below is skipped.
		screen.load_region(target)
		MapPlaySetup.refresh_after_load(play)
		return
	play.region_index = target
	play.model = play.world.region(target)
	_rebind_layers(screen, play)
	# The chart the view stands on was not rebuilt, so its fog and markers are
	# re-read from the restored fog tables rather than repainted.
	MapPlaySetup.build_visibility(play)
	screen.overlay.snap_fog()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)
	MapPlaySetup.refresh_after_load(play)


## Clears the view state a previous case may have left: a selected marker would
## otherwise keep an order highlight alive, an open sheet would answer for a case
## that expects a bare chart, and a full news lane would queue the next case's
## toast instead of raising it.
static func _reset_view(screen: MapScreen) -> void:
	if screen.ship_layer != null:
		screen.ship_layer.deselect()
	if screen.army_layer != null:
		screen.army_layer.deselect()
	if screen.civilian_layer != null:
		screen.civilian_layer.deselect()
	if screen.overlay != null:
		screen.overlay.move_zones = []
		screen.overlay.move_provinces = []
	if screen.hud != null and screen.hud.panels != null:
		screen.hud.panels.close_sheets()
		DiplomacyHud.hide(screen.hud.panels)
	if screen.hud != null:
		# The ledger sheets and the court dossier are not dock panels; one left
		# open would answer for a case that expects a bare chart.
		_close_sheet(screen.hud.civilian_roster)
		_close_sheet(screen.hud.muster_roll)
		_close_sheet(screen.hud.dossier_screen)
	if screen.game_menu != null and screen.game_menu.is_open():
		screen.game_menu.close()
	if screen.hud != null and screen.hud.gazette_plate != null:
		if screen.hud.gazette_plate.is_shown():
			screen.hud.gazette_plate.dismiss()
	if screen.improvements != null and screen.improvements.is_open():
		screen.improvements.close()
	if screen.hud != null:
		_reset_ledger_filters(screen.hud)
		# A hover line from the last case would answer for a case that expects a
		# bare cursor.
		if screen.hud._tooltip_label != null:
			screen.hud._tooltip_label.text = ""
	_lower_lenses(screen.play)
	_clear_news(screen.hud)


static func _close_sheet(sheet: SheetFrame) -> void:
	if sheet != null and sheet.is_open():
		sheet.close()


## Every reading a case may have raised, lowered in turn: the map opens on the
## bare chart, as a mount did (`test_map_view_rules` lowers them the same way).
static func _lower_lenses(play: PlaySession) -> void:
	if play == null:
		return
	if play.lens != null and play.lens.active:
		MapPlayInput.set_lens(play, false)
	if play.diplomacy_lens != null and play.diplomacy_lens.active:
		MapPlayInput.set_diplomacy_lens(play, false)
	if play.crown_lens != null and play.crown_lens.active:
		MapPlayInput.set_crown_lens(play, false)
	if play.defence_lens != null and play.defence_lens.active:
		MapPlayInput.set_defence_lens(play, false)


## The market ledger keeps the court's chips between repaints, so a filter a
## case set would hide the next case's book under it. A remount used to hand
## back the unfiltered page; reset the chips instead.
static func _reset_ledger_filters(hud: GameHud) -> void:
	if hud._economy_panel == null:
		return
	var market: LedgerMarket = hud._economy_panel.page_body(
		EconomyPanel.TAB_MARKET
	) as LedgerMarket
	if market == null:
		return
	market._seller_filter = MarketOffersHead.ALL_SELLERS
	market._good_filter = MarketOffersHead.ALL_GOODS
	market._offer_sort = MarketOffersHead.SORT_SELLER


## Drops any plate covering the lane and the news queued behind it, so a case
## reads only the news its own turn raised. The panels already up finish their
## own fade and free themselves — freeing them here would pull the tween out
## from under its own callback — so their lines are blanked instead.
static func _clear_news(hud: GameHud) -> void:
	if hud == null or hud.despatches == null:
		return
	var news: HudDespatches = hud.despatches
	news._covered = false
	news._live = 0
	news._compact_queue.clear()
	news._queue = PackedStringArray()
	news._queue_narrated.clear()
	for panel: Node in news.box.get_children():
		for label: Label in panel.find_children("*", "Label", true, false):
			label.text = ""


## Restore parks units in region tables and clears the live arrays; spawn rebinds
## the markers without rebuilding the canvas (`load_region` would repaint).
static func _rebind_layers(screen: MapScreen, play: PlaySession) -> void:
	var model: MapModel = play.model
	screen.army_layer.spawn(model)
	screen.ship_layer.world = play.world
	screen.ship_layer.spawn(
		model,
		MapScreen.SHIP_COUNT,
		MapScreen.MAP_SEED + 3 + play.region_index,
		play.capital_province,
		play.player_present(),
		play.player_faction
	)
	screen.civilian_layer.viewer_faction = play.player_faction
	screen.civilian_layer.spawn(
		model, play.capital_province, play.player_faction, MapScreen.STARTING_CIVILIANS
	)
	play.land_works = screen.civilian_layer.works


static func mouse_button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


static func mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(400, 300)
	return event


static func attach_screen(
	host: Node,
	faction: int = FactionCatalog.PLAYER_FACTION,
	leader: String = ""
) -> MapScreen:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.player_faction = faction
	screen.player_leader = leader
	screen.preset_world = world()
	host.add_child(screen)
	return screen


## Reopens a saved session on the shared world. The preset is what keeps a
## reload from regenerating the map — SaveCodec applies the save's ownership,
## resources and deeds on top of the same world it would have generated.
static func open_save(host: Node, data: Dictionary, save_dir: String = "") -> MapScreen:
	var screen: MapScreen = SCENE.instantiate()
	screen.map_width = WORLD_WIDTH
	screen.map_height = WORLD_HEIGHT
	screen.save_dir = save_dir
	screen.preset_world = world()
	screen.pending_save = data
	host.add_child(screen)
	return screen
