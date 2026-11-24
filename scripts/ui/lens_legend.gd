class_name LensLegend
extends Control
## Key cartouche shown while a map lens is on. Vector swatches mirror the lens
## inks (`Palette`) so the map and the key cannot drift apart (REQ-P1-02).
## One node serves every lens: the survey key while the resource lens is on,
## the political key while the diplomatic lens is on. The reading rows are this
## cartouche's own; the marks beside them are `LensKeyMarks`' (REQ-P3-01).

const WIDTH: float = 244.0
## Tall enough for the six estate rows, the three road strokes and the three
## footer lines (badge, compass, the court's pick ring).
const HEIGHT: float = 226.0

const SURVEY_ROWS: Array[Dictionary] = [
	{"status": "producing", "text": "Yielding estate"},
	{"status": "building", "text": "Under works"},
	{"status": "vacant", "text": "Vacant — can raise"},
	{"status": "survey", "text": "Prospectable — send an Explorer"},
	{"status": "disconnected", "text": "No road to the crown"},
	{"status": "foreign", "text": "Foreign holding"},
]

## The lens carries the built network (roads leave the chart): three strokes,
## the same shapes `RoadInk` paints in world space.
const ROAD_ROWS: Array[Dictionary] = [
	{"kind": "road", "text": "Road to the crown"},
	{"kind": "rail", "text": "Railroad"},
	{"kind": "cut", "text": "No crown link"},
]

const DIPLOMACY_ROWS: Array[Dictionary] = [
	{"band": DiplomacySurvey.BAND_SELF, "text": "Your realm"},
	{"band": DiplomacySurvey.BAND_FRIENDLY, "text": "Friendly or allied"},
	{"band": DiplomacySurvey.BAND_NEUTRAL, "text": "Neutral"},
	{"band": DiplomacySurvey.BAND_WAR, "text": "At war"},
]

const CROWN_ROWS: Array[Dictionary] = [
	{"state": CrownRoadSurvey.STATE_ROAD, "text": "Road to the crown"},
	{"state": CrownRoadSurvey.STATE_TOWN, "text": "Town road only — capped"},
	{"state": CrownRoadSurvey.STATE_CUT, "text": "Cut off — road tiles left"},
]

## One row per defence band, in the order the shield colours run: open ground
## first, then a garrison, then the two wall tiers (DefenceSurvey.BANDS).
const DEFENCE_ROWS: Array[Dictionary] = [
	{"band": DefenceSurvey.BAND_OPEN, "text": "Open — no garrison, no wall"},
	{"band": DefenceSurvey.BAND_HELD, "text": "Garrison only"},
	{"band": DefenceSurvey.BAND_WALLED, "text": "Walled — fort 1–2"},
	{"band": DefenceSurvey.BAND_CITADEL, "text": "Citadel — fort 3+"},
]

const KIND_SURVEY: String = "survey"
const KIND_DIPLOMACY: String = "diplomacy"
const KIND_CROWN_ROAD: String = "crown_road"
const KIND_DEFENCE: String = "defence"
const KIND_SEA: String = "sea"

## One pennant per sea band, in the order the threat runs: our own quiet water,
## a rival under the peace, hostile water we do not hold, then the two fights
## the turn will resolve — read and unread (SeaSurvey.BANDS).
const SEA_ROWS: Array[Dictionary] = [
	{"band": SeaSurvey.BAND_QUIET, "text": "Our water — no hostile sail"},
	{"band": SeaSurvey.BAND_WATCHED, "text": "A rival's sails, no war"},
	{"band": SeaSurvey.BAND_STANDOFF, "text": "Hostile water we do not hold"},
	{"band": SeaSurvey.BAND_CONTESTED, "text": "A battle resolves at turn end"},
	{"band": SeaSurvey.BAND_BLIND, "text": "…and her weight unread"},
]

## Which key to draw: KIND_SURVEY (default), KIND_DIPLOMACY, KIND_CROWN_ROAD,
## KIND_DEFENCE or KIND_SEA.
var kind: String = KIND_SURVEY

var _style: StyleBoxFlat = null
var _font: Font = null


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure()


func set_kind(value: String) -> void:
	if kind == value:
		return
	kind = value
	queue_redraw()


func is_survey() -> bool:
	return kind == KIND_SURVEY


