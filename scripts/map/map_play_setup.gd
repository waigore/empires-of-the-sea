class_name MapPlaySetup
extends RefCounted
## Screen setup that is not map rules: initial HUD values, region chips, capital
## framing, the opening frame and the post-load refresh (REQ-P3-01, REQ-P3-02).
## The chart's readings are MapPlayLens' to mount and raise; this boot never
## builds a lens.


static func find_capital(play: PlaySession) -> int:
	return play.world.seat_province(play.region_index, play.player_faction)


## Centres the camera on the ruler's seat; the map screen and the intro share it.
static func focus_capital(play: PlaySession) -> void:
	play.camera.focus_on(capital_world(play), 0.7)


## World position of the ruler's seat: the capital tile from the capital-choice
## phase, falling back to the province centre when the map has no capital.
static func capital_world(play: PlaySession) -> Vector2:
	if play.capital_tile.x >= 0:
		return MapGeo.tile_center(play.capital_tile.x, play.capital_tile.y, PlaySession.TILE_SIZE)
	if play.capital_province >= 0:
		return play.model.province_center(play.capital_province) * PlaySession.TILE_SIZE
	return MapGeo.world_size(play.model, PlaySession.TILE_SIZE) * 0.5


## Builds the HUD against a region `load_region` has just painted: the chips,
## minimap and chart readings are already there (`refresh_region_hud`), so this
## creates the economy and fills the values the region load could not know
## (turn, treasury, income, improvements, dossier, lens wiring).
static func build_hud(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	HudChrome.set_nation(hud, FactionCatalog.name_of(play.player_faction))
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	# The Gazette's cartouche seal reopens the crown's news and its archive at
	# any time (wiki: the-gazette).
	hud.gazette_pressed.connect(func() -> void: MapPlayGazette.open_archive(play))
	# The cartouche's estates door opens the works ledger from anywhere on the
	# map: no chrome of its own sits over the chart (REQ-P1-07).
	hud.estates_pressed.connect(func() -> void:
		if play.improvements != null:
			play.improvements.open()
	)
	# The crown's whole-empire sheets read the session this screen is playing:
	# one registry binds them all (REQ-P5-01, REQ-P5-03).
	HudLedgerDoors.bind_all(hud, play)
	_seat_commanders(play)
	play.economy = EconomyController.new()
	play.host.add_child(play.economy)
	# Build/work's recruits land on the session's layers when the ledger closes.
	play.economy.play = play
	play.economy.setup(
		play.model, play.player_faction, play.capital_province, play.ship_layer,
		play.army_layer, hud, play.land_works, play.capital_tile,
		String(play.leaders.get(play.player_faction, ""))
	)
	# Colonial yield ships home from every region, so the controller reads the
	# whole works table (the world already reaches it through the ship layer).
	play.economy.works_by_region = play.civilian_layer.works_regions
	# A blockade severs the harvest, so the ledger prices it against the court's
	# own sealed ports (wiki: capital-and-connectivity § Blockade). The estates
	# ledger and its rows read the same seals, so a sealed colony's row is the
	# yield the Extraction phase pays, never a second sum (REQ-P2-03).
	play.economy.blockade_source = func() -> Blockades: return MapPlayBlockades.crown(play)
	play.improvements.blockade_source = (
		func() -> Blockades: return MapPlayBlockades.crown(play)
	)
	hud.set_treasury(play.treasury(), false)
	play.income = play.economy.projected_income()
	hud.set_income(play.income)
	MapPlayFocus.bind(play)
	play.improvements.play = play
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)
	refresh_dossier(play)
	# One seal now: the click walks the readings and the menu names one, so the
	# screen keeps a single path for all four lenses (REQ-P5-03).
	hud.lens_cycle_pressed.connect(func() -> void: MapPlayInput.cycle_lens(play))
	hud.lens_selected.connect(func(kind: String) -> void: MapPlayInput.select_lens(play, kind))


## Seats every Great Power's opening commanders before any reading touches the
## pool: the wiki's cap is a state, not a goal, so THE CROWN'S COMMAND must not
## open on "0 of 1 commander" with the commander's own row missing (wiki:
## military-generals § Count and tech-gated cap; REQ-P2-03). Spawn-only, so a
## loaded save keeps the roster it carried.
static func _seat_commanders(play: PlaySession) -> void:
	if play == null or play.army_layer == null:
		return
	play.army_layer.generals.seat_great_powers()


