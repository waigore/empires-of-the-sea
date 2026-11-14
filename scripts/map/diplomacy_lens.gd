class_name DiplomacyLens
extends MapLens
## Diplomatic lens: a political wash over every charted province, coloured by
## the owner's standing toward the human court — blue for the crown's own land,
## green for friendly or allied courts, grey for neutral and red for those at
## war (wiki: diplomacy § Relation Model).
## Pure view — `DiplomacySurvey` decides every band (REQ-P3-03). The wash draws
## above the fog because ownership is remembered knowledge; unknown ground was
## already dropped by the projection.

## Wash strength over the terrain: strong enough to read at fit zoom, light
## enough that coastlines, borders and glyphs stay legible.
const WASH_ALPHA: float = 0.70
## A knee of parchment under the band ink, so a crimson faction colour cannot
## turn the blue band purple: the map's own ownership wash is neutralised first.
const VEIL_ALPHA: float = 0.62

var state: DiplomacyState = null


## Recomputes the projection. Called on region load, after diplomacy changes
## and at turn boundaries — never per frame.
func build(
	p_model: MapModel,
	p_state: DiplomacyState,
	p_faction: int,
	p_visibility: VisibilityModel = null
) -> void:
	model = p_model
	state = p_state
	faction = p_faction
	visibility = p_visibility
	refresh()


## Fog changes move what the crown may read; nothing else repaints the lens.
func watch(fog: MapOverlay) -> void:
	_watch(fog, &"fog_changed", refresh)


func refresh() -> void:
	survey = DiplomacySurvey.snapshot(model, state, faction, visibility)
	queue_redraw()


func _summary_of(entry: Dictionary) -> String:
	return String(entry["standing"])


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not _visible():
		return
	var runs: Dictionary = survey.get("runs", {})
	for band: String in DiplomacySurvey.BANDS:
		var veil := Color(
			Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b, VEIL_ALPHA * _reveal
		)
		var tint: Color = Palette.diplo_color(band)
		tint.a = WASH_ALPHA * _reveal
		for raw: Variant in runs.get(band, []):
			var run: Rect2 = raw
			var rect := Rect2(run.position * TILE_SIZE, run.size * TILE_SIZE)
			draw_rect(rect, veil)
			draw_rect(rect, tint)
