class_name MapPlaySetup
extends RefCounted
## Screen setup that is not map rules: initial HUD values, region chips, capital
## framing, the opening frame and the post-load refresh (REQ-P3-01, REQ-P3-02).


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


static func build_hud(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	HudChrome.set_nation(hud, FactionCatalog.name_of(play.player_faction))
	HudChrome.set_region_label(
		hud, FactionCatalog.region_label(play.region_index), play.world.region_count() > 1
	)
	hud.set_minimap(
		play.model, MapGeo.world_size(play.model, PlaySession.TILE_SIZE), play.visibility
	)
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	if hud.civilian_roster != null:
		hud.civilian_roster.bind(play)
	play.economy = EconomyController.new()
	play.host.add_child(play.economy)
	play.economy.setup(
		play.model, play.player_faction, play.capital_province, play.ship_layer,
		play.army_layer, hud, play.land_works, play.capital_tile
	)
	# Colonial yield ships home from every region, so the controller reads the
	# whole works table (the world already reaches it through the ship layer).
	play.economy.works_by_region = play.civilian_layer.works_regions
	hud.set_treasury(play.treasury(), false)
	play.income = play.economy.projected_income()
	hud.set_income(play.income)
	MapPlayFocus.bind(play)
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)
	build_lens(play)


## Survey lens data follows the region on screen and the works just completed.
## Rebuilding also refreshes the extraction caps the plaque totals use.
static func build_lens(play: PlaySession) -> void:
	var lens: ResourceLens = play.lens
	if lens == null:
		build_diplomacy_lens(play)
		return
	lens.build(
		play.model, play.land_works, play.civilian_layer.units, play.player_faction,
		play.visibility, play.capital_tile, play.tech_caps()
	)
	lens.watch(play.civilian_layer, play.overlay)
	build_diplomacy_lens(play)


## Political wash follows the region, the fog and every court that moved. The
## snapshot is cheap (pure projection), but it still runs on events only.
static func build_diplomacy_lens(play: PlaySession) -> void:
	var lens: DiplomacyLens = play.diplomacy_lens
	if lens == null:
		return
	lens.build(play.model, play.diplomacy, play.player_faction, play.visibility)
	lens.watch(play.overlay)


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
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)


## After a load the economy, court and chips must read the restored state, not
## the starting values used while the screen was assembling.
static func refresh_after_load(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_treasury(play.treasury(), false)
	refresh_region_hud(play, MapGeo.world_size(play.model, PlaySession.TILE_SIZE))
	build_lens(play)
	MapPlayDiplomacy.refresh(play)
	# A call to arms waiting in the save keeps the turn suspended, with the court
	# open for the answer (wiki: diplomacy § Alliances § Mutual defence).
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		play.turn_suspended = true
		MapPlayDiplomacy.show_call(play)
	elif Intervention.has_pending(play.diplomacy, play.player_faction):
		play.turn_suspended = true
		MapPlayDiplomacy.show_intervention(play)
	elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		play.turn_suspended = true
		MapPlayDiplomacy.show_offer(play)
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
static func intro(play: PlaySession, fade: ColorRect, brief: bool = true) -> void:
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
			play.hud, play.model, play.capital_province, play.player_faction
		)
	if fade == null:
		return
	var tween: Tween = play.host.create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


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
