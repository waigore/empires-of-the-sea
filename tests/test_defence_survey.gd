extends GdToolsTest
## Defence projection for the military lens: a province is banded by its wall
## first and its garrison second, the garrison is the published order of battle
## (FPN + FPM, no medals and no wounds) of the province's owner, and ground the
## crown has not charted never reaches the reading.

const WIDTH: int = 12
const HEIGHT: int = 4
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3

var _model: MapModel = null
var _armies: Array[ArmyState] = []


func before_each() -> void:
	_model = _build()
	_armies = []


## Four provinces, three columns each: the crown's open ground, a garrisoned
## province in the open, a rival's stone wall and the crown's modern citadel.
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: [], 3: []}
	for y in HEIGHT:
		for x in WIDTH:
			var sea: bool = y == HEIGHT - 1
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.OCEAN if sea else MapModel.Terrain.PLAINS
			)
			if sea:
				model.sea_zone[model.index_of(x, y)] = 0
				continue
			var province_id: int = mini(x / 3, 3)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var names: Array[String] = ["Sevilla", "Córdoba", "Évora", "Lisboa"]
	var owners: Array[int] = [PLAYER, PLAYER, RIVAL, PLAYER]
	var forts: Array[int] = [0, 0, 2, 3]
	var provinces: Array[ProvinceState] = []
	for province_id in 4:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(tiles[0]),
			tiles.size(), owners[province_id], province_id == 0
		)
		province.fort_level = forts[province_id]
		provinces.append(province)
	provinces[1].hospital_level = 1
	model.provinces = provinces
	return model


func _army(owner: int, province: int, types: Array[String]) -> ArmyState:
	var army: ArmyState = ArmyState.muster(
		_armies.size() + 1, owner, province, false, types, 1
	)
	_armies.append(army)
	return army


func _snapshot(visibility: VisibilityModel = null) -> Dictionary:
	return DefenceSurvey.snapshot(_model, _armies, visibility, PLAYER)


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func test_the_wall_outranks_the_garrison() -> void:
	assert_eq(DefenceSurvey.band_for(0, 0), DefenceSurvey.BAND_OPEN)
	assert_eq(DefenceSurvey.band_for(0, 3), DefenceSurvey.BAND_HELD)
	assert_eq(DefenceSurvey.band_for(1, 0), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(2, 4), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(3, 0), DefenceSurvey.BAND_CITADEL)


func test_a_garrison_is_read_on_the_published_order_of_battle() -> void:
	var army: ArmyState = _army(PLAYER, 1, ["musketeers", "pikemen"])
	# Chevrons and wounds are the crown's own reading, not the published one.
	army.regiment_medals["unit_1"] = 4
	army.regiment_health["unit_1"] = 10
	var survey: Dictionary = _snapshot()
	var held: Dictionary = _entry(survey, 1)
	assert_eq(int(held["strength"]), 14, "9 + 5, with no medal multiplier")
	assert_eq(int(held["regiments"]), 2)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_HELD)
	assert_eq(int(held["hospital"]), 1)


func test_an_empty_province_reads_open_and_a_wall_reads_walled() -> void:
	_army(PLAYER, 3, ["guards"])
	var survey: Dictionary = _snapshot()
	assert_eq(String(_entry(survey, 0)["band"]), DefenceSurvey.BAND_OPEN)
	assert_eq(int(_entry(survey, 0)["strength"]), 0)
	var citadel: Dictionary = _entry(survey, 3)
	assert_eq(String(citadel["band"]), DefenceSurvey.BAND_CITADEL)
	assert_eq(int(citadel["fort"]), 3)
	assert_eq(int(citadel["guns"]), 3)
	var rival: Dictionary = _entry(survey, 2)
	assert_eq(String(rival["band"]), DefenceSurvey.BAND_WALLED)
	assert_eq(int(rival["guns"]), 2)


## The garrison is the owner's: a foreign host ashore is a contested ground,
## never part of the province's defence.
func test_a_foreign_host_is_flagged_and_never_counted_as_the_garrison() -> void:
	_army(PLAYER, 2, ["musketeers"])
	var rival: Dictionary = _entry(_snapshot(), 2)
	assert_true(bool(rival["foreign"]))
	assert_eq(int(rival["strength"]), 0)
	assert_eq(int(rival["regiments"]), 0)


func test_counts_and_the_crown_totals() -> void:
	_army(PLAYER, 1, ["musketeers"])
	_army(PLAYER, 3, ["pikemen"])
	var survey: Dictionary = _snapshot()
	var counts: Dictionary = survey["counts"]
	assert_eq(int(counts[DefenceSurvey.BAND_OPEN]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_HELD]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_WALLED]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_CITADEL]), 1)
	var totals: Dictionary = survey["totals"]
	assert_eq(int(totals["provinces"]), 4)
	assert_eq(int(totals["undefended"]), 1, "Sevilla is the crown's only open province")
	assert_eq(int(totals["strength"]), 14, "9 + 5 over the crown's own garrisons")


func test_uncharted_ground_never_reaches_the_reading() -> void:
	_army(PLAYER, 1, ["musketeers"])
	var visibility := VisibilityModel.new()
	visibility.setup(_model, PLAYER)
	for tile: Vector2i in _model.provinces[0].tiles:
		visibility.lower_to(
			_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = _snapshot(visibility)
	assert_true(_entry(survey, 0).is_empty())
	assert_false(_entry(survey, 1).is_empty())
	assert_eq(int(survey["totals"]["provinces"]), 3)


func test_the_hover_line_names_the_strength_the_wall_and_the_hospital() -> void:
	_army(PLAYER, 1, ["musketeers", "pikemen"])
	var held: Dictionary = _entry(_snapshot(), 1)
	var text: String = DefenceSurvey.summary_text(held)
	assert_true(text.contains("14 strength"), text)
	assert_true(text.contains("2 regiments"), text)
	assert_true(text.contains("No wall"), text)
	assert_true(text.contains(HospitalRules.level_name(1)), text)
	var open_line: String = DefenceSurvey.summary_text(_entry(_snapshot(), 0))
	assert_true(open_line.contains("No garrison"), open_line)
	assert_true(open_line.contains("No wall"), open_line)


func test_one_regiment_and_one_gun_read_in_the_singular() -> void:
	_army(PLAYER, 3, ["guards"])
	var text: String = DefenceSurvey.summary_text(_entry(_snapshot(), 3))
	assert_true(text.contains("22 strength · 1 regiment"), text)
	assert_true(text.contains("Fort 3 (3 guns)"), text)


func test_an_embarked_army_defends_nothing() -> void:
	var army: ArmyState = _army(PLAYER, 1, ["musketeers"])
	army.embarked_fleet = 7
	var held: Dictionary = _entry(_snapshot(), 1)
	assert_eq(int(held["strength"]), 0)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_OPEN)
