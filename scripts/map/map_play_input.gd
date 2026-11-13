class_name MapPlayInput
extends RefCounted
## Tap, selection, hover, and province-panel orders for the map screen.
## Operates on PlaySession — the screen stays the Node host (REQ-P3-02).

## Copy for land no fleet or explorer has charted. The hover tooltip is
## mouse-only, so a tap repeats it as a toast for touch players.
const UNCHARTED_TEXT: String = "Uncharted land"
## The readings in the order the bar's seal walks them (REQ-P5-03).
const LENS_ORDER: Array = [
	LensLegend.KIND_SURVEY,
	LensLegend.KIND_DIPLOMACY,
	LensLegend.KIND_CROWN_ROAD,
	LensLegend.KIND_DEFENCE,
]



static func on_tapped(play: PlaySession, world_position: Vector2) -> void:
	# A decided campaign takes no orders; the map stays for viewing (wiki: victory).
	if play.campaign_over():
		return
	# A pending call to arms holds the turn; map intents wait for the answer.
	if play.turn_suspended:
		return
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
	if MapPlayCivilians.try_move(play, world_position):
		return
	if army != null:
		play.army_layer.select(army)
		return
	var tile: Vector2i = MapGeo.tile_at_world(world_position, PlaySession.TILE_SIZE)
	if not play.model.in_bounds(tile.x, tile.y):
		return
	if play.army_layer.selected_army != null and MapPlayArmies.try_order(play, tile):
		return
	var ship: Ship = play.ship_layer.ship_at(
		world_position, 30.0 / maxf(play.camera.zoom.x, 0.001)
	)
	if ship != null:
		play.ship_layer.select(ship)
		return
	if play.ship_layer.selected() != null and MapPlayFleets.try_order(play, tile):
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
	play.hud.panels.set_civilian_training(province_id == play.capital_province)
	play.emit_province_selected(province_id)


static func deselect(play: PlaySession) -> void:
	play.selected_province = -1
	play.overlay.select_province(-1)
	play.emit_selection_cleared()
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
## map lenses are exclusive readings: raising one lowers the others.
static func set_lens(play: PlaySession, active: bool) -> void:
	_raise_lens(play, play.lens, LensLegend.KIND_SURVEY, active)


## The diplomatic lens reads the political map; it shares the key cartouche and
## the unit fade with the other lenses, never both at once.
static func set_diplomacy_lens(play: PlaySession, active: bool) -> void:
	_raise_lens(play, play.diplomacy_lens, LensLegend.KIND_DIPLOMACY, active)


## The crown-road lens reads the crown's own connectivity to its capital.
static func set_crown_lens(play: PlaySession, active: bool) -> void:
	_raise_lens(play, play.crown_lens, LensLegend.KIND_CROWN_ROAD, active)


## The defence lens reads every charted province's garrison, wall and hospital.
static func set_defence_lens(play: PlaySession, active: bool) -> void:
	_raise_lens(play, play.defence_lens, LensLegend.KIND_DEFENCE, active)


## One lens up: the others come down and the key cartouche follows the reading
## that was raised (REQ-P5-03).
static func _raise_lens(
	play: PlaySession, lens: Variant, kind: String, active: bool
) -> void:
	if lens == null:
		return
	if active:
		_lower_other_lenses(play, lens)
	lens.set_active(active)
	play.hud.set_lens(active, kind)
	_fade_field_units(play, _any_lens(play))
	# A stationary cursor would keep the pre-lens tooltip: rebuild it next frame.
	clear_hover(play)


## The four readings never stack: each open lens takes its own toggle down so
## no button claims a mode that is not on.
static func _lower_other_lenses(play: PlaySession, keep: Variant) -> void:
	var lenses: Array = [play.lens, play.diplomacy_lens, play.crown_lens, play.defence_lens]
	var kinds: Array[String] = [
		LensLegend.KIND_SURVEY, LensLegend.KIND_DIPLOMACY,
		LensLegend.KIND_CROWN_ROAD, LensLegend.KIND_DEFENCE,
	]
	for i in lenses.size():
		var other: Variant = lenses[i]
		if other == null or other == keep or not bool(other.active):
			continue
		other.set_active(false)
		play.hud.set_lens(false, kinds[i])


