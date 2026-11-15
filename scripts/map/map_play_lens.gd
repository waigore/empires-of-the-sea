class_name MapPlayLens
extends RefCounted
## The chart's five readings: raising and lowering them, the bar seal's walk,
## the one key cartouche and the unit fade that keeps a reading legible
## (REQ-P5-03, REQ-P1-07). Operates on PlaySession — the screen stays the Node
## host (REQ-P3-02). Kept out of MapPlayInput so the tap, selection and hover
## module stays under the 400-line soft bar (REQ-P3-01).

## The readings in the order the bar's seal walks them (REQ-P5-03).
const ORDER: Array = [
	LensLegend.KIND_SURVEY,
	LensLegend.KIND_DIPLOMACY,
	LensLegend.KIND_CROWN_ROAD,
	LensLegend.KIND_DEFENCE,
	LensLegend.KIND_SEA,
]


## Raises or lowers one named reading. The map's readings are exclusive: a raise
## takes every other lens down first, so two never paint over one another.
static func set_kind(play: PlaySession, kind: String, active: bool) -> void:
	var lens: Variant = lens_for(play, kind)
	if lens == null:
		return
	if active:
		_lower_other_lenses(play, lens)
	lens.set_active(active)
	play.hud.set_lens(active, kind)
	_fade_field_units(play, any_lens(play))
	# A stationary cursor would keep the pre-lens tooltip: rebuild it next frame.
	MapPlayInput.clear_hover(play)


## One reading's own toggle: raise it while it is down, put it down while it is
## up, so a key or a menu pick never has to read the lens first.
static func toggle(play: PlaySession, kind: String) -> void:
	var lens: Variant = lens_for(play, kind)
	if lens == null:
		return
	set_kind(play, kind, not bool(lens.active))


## Raises one named reading, or clears them all with an empty kind. The menu
## and the keys share this, so neither can leave two lenses on.
static func select(play: PlaySession, kind: String) -> void:
	if kind.is_empty():
		_lower_other_lenses(play, null)
		_fade_field_units(play, false)
		MapPlayInput.clear_hover(play)
		return
	set_kind(play, kind, true)


## The reading a click on the bar's seal walks next: none -> survey ->
## diplomacy -> crown road -> defence -> sea -> none. The last step clears the
## map because touch has no other way to put a reading down (REQ-P5-03).
static func cycle(play: PlaySession) -> void:
	var next: int = 0
	for i in ORDER.size():
		var lens: Variant = lens_for(play, String(ORDER[i]))
		if lens != null and bool(lens.active):
			next = i + 1
			break
	for offset in ORDER.size() + 1:
		var index: int = next + offset
		if index >= ORDER.size():
			select(play, "")
			return
		if lens_for(play, String(ORDER[index])) != null:
			select(play, String(ORDER[index]))
			return


## The lens that draws one reading; null before its layer exists or is bound.
static func lens_for(play: PlaySession, kind: String) -> Variant:
	match kind:
		LensLegend.KIND_SURVEY:
			return play.lens
		LensLegend.KIND_DIPLOMACY:
			return play.diplomacy_lens
		LensLegend.KIND_CROWN_ROAD:
			return play.crown_lens
		LensLegend.KIND_DEFENCE:
			return play.defence_lens
		LensLegend.KIND_SEA:
			return play.sea_lens
	return null


## Whether any reading is up: the fade follows the map, not the button pressed.
static func any_lens(play: PlaySession) -> bool:
	for kind: String in ORDER:
		var lens: Variant = lens_for(play, kind)
		if lens != null and bool(lens.active):
			return true
	return false


## The readings never stack: each open lens takes its own toggle down so no
## button claims a mode that is not on.
static func _lower_other_lenses(play: PlaySession, keep: Variant) -> void:
	var lenses: Array = [
		play.lens, play.diplomacy_lens, play.crown_lens, play.defence_lens, play.sea_lens,
	]
	var kinds: Array[String] = [
		LensLegend.KIND_SURVEY, LensLegend.KIND_DIPLOMACY,
		LensLegend.KIND_CROWN_ROAD, LensLegend.KIND_DEFENCE, LensLegend.KIND_SEA,
	]
	for i in lenses.size():
		var other: Variant = lenses[i]
		if other == null or other == keep or not bool(other.active):
			continue
		other.set_active(false)
		play.hud.set_lens(false, kinds[i])


## The reading is the subject while a lens is on: land units ghost back so it
## stays legible, and return to full ink when every lens closes.
static func _fade_field_units(play: PlaySession, active: bool) -> void:
	var alpha: float = 0.22 if active else 1.0
	if play.civilian_layer != null:
		play.civilian_layer.modulate.a = alpha
	if play.army_layer != null:
		play.army_layer.modulate.a = alpha
