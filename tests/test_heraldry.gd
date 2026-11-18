extends GdToolsTest
## Every court wears its own arms: one diegetic shield per faction, drawn in the
## crown's own heraldic colour and stable across sessions (wiki: diplomacy § The
## court sheet; DR-20261118-30). The blazon is pure data, so the assertions here
## are tables and tuples; the control is proved where it is mounted (the court
## rows, the open court's page and the dossier head).

const CHARGES: int = 18


## Every court in the catalog has arms the sheet can paint.
func test_every_court_has_arms() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		assert_false(arms.is_empty(), "no arms for %s" % faction["name"])
		assert_eq(String(arms["name"]), String(faction["name"]))


## No two courts wear the same shield: a crest that repeated would be a second
## colour wash and nothing more (REQ-P1-08).
func test_no_two_courts_wear_the_same_shield() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var key: String = "%s|%s|%s" % [
			(arms["field"] as Color).to_html(false),
			String(arms["charge"]),
			String(arms["division"]),
		]
		assert_false(seen.has(key), "%s repeats %s" % [faction["name"], seen.get(key, "")])
		seen[key] = faction["name"]
	assert_eq(seen.size(), FactionCatalog.count())


## A charge and its division are dealt as one disposition, so two courts that
## share a charge are parted by their field's division and never read as one
## shield (the roster outgrows the charge table by a few).
func test_each_court_has_its_own_disposition() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var key: String = "%s|%s" % [String(arms["charge"]), String(arms["division"])]
		assert_false(seen.has(key), "%s repeats %s" % [faction["name"], seen.get(key, "")])
		seen[key] = faction["name"]
	assert_eq(seen.size(), FactionCatalog.count())
	assert_true(FactionCatalog.count() <= CHARGES * 3, "the divisions carry the overflow")


## The field is the crown's own catalog colour, so a province on the chart and
## its court on the sheet can never disagree about who owns it (REQ-P2-03).
func test_the_field_is_the_crowns_own_colour() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_eq(FactionHeraldry.blazon(id)["field"], FactionCatalog.color_of(id))


## A charge never sinks into its field: the tincture is the metal on a dark
## colour and the sheet's ink on a light one (REQ-P1-07).
func test_the_charge_never_sinks_into_its_field() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var field: Color = arms["field"]
		var ink: Color = arms["tincture"]
		assert_true(
			absf(FactionHeraldry.luminance(field) - FactionHeraldry.luminance(ink)) > 0.25,
			"%s's charge is too close to its field" % faction["name"]
		)


## The bordure reads the rank the court sheet already sorts by: a Great Power's
## bright gilt, a Minor Nation's dim one, a Tribe's plain ink (wiki: factions).
func test_the_bordure_reads_the_rank() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_GREAT_POWER)
	for id: int in FactionCatalog.minor_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_MINOR)
	for id: int in FactionCatalog.tribe_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_TRIBE)


## Arms are the court's, not the session's: the same court reads the same shield
## every time it is asked.
func test_arms_are_stable() -> void:
	var first: Dictionary = FactionHeraldry.blazon(2)
	for i in 5:
		assert_eq(FactionHeraldry.blazon(2), first, "the %d read moved" % i)


## A court the catalog does not know wears nothing, and its crest keeps the
## footprint a row reserved for it.
func test_an_unknown_court_wears_nothing() -> void:
	assert_true(FactionHeraldry.blazon(-1).is_empty())
	assert_true(FactionHeraldry.blazon(999).is_empty())
	assert_eq(FactionHeraldry.position_of(999), -1)
	var crest := FactionCrest.of(999)
	add_child(crest)
	assert_true(crest.arms.is_empty())
	assert_eq(crest.custom_minimum_size, Vector2(FactionCrest.ROW_SIZE, FactionCrest.ROW_SIZE))
	crest.free()


## A crest takes the size its sheet asks for and never swallows a tap: the court
## row's own press stays the row's (REQ-P1-05).
func test_a_crest_keeps_its_size_and_lets_the_press_through() -> void:
	var row := FactionCrest.of(1)
	add_child(row)
	assert_eq(row.custom_minimum_size, Vector2(FactionCrest.ROW_SIZE, FactionCrest.ROW_SIZE))
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(String(row.arms["name"]), "England")
	var head := FactionCrest.of(1, FactionCrest.HEAD_SIZE)
	add_child(head)
	assert_eq(head.custom_minimum_size, Vector2(FactionCrest.HEAD_SIZE, FactionCrest.HEAD_SIZE))
	head.free()
	row.free()


# --- the shield's data -------------------------------------------------------


## The shield is a closed heater outline inside the box it was given, so it can
## never spill outside its row.
func test_the_shield_stays_inside_its_box() -> void:
	var centre := Vector2(20, 20)
	var half: float = 16.0
	var outline: PackedVector2Array = FactionCrest.shield_points(centre, half)
	assert_eq(outline.size(), FactionCrest.SHIELD.size())
	for point: Vector2 in outline:
		assert_true(absf(point.x - centre.x) <= half + 0.01, "%s is off the box" % point)
		assert_true(absf(point.y - centre.y) <= half + 0.01, "%s is off the box" % point)


