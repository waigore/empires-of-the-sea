class_name MapPlaySetup
extends RefCounted
## Screen setup that is not map rules: initial HUD values, region chips, the
## opening frame and the post-load refresh (REQ-P3-01, REQ-P3-02).


static func find_capital(play: PlaySession) -> int:
	return play.world.seat_province(play.region_index, play.player_faction)


static func build_hud(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	HudChrome.set_nation(hud, FactionCatalog.name_of(play.player_faction))
	HudChrome.set_region_label(hud, FactionCatalog.region_label(play.region_index))
	hud.set_minimap(play.model, MapGeo.world_size(play.model, PlaySession.TILE_SIZE))
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_prestige(play.prestige)
	hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	play.economy = EconomyController.new()
	play.host.add_child(play.economy)
	play.economy.setup(
		play.model, play.player_faction, play.capital_province, play.ship_layer,
		play.army_layer, hud, play.land_works, play.capital_tile
	)
	hud.set_treasury(play.treasury(), false)
	play.income = play.economy.projected_income()
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)


## Chips and the estates ledger follow the region on screen.
static func refresh_region_hud(play: PlaySession, map_size: Vector2) -> void:
	var hud: GameHud = play.hud
	hud.set_minimap(play.model, map_size)
	HudChrome.set_region_label(hud, FactionCatalog.region_label(play.region_index))
	hud.set_fleets(play.ship_layer.hull_count_all(play.player_faction))
	hud.set_civilians(play.civilian_layer.unit_count_all(play.player_faction))
	hud.set_armies(play.army_layer.regiment_count_all(play.player_faction))
	if play.economy == null:
		return
	play.refresh_research()
	play.income = play.economy.projected_income()
	play.improvements.set_data(
		play.model, play.land_works, play.civilian_layer.units, play.stockpile(),
		play.capital_tile, play.player_faction, play.tech_caps()
	)


## After a load the economy, court and chips must read the restored state, not
## the starting values used while the screen was assembling.
static func refresh_after_load(play: PlaySession) -> void:
	var hud: GameHud = play.hud
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_prestige(play.prestige)
	hud.set_treasury(play.treasury(), false)
	refresh_region_hud(play, MapGeo.world_size(play.model, PlaySession.TILE_SIZE))
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
			MapPlayTurn.declared_leader(play), play.turn, play.player_faction
		)


## Opening frame: wide then settle on the capital; the parchment fades away.
static func intro(play: PlaySession, fade: ColorRect, brief: bool = true) -> void:
	var camera: MapCamera = play.camera
	var map_size: Vector2 = MapGeo.world_size(play.model, PlaySession.TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(
		MapPlayTurn.capital_world(play), maxf(start_zoom * 1.65, 0.75)
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
