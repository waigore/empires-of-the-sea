extends GdToolsTest
## The painted chart stamps (assets/art/map): every symbol the plan can scatter
## has a generated sprite, the sprite loads from its imported path, and the draw
## path (including the capital's pennant) runs instead of the vector fallback.
## `MapGlyphs` keeps the ink fallback, so this suite also pins the texture
## coverage those two draw paths agree on.

const KINDS: Array[String] = [
	"mountain", "hill", "tree", "scrub", "dune", "reed", "grass", "field",
	"port", "capital", "town",
]


func test_every_planned_kind_has_a_painted_stamp() -> void:
	for kind: String in KINDS:
		var tex: Texture2D = MapSymbols.texture(kind)
		assert_not_null(tex, "%s has no painted stamp" % kind)
		assert_gt(tex.get_width(), 63, "%s is drawn from a downscaled source" % kind)


func test_unknown_kind_has_no_stamp() -> void:
	assert_null(MapSymbols.texture("nonesuch"))


## The stamp falls back to the ink vectors rather than drawing nothing.
func test_stamp_refuses_a_kind_it_has_no_art_for() -> void:
	assert_false(MapSymbols.stamp(_probe(), {"kind": "nonesuch", "position": Vector2.ZERO, "size": 20.0}))
	assert_false(MapSymbols.stamp(_probe(), {"kind": "tree", "position": Vector2.ZERO, "size": 0.0}))


## A scattered province uses more than one sprite, so a range is not one stamp.
func test_terrain_mountains_take_several_variants() -> void:
	var seen: Dictionary = {}
	for i in 40:
		var at := Vector2(float(i) * 37.0, float(i) * 91.0)
		seen[MapSymbols.texture("mountain", at)] = true
	assert_gt(seen.size(), 1, "a mountain range repeats one sprite")


func test_stamp_draws_a_scenery_mark() -> void:
	var drawn: bool = await _draw_mark({
		"kind": "tree", "position": Vector2(30, 30), "size": 18.0, "flip": true,
	})
	assert_true(drawn, "the painted stamp drew instead of falling back")


func test_stamp_draws_a_town() -> void:
	assert_true(await _draw_mark({"kind": "town", "position": Vector2(64, 64), "size": 20.0}))


## The capital flies its owner's pennant, and still draws when nobody holds it.
func test_capital_stamp_covers_owner_and_neutral() -> void:
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(90, 90), "size": 24.0, "owner": 2,
	}))
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(120, 120), "size": 24.0,
		"owner": MapModel.NO_ID,
	}))


func test_ship_uses_a_painted_hull() -> void:
	var tex: Texture2D = MapSymbols.texture("ship")
	assert_not_null(tex, "the fleet has no painted hull")
	assert_eq(tex.get_width(), 256)


func _probe() -> _StampProbe:
	return _StampProbe.new()


## Drawing is only legal inside `_draw`, so the probe's own draw runs the stamp
## and the test reads its result after a rendered frame.
func _draw_mark(glyph: Dictionary) -> bool:
	var probe := _probe()
	probe.name = "StampProbe"
	probe.glyph = glyph
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	var drawn: bool = probe.result
	probe.queue_free()
	return drawn


class _StampProbe:
	extends Node2D

	var glyph: Dictionary = {}
	var result: bool = false

	func _draw() -> void:
		result = MapSymbols.stamp(self, glyph)