## The survey is the subject while a lens is on: land units ghost back so the
## reading stays legible, and return to full ink when every lens closes.
static func _fade_field_units(play: PlaySession, active: bool) -> void:
	var alpha: float = 0.22 if active else 1.0
	if play.civilian_layer != null:
		play.civilian_layer.modulate.a = alpha
	if play.army_layer != null:
		play.army_layer.modulate.a = alpha


static func _any_lens(play: PlaySession) -> bool:
	var survey: bool = play.lens != null and play.lens.active
	var political: bool = play.diplomacy_lens != null and play.diplomacy_lens.active
	var crown: bool = play.crown_lens != null and play.crown_lens.active
	var defence: bool = play.defence_lens != null and play.defence_lens.active
	return survey or political or crown or defence


## L still toggles the survey reading (the seal walks them; P names the court).
static func toggle_lens(play: PlaySession) -> void:
	if play.lens == null:
		return
	set_lens(play, not play.lens.active)


static func toggle_diplomacy_lens(play: PlaySession) -> void:
	if play.diplomacy_lens == null:
		return
	set_diplomacy_lens(play, not play.diplomacy_lens.active)


## The reading a click on the bar's seal walks next: none -> survey ->
## diplomacy -> crown road -> defence -> none. The last step clears the map
## because touch has no other way to put a reading down (REQ-P5-03).
static func cycle_lens(play: PlaySession) -> void:
	var next: int = 0
	for i in LENS_ORDER.size():
		var lens: Variant = _lens_for(play, String(LENS_ORDER[i]))
		if lens != null and bool(lens.active):
			next = i + 1
			break
	for offset in LENS_ORDER.size() + 1:
		var index: int = next + offset
		if index >= LENS_ORDER.size():
			select_lens(play, "")
			return
		if _lens_for(play, String(LENS_ORDER[index])) != null:
			select_lens(play, String(LENS_ORDER[index]))
			return


## Raises one named reading, or clears them all with an empty kind. The menu
## and the keys share this, so neither can leave two lenses on.
static func select_lens(play: PlaySession, kind: String) -> void:
	if kind.is_empty():
		_lower_other_lenses(play, null)
		_fade_field_units(play, false)
		clear_hover(play)
		return
	var lens: Variant = _lens_for(play, kind)
	if lens == null:
		return
	_raise_lens(play, lens, kind, true)


## The lens that draws one reading; null before its layer exists or is bound.
static func _lens_for(play: PlaySession, kind: String) -> Variant:
	match kind:
		LensLegend.KIND_SURVEY:
			return play.lens
		LensLegend.KIND_DIPLOMACY:
			return play.diplomacy_lens
		LensLegend.KIND_CROWN_ROAD:
			return play.crown_lens
		LensLegend.KIND_DEFENCE:
			return play.defence_lens
	return null


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
	if play.lens != null:
		play.lens.hover_province = province_id
	if play.defence_lens != null:
		play.defence_lens.hover_province = province_id
	if province_id < 0:
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
	HudChrome.show_tooltip(play.hud, text)


static func clear_hover(play: PlaySession) -> void:
	if play.hover_province == -1:
		return
	play.hover_province = -1
	play.overlay.hover_province = -1
	if play.lens != null:
		play.lens.hover_province = -1
	if play.defence_lens != null:
		play.defence_lens.hover_province = -1
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
	if play.selected_province < 0:
		return
	var name: String = play.model.province_name(play.selected_province)
	# Any catalog type trains through the same intent; the rules gate each one.
	if action.begins_with("train_"):
		MapPlayCivilians.train(play, action.trim_prefix("train_"))
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
		_:
			play.hud.toast("Order noted in %s" % name)
