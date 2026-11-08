class_name MapPlayInput
extends RefCounted
## Tap, selection, hover, and province-panel orders for the map screen.
## Operates on PlaySession — the screen stays the Node host (REQ-P3-02).


static func on_tapped(play: PlaySession, world_position: Vector2) -> void:
	var civilian: CivilianState = play.civilian_layer.unit_at(world_position)
	if civilian != null:
		play.civilian_layer.select(civilian)
		return
	if MapPlayCivilians.try_move(play, world_position):
		return
	var ship: Ship = play.ship_layer.ship_at(
		world_position, 30.0 / maxf(play.camera.zoom.x, 0.001)
	)
	if ship != null:
		play.ship_layer.select(ship)
		return
	var tile: Vector2i = MapGeo.tile_at_world(world_position, PlaySession.TILE_SIZE)
	if not play.model.in_bounds(tile.x, tile.y):
		return
	if play.ship_layer.selected_ship != null and MapPlayFleets.try_order(play, tile):
		return
	var province_id: int = play.model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		deselect(play)
		return
	select_province(play, province_id, world_position)


static func select_province(play: PlaySession, province_id: int, world_position: Vector2) -> void:
	play.ship_layer.deselect()
	play.civilian_layer.deselect()
	play.overlay.clear_move_options()
	play.overlay.clear_tile_options()
	play.hud.hide_fleet()
	play.hud.hide_civilian()
	play.selected_province = province_id
	play.overlay.select_province(province_id, world_position)
	play.hud.show_province(play.model, province_id)
	play.hud.set_civilian_training(province_id == play.capital_province)
	play.emit_province_selected(province_id)


static func deselect(play: PlaySession) -> void:
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.emit_selection_cleared()
	play.ship_layer.deselect()
	play.civilian_layer.deselect()
	play.overlay.clear_move_options()
	play.overlay.clear_tile_options()
	play.hud.hide_province()
	play.hud.hide_fleet()
	play.hud.hide_civilian()


static func on_minimap_jump(play: PlaySession, world_position: Vector2) -> void:
	play.camera.focus_on(world_position)


static func on_view_changed(play: PlaySession) -> void:
	var viewport: Vector2 = play.camera.viewport_size()
	var half: Vector2 = viewport / (2.0 * maxf(play.camera.zoom.x, 0.001))
	play.hud.update_view_rect(Rect2(play.camera.position - half, half * 2.0))
	play.ship_layer.set_zoom(play.camera.zoom.x)
	play.civilian_layer.set_zoom(play.camera.zoom.x)


static func update_hover(play: PlaySession, screen_position: Vector2 = Vector2.INF) -> void:
	if play.camera.is_dragging():
		clear_hover(play)
		return
	var view: Viewport = play.viewport()
	if view != null and view.gui_get_hovered_control() != null:
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
	if province_id == play.hover_province:
		return
	play.hover_province = province_id
	play.overlay.hover_province = province_id
	if province_id < 0:
		HudChrome.hide_tooltip(play.hud)
		return
	if (
		play.visibility != null
		and play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN
	):
		HudChrome.show_tooltip(play.hud, "Uncharted land")
		return
	var data: Dictionary = play.model.province_data(province_id)
	var terrain: int = play.model.terrain_at(tile.x, tile.y)
	HudChrome.show_tooltip(
		play.hud,
		"%s  ·  %s  ·  %s"
		% [
			String(data["name"]),
			String(MapModel.TERRAIN_LABELS.get(terrain, "Unknown")),
			FactionCatalog.name_of(int(data["owner"])),
		]
	)


static func clear_hover(play: PlaySession) -> void:
	if play.hover_province == -1:
		return
	play.hover_province = -1
	play.overlay.hover_province = -1
	HudChrome.hide_tooltip(play.hud)


static func on_panel_action(play: PlaySession, action: String) -> void:
	if play.selected_province < 0:
		return
	var name: String = play.model.province_name(play.selected_province)
	match action:
		"recruit":
			play.hud.toast("Regiments arrive with the military slice — no order was placed.")
		"build":
			play.improvements.open(play.selected_province)
		"train_explorer", "train_builder", "train_engineer":
			MapPlayCivilians.train(play, action.trim_prefix("train_"))
		_:
			play.hud.toast("Order noted in %s" % name)
