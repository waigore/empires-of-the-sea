extends GdToolsTest
## Left/right selection-dossier dock persistence and layout (REQ-P1 / P3).

const TEMP_PATH := "user://test_panel_dock.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


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
