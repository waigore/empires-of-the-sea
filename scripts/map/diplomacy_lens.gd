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
## The reading's wash, baked when the projection is rebuilt — never per frame.
var _wash: WashBake = null


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
	_wash = WashBake.of(
		survey.get("runs", {}), DiplomacySurvey.BANDS, Palette.diplo_color,
		WASH_ALPHA, VEIL_ALPHA, TILE_SIZE
	)
	queue_redraw()


func _summary_of(entry: Dictionary) -> String:
	return String(entry["standing"])


# --- draw --------------------------------------------------------------------


func _draw() -> void:
	if not _visible():
		return
	if _wash != null:
		_wash.draw(self, _reveal)
