class_name CrownRoadLens
extends MapLens
## Crown-road lens: a wash over the crown's own land showing what reaches the
## capital — gold where the road network already carries an estate's yield,
## amber where only the province town links it (so town development caps it),
## and crimson where nothing does. Every cut province also shows the road tiles
## still to lay and their count (wiki: capital-and-connectivity,
## extraction-and-improvements § Extraction formula and town development cap).
##
## Pure view — `CrownRoadSurvey` decides every state and route (REQ-P3-03). The
## wash draws above the fog because the crown's own works are remembered
## knowledge; unknown ground was already dropped by the projection.

## Wash strength over the terrain: readable at fit zoom, light enough that
## coastlines, borders and glyphs stay legible.
const WASH_ALPHA: float = 0.62
## A knee of parchment under the state ink, so a faction's ownership wash cannot
## turn the reading muddy: the map's own colour is neutralised first.
const VEIL_ALPHA: float = 0.58
## Route ink: the tiles to lay, and the line that joins them.
const ROUTE_ALPHA: float = 0.95
const ROUTE_WIDTH: float = 2.0

var works: LandWorks = null
var capital_tile: Vector2i = CivilianState.NO_TILE


## Recomputes the projection. Called on region load, work completion, fog change
## and lens activation — never per frame (REQ-P4-01).
func build(
	p_model: MapModel,
	p_works: LandWorks,
	p_owner: int,
	p_visibility: VisibilityModel = null,
	p_capital_tile: Vector2i = CivilianState.NO_TILE
) -> void:
	model = p_model
	works = p_works
	faction = p_owner
	visibility = p_visibility
	capital_tile = p_capital_tile
	refresh()


## Source nodes whose changes invalidate the projection: a finished road, a
## charted province. Kept as a narrow subscription so the lens never polls.
func watch(civilians: CivilianLayer, fog: MapOverlay) -> void:
	_watch(civilians, &"works_changed", refresh)
	_watch(fog, &"fog_changed", refresh)


func refresh() -> void:
	if model == null or works == null:
		survey = {}
		queue_redraw()
		return
	survey = CrownRoadSurvey.snapshot(
		model, works, faction, capital_tile, visibility
	)
	queue_redraw()


## One hover line for a province: what links it, or how far the road still has
## to run (wiki: extraction-and-improvements § Extraction formula).
func _summary_of(entry: Dictionary) -> String:
	return CrownRoadSurvey.summary_text(entry)


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not _visible():
		return
	_draw_wash()
	_draw_routes()
	_draw_gaps()


## Flat tint per state, one rect per merged run — the same recipe the political
## lens uses, so a 10k-tile map costs a few hundred draw calls.
func _draw_wash() -> void:
	var runs: Dictionary = survey.get("runs", {})
	for state: String in CrownRoadSurvey.STATES:
		var veil := Color(
			Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b, VEIL_ALPHA * _reveal
		)
		var tint: Color = Palette.crown_color(state)
		tint.a = WASH_ALPHA * _reveal
		for raw: Variant in runs.get(state, []):
			var run: Rect2 = raw
			var rect := Rect2(run.position * TILE_SIZE, run.size * TILE_SIZE)
			draw_rect(rect, veil)
			draw_rect(rect, tint)


## The road still to lay: one gold mark per tile, joined by a dashed line, so the
## player can count the works and see where the crew must walk.
func _draw_routes() -> void:
	var ink := Color(
		Palette.GOLD_PALE.r, Palette.GOLD_PALE.g, Palette.GOLD_PALE.b,
		ROUTE_ALPHA * _reveal
	)
	var edge := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55 * _reveal)
	for raw: Variant in survey.get("routes", []):
		var route: Dictionary = raw
		var tiles: Array = route.get("tiles", [])
		var previous: Vector2 = Vector2.INF
		for tile_raw: Variant in tiles:
			var tile: Vector2i = tile_raw
			var center := Vector2(tile) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
			if previous != Vector2.INF:
				draw_line(previous, center, edge, ROUTE_WIDTH + 2.0, true)
				draw_line(previous, center, ink, ROUTE_WIDTH, true)
			draw_rect(
				Rect2(center - Vector2.ONE * 4.0, Vector2.ONE * 8.0), edge
			)
			draw_rect(
				Rect2(center - Vector2.ONE * 3.0, Vector2.ONE * 6.0), ink
			)
			previous = center


## Gap badge over a cut province town: "3" reads as three road tiles to lay.
func _draw_gaps() -> void:
	if _font == null:
		_font = UiTheme.serif()
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if bool(entry.get("linked", false)):
			continue
		var gap: int = int(entry.get("gap", -1))
		if gap <= 0:
			continue
		var anchor: Vector2i = entry.get("anchor", Vector2i(-1, -1))
		if anchor.x < 0:
			continue
		var center := Vector2(anchor) * TILE_SIZE + Vector2.ONE * TILE_SIZE * 0.5
		var label: String = str(gap)
		var plate := Rect2(center + Vector2(3.0, -16.0), Vector2(20.0, 14.0))
		draw_rect(plate, Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.82 * _reveal))
		draw_rect(plate, Color(Palette.GOLD_DIM.r, Palette.GOLD_DIM.g, Palette.GOLD_DIM.b, _reveal), false, 1.0)
		draw_string(
			_font, plate.position + Vector2(5.0, 10.5), label,
			HORIZONTAL_ALIGNMENT_CENTER, 10.0, 10,
			Color(Palette.GOLD_PALE.r, Palette.GOLD_PALE.g, Palette.GOLD_PALE.b, _reveal)
		)
