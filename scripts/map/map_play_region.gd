class_name MapPlayRegion
extends RefCounted
## Swaps the whole view onto one region and cycles Old World <-> New World
## (REQ-P3-01, REQ-P3-02). MapScreen keeps the host surface (`load_region`,
## `_cycle_region`, `refresh_political_map`); this owner composes the chart,
## fog, units, works, camera and lenses, so the screen never mounts layers by
## hand.

## The default chart recipe seed. The ship muster offsets it per region, so
## every campaign musters the same squadrons on the same chart recipe.
const MAP_SEED: int = 1500
## Hulls mustered per region at game start.
const SHIP_COUNT: int = 7
const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]


## Mounts one region: canvas, fog, units, works, minimap and camera.
static func mount(play: PlaySession, backdrop: ColorRect, index: int) -> void:
	play.region_index = clampi(index, 0, play.world.region_count() - 1)
	play.model = play.world.region(play.region_index)
	play.civilian_layer.viewer_faction = play.player_faction
	play.ship_layer.world = play.world
	var map_size: Vector2 = MapGeo.world_size(play.model, PlaySession.TILE_SIZE)
	SeaBackdrop.fit(backdrop, map_size)
	play.capital_province = MapPlaySetup.find_capital(play)
	play.capital_tile = play.model.capital_tile_of(play.capital_province)
	# Prepare works first so the post-pass can wire them before units muster.
	if not play.bootstrapped_regions.has(play.region_index):
		play.civilian_layer.spawn(
			play.model, play.capital_province, play.player_faction, STARTING_CIVILIANS, false
		)
		MapPlaySetup.bootstrap_region(play)
	play.canvas.build(play.model, play.world)
	play.overlay.build(play.model)
	play.ship_layer.spawn(
		play.model, SHIP_COUNT, MAP_SEED + 3 + play.region_index,
		play.capital_province, play.player_present(), play.player_faction
	)
	play.army_layer.spawn(play.model)
	play.civilian_layer.spawn(
		play.model, play.capital_province, play.player_faction, STARTING_CIVILIANS
	)
	play.land_works = play.civilian_layer.works
	play.camera.configure(map_size)
	MapPlaySetup.build_visibility(play)
	MapPlayCourtFog.build(play)
	play.overlay.snap_fog()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)
	MapPlaySetup.build_lens(play)
	MapPlaySetup.refresh_region_hud(play, map_size)


## Cycles Old World -> New World and back. Intents never change rules state.
static func cycle(play: PlaySession, backdrop: ColorRect) -> void:
	if play.world == null or play.world.region_count() < 2:
		return
	MapPlayInput.deselect(play)
	mount(play, backdrop, (play.region_index + 1) % play.world.region_count())
	MapPlayDiplomacy.sync_first_contact(play)
	MapPlayDiplomacy.refresh(play)
	play.camera.focus_on(MapPlaySetup.capital_world(play), maxf(play.camera.target_zoom, 0.75))
	RegionBriefing.arrival(play.hud, play.model, play.region_index)
	MapPlayInput.on_view_changed(play)


## Ownership changed outside the map layers (Join Empire): redraw politics.
static func refresh_political(play: PlaySession) -> void:
	if play == null or play.model == null:
		return
	play.canvas.build(play.model, play.world)
	play.overlay.build(play.model)
	MapPlaySetup.build_lens(play)
	if play.visibility != null:
		play.overlay.sync_visibility(play.visibility)
	MapPlaySetup.refresh_region_hud(
		play, MapGeo.world_size(play.model, PlaySession.TILE_SIZE)
	)
