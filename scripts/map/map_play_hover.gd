class_name MapPlayHover
extends RefCounted
## Pointer hover and tooltip reading for the map screen (wiki:
## tile-map-and-generation § Reading the chart; issue #1084).
##
## Owns the hover province, the lens hover fields and the chrome tooltip.
## `MapPlayInput` keeps the public door; this home owns the reading under the
## cursor (REQ-P3-01, REQ-P3-02).

## Copy for land no fleet or explorer has charted. The hover tooltip is
## mouse-only, so a tap repeats it as a toast for touch players.
const UNCHARTED_TEXT: String = "Uncharted land"


## Refresh the hover reading under the pointer. An empty screen position reads
## the live mouse; a drag or a control that owns the pointer clears the line.
static func update(play: PlaySession, screen_position: Vector2 = Vector2.INF) -> void:
	if play.camera.is_dragging():
		clear(play)
		return
	var view: Viewport = play.screen.viewport()
	if view != null and _over_gui(view):
		clear(play)
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


## Clear the hover province and hide the tooltip. A sea-only hover still clears.
static func clear(play: PlaySession) -> void:
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


## True when the pointer stands over a control that really owns it. The bar
## re-lays itself on every resize, and a control the viewport still remembers
## from before that sort no longer sits under the pointer — a stale memory must
## not silence the map's own reading (REQ-P1-07).
static func _over_gui(view: Viewport) -> bool:
	var hovered: Control = view.gui_get_hovered_control()
	if hovered == null or not hovered.is_visible_in_tree():
		return false
	return hovered.get_global_rect().has_point(view.get_mouse_position())
