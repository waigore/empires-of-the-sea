class_name MapPlayInput
extends RefCounted
## Tap, selection, and the public doors for hover, lenses and province-panel
## orders on the map screen. Hover lives in `MapPlayHover`; sheet presses in
## `MapPlayPanelOrders`; readings in `MapPlayLens`. Operates on PlaySession —
## the screen stays the Node host (REQ-P3-01, REQ-P3-02).

## Copy for land no fleet or explorer has charted (held on MapPlayHover).
const UNCHARTED_TEXT: String = MapPlayHover.UNCHARTED_TEXT


static func on_tapped(play: PlaySession, world_position: Vector2) -> void:
	# A decided campaign takes no orders; the map stays for viewing (wiki: victory).
	if play.campaign_over():
		return
	# A pending call to arms holds the turn; map intents wait for the answer.
	if play.turn_suspended:
		return
	# Auto holds the crown's seat: the chart stays pannable and every marker
	# selectable, but a tap raises no order (wiki: auto-mode § Read-only).
	# The full-AI observer has no seat at all, so its taps are readings too —
	# a province opens its sheet and no march, muster or work is ever ordered
	# from the observatory (docs/ai-observer.md; REQ-P2-03).
	var ordering: bool = not MapPlayAuto.blocks_orders(play) and not play.observer_mode
	var civilian: CivilianState = play.civilian_layer.unit_at(world_position)
	var army: ArmyState = play.army_layer.army_at(world_position)
	# Overlapping medallions (a capital muster beside its civilians) go to the
	# marker the tap is actually nearest, so either can be picked deliberately.
	if army != null and (civilian == null or _army_is_nearer(play, army, civilian, world_position)):
		play.army_layer.select(army)
		return
	if civilian != null:
		play.civilian_layer.select(civilian)
		return
	if ordering:
		if MapPlayCivilians.try_move(play, world_position):
			return
	if army != null:
		play.army_layer.select(army)
		return
	var tile: Vector2i = MapGeo.tile_at_world(world_position, PlaySession.TILE_SIZE)
	if not play.model.in_bounds(tile.x, tile.y):
		return
	if ordering:
		if play.army_layer.selected_army != null and MapPlayArmies.try_order(play, tile):
			return
	var ship: Ship = play.ship_layer.ship_at(
		world_position, 30.0 / maxf(play.camera.zoom.x, 0.001)
	)
	if ship != null:
		# A station the crown's squadrons share fans out; a stack cycles, so the
		# second tap on crowded water reads the next squadron rather than the
		# one already in hand (wiki: ships-and-naval § Fleets in one station).
		play.ship_layer.select(play.ship_layer.tap(ship))
		return
	if ordering:
		if play.ship_layer.selected() != null and MapPlayFleets.try_order(play, tile):
			return
	# The sea reading is a reading, not a door: a tap on its water says the line
	# a hover would print, because a phone has no cursor to hover with
	# (REQ-P1-05, REQ-P5-05).
	if play.sea_lens != null and play.sea_lens.active:
		var sea: String = play.sea_lens.summary_at(world_position)
		if not sea.is_empty():
			play.hud.toast(sea)
			return
	var province_id: int = play.model.province_at(tile.x, tile.y)
	if play.lens != null and play.lens.active:
		var surveyed: int = play.lens.hit_test(world_position)
		if surveyed >= 0:
			province_id = surveyed
	if play.defence_lens != null and play.defence_lens.active:
		var defended: int = play.defence_lens.hit_test(world_position)
		if defended >= 0:
			province_id = defended
	if province_id == MapModel.NO_ID:
		deselect(play)
		return
	if (
		play.visibility != null
		and play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN
	):
		deselect(play)
		play.hud.toast("%s — no fleet or explorer has charted it" % UNCHARTED_TEXT)
		return
	select_province(play, province_id, world_position)


static func select_province(play: PlaySession, province_id: int, world_position: Vector2) -> void:
	play.ship_layer.deselect()
	play.civilian_layer.deselect()
	play.army_layer.deselect()
	play.overlay.clear_move_options()
	play.overlay.clear_tile_options()
	play.hud.panels.hide_fleet()
	play.hud.panels.hide_civilian()
	play.hud.panels.hide_army()
	play.selected_province = province_id
	play.overlay.select_province(province_id, world_position)
	play.hud.panels.show_province(
		play.model, province_id, MapPlayImprovements.crown_link(play, province_id)
	)
	# The seat's chart, not the chart's framing field: a colony wearing the
	# seat's own number on another chart hires nobody (wiki:
	# capital-and-connectivity § Capital; world-model-identity).
	var seat: Dictionary = MapPlayCourt.crown_seat(play)
	var at_capital: bool = (
		int(seat["region"]) == play.region_index and province_id == int(seat["province"])
	)
	# The province sheet's own training line: the capital offers its crew, any
	# other province offers none (wiki: civilian-units § Training).
	play.hud.panels.panel.set_training_visible(at_capital)
	# The capital's rail carries the court's own hire pick: the crew the published
	# hire order takes next, read on this crown's own staff, purse and studies
	# (wiki: civilian-units § Training; DR-20261121-06). Any other province hires
	# nobody, so it carries none.
	play.hud.panels.panel.set_hire_pick(
		MapPlayHirePick.pick(play) if at_capital else {}
	)
	play.screen.emit_province_selected(province_id)


