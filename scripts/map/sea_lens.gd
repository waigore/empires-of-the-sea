class_name SeaLens
extends MapLens
## The sea reading: one parchment slip over every sea zone the crown has a sail
## under its eye in — its own hulls and strength, the station they hold, the
## hostile sail sharing the water and whether the turn resolves a battle here
## (wiki: ships-and-naval § Missions and Movement, § Naval Combat Resolution).
## Pure view — `SeaSurvey` decides every band, number and word (REQ-P3-03).
## A slip draws above the fog because the crown's chart is remembered
## knowledge; a squadron the fog withholds, or one not watched across a turn,
## was dropped by the projection and never reaches a plate.

const PLATE_W: float = 104.0
const PLATE_H: float = 40.0
const PLATE_PAD: float = 6.0
const RIBBON: float = 2.4

## Region roster the reading is derived from; null in a hand-built test.
var roster: ShipLayer = null
var fleets: Array = []
## The resolver's own war test and the chart's own answer for one squadron
## (`drawn`, `read`), handed in so the plate and the marker cannot disagree
## (REQ-P2-03).
var hostile: Callable = Callable()
var crown_view: Callable = Callable()
## The zone under the cursor, so its slip prints the hover rule. -1 for open
## water the reading does not carry.
var hover_zone: int = -1


## Rebuilds the projection. Called on region load, turn end, lens activation and
## after a sail — never per frame.
func build(
	p_model: MapModel,
	p_roster: ShipLayer,
	p_visibility: VisibilityModel,
	p_faction: int,
	p_hostile: Callable = Callable(),
	p_crown_view: Callable = Callable()
) -> void:
	model = p_model
	roster = p_roster
	visibility = p_visibility
	faction = p_faction
	hostile = p_hostile
	crown_view = p_crown_view
	refresh()


## A sail, a battle's pruning or a chart that moved: the three events that
## change the reading. It repaints then and only then (REQ-P4-01).
func watch(fog: MapOverlay) -> void:
	_watch(fog, &"fog_changed", refresh)
	_watch(roster, &"fleet_moved", _on_fleet_moved)
	_watch(roster, &"warp_crossed", _on_fleet_moved)
	_watch(roster, &"zone_entered", _on_zone_entered)


func _on_fleet_moved(_fleet: FleetState, _result: Dictionary) -> void:
	refresh()


func _on_zone_entered(_zone_id: int, _ship: Ship) -> void:
	refresh()


func refresh() -> void:
	if model == null:
		survey = {}
		queue_redraw()
		return
	fleets = []
	if roster != null:
		fleets.assign(roster.regions.value(model.region_id, []))
	survey = SeaSurvey.snapshot(
		model, fleets, visibility, faction, hostile, crown_view
	)
	_layout_plates()
	queue_redraw()


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not _visible():
		return
	if _font == null:
		_font = UiTheme.serif()
	for raw: Variant in _rows():
		_draw_plate(raw)


func _draw_plate(entry: Dictionary) -> void:
	var rect: Rect2 = _plate_rect(entry)
	var alpha: float = _reveal * _charted_alpha(int(entry["charted"]))
	if alpha <= 0.01:
		return
	var shape: PackedVector2Array = _plate_shape(rect, 3.0)
	draw_colored_polygon(
		_offset_shape(shape, Vector2(1.4, 2.2)), Color(0.10, 0.08, 0.05, 0.32 * alpha)
	)
	draw_colored_polygon(shape, Color(0.945, 0.902, 0.792, 0.99 * alpha))
	draw_polyline(
		_closed(shape), Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.90 * alpha),
		1.4, true
	)
	var band: String = String(entry["band"])
	var tint: Color = Palette.sea_color(band)
	var ribbon: Color = tint
	ribbon.a *= alpha
	draw_rect(Rect2(rect.position + Vector2(2, 4), Vector2(RIBBON, rect.size.y - 8)), ribbon)

	_draw_pennant(Vector2(rect.position.x + 15.0, rect.position.y + 13.0), tint, alpha)
	var ink := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, alpha)
	draw_string(
		_font, Vector2(rect.position.x + 27.0, rect.position.y + 18.0),
		_hull_line(entry), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 38.0, 13, ink
	)
	var second: String = _second_line(entry)
	if not second.is_empty():
		var dim := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.72 * alpha)
		draw_string(
			_font, Vector2(rect.position.x + 27.0, rect.position.y + 32.0),
			second, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 38.0, 10, dim
		)
	# A marker for the fight itself, under the pennant: a battle the court can
	# see coming is the one thing this reading exists to say.
	if bool(entry["fight"]):
		draw_rect(
			Rect2(rect.position + Vector2(8.0, rect.size.y - 9.0), Vector2(14.0, 2.0)),
			Color(Palette.DIPLO_WAR.r, Palette.DIPLO_WAR.g, Palette.DIPLO_WAR.b, alpha)
		)
	if int(entry["id"]) == hover_zone:
		draw_rect(
			Rect2(rect.position + Vector2(2, rect.size.y - 4), Vector2(rect.size.x - 4, 2)),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)


