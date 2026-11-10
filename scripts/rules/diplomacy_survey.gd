class_name DiplomacySurvey
extends RefCounted
## Standing projection for the diplomatic lens (wiki: diplomacy § Relation Model).
## Pure read of the political map: every charted land tile is banded by its
## owner's standing toward the human court, and the bands are returned as merged
## horizontal runs so the lens draws a few rects, not one per tile
## (REQ-P3-03, REQ-P4-01).
##
## Bands are the four readings the key teaches: `self` (blue), `friendly`
## (green: a friendly or allied relation, a formal alliance, or our colony),
## `neutral` (grey) and `war` (red). Unknown ground never contributes a run, so
## the lens cannot leak a court the player has not met.

const BAND_SELF: String = "self"
const BAND_FRIENDLY: String = "friendly"
const BAND_NEUTRAL: String = "neutral"
const BAND_WAR: String = "war"
const BANDS: Array[String] = [BAND_SELF, BAND_FRIENDLY, BAND_NEUTRAL, BAND_WAR]

const BAND_LABELS: Dictionary = {
	BAND_SELF: "Your realm",
	BAND_FRIENDLY: "Friendly or allied",
	BAND_NEUTRAL: "Neutral",
	BAND_WAR: "At war",
}


## Runs per band in tile coordinates, one entry per charted province, and the
## province/tile counts each band holds.
static func snapshot(
	model: MapModel,
	state: DiplomacyState,
	player: int,
	visibility: VisibilityModel = null
) -> Dictionary:
	var result: Dictionary = {
		"runs": _empty_runs(),
		"provinces": [] as Array[Dictionary],
		"counts": _empty_counts(),
		"tiles": _empty_counts(),
	}
	if model == null:
		return result
	_collect_runs(result, model, state, player, visibility)
	_collect_provinces(result, model, state, player, visibility)
	return result


## Standing of one owner toward `player`. Tiles and provinces share this rule,
## so the wash and the hover line cannot disagree.
static func band_for(state: DiplomacyState, player: int, owner: int) -> String:
	if owner == MapModel.NO_ID:
		return BAND_NEUTRAL
	if owner == player:
		return BAND_SELF
	if state == null:
		return BAND_NEUTRAL
	if state.colony_of(owner) == player:
		return BAND_FRIENDLY
	var relation: DiplomacyRelation = state.relation(player, owner)
	if relation == null:
		return BAND_NEUTRAL
	if relation.at_war:
		return BAND_WAR
	if relation.formal_alliance:
		return BAND_FRIENDLY
	# The friendly and allied relation bands (51–100) read the same green.
	var level: String = relation.level()
	if level == "Friendly" or level == "Allied":
		return BAND_FRIENDLY
	return BAND_NEUTRAL


static func band_label(band: String) -> String:
	return String(BAND_LABELS.get(band, BAND_LABELS[BAND_NEUTRAL]))


## Short hover phrase for one province: "Your realm", "Allied", "At war"…
static func standing_text(state: DiplomacyState, player: int, owner: int) -> String:
	if owner == MapModel.NO_ID:
		return "Unclaimed"
	var band: String = band_for(state, player, owner)
	if band == BAND_SELF:
		return "Your realm"
	if band == BAND_WAR:
		return "At war"
	if band == BAND_FRIENDLY:
		if state == null:
			return "Friendly"
		if state.colony_of(owner) == player:
			return "Your colony"
		var relation: DiplomacyRelation = state.relation(player, owner)
		if relation != null and relation.formal_alliance:
			return "Allied"
		return "Friendly"
	if state != null and state.relation(player, owner) == null:
		return "No court"
	return "Neutral"


# --- collection --------------------------------------------------------------


## Row-major run merge: consecutive tiles of one band become one Rect2, so a
## 10k-tile map costs a few hundred draw calls instead of ten thousand.
static func _collect_runs(
	result: Dictionary,
	model: MapModel,
	state: DiplomacyState,
	player: int,
	visibility: VisibilityModel
) -> void:
	var runs: Dictionary = result["runs"]
	var tiles: Dictionary = result["tiles"]
	# One lookup per crown, not per tile: a 10k-tile map stays cheap on turn end.
	var bands: Dictionary = _band_table(state, player)
	for y in model.height:
		var x: int = 0
		while x < model.width:
			var band: String = _tile_band(model, bands, visibility, x, y)
			if band.is_empty():
				x += 1
				continue
			var start: int = x
			x += 1
			while x < model.width:
				if _tile_band(model, bands, visibility, x, y) != band:
					break
				x += 1
			var span: int = x - start
			var band_runs: Array = runs[band]
			band_runs.append(Rect2(float(start), float(y), float(span), 1.0))
			tiles[band] = int(tiles[band]) + span


## Band for one land tile, or "" when the tile must not be painted (sea,
## unclaimed-by-generation ground, or ground the crown has not charted).
static func _tile_band(
	model: MapModel,
	bands: Dictionary,
	visibility: VisibilityModel,
	x: int,
	y: int
) -> String:
	if not model.is_land(x, y):
		return ""
	if model.province_at(x, y) == MapModel.NO_ID:
		return ""
	if visibility != null and visibility.level_at(x, y) == VisibilityModel.Level.UNKNOWN:
		return ""
	return String(bands.get(model.owner_at(x, y), BAND_NEUTRAL))


## Standing of every configured crown plus unclaimed ground, so the tile pass
## never formats a pair key per tile.
static func _band_table(state: DiplomacyState, player: int) -> Dictionary:
	var table: Dictionary = {MapModel.NO_ID: BAND_NEUTRAL}
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		table[id] = band_for(state, player, id)
	return table


static func _collect_provinces(
	result: Dictionary,
	model: MapModel,
	state: DiplomacyState,
	player: int,
	visibility: VisibilityModel
) -> void:
	var counts: Dictionary = result["counts"]
	var provinces: Array = result["provinces"]
	for province: ProvinceState in model.provinces:
		var charted: int = VisibilityModel.Level.FULLY_VISIBLE
		if visibility != null:
			charted = visibility.province_visibility(province.id)
		if charted == VisibilityModel.Level.UNKNOWN:
			continue
		var band: String = band_for(state, player, province.owner)
		counts[band] = int(counts[band]) + 1
		provinces.append({
			"id": province.id,
			"name": province.name,
			"owner": province.owner,
			"band": band,
			"charted": charted,
			"standing": standing_text(state, player, province.owner),
		})


static func _empty_runs() -> Dictionary:
	var runs: Dictionary = {}
	for band: String in BANDS:
		runs[band] = [] as Array[Rect2]
	return runs


static func _empty_counts() -> Dictionary:
	var counts: Dictionary = {}
	for band: String in BANDS:
		counts[band] = 0
	return counts
