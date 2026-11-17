extends GdToolsTest
## The civilian dossier's two halves read out of the sheet: [CivilianPanelDetail]
## words the ground rows and [CivilianPanelStatus] the standing lines, so the
## panel only composes them (REQ-P3-01, REQ-P3-03).

const Fixture = preload("res://tests/civilian_fixture.gd")
const PLAYER: int = 0

## The ground rows the sheet prints are a pure read, so the module answers with
## words alone and the panel only composes them (REQ-P3-01, REQ-P3-03).
func test_the_dossier_ground_rows_read_the_tile() -> void:
	var model: MapModel = Fixture.build()
	var builder: CivilianState = CivilianState.create(
		1, PLAYER, "builder", Fixture.TIMBER_TILE
	)
	var rows: Array[Array] = CivilianPanelDetail.rows(
		model, builder, LandWorks.new(), {}
	)
	var by_caption: Dictionary = {}
	for row: Array in rows:
		by_caption[String(row[0])] = String(row[1])
	assert_eq(
		String(by_caption.get("Tile", "")),
		"%d, %d" % [Fixture.TIMBER_TILE.x, Fixture.TIMBER_TILE.y]
	)
	assert_eq(
		String(by_caption.get("Held by", "")),
		FactionCatalog.name_of(PLAYER)
	)
	assert_true(by_caption.has("Province") and by_caption.has("Works"), "the ground reads")
	assert_false(by_caption.has("Tradecraft"), "a builder keeps no tradecraft row")
	assert_false(by_caption.has("Survey"), "and no survey row")
	var spy: CivilianState = CivilianState.create(
		2, PLAYER, "spy", Fixture.BARE_TILE
	)
	var tradecraft: String = _detail_of(spy, model, "Tradecraft")
	assert_eq(
		tradecraft,
		"No screen up — only the counter-espionage order covers your land"
	)
	# A rival reading the sheet reads the ground through its own survey record,
	# so a Prospected mark the crew's owner holds never shows on the rival's
	# sheet (wiki: fog-and-exploration § Prospecting; DR-20261111-26).
	var works := LandWorks.new()
	var owner_ground: Array[Array] = CivilianPanelDetail.rows(model, builder, works, {})
	assert_false(_row_of(owner_ground, "Works").contains("Prospected"), "unprospected")
	works.set_prospected(PLAYER, model, Fixture.TIMBER_TILE)
	owner_ground = CivilianPanelDetail.rows(model, builder, works, {})
	assert_true(
		_row_of(owner_ground, "Works").contains("Prospected"), "the owner sees it"
	)
	var rival_ground: Array[Array] = CivilianPanelDetail.rows(
		model, builder, works, {}, 5
	)
	assert_false(
		_row_of(rival_ground, "Works").contains("Prospected"), "the rival does not"
	)


## The standing line and the pick's wording are one module's job: the panel adds
## the capitals, the module answers the words (REQ-P5-06, DR-20261117-06).
func test_the_dossier_standing_lines_are_plain_words() -> void:
	var model: MapModel = Fixture.build()
	var builder: CivilianState = CivilianState.create(
		1, PLAYER, "builder", Fixture.TIMBER_TILE
	)
	assert_eq(
		CivilianPanelStatus.text(model, builder, PLAYER), "Idle — choose an order below."
	)
	assert_eq(
		CivilianPanelStatus.text(model, builder, 9), "Enemy colours · no orders"
	)
	builder.start_work("build_improvement", builder.tile, 2)
	assert_eq(
		CivilianPanelStatus.text(model, builder, PLAYER),
		"Build improvement · 2 turns left."
	)
	assert_eq(CivilianPanelStatus.pick_line({}), "", "no pick, no line")
	assert_eq(
		CivilianPanelStatus.pick_line({"pick": {"line": "the court would raise a road"}}),
		"The court would raise a road."
	)


func _detail_of(unit: CivilianState, model: MapModel, caption: String) -> String:
	for row: Array in CivilianPanelDetail.rows(model, unit, LandWorks.new(), {}):
		if String(row[0]) == caption:
			return String(row[1])
	return ""


func _row_of(rows: Array[Array], caption: String) -> String:
	for row: Array in rows:
		if String(row[0]) == caption:
			return String(row[1])
	return ""
