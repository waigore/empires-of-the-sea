extends GdToolsTest
## Standing projection for the diplomatic lens: own/friendly/neutral/war bands,
## the fog rule (unknown ground is never painted) and the run merge the view
## draws from.

const Fixture = preload("res://tests/map_fixture.gd")

var _model: MapModel = null
var _state: DiplomacyState = null
var _player: int = FactionCatalog.PLAYER_FACTION


func before_each() -> void:
	_model = Fixture.region()
	_state = DiplomacyState.new()
	_state.initialize(1)


func test_own_provinces_read_as_self() -> void:
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	var own: Dictionary = _entry(survey, _owned_province())
	assert_eq(String(own["band"]), DiplomacySurvey.BAND_SELF)
	assert_eq(String(own["standing"]), "Your realm")
	assert_gt(int(survey["counts"]["self"]), 0)
	assert_gt(int(survey["tiles"]["self"]), 0)
	assert_false((survey["runs"]["self"] as Array).is_empty())


func test_war_reads_red() -> void:
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.at_war = true
	relation.normalize()
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	var entry: Dictionary = _entry(survey, _province_of(owner))
	assert_eq(String(entry["band"]), DiplomacySurvey.BAND_WAR)
	assert_eq(String(entry["standing"]), "At war")
	assert_gt(int(survey["counts"]["war"]), 0)
	assert_gt(int(survey["tiles"]["war"]), 0)


func test_allied_and_friendly_courts_read_green() -> void:
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(60.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_FRIENDLY
	)
	relation.set_score(80.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_FRIENDLY
	)
	# A formal alliance is green even while the score sits in the neutral band.
	relation.set_score(50.0)
	relation.formal_alliance = true
	assert_eq(String(_entry(
		DiplomacySurvey.snapshot(_model, _state, _player), _province_of(owner)
	)["band"]), DiplomacySurvey.BAND_FRIENDLY)


func test_neutral_covers_mid_scores_and_unmet_courts() -> void:
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(50.0)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, owner), DiplomacySurvey.BAND_NEUTRAL
	)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, MapModel.NO_ID),
		DiplomacySurvey.BAND_NEUTRAL
	)
	assert_eq(
		DiplomacySurvey.standing_text(_state, _player, MapModel.NO_ID), "Unclaimed"
	)


func test_a_colony_reads_friendly() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	_state.set_colony(tribe, _player)
	assert_eq(
		DiplomacySurvey.band_for(_state, _player, tribe), DiplomacySurvey.BAND_FRIENDLY
	)
	assert_eq(
		DiplomacySurvey.standing_text(_state, _player, tribe), "Your colony"
	)


func test_unknown_ground_is_never_painted() -> void:
	var visibility := VisibilityModel.new()
	visibility.setup(_model, _player)
	for province: ProvinceState in _model.provinces:
		for tile: Vector2i in province.tiles:
			visibility.lower_to(
				_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
			)
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player, visibility)
	assert_true((survey["provinces"] as Array).is_empty())
	for band: String in DiplomacySurvey.BANDS:
		assert_true((survey["runs"][band] as Array).is_empty())
		assert_eq(int(survey["tiles"][band]), 0)


func test_runs_merge_rows_and_cover_the_tiles() -> void:
	var survey: Dictionary = DiplomacySurvey.snapshot(_model, _state, _player)
	for band: String in DiplomacySurvey.BANDS:
		var covered: int = 0
		for raw: Variant in survey["runs"][band]:
			var run: Rect2 = raw
			assert_almost_eq(run.size.y, 1.0, 0.001, "one run is one row")
			assert_gt(int(run.size.x), 0)
			covered += int(run.size.x)
			for x in int(run.size.x):
				assert_true(
					_model.is_land(int(run.position.x) + x, int(run.position.y)),
					"a run never paints sea"
				)
		assert_eq(int(survey["tiles"][band]), covered)


func test_standing_text_names_allied_and_neutral() -> void:
	var owner: int = _foreign_owner()
	var relation: DiplomacyRelation = _state.ensure_relation(_player, owner, 1)
	relation.set_score(80.0)
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Friendly")
	relation.formal_alliance = true
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Allied")
	relation.formal_alliance = false
	relation.set_score(50.0)
	assert_eq(DiplomacySurvey.standing_text(_state, _player, owner), "Neutral")


# --- helpers -----------------------------------------------------------------


func _owned_province() -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner == _player:
			return province.id
	return -1


func _foreign_owner() -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner != _player and province.owner != MapModel.NO_ID:
			return province.owner
	return MapModel.NO_ID


func _province_of(owner: int) -> int:
	for province: ProvinceState in _model.provinces:
		if province.owner == owner:
			return province.id
	return -1


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}
