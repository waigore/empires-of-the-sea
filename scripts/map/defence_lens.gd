class_name DefenceLens
extends MapLens
## Military lens: one parchment slip over every charted province, showing what
## would meet an attack — the owner's published order of battle, the wall and
## the hospital (wiki: combat § Strength, siege-mechanics, hospital_rules).
## Pure view — `DefenceSurvey` decides every number and band (REQ-P3-03).
## Slips draw above the fog because a charted province is remembered knowledge;
## ground the crown has not charted was dropped by the projection.

const PLATE_W: float = 96.0
## A slip with a headcount and a wall needs a second line; open ground does not.
const PLATE_H: float = 40.0
const PLATE_H_OPEN: float = 26.0

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
## province keeps a hospital. An open province needs no words — the dash and the
## rust shield already say it — so the reading stays quiet on a calm map.
func _draw_marks(entry: Dictionary, rect: Rect2, tint: Color, alpha: float) -> void:
	var regiments: int = int(entry["regiments"])
	var fort: int = int(entry["fort"])
	var line: String = ""
	if regiments > 0:
		line = "%d reg" % regiments
		if fort > 0:
			line += " · Fort %d" % fort
	elif fort > 0:
		line = "No garrison · Fort %d" % fort
	if not line.is_empty():
		draw_string(
			_font, Vector2(rect.position.x + 30.0, rect.position.y + 34.0), line,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 46.0, 10, Palette.ink(0.72 * alpha)
		)
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


# --- layout ------------------------------------------------------------------


## A held or walled province carries a second line, so its slip is taller.
func _plate_size(entry: Dictionary) -> Vector2:
	var tall: bool = int(entry["regiments"]) > 0 or int(entry["fort"]) > 0
	return Vector2(PLATE_W, PLATE_H if tall else PLATE_H_OPEN)
