class_name MapPlayLens
extends RefCounted
## The chart's five readings: mounting them on the region on screen, raising
## and lowering them, the bar seal's walk, the one key cartouche and the unit
## fade that keeps a reading legible (REQ-P5-03, REQ-P1-07). Operates on
## PlaySession — the screen stays the Node host (REQ-P3-02). Kept out of
## MapPlayInput so the tap, selection and hover module stays under the 400-line
## soft bar (REQ-P3-01); kept out of MapPlaySetup so the screen's boot owns no
## reading of its own (REQ-P3-01).

## The readings in the order the bar's seal walks them (REQ-P5-03).
const ORDER: Array = [
	LensLegend.KIND_SURVEY,
	LensLegend.KIND_DIPLOMACY,
	LensLegend.KIND_CROWN_ROAD,
	LensLegend.KIND_DEFENCE,
	LensLegend.KIND_SEA,
]

## The lens layers the chart holds beyond the two `bind_views` takes: the
## screen's scene tree names them, this module alone resolves them, so a new
## reading never widens MapScreen.bind_views (REQ-P3-02).
const CROWN_ROAD_PATH: String = "World/CrownRoadLens"
const DEFENCE_PATH: String = "World/DefenceLens"
const SEA_PATH: String = "World/SeaLens"


# --- mounting ----------------------------------------------------------------


## Rebuilds every reading against the region on screen: what the chart holds,
## the fog, the works and the wars. Called on a region load, a turn's close and
## a load, so each lens is one projection over the state it reads.
static func mount_all(play: PlaySession) -> void:
	mount_survey(play)
	mount_diplomacy(play)
	mount_crown_road(play)
	mount_defence(play)
	mount_sea(play)


## Survey lens data follows the region on screen, the works just completed and
## the court's sealed coasts. Rebuilding also refreshes the extraction caps the
## plaque totals use. The court's own picks ride the reading, so the chart marks
## the ground its planner would send each idle crew to (DR-20261117-07).
static func mount_survey(play: PlaySession) -> void:
	var lens: ResourceLens = play.lens
	if lens == null:
		return
	lens.pick_source = func() -> Dictionary:
		return MapPlayCivilianPick.picks(play, play.player_faction)
	lens.build(
		play.model, play.land_works, play.civilian_layer.units,
		play.player_faction, play.visibility, play.capital_tile,
		play.tech_caps(), MapPlayBlockades.crown(play)
	)
	lens.watch(play.civilian_layer, play.overlay)


## Political wash follows the region, the fog and every court that moved. The
## snapshot is cheap (pure projection), but it still runs on events only.
static func mount_diplomacy(play: PlaySession) -> void:
	var lens: DiplomacyLens = play.diplomacy_lens
	if lens == null:
		return
	lens.build(play.model, play.diplomacy, play.player_faction, play.visibility)
	lens.watch(play.overlay)


## Crown-road reading follows the region, the works, the fog and the war's
## sealed coasts. The projection is one connectivity pass, so it still runs on
## events only, never per frame.
static func mount_crown_road(play: PlaySession) -> void:
	if play.crown_lens == null:
		play.crown_lens = _from_host(play, CROWN_ROAD_PATH) as CrownRoadLens
	var lens: CrownRoadLens = play.crown_lens
	if lens == null:
		return
	lens.build(
		play.model, play.land_works, play.player_faction, play.visibility,
		play.capital_tile, MapPlayBlockades.crown(play)
	)
	lens.watch(play.civilian_layer, play.overlay)


## The defence reading follows the region, its roster and the fog. The snapshot
## is one walk over the province list, so it runs on events only.
static func mount_defence(play: PlaySession) -> void:
	if play.defence_lens == null:
		play.defence_lens = _from_host(play, DEFENCE_PATH) as DefenceLens
	var lens: DefenceLens = play.defence_lens
	if lens == null:
		return
	lens.build(
		play.model, play.army_layer, play.visibility, play.player_faction
	)
	lens.watch(play.overlay)


## The sea reading follows the region's roster, the fog and the court's wars: it
## reads what each zone holds and whether the turn resolves a battle there. The
## war test is the one the naval turn resolves the zones with and the view is the
## chart's own `drawn`/`read` answer, so a plate can never name a fight or a
## weight the resolver would not (REQ-P2-03).
static func mount_sea(play: PlaySession) -> void:
	if play.sea_lens == null:
		play.sea_lens = _from_host(play, SEA_PATH) as SeaLens
	var lens: SeaLens = play.sea_lens
	if lens == null:
		return
	var war := func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)
	lens.build(
		play.model, play.ship_layer, play.visibility, play.player_faction,
		war, MapPlayFleets.view_filter(play)
	)
	lens.watch(play.overlay)


## The chart's own layer for a reading the screen did not hand the session at
## bind time; null when the host is not mounted (a rules-only suite).
static func _from_host(play: PlaySession, path: String) -> Node:
	if play.screen.host == null:
		return null
	return play.screen.host.get_node_or_null(path)


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