static func deselect(play: PlaySession) -> void:
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.screen.emit_selection_cleared()
	play.ship_layer.deselect()
	play.civilian_layer.deselect()
	play.army_layer.deselect()
	play.overlay.clear_move_options()
	play.overlay.clear_tile_options()
	play.hud.panels.hide_province()
	play.hud.panels.hide_fleet()
	play.hud.panels.hide_civilian()
	play.hud.panels.hide_army()


static func on_minimap_jump(play: PlaySession, world_position: Vector2) -> void:
	play.camera.focus_on(world_position)


## Toggles the survey lens and keeps the cartouche seal and key in step. The
## map lenses are exclusive readings: raising one lowers the others. Every
## reading's own raise, walk and fade is MapPlayLens' (REQ-P3-01).
static func set_lens(play: PlaySession, active: bool) -> void:
	MapPlayLens.set_kind(play, LensLegend.KIND_SURVEY, active)


## The diplomatic lens reads the political map; it shares the key cartouche and
## the unit fade with the other lenses, never both at once.
static func set_diplomacy_lens(play: PlaySession, active: bool) -> void:
	MapPlayLens.set_kind(play, LensLegend.KIND_DIPLOMACY, active)


## The crown-road lens reads the crown's own connectivity to its capital.
static func set_crown_lens(play: PlaySession, active: bool) -> void:
	MapPlayLens.set_kind(play, LensLegend.KIND_CROWN_ROAD, active)


## The defence lens reads every charted province's garrison, wall and hospital.
static func set_defence_lens(play: PlaySession, active: bool) -> void:
	MapPlayLens.set_kind(play, LensLegend.KIND_DEFENCE, active)


## The sea reading names what stands in every zone the crown has a sail under
## its eye in, and whether the turn resolves a battle there.
static func set_sea_lens(play: PlaySession, active: bool) -> void:
	MapPlayLens.set_kind(play, LensLegend.KIND_SEA, active)


## L still toggles the survey reading (the seal walks them; P names the court).
static func toggle_lens(play: PlaySession) -> void:
	MapPlayLens.toggle(play, LensLegend.KIND_SURVEY)


static func toggle_diplomacy_lens(play: PlaySession) -> void:
	MapPlayLens.toggle(play, LensLegend.KIND_DIPLOMACY)


## The bar's one seal steps to the next reading (MapPlayLens.ORDER).
static func cycle_lens(play: PlaySession) -> void:
	MapPlayLens.cycle(play)


## The seal's menu and the keys name one reading, or none with an empty kind.
static func select_lens(play: PlaySession, kind: String) -> void:
	MapPlayLens.select(play, kind)


static func on_view_changed(play: PlaySession) -> void:
	var viewport: Vector2 = play.camera.viewport_size()
	var half: Vector2 = viewport / (2.0 * maxf(play.camera.zoom.x, 0.001))
	play.hud.update_view_rect(Rect2(play.camera.position - half, half * 2.0))
	play.ship_layer.set_zoom(play.camera.zoom.x)
	play.civilian_layer.set_zoom(play.camera.zoom.x)
	play.army_layer.set_zoom(play.camera.zoom.x)


static func update_hover(play: PlaySession, screen_position: Vector2 = Vector2.INF) -> void:
	MapPlayHover.update(play, screen_position)


static func clear_hover(play: PlaySession) -> void:
	MapPlayHover.clear(play)


## True when the tap sits nearer the army standard than the civilian medallion.
static func _army_is_nearer(
	play: PlaySession, army: ArmyState, civilian: CivilianState, point: Vector2
) -> bool:
	var army_marker: ArmyMarker = play.army_layer.marker_for(army)
	var civilian_marker: CivilianMarker = play.civilian_layer.marker_for(civilian)
	if army_marker == null:
		return false
	if civilian_marker == null:
		return true
	return army_marker.position.distance_to(point) <= civilian_marker.position.distance_to(point)


static func on_panel_action(play: PlaySession, action: String) -> void:
	MapPlayPanelOrders.apply(play, action)
