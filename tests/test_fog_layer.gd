extends GdToolsTest
## Fog of war view contract: the fog texture is a child layer that draws behind
## the overlaid ink, fog ids map from visibility levels, and reveal fades settle
## back to a stable texture (no per-frame work once settled).

const Fixture = preload("res://tests/map_fixture.gd")

var _overlay: MapOverlay = null


func before_each() -> void:
	_overlay = MapOverlay.new()
	_overlay.build(Fixture.region())
	add_child(_overlay)


func after_each() -> void:
	if is_instance_valid(_overlay):
		_overlay.free()
	_overlay = null


func test_fog_is_a_child_sprite_behind_the_ink() -> void:
	var fog: FogLayer = _overlay.get_node_or_null("Fog")
	assert_not_null(fog)
	assert_eq(fog, _overlay.fog_layer)
	var sprite: Sprite2D = null
	for child in fog.get_children():
		if child is Sprite2D:
			sprite = child as Sprite2D
	assert_not_null(sprite)
	assert_true(sprite.show_behind_parent)


func test_levels_map_to_fog_ids() -> void:
	assert_eq(MapOverlay.FOG_VISIBLE, FogLayer.FOG_VISIBLE)
	assert_eq(
		FogLayer.fog_state_for(VisibilityModel.Level.FULLY_VISIBLE), FogLayer.FOG_VISIBLE
	)
	assert_eq(FogLayer.fog_state_for(VisibilityModel.Level.UNKNOWN), FogLayer.FOG_UNKNOWN)
	assert_eq(FogLayer.fog_state_for(VisibilityModel.Level.FOGGED), FogLayer.FOG_FOGGED)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_FOGGED), 0.55, 0.0001)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_UNKNOWN), 1.0, 0.0001)
	assert_almost_eq(FogLayer.target_alpha(FogLayer.FOG_VISIBLE), 0.0, 0.0001)


func test_overlay_delegates_fog_state_to_the_layer() -> void:
	var tile: Vector2i = Vector2i(1, 1)
	_overlay.set_fog_state(_overlay.model.index_of(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	assert_eq(_overlay.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED)
	assert_eq(
		_overlay.fog_layer.fog_state_at(tile.x, tile.y), MapOverlay.FOG_FOGGED
	)


func test_snapped_fog_settles_and_stops_fading() -> void:
	var tile: Vector2i = Vector2i(2, 2)
	_overlay.set_fog_state(_overlay.model.index_of(tile.x, tile.y), MapOverlay.FOG_UNKNOWN)
	assert_true(_overlay.fog_layer.is_fading())
	_overlay.snap_fog()
	assert_false(_overlay.fog_layer.is_fading())
	assert_true(_overlay.fog_layer.advance(0.016), "snap repaints once")
	assert_false(_overlay.fog_layer.advance(0.016), "settled fog does not repaint")
