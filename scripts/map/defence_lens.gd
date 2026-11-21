class_name DefenceLens
extends MapLens
## Military lens: one parchment slip over every charted province, showing what
## would meet an attack — the owner's published order of battle, the wall, the
## hospital and the ground the fight would be had on (wiki: combat § Strength,
## siege-mechanics, hospital_rules, resource-terrain-region-rules §
## Player-facing terrain display names).
## Pure view — `DefenceSurvey` decides every number, band and ground word
## (REQ-P3-03). Slips draw above the fog because a charted province is
## remembered knowledge; ground the crown has not charted was dropped by the
## projection.

const PLATE_W: float = 96.0
## One line of reading under the strength: the garrison and wall, then the
## ground that shelters. An open province on open ground keeps its slip quiet.
const PLATE_H_OPEN: float = 26.0
const LINE_H: float = 14.0
## The ground's own line is set a step smaller than the garrison's.
const GROUND_FONT: int = 9
## The reading's text column, and the room the gun pips and the ward cross keep.
const TEXT_LEFT: float = 30.0
const TEXT_ROOM: float = 46.0

## Region roster the reading is derived from; null in a hand-built test.
var roster: ArmyLayer = null
var armies: Array[ArmyState] = []


## Rebuilds the projection. Called on region load, turn end, lens activation and
## after a march — never per frame.
func build(
	p_model: MapModel,
	p_roster: ArmyLayer,
	p_visibility: VisibilityModel,
	p_faction: int
) -> void:
	model = p_model
	roster = p_roster
	visibility = p_visibility
	faction = p_faction
	refresh()


## Fog changes move what the crown may read, and a march moves a garrison; the
## lens repaints on those events only (REQ-P4-01).
func watch(fog: MapOverlay) -> void:
	_watch(fog, &"fog_changed", refresh)
	_watch(roster, &"army_moved", _on_army_moved)


func _on_army_moved(_army: ArmyState, _result: Dictionary) -> void:
	refresh()


func refresh() -> void:
	if model == null:
		survey = {}
		queue_redraw()
		return
	_ensure_font()
	armies = []
	if roster != null:
		armies.assign(roster.regions.value(model.region_id, []))
	survey = DefenceSurvey.snapshot(model, armies, visibility, faction)
	_layout_plates()
	queue_redraw()


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not _visible():
		return
	_ensure_font()
	for raw: Variant in survey.get("provinces", []):
		_draw_plate(raw)


func _draw_plate(entry: Dictionary) -> void:
	var rect: Rect2 = _plate_rect(entry)
	var alpha: float = _reveal * _charted_alpha(int(entry["charted"]))
	if alpha <= 0.01:
		return
	LensSlip.draw_slip(self, rect, alpha, _owner_tint(int(entry["owner"])))

	var band: String = String(entry["band"])
	var tint: Color = Palette.defence_color(band)
	_draw_shield(Vector2(rect.position.x + 16.0, rect.position.y + 14.0), tint, alpha)
	var strength: int = int(entry["strength"])
	var number: String = "—" if strength <= 0 else str(strength)
	draw_string(
		_font, Vector2(rect.position.x + 30.0, rect.position.y + 20.0), number,
		HORIZONTAL_ALIGNMENT_LEFT, 30.0, 16, Palette.ink(alpha)
	)
	_draw_marks(entry, rect, tint, alpha)
	if int(entry["id"]) == hover_province:
		LensSlip.hover_rule(self, rect, alpha)


## A heraldic shield, filled in the band's ink: open rust, held ochre, walled
## slate, citadel indigo. The same shape keys the legend.
func _draw_shield(center: Vector2, tint: Color, alpha: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-6.0, -7.0),
		center + Vector2(6.0, -7.0),
		center + Vector2(6.0, 1.0),
		center + Vector2(0.0, 8.0),
		center + Vector2(-6.0, 1.0),
	])
	var fill := Color(tint.r, tint.g, tint.b, 0.90 * alpha)
	draw_colored_polygon(points, fill)
	draw_polyline(LensSlip.closed(points), Palette.ink(0.55 * alpha), 1.0, true)


## Second line: the garrison's headcount and the wall, then a cross when the
## province keeps a hospital. Under it, the ground the fight would be had on —
## named only when it shelters, because open ground already reads weak through
## the dash and the rust shield.
func _draw_marks(entry: Dictionary, rect: Rect2, tint: Color, alpha: float) -> void:
	var line: String = _garrison_line(entry)
	if not line.is_empty():
		_draw_reading(rect, 34.0, line, 10, 0.72 * alpha)
	if bool(entry.get("shelters", false)):
		var baseline: float = 34.0 if line.is_empty() else 48.0
		_draw_reading(rect, baseline, String(entry.get("terrain_name", "")), GROUND_FONT, 0.72 * alpha)
	# One gold pip per standing gun, so a wall reads without the words.
	for i in int(entry["guns"]):
		draw_rect(
			Rect2(
				Vector2(rect.end.x - 8.0 - float(i) * 5.0, rect.position.y + 10.0),
				Vector2(3.2, 6.0)
			),
			Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
		)
	if int(entry["hospital"]) > 0:
		var spot := Vector2(rect.end.x - 10.0, rect.position.y + 26.0)
		var cross: Color = Color(tint.r, tint.g, tint.b, alpha)
		draw_line(spot + Vector2(-3.5, 0), spot + Vector2(3.5, 0), cross, 1.6, true)
		draw_line(spot + Vector2(0, -3.5), spot + Vector2(0, 3.5), cross, 1.6, true)


## The garrison line: men and wall in the words the slips have always used.
## Open ground with no wall prints nothing, so its slip keeps one line.
func _garrison_line(entry: Dictionary) -> String:
	var regiments: int = int(entry["regiments"])
	var fort: int = int(entry["fort"])
	if regiments > 0:
		var line: String = "%d reg" % regiments
		return line if fort <= 0 else line + " · Fort %d" % fort
	if fort > 0:
		return "No garrison · Fort %d" % fort
	return ""


func _draw_reading(rect: Rect2, baseline: float, text: String, size: int, alpha: float) -> void:
	draw_string(
		_font, Vector2(rect.position.x + TEXT_LEFT, rect.position.y + baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - TEXT_ROOM, size, Palette.ink(alpha)
	)


# --- layout ------------------------------------------------------------------


## A held, walled or sheltered province carries a line of reading under its
## strength; the ground that shelters adds one more and widens the slip to the
## room its name needs, since `Hardwood Forest` is longer than the column.
func _plate_size(entry: Dictionary) -> Vector2:
	var lines: int = 0
	if not _garrison_line(entry).is_empty():
		lines += 1
	var shelters: bool = bool(entry.get("shelters", false))
	if shelters:
		lines += 1
	var width: float = PLATE_W
	if shelters:
		width = maxf(PLATE_W, _ground_width(String(entry.get("terrain_name", ""))))
	return Vector2(width, PLATE_H_OPEN + LINE_H * float(lines))


## The width a ground's name needs: the words and the room the column, the pips
## and the ward keep on either side.
func _ground_width(name: String) -> float:
	if name.is_empty():
		return PLATE_W
	var measured: float = _font.get_string_size(
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, GROUND_FONT
	).x
	return measured + TEXT_ROOM
