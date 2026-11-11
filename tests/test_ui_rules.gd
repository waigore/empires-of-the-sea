extends GdToolsTest
## Toast plates: a despatch that changed the world is acknowledged, and a siege
## that silenced a battery carries its medallion so the loss is not mistaken for
## chatter (REQ-P5-05, DR-20261110-22).
## Consolidated rulebook: test_panel_dock, test_unit_icons (one Godot boot per domain).


const LINE := "France holds Burgundy — 2 of 2 emplaced guns silenced"

const TEMP_PATH := "user://test_panel_dock.cfg"

var _hud: GameHud = null


func before_each() -> void:
	_hud = GameHud.new()
	add_child(_hud)


func after_each() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	_hud = null
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_a_plain_toast_keeps_its_single_label() -> void:
	_hud.toast("The turn opens")
	var panel: Control = _hud._toast_box.get_child(0)
	assert_eq(panel.get_child_count(), 1)
	var label: Label = panel.get_child(0) as Label
	assert_true(label != null)
	assert_eq(label.text, "The turn opens")


func test_a_siege_toast_carries_the_silenced_battery_medallion() -> void:
	_hud.toast(LINE, "silenced_gun")
	var panel: Control = _hud._toast_box.get_child(0)
	var row: HBoxContainer = panel.get_child(0) as HBoxContainer
	assert_true(row != null, "the medallion sits in a row with its line")
	var medallion: TextureRect = row.get_child(0) as TextureRect
	assert_true(medallion != null)
	assert_true(medallion.texture != null, "the icon asset is imported")
	assert_eq(medallion.custom_minimum_size, Vector2(26.0, 26.0))
	var label: Label = row.get_child(1) as Label
	assert_true(label != null)
	assert_eq(label.text, LINE)


func test_a_hidden_hud_keeps_no_toast_plates() -> void:
	_hud.visible = false
	_hud.toast(LINE, "silenced_gun")
	assert_eq(_hud._toast_box.get_child_count(), 0)


# --- merged from tests/test_panel_dock.gd ---


## Left/right selection-dossier dock persistence and layout (REQ-P1 / P3).
func test_defaults_to_right() -> void:
	var dock := PanelDock.new()
	assert_eq(dock.side, PanelDock.Side.RIGHT)
	assert_false(dock.is_left())


func test_toggle_flips_side() -> void:
	var dock := PanelDock.new()
	assert_eq(dock.toggle(), PanelDock.Side.LEFT)
	assert_eq(dock.toggle(), PanelDock.Side.RIGHT)


func test_save_and_load_round_trip() -> void:
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	assert_true(dock.save(TEMP_PATH))

	var fresh := PanelDock.new()
	assert_true(fresh.load_from(TEMP_PATH))
	assert_eq(fresh.side, PanelDock.Side.LEFT)


func test_missing_file_keeps_default() -> void:
	var dock := PanelDock.new()
	assert_false(dock.load_from("user://definitely_not_panel_dock.cfg"))
	assert_eq(dock.side, PanelDock.Side.RIGHT)


func test_right_shown_offsets_match_legacy_panel() -> void:
	var dock := PanelDock.new()
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, -(PanelDock.WIDTH + PanelDock.MARGIN))
	assert_eq(wrap.offset_right, -PanelDock.MARGIN)
	wrap.free()


func test_left_shown_offsets_clear_the_margin() -> void:
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.place_shown(wrap)
	assert_eq(wrap.offset_left, PanelDock.MARGIN)
	assert_eq(wrap.offset_right, PanelDock.MARGIN + PanelDock.WIDTH)
	wrap.free()


func test_prepare_wrap_uses_left_anchors_when_docked_left() -> void:
	var dock := PanelDock.new()
	dock.set_side(PanelDock.Side.LEFT)
	var wrap := Control.new()
	add_child(wrap)
	dock.prepare_wrap(wrap)
	assert_eq(wrap.anchor_left, 0.0)
	assert_eq(wrap.anchor_right, 0.0)
	assert_eq(wrap.offset_left, PanelDock.MARGIN - PanelDock.WIDTH)
	wrap.free()