func _draw() -> void:
	_ensure()
	draw_style_box(_style, Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT)))
	if kind == KIND_DIPLOMACY:
		_draw_diplomacy()
		return
	if kind == KIND_CROWN_ROAD:
		_draw_crown_road()
		return
	if kind == KIND_DEFENCE:
		_draw_defence()
		return
	if kind == KIND_SEA:
		_draw_sea()
		return
	_draw_survey()


## Six readings, the three road strokes, then the two lines that spell the
## plate's badge and its Explorer cue out. The rows close at 174 so the two footer
## lines never sit on the last road row.
func _draw_survey() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SURVEY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 44.0
	for row: Dictionary in SURVEY_ROWS:
		var status: String = String(row["status"])
		var tint: Color = (
			Palette.SURVEY_FOREIGN if status == "foreign" else Palette.survey_color(status)
		)
		LensKeyMarks.dot(self, Vector2(22, y - 4.5), status, tint)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 16.0
	y += 2.0
	for row: Dictionary in ROAD_ROWS:
		LensKeyMarks.road(self, Vector2(16, y - 4.5), String(row["kind"]))
		draw_string(
			_font, Vector2(44, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 54, 13, Palette.TEXT
		)
		y += 16.0
	draw_string(
		_font, Vector2(14, HEIGHT - 38), "Badge: built / linked / held, per resource type",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 22), "Compass: tiles an Explorer can still read",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 8), "Ring: the court's pick for an idle crew",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## Four readings, one per band. The wash is a flat tint, so the key shows the
## same flat swatch rather than a status ring.
func _draw_diplomacy() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("DIPLOMACY KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in DIPLOMACY_ROWS:
		var band: String = String(row["band"])
		var tint: Color = Palette.diplo_color(band)
		LensKeyMarks.swatch(self, Vector2(14, y - 13), tint)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Charted land only  ·  grey: no court",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## Three readings, one per state, plus the gap badge the cut rows carry. The
## wash is a flat tint, so the key shows the same flat swatch as the lens.
func _draw_crown_road() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("CROWN ROAD KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in CROWN_ROWS:
		var state: String = String(row["state"])
		var tint: Color = Palette.crown_color(state)
		LensKeyMarks.swatch(self, Vector2(14, y - 13), tint)
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Badge: road tiles still to lay",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Gold line: the route the crew walks",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## Four bands, one shield each, in the same order as the colours: open ground,
## a garrison, a walled province and a citadel. The gold pips are the guns and
## the cross is the hospital, exactly as the slips carry them; a ground that
## shelters a defence prints its own name under them.
func _draw_defence() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("DEFENCE KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in DEFENCE_ROWS:
		var band: String = String(row["band"])
		LensKeyMarks.shield(self, Vector2(22, y - 4), Palette.defence_color(band))
		draw_string(
			_font, Vector2(38, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 48, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 46), "Ground: the dominant terrain, when it shelters",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Number: strength · pips: guns",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "Cross: hospital · charted land only",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


## One pennant per band, in the same ink the water carries: our quiet sea, a
## rival under the peace, hostile water, then the two fights the turn resolves.
## The footer spells the two figures a slip prints.
func _draw_sea() -> void:
	draw_string(
		_font, Vector2(14, 24), MapGlyphs.spaced("SEA KEY"),
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 11, Palette.GOLD_DIM
	)
	var y: float = 50.0
	for row: Dictionary in SEA_ROWS:
		var band: String = String(row["band"])
		LensKeyMarks.pennant(self, Vector2(22, y - 4), Palette.sea_color(band))
		draw_string(
			_font, Vector2(40, y), String(row["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 50, 13, Palette.TEXT
		)
		y += 22.0
	draw_string(
		_font, Vector2(14, HEIGHT - 30), "Line: our hulls and strength · below: station, foe",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)
	draw_string(
		_font, Vector2(14, HEIGHT - 14), "??? : a weight not yet read · red rule: a fight",
		HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 24, 10, Palette.TEXT_DIM
	)


func _ensure() -> void:
	if _font != null:
		return
	_style = UiTheme.box(
		Palette.with_alpha(Palette.PARCHMENT, 0.94), Palette.GOLD_DIM, 1, 3, Vector4.ZERO
	)
	_style.shadow_color = Color(0, 0, 0, 0.35)
	_style.shadow_size = 6
	_font = UiTheme.serif()
	custom_minimum_size = Vector2(WIDTH, HEIGHT)


## One swatch per reading. `survey` is the Explorer's own compass mark, the same
## the plates carry beside their prospectable count; a plate's badge reads
## `built/linked/held` per resource type, which the footer spells out.