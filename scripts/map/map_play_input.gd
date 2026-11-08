class_name MapPlayInput
extends RefCounted
## Tap, selection, hover, and province-panel orders for the map screen.
## The screen stays the node; this helper only sequences presentation.


static func on_tapped(screen: MapScreen, world_position: Vector2) -> void:
	var civilian: CivilianState = screen.civilian_layer.unit_at(world_position)
	if civilian != null:
		screen.civilian_layer.select(civilian)
		return
	if MapPlayCivilians.try_move(screen, world_position):
		return
	var ship: Ship = screen.ship_layer.ship_at(
		world_position, 30.0 / maxf(screen.camera.zoom.x, 0.001)
	)
	if ship != null:
		screen.ship_layer.select(ship)
		return
	var tile: Vector2i = MapGeo.tile_at_world(world_position, MapScreen.TILE_SIZE)
	if not screen.model.in_bounds(tile.x, tile.y):
		return
	if screen.ship_layer.selected_ship != null and MapPlayFleets.try_order(screen, tile):
		return
	var province_id: int = screen.model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		deselect(screen)
		return
	select_province(screen, province_id, world_position)


static func select_province(screen: MapScreen, province_id: int, world_position: Vector2) -> void:
	screen.ship_layer.deselect()
	screen.civilian_layer.deselect()
	screen.overlay.clear_move_options()
	screen.overlay.clear_tile_options()
	screen.hud.hide_fleet()
	screen.hud.hide_civilian()
	screen.selected_province = province_id
	screen.overlay.select_province(province_id, world_position)
	screen.hud.show_province(screen.model, province_id)
	screen.hud.set_civilian_training(province_id == screen.capital_province)
	screen.province_selected.emit(province_id)


static func deselect(screen: MapScreen) -> void:
	screen.selected_province = -1
	screen.overlay.select_province(-1)
	screen.selection_cleared.emit()
	screen.ship_layer.deselect()
	screen.civilian_layer.deselect()
	screen.overlay.clear_move_options()
	screen.overlay.clear_tile_options()
	screen.hud.hide_province()
	screen.hud.hide_fleet()
	screen.hud.hide_civilian()


static func on_minimap_jump(screen: MapScreen, world_position: Vector2) -> void:
	screen.camera.focus_on(world_position)


static func on_view_changed(screen: MapScreen) -> void:
	var viewport: Vector2 = screen.camera.viewport_size()
	var half: Vector2 = viewport / (2.0 * maxf(screen.camera.zoom.x, 0.001))
	screen.hud.update_view_rect(Rect2(screen.camera.position - half, half * 2.0))
	screen.ship_layer.set_zoom(screen.camera.zoom.x)
	screen.civilian_layer.set_zoom(screen.camera.zoom.x)


static func update_hover(screen: MapScreen, screen_position: Vector2 = Vector2.INF) -> void:
	if screen.camera.is_dragging():
		clear_hover(screen)
		return
	if screen.get_viewport().gui_get_hovered_control() != null:
		clear_hover(screen)
		return
	var mouse: Vector2 = screen_position
	if mouse == Vector2.INF:
		mouse = screen.get_viewport().get_mouse_position()
	var world: Vector2 = CameraMath.screen_to_world(
		screen.camera.position, screen.camera.zoom.x, mouse, screen.camera.viewport_size()
	)
	var tile: Vector2i = MapGeo.tile_at_world(world, MapScreen.TILE_SIZE)
	var province_id: int = screen.model.province_at(tile.x, tile.y)
	if province_id == screen._hover_province:
		return
	screen._hover_province = province_id
	screen.overlay.hover_province = province_id
	if province_id < 0:
		HudChrome.hide_tooltip(screen.hud)
		return
	if (
		screen.visibility != null
		and screen.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN
	):
		HudChrome.show_tooltip(screen.hud, "Uncharted land")
		return
	var data: Dictionary = screen.model.province_data(province_id)
	var terrain: int = screen.model.terrain_at(tile.x, tile.y)
	HudChrome.show_tooltip(screen.hud,
		"%s  ·  %s  ·  %s"
		% [
			String(data["name"]),
			String(MapModel.TERRAIN_LABELS.get(terrain, "Unknown")),
			FactionCatalog.name_of(int(data["owner"])),
		]
	)


static func clear_hover(screen: MapScreen) -> void:
	if screen._hover_province == -1:
		return
	screen._hover_province = -1
	screen.overlay.hover_province = -1
	HudChrome.hide_tooltip(screen.hud)


static func on_panel_action(screen: MapScreen, action: String) -> void:
	if screen.selected_province < 0:
		return
	var name: String = screen.model.province_name(screen.selected_province)
	match action:
		"recruit":
			screen.hud.toast("A regiment is raised in %s" % name)
		"build":
			screen.hud.toast("Works begin in %s" % name)
		"train_explorer", "train_builder", "train_engineer":
			MapPlayCivilians.train(screen, action.trim_prefix("train_"))
		_:
			screen.hud.toast("Order noted in %s" % name)
