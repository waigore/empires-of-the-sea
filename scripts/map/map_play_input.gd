class_name MapPlayInput
extends RefCounted
## Tap, selection, hover, and province-panel orders for the map screen.
## Operates on PlaySession — the screen stays the Node host (REQ-P3-02).

## Copy for land no fleet or explorer has charted. The hover tooltip is
## mouse-only, so a tap repeats it as a toast for touch players.
const UNCHARTED_TEXT: String = "Uncharted land"


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
	var seat: Dictionary = MapPlayCourtHoldings.crown_seat(play)
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
	if play.camera.is_dragging():
		clear_hover(play)
		return
	var view: Viewport = play.screen.viewport()
	if view != null and _over_gui(view):
		clear_hover(play)
		return
	var mouse: Vector2 = screen_position
	if mouse == Vector2.INF and view != null:
		mouse = view.get_mouse_position()
	var world: Vector2 = CameraMath.screen_to_world(
		play.camera.position, play.camera.zoom.x, mouse, play.camera.viewport_size()
	)
	var tile: Vector2i = MapGeo.tile_at_world(world, PlaySession.TILE_SIZE)
	var province_id: int = play.model.province_at(tile.x, tile.y)
	# Water moves zone to zone without a province changing, and one province
	# paints several grounds, so every landing is written: the tile under the
	# cursor decides the line, and HudChrome repaints only a line that changed
	# (wiki: tile-map-and-generation § Reading the chart; issue #1084).
	var sea_zone: int = -1
	if play.sea_lens != null:
		sea_zone = play.sea_lens.zone_at(world)
	play.hover_province = province_id
	play.overlay.hover_province = province_id
	if play.lens != null:
		play.lens.hover_province = province_id
	if play.defence_lens != null:
		play.defence_lens.hover_province = province_id
	if play.sea_lens != null:
		play.sea_lens.hover_zone = sea_zone
	if province_id < 0:
		# Over water the sea reading is the only line there is: read it here, so
		# a chart reading never silences itself on the element it describes.
		if play.sea_lens != null and play.sea_lens.active:
			var water: String = play.sea_lens.summary_at(world)
			if not water.is_empty():
				HudChrome.show_tooltip(play.hud, water)
				return
		HudChrome.hide_tooltip(play.hud)
		return
	if (
		play.visibility != null
		and play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN
	):
		HudChrome.show_tooltip(play.hud, UNCHARTED_TEXT)
		return
	var data: ProvinceState = play.model.province_data(province_id)
	if data == null:
		return
	var terrain: int = play.model.terrain_at(tile.x, tile.y)
	var text: String = "%s  ·  %s  ·  %s" % [
		data.name,
		String(MapModel.TERRAIN_LABELS.get(terrain, "Unknown")),
		FactionCatalog.name_of(data.owner),
	]
	if play.lens != null and play.lens.active:
		var survey: String = play.lens.summary_for(province_id)
		if not survey.is_empty():
			text += "\n" + survey
	if play.diplomacy_lens != null and play.diplomacy_lens.active:
		var standing: String = play.diplomacy_lens.summary_for(province_id)
		if not standing.is_empty():
			text += "\nStanding: " + standing
	if play.crown_lens != null and play.crown_lens.active:
		var road: String = play.crown_lens.summary_for(province_id)
		if not road.is_empty():
			text += "\n" + road
	if play.defence_lens != null and play.defence_lens.active:
		var defence: String = play.defence_lens.summary_for(province_id)
		if not defence.is_empty():
			text += "\nDefence: " + defence
	# A sea slip packed over the coast still reads: the plaque's own rect answers
	# before the water under the cursor does.
	if play.sea_lens != null and play.sea_lens.active:
		var sea: String = play.sea_lens.summary_at(world)
		if not sea.is_empty():
			text += "\nSea: " + sea
	HudChrome.show_tooltip(play.hud, text)


## True when the pointer stands over a control that really owns it. The bar
## re-lays itself on every resize, and a control the viewport still remembers
## from before that sort no longer sits under the pointer — a stale memory must
## not silence the map's own reading (REQ-P1-07).
static func _over_gui(view: Viewport) -> bool:
	var hovered: Control = view.gui_get_hovered_control()
	if hovered == null or not hovered.is_visible_in_tree():
		return false
	return hovered.get_global_rect().has_point(view.get_mouse_position())


static func clear_hover(play: PlaySession) -> void:
	if play.hover_province == -1:
		if play.sea_lens != null and play.sea_lens.hover_zone >= 0:
			play.sea_lens.hover_zone = -1
			HudChrome.hide_tooltip(play.hud)
		return
	play.hover_province = -1
	play.overlay.hover_province = -1
	if play.lens != null:
		play.lens.hover_province = -1
	if play.defence_lens != null:
		play.defence_lens.hover_province = -1
	if play.sea_lens != null:
		play.sea_lens.hover_zone = -1
	HudChrome.hide_tooltip(play.hud)


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
	if play.campaign_over():
		return
	if play.turn_suspended:
		return
	# Auto holds the seat: the province sheet stays readable, but a press raises
	# no order (wiki: auto-mode § Read-only while it runs).
	if MapPlayAuto.blocks_orders(play):
		return
	if play.selected_province < 0:
		return
	var name: String = play.model.province_name(play.selected_province)
	# Any catalog type trains through the same intent; the rules gate each one.
	if action.begins_with("train_"):
		MapPlayTraining.train(play, action.trim_prefix("train_"))
		return
	if action.begins_with("road:"):
		MapPlayImprovements.build_road(play, _tile_of(action, "road:"))
		return
	if action.begins_with("rail:"):
		MapPlayImprovements.build_rail(play, _tile_of(action, "rail:"))
		return
	match action:
		"recruit":
			MapPlayArmies.open_muster(play)
		"shipyard":
			MapPlayFleetYard.open(play)
		"build":
			play.improvements.open(play.selected_province)
		"upgrade_town":
			MapPlayImprovements.upgrade_town(play, play.selected_province)
		"raise_wall":
			MapPlayImprovements.raise(
				play, play.region_index, play.selected_province,
				MapPlayImprovements.RAISE_WALL
			)
		"raise_ward":
			MapPlayImprovements.raise(
				play, play.region_index, play.selected_province,
				MapPlayImprovements.RAISE_WARD
			)
		_:
			play.hud.toast("Order noted in %s" % name)


## "<prefix><x>,<y>": the tile a dossier control names — the estate the Build
## road control roads, the road tile the rail block rails. (-1,-1) when the
## intent is malformed, so the rules refuse it plainly.
static func _tile_of(action: String, prefix: String) -> Vector2i:
	var parts: PackedStringArray = action.trim_prefix(prefix).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