## Every charge the table deals paints at least one mark, in the tincture the
## field earned — so a shield always bears something and never draws blank. The
## tower's gate is the one mark cut in the field, so the tower reads as a tower.
func test_every_charge_paints_at_least_one_mark() -> void:
	var ink: Color = Palette.GOLD_PALE
	var field: Color = Palette.NAVY
	for charge: String in FactionHeraldry.CHARGES:
		var marks: Array[Dictionary] = FactionCrest.charge_marks(
			charge, Vector2(24, 24), 12.0, ink, field
		)
		assert_true(marks.size() > 0, "%s paints nothing" % charge)
		var inked: int = 0
		for mark: Dictionary in marks:
			assert_true(
				["rect", "poly", "line", "polyline", "arc", "circle"].has(String(mark["kind"])),
				"%s's mark is not a shape the painter draws" % charge
			)
			assert_true(
				mark["color"] == ink or mark["color"] == field,
				"%s's mark is in neither the tincture nor the field" % charge
			)
			if mark["color"] == ink:
				inked += 1
		assert_true(inked > 0, "%s bears no ink at all" % charge)


## A charge the table does not know still draws a roundel rather than nothing.
func test_an_unknown_charge_still_paints() -> void:
	var marks: Array[Dictionary] = FactionCrest.charge_marks(
		"not_a_charge", Vector2(10, 10), 6.0, Palette.INK, Palette.PAPER
	)
	assert_eq(marks.size(), 1)
	assert_eq(String(marks[0]["kind"]), "circle")


## The division parts a field with the party colour, and a plain field takes no
## line at all.
func test_the_division_parts_the_field() -> void:
	assert_eq(FactionCrest.division_marks(Vector2(10, 10), 8.0, Palette.GOLD, "plain").size(), 0)
	assert_eq(
		FactionCrest.division_marks(Vector2(10, 10), 8.0, Palette.GOLD, "quarterly").size(), 2
	)
	var bend: Array[Dictionary] = FactionCrest.division_marks(
		Vector2(10, 10), 8.0, Palette.GOLD, "per_bend"
	)
	assert_eq(bend.size(), 1)
	assert_eq(String(bend[0]["kind"]), "poly")


## Re-arming a crest for another court repaints it rather than stacking a second
## shield: the dossier's head keeps one control over every open (REQ-P4-04).
func test_a_crest_re_arms_for_another_court() -> void:
	var crest := FactionCrest.of(1)
	add_child(crest)
	crest.set_faction(2)
	assert_eq(crest.arms, FactionHeraldry.blazon(2))
	assert_eq(String(crest.arms["name"]), "France")
	crest.set_faction(-1)
	assert_true(crest.arms.is_empty())
	crest.free()


# --- the three surfaces that wear the arms -----------------------------------


## Every court row wears its own arms before its name, one shield per court, so a
## crown finds a court by sight (REQ-P1-07, REQ-P1-08).
func test_every_court_row_wears_its_own_arms() -> void:
	var panel: DiplomacyPanel = _court_panel()
	var crests: Array[FactionCrest] = []
	for node: Node in panel._list.find_children("*", "FactionCrest", true, false):
		crests.append(node as FactionCrest)
	var rows: int = 0
	for node: Node in panel._list.get_children():
		if node is HBoxContainer:
			rows += 1
	assert_eq(crests.size(), rows, "one shield per court row")
	assert_true(rows > 1, "the sheet lists more than one court")
	var seen: Dictionary = {}
	for crest: FactionCrest in crests:
		var id: int = int(crest.arms.get("faction", -1))
		assert_false(seen.has(id), "a court wears one shield, not two")
		seen[id] = true
		assert_eq(crest.arms["field"], FactionCatalog.color_of(id), "the chart's own colour")
	panel.free()


## The open court's page wears the arms of the court it names, over the name.
func test_the_open_courts_page_wears_the_arms_it_names() -> void:
	var panel: DiplomacyPanel = _court_panel()
	panel.select_faction(6)
	var found: FactionCrest = null
	for node: Node in panel._detail.find_children("*", "FactionCrest", true, false):
		found = node as FactionCrest
	assert_not_null(found, "the open court shows its shield")
	assert_eq(found.arms, FactionHeraldry.blazon(6), "Genoa's own arms")
	assert_true(_has_text(panel._detail, "Genoa"))
	panel.free()


## The dossier's head wears the arms of the court it is open on, and re-arms for
## the next court rather than stacking a second shield (REQ-P4-04).
func test_the_dossier_head_wears_the_courts_arms() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var sheet := CourtDossierScreen.new()
	add_child(sheet)
	sheet.show_for(state, null, 0, 1)
	assert_eq(sheet._arms.arms, FactionHeraldry.blazon(1), "England's arms")
	sheet.show_for(state, null, 0, 6)
	assert_eq(sheet._arms.arms, FactionHeraldry.blazon(6), "Genoa's arms after")
	sheet.free()


## A court sheet with the crown's own relations, mounted the way the HUD mounts
## it: the list and the open court's page, no chart behind them.
func _court_panel() -> DiplomacyPanel:
	var state := DiplomacyState.new()
	state.initialize(1)
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, 0, 2500)
	return panel


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false