## The province dossier reads the same live tables as the estates ledger: the
## works, the civilians and the researched tech that gates the town order.
static func refresh_dossier(play: PlaySession) -> void:
	if play.hud == null or play.model == null or play.land_works == null:
		return
	play.hud.panels.panel.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.visibility,
		play.capital_tile, play.player_faction, play.tech_caps(),
		play.tech_unlocked(), play.stockpile(), MapPlayBlockades.crown(play)
	)


## Chips and the estates ledger follow the region on screen.
static func refresh_region_hud(play: PlaySession, map_size: Vector2) -> void:
	var hud: GameHud = play.hud
	hud.set_minimap(play.model, map_size, play.visibility)
	HudChrome.set_region_label(
		hud, FactionCatalog.region_label(play.region_index), play.world.region_count() > 1
	)
	hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	if play.economy == null:
		return
	play.refresh_research()
	play.income = play.economy.projected_income()
	hud.set_income(play.income)
	play.improvements.play = play
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)
	refresh_dossier(play)


## After a load the economy, court and chips must read the restored state, not
## the starting values used while the screen was assembling.
static func refresh_after_load(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_treasury(play.treasury(), false)
	refresh_region_hud(play, MapGeo.world_size(play.model, PlaySession.TILE_SIZE))
	MapPlayLens.mount_all(play)
	MapPlayDiplomacy.refresh(play)
	# A save written before the home-fleet merge could park two squadrons at the
	# seat; fold them in before the court reads its squadrons.
	MapPlayHomeMerge.repair(play)
	# A decision waiting in the save keeps the turn suspended, with the court
	# open for the answer (wiki: diplomacy § Alliances § Mutual defence).
	MapPlayDiplomacyConsent.hold_turn(play, play.player_faction)
	# A slot saved after the human crown fell re-mounts the defeat plate; the
	# defeat variant wins over military and calendar endings (wiki: victory
	# § Victory Screen, campaign-persistence § Load and resume).
	if play.defeat != null:
		play.hud.show_defeat(play.defeat, play.player_faction)
	elif play.victory != null:
		play.hud.show_victory(
			play.victory,
			play.player_faction,
			VictoryRules.old_world_holdings(play.world, play.victory.winner_player_id)
		)
	elif play.campaign_halted:
		play.hud.show_campaign_complete(
			MapPlayCampaign.declared_leader(play), play.turn, play.player_faction
		)


## Opening frame: wide then settle on the capital; the parchment fades away.
## The plate is lifted first: the framing below is the only other work the
## opening needs, and a fault in it must never leave the parchment up for good
## (issue #886 — that is a blank parchment with only MENU above it).
static func intro(play: PlaySession, fade: OpeningPlate, brief: bool = true) -> void:
	if fade != null:
		fade.lift()
	var camera: MapCamera = play.camera
	var map_size: Vector2 = MapGeo.world_size(play.model, PlaySession.TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(
		capital_world(play), maxf(start_zoom * 1.65, 0.75)
	)
	if brief:
		RegionBriefing.opening(
			play.hud, play.model, play.capital_province, play.player_faction,
			play.turn
		)


## One fog model per region, kept across map switches: switching back must not
## re-reveal or re-fog what the crown already charted (wiki: fog-and-exploration).
static func build_visibility(play: PlaySession) -> void:
	if play.visibility_by_region.has(play.region_index):
		play.visibility = play.visibility_by_region[play.region_index]
		play.overlay.sync_visibility(play.visibility)
		return
	play.visibility = VisibilityModel.new()
	play.visibility.setup(play.model, play.player_faction)
	play.visibility.apply_initial()
	play.visibility_by_region[play.region_index] = play.visibility
	play.overlay.sync_visibility(play.visibility)


## Setup post-pass per region: capital ports and harbour roads become real
## LandWorks entries, and Great Powers receive their guaranteed grain farms.
## Runs once per region, before civilians muster and before the economy reads it.
static func bootstrap_region(play: PlaySession) -> void:
	if play.bootstrapped_regions.has(play.region_index):
		return
	WorldBootstrap.apply(play.model, play.civilian_layer.works)
	play.bootstrapped_regions[play.region_index] = true