## A pennant over a short mast, in the band's ink — the reading's one emblem,
## the same shape the key prints.
func _draw_pennant(center: Vector2, tint: Color, alpha: float) -> void:
	var mast: Color = Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.55 * alpha)
	draw_line(center + Vector2(-4.0, -8.0), center + Vector2(-4.0, 8.0), mast, 1.2, true)
	var fly := PackedVector2Array([
		center + Vector2(-3.0, -7.0),
		center + Vector2(8.0, -3.0),
		center + Vector2(-3.0, 1.0),
	])
	draw_colored_polygon(fly, Color(tint.r, tint.g, tint.b, 0.92 * alpha))


## First line: the crown's hulls and the strength they would fight with. An
## empty sea says so in a dash, never a zero that reads as a real squadron.
func _hull_line(entry: Dictionary) -> String:
	var hulls: int = int(entry["own_hulls"])
	if hulls <= 0:
		return "— no sail"
	return "%d hull%s · %.1f" % [hulls, "" if hulls == 1 else "s", float(entry["own_strength"])]


## Second line: the station our squadrons hold, then the hostile sail sharing
## the water. The court's name stays in the hover line: a slip at fit zoom has
## room for a figure, never for a sentence.
func _second_line(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	var station: String = String(entry["station_text"])
	if not station.is_empty():
		parts.append(station)
	var foe: int = int(entry["foe_squadrons"])
	if foe > 0:
		var weight: String = (
			"???" if int(entry["foe_unread"]) > 0 else "%.1f" % float(entry["foe_strength"])
		)
		parts.append("Foe %d · %s" % [foe, weight])
	return " · ".join(parts)


# --- layout ------------------------------------------------------------------


## The zone whose slip covers a world point, else the zone under it. A packed
## slip can sit away from its water, so a hover over the plate must still name
## the sea it reads.
func zone_at(world_position: Vector2) -> int:
	var zone: int = hit_test(world_position)
	if zone >= 0:
		return zone
	if model == null:
		return -1
	var tile: Vector2i = MapGeo.tile_at_world(world_position, TILE_SIZE)
	return model.sea_zone_at(tile.x, tile.y)


## The hover line for the water under a point, empty where the reading carries
## no row: a chart that names every empty zone would be noise, not evidence.
func summary_at(world_position: Vector2) -> String:
	var zone: int = zone_at(world_position)
	if zone < 0:
		return ""
	for raw: Variant in _rows():
		var entry: Dictionary = raw
		if int(entry["id"]) == zone:
			return String(entry.get("summary", ""))
	return ""


## The sea's slips are keyed by zone, not province: the kit packs and hit-tests
## whichever rows the reading names.
func _rows() -> Array:
	return survey.get("zones", [])


func _plate_size(_entry: Dictionary) -> Vector2:
	return Vector2(PLATE_W, PLATE_H)


func _pack_step() -> float:
	return PACK_STEP + PLATE_H * 0.5


## Print the slip under the water's own marker: a squadron's hull badge and
## strength plate hang below her flag, so a slip at the anchor would print over
## them (REQ-P1-07).
func _pack_drop(_entry: Dictionary) -> float:
	return 40.0