## A show right after a hide must cancel the outgoing slide: its callback would
## otherwise park the panel off screen while the dossier reports it open.
func test_a_slide_in_cancels_a_running_slide_out() -> void:
	var dock := PanelDock.new()
	var host := Node.new()
	add_child(host)
	var wrap := Control.new()
	host.add_child(wrap)
	dock.prepare_wrap(wrap)
	dock.slide_out(host, wrap, func() -> void: wrap.visible = false)
	var outgoing: Tween = wrap.get_meta(PanelDock.SLIDE_KEY)

	dock.slide_in(host, wrap)

	assert_false(outgoing.is_valid(), "the slide-out tween is killed")
	assert_true(wrap.visible)
	assert_ne(wrap.get_meta(PanelDock.SLIDE_KEY), outgoing)
	host.free()


# --- merged from tests/test_unit_icons.gd ---


## Every unit type carries its own medallion plate, cut on the shell's brass
## frame (REQ-P1-02, REQ-P4-04; tools/art/unit-medallions.md).
func test_every_worker_type_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "workers without a plate: %s" % ", ".join(missing))


func test_every_hull_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: Variant in ShipStats.STATS.keys():
		if ShipArt.medallion(String(type_id)) == null:
			missing.append(String(type_id))
	assert_eq(missing.size(), 0, "hulls without a plate: %s" % ", ".join(missing))


func test_every_regiment_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in RegimentCatalog.ids():
		if RegimentArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "regiments without a plate: %s" % ", ".join(missing))


## Unique icons, not one plate reused under several names: every type resolves
## a file of its own.
func test_no_two_types_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for type_id: String in _every_type():
		var texture: Texture2D = _plate(type_id)
		var path: String = texture.resource_path if texture != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [type_id, String(seen[path])])
		seen[path] = type_id
	assert_eq(clashes.size(), 0, "types sharing a plate: %s" % ", ".join(clashes))


func test_an_unknown_hull_falls_back_to_the_default_plate() -> void:
	assert_eq(
		ShipArt.medallion("no_such_hull").resource_path,
		ShipArt.medallion(ShipStats.DEFAULT_TYPE).resource_path
	)
	assert_eq(
		RegimentArt.medallion("no_such_regiment").resource_path,
		RegimentArt.medallion(RegimentCatalog.DEFAULT_TYPE).resource_path
	)


func test_an_unknown_worker_has_no_plate() -> void:
	assert_null(CivilianArt.medallion("no_such_worker"))


## The row widget wears the plate at its own size, mipmapped, and a missing
## plate leaves a gap of the same width so the row's columns do not shift.
func test_the_row_widget_draws_the_plate_it_is_given() -> void:
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(medallion.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(medallion.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	assert_eq(bare.custom_minimum_size, Vector2(20.0, 20.0), "an absent plate keeps its width")
	add_child(bare)
	bare.queue_free()


func test_a_regiment_medallion_names_its_own_type() -> void:
	var medallion: UnitMedallion = UnitMedallion.of_regiment("grenadiers")
	assert_eq(medallion.texture, RegimentArt.medallion("grenadiers"))
	assert_eq(medallion.custom_minimum_size, Vector2(28.0, 28.0))


func _every_type() -> Array[String]:
	var all: Array[String] = []
	all.append_array(CivilianCatalog.ORDER)
	for type_id: Variant in ShipStats.STATS.keys():
		all.append(String(type_id))
	all.append_array(RegimentCatalog.ids())
	return all


func _plate(type_id: String) -> Texture2D:
	if CivilianCatalog.known(type_id):
		return CivilianArt.medallion(type_id)
	if ShipStats.known(type_id):
		return ShipArt.medallion(type_id)
	return RegimentArt.medallion(type_id)
