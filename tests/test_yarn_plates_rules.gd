extends GdToolsTest
## One boot for yarn dialogue, symbol plates and espionage rules. Merged from
## test_dialogue_yarn, test_symbol_plates and test_espionage so coverage pays
## one instrumentation pass instead of three.

# --- test_dialogue_yarn ---

## The court's authored voice: the Yarn runtime that reads a script, the locale
## keys a translation follows, and the standing word the panel shows (wiki:
## dialogue-content-and-yarn; DR-20261113-01). Pure data in, lines out — no node
## tree, no randomness.

const SCRIPT: String = """
// A gate, a set and two nodes: everything the runtime reads, in one program.
title: gate
tags: category:reactive mood:calculating
---
Will you sign? #firm
<<if $score >= 80>>
Warm.
<<elseif $score >= 40>>
Civil.
<<else>>
Cold.
<<endif>>
<<set $seen = true>>
Seen: {$seen} at {$score + 1}.
===

title: signed
tags: category:diplomatic mood:pleased
---
It is signed.
===

title: ask
---
Will you sign?
-> Accept <<jump signed>> #bold
-> Refuse
===
"""


func _program() -> Dictionary:
	return YarnScript.parse(SCRIPT)


## Every beat the runner reads from one node, as plain text; options are listed
## as `-> <text>` so a test can read the whole scene in order.
func _read(source: String, node: String, vars: Dictionary = {}) -> Array[String]:
	var program := YarnScript.parse(source)
	var runner := YarnRunner.new(program, vars)
	var beats: Array[String] = []
	if not runner.start(node):
		return beats
	for _step in 40:
		var beat: Dictionary = runner.advance()
		if String(beat.get("kind", "")) == "line":
			beats.append(String(beat["text"]))
			continue
		if String(beat.get("kind", "")) == "options":
			for option: Variant in beat.get("options", []):
				beats.append("-> %s" % String((option as Dictionary).get("text", "")))
			runner.choose(0)
			continue
		break
	return beats


# --- the parser -------------------------------------------------------------

func test_a_node_reads_its_title_tags_lines_and_options() -> void:
	var program := _program()
	assert_true(bool(program["ok"]), String(program.get("error", "")))
	assert_eq(YarnScript.node_names(program), ["ask", "gate", "signed"] as Array[String])
	var node: Dictionary = program["nodes"]["gate"]
	assert_eq(node["tags"], ["category:reactive", "mood:calculating"] as Array[String])
	var steps: Array = node["steps"]
	assert_eq(String(steps[0]["kind"]), "line")
	assert_eq(String(steps[0]["text"]), "Will you sign?")
	assert_eq(steps[0]["tags"], ["firm"] as Array[String])
	assert_eq(String(steps[1]["kind"]), "if")
	var option_steps: Array = program["nodes"]["ask"]["steps"]
	assert_eq(String(option_steps[1]["kind"]), "options")
	assert_eq((option_steps[1]["options"] as Array).size(), 2, "two options, one group")
	assert_eq(String(option_steps[1]["options"][0]["command"]), "jump signed")
	assert_eq(String(option_steps[1]["options"][1]["command"]), "", "a bare option is silent")


func test_a_body_that_never_ends_is_refused() -> void:
	var broken := "title: gate\n---\nWill you sign?\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]), "a node without === is refused")
	assert_true(String(program["error"]).contains("gate"), String(program["error"]))


func test_an_unclosed_condition_is_refused() -> void:
	var broken := "title: gate\n---\n<<if $x>>\nYes.\n===\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("endif"), String(program["error"]))


func test_an_unreadable_condition_is_refused() -> void:
	var broken := "title: gate\n---\n<<if $x ???>>\nYes.\n<<endif>>\n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


func test_an_unknown_command_is_refused() -> void:
	var broken := "title: gate\n---\n<<teleport somewhere>>\n===\n"
	var program := YarnScript.parse(broken)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("teleport"), String(program["error"]))


func test_an_option_without_text_is_refused() -> void:
	var broken := "title: gate\n---\n-> \n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


func test_a_body_without_a_title_is_refused() -> void:
	assert_false(bool(YarnScript.parse("---\nA line.\n===\n")["ok"]))


func test_the_same_title_twice_is_refused() -> void:
	var twice := "title: gate\n---\nA.\n===\ntitle: gate\n---\nB.\n===\n"
	assert_false(bool(YarnScript.parse(twice)["ok"]))


# --- expressions ------------------------------------------------------------

func test_an_expression_reads_numbers_variables_and_flags() -> void:
	var vars: Dictionary = {"score": 70, "flag": true, "name": "Lisboa"}
	var cases: Dictionary = {
		"$score >= 40 and $flag": true,
		"not $flag or $score < 10": false,
		"($score + 10) * 2 == 160": true,
		"$score % 2 == 0": true,
		"$name == 'Lisboa'": true,
		"$missing": null,
		"$score / 0": 0,
		"not ($score < 40)": true,
	}
	for text: String in cases.keys():
		var ast := YarnExpr.parse(text)
		assert_false(ast.is_empty(), "'%s' parses" % text)
		assert_eq(YarnExpr.evaluate(ast, vars), cases[text], "'%s' reads" % text)


func test_a_malformed_expression_is_refused() -> void:
	for text: String in ["$x ==", "1 +", "and 2", "($x", "unknown_word", "$", "'unclosed"]:
		assert_true(YarnExpr.parse(text).is_empty(), "'%s' is refused" % text)


func test_arithmetic_and_string_joins_read() -> void:
	var vars: Dictionary = {"score": 70, "name": "Lisboa"}
	var cases: Dictionary = {
		"'a' + 'b' == 'ab'": true,
		"-$score == -70": true,
		"$score >= 70 and $score <= 70": true,
		"$score != 71": true,
		"2.5 + 0.5 == 3": true,
		"'12' < 20": true,
		"$score % 4 == 2": true,
		"$name + '!' == 'Lisboa!'": true,
	}
	for text: String in cases.keys():
		var ast := YarnExpr.parse(text)
		assert_false(ast.is_empty(), "'%s' parses" % text)
		assert_eq(YarnExpr.evaluate(ast, vars), cases[text], "'%s' reads" % text)
	assert_true(YarnExpr.truthy("x"), "a non-empty string is true")
	assert_false(YarnExpr.truthy(""), "an empty string is not")
	assert_true(YarnExpr.truthy(1), "a number is true")
	assert_false(YarnExpr.truthy(null), "a missing value is false")


# --- the runner -------------------------------------------------------------

func test_the_runner_speaks_lines_in_order() -> void:
	assert_eq(
		_read(SCRIPT, "signed"), ["It is signed."] as Array[String], "one line, one beat"
	)


func test_a_set_feeds_the_next_line() -> void:
	assert_eq(
		_read(SCRIPT, "gate", {"score": 50}),
		["Will you sign?", "Civil.", "Seen: true at 51."] as Array[String],
		"the set is read back through interpolation"
	)


func test_a_condition_picks_its_branch() -> void:
	assert_eq(_read(SCRIPT, "gate", {"score": 90})[1], "Warm.", "the first branch")
	assert_eq(_read(SCRIPT, "gate", {"score": 40})[1], "Civil.", "the elseif branch")
	assert_eq(_read(SCRIPT, "gate", {"score": 1})[1], "Cold.", "the else branch")
	assert_eq(
		_read(SCRIPT, "gate", {})[1], "Cold.", "a variable a script never set is false"
	)


func test_an_option_group_waits_for_the_choice() -> void:
	assert_eq(
		_read(SCRIPT, "ask"),
		["Will you sign?", "-> Accept", "-> Refuse", "It is signed."] as Array[String],
		"choosing the jump continues in the other node"
	)


func test_an_option_nobody_wrote_is_refused() -> void:
	var runner := YarnRunner.new(_program())
	assert_true(runner.start("ask"))
	assert_eq(String(runner.advance()["kind"]), "line")
	assert_eq(String(runner.advance()["kind"]), "options")
	assert_false(runner.choose(9), "an option nobody wrote is not taken")
	assert_false(runner.at_end(), "the scene waits for a real answer")
	assert_eq(String(runner.advance()["kind"]), "options", "the same options are still on offer")


func test_a_jump_into_a_missing_node_is_reported() -> void:
	var orphan := YarnScript.parse("title: gate\n---\n<<jump nowhere>>\n===\n")
	var runner := YarnRunner.new(orphan)
	assert_true(runner.start("gate"))
	var beat: Dictionary = runner.advance()
	assert_eq(String(beat["kind"]), "error")
	assert_true(String(beat["error"]).contains("nowhere"), String(beat["error"]))


func test_stop_ends_the_scene_without_the_lines_below_it() -> void:
	var stopped := "title: gate\n---\nOne.\n<<stop>>\nTwo.\n===\n"
	assert_eq(_read(stopped, "gate"), ["One."] as Array[String], "the stop is obeyed")


func test_an_unknown_node_cannot_start() -> void:
	assert_false(YarnRunner.new(_program()).start("no_such_node"))


func test_a_declare_is_a_set() -> void:
	var declared := "title: gate\n---\n<<declare $x = 2>>\nCount: {$x}.\n===\n"
	assert_eq(_read(declared, "gate"), ["Count: 2."] as Array[String])


func test_an_option_can_stop_the_scene() -> void:
	var scene := "title: ask\n---\nSign?\n-> Enough <<stop>>\nUnsigned.\n===\n"
	assert_eq(
		_read(scene, "ask"), ["Sign?", "-> Enough"] as Array[String], "the stop ends the scene"
	)


func test_an_unreadable_interpolation_is_left_as_written() -> void:
	var runner := YarnRunner.new(_program())
	assert_eq(runner.interpolate("A {$ } line."), "A {$ } line.", "no expression, no fill")
	assert_eq(runner.interpolate("A plain line."), "A plain line.")
	assert_eq(runner.interpolate("An open {$score line."), "An open {$score line.")


func test_the_runner_names_the_node_it_reads() -> void:
	var runner := YarnRunner.new(_program())
	assert_true(runner.start("signed"))
	assert_eq(runner.node_name(), "signed")
	assert_false(runner.at_end(), "a node just started is not ended")
	runner.advance()
	assert_true(runner.at_end(), "the last line ends it")


# --- the court's standing word ---------------------------------------------

func test_the_court_speaks_its_standing_word_from_yarn() -> void:
	var program := DialogueYarn.program()
	assert_true(bool(program.get("ok", false)), "the authored source parses")
	assert_eq(
		DialogueYarn.points(),
		[
			"reactive/standing_alliance", "reactive/standing_cold",
			"reactive/standing_friendly", "reactive/standing_neutral",
			"reactive/standing_war",
		] as Array[String],
		"one node per band, keyed as a point"
	)
	for point: String in DialogueYarn.points():
		assert_eq(DialogueYarn.category_for(point), DialogueCatalog.CAT_REACTIVE, point)
		assert_true(DialogueYarn.lines_for(point).size() >= 2, "%s repeats less" % point)
		assert_false(DialogueYarn.moods_for(point).is_empty(), "%s wears a face" % point)
		for mood: Variant in DialogueYarn.moods_for(point):
			assert_true(DialogueMood.MOODS.has(String(mood)), "%s wears a real face" % point)


func test_the_standing_word_is_stable_and_inside_its_variants() -> void:
	for point: String in DialogueYarn.points():
		var lines: Array = DialogueYarn.lines_for(point)
		for salt: int in [0, 7, 131, 1000002]:
			var spoken: String = DialogueYarn.line_for(point, salt)
			assert_true(lines.has(spoken), "%s speaks one of its lines" % point)
			assert_eq(spoken, DialogueYarn.line_for(point, salt), "the same salt, the same word")


func test_the_merged_catalogue_keeps_every_point() -> void:
	assert_eq(
		DialogueCatalog.table().size(),
		DialogueCatalog.POINTS.size() + DialogueEpisodes.POINTS.size()
		+ DialogueAgendaLines.POINTS.size() + DialogueYarn.points().size(),
		"the merged catalogue loses no point"
	)
	for point: String in DialogueYarn.points():
		assert_true(DialogueCatalog.has_point(point), "%s is reachable" % point)
		assert_eq(DialogueCatalog.lines_for(point), DialogueYarn.lines_for(point), point)


func test_an_unknown_point_speaks_nothing() -> void:
	assert_eq(DialogueYarn.line_for("reactive/standing_unknown", 0), "")
	assert_eq(DialogueCatalog.line_for("reactive/standing_unknown", 0), "")
	assert_false(DialogueYarn.has_point("reactive/standing_unknown"))
	assert_eq(DialogueYarn.category_for("reactive/standing_unknown"), "")
	assert_eq(DialogueYarn.lines_for("reactive/standing_unknown"), [])
	assert_eq(DialogueYarn.moods_for("reactive/standing_unknown"), [])


func test_a_line_outside_a_node_is_refused() -> void:
	var stray := "title: gate\n---\nA.\n===\nA stray line.\n"
	var program := YarnScript.parse(stray)
	assert_false(bool(program["ok"]))
	assert_true(String(program["error"]).contains("stray"), String(program["error"]))


func test_a_jump_without_a_node_is_refused() -> void:
	assert_false(bool(YarnScript.parse("title: gate\n---\n<<jump>>\n===\n")["ok"]))


func test_an_option_command_that_is_not_closed_is_refused() -> void:
	var broken := "title: gate\n---\n-> Accept <<jump signed\n===\n"
	assert_false(bool(YarnScript.parse(broken)["ok"]))


# --- localization keys ------------------------------------------------------

## The shipped tongue is content (DR-20261113-06): `assets/locales/fr.po` answers
## every authored variant, keyed by what [method DialogueLocale.line_key] builds,
## so a reader whose OS speaks French reads the court in French and an English
## reader reads exactly what he read before. The suite holds the file to the
## catalogue: a rewritten or dropped point fails here rather than leaving a
## French court with an English line.

## Every variant the shipped file answers, as `DialoguePoint/<point>/<variant>`.
func _shipped_keys() -> Array[String]:
	var found: Array[String] = []
	var text := FileAccess.get_file_as_string(DialogueLocale.SHIPPED)
	var re := RegEx.new()
	re.compile("msgid \"(DialoguePoint/[^\"]+)\"")
	for row in re.search_all(text):
		found.append(row.get_string(1))
	return found


## Every authored variant, as `[point, index, english]` — the catalogue as the
## file must answer it.
func _authored_variants() -> Array:
	var found: Array = []
	for point in DialogueCatalog.points():
		var lines := DialogueCatalog.lines_for(point)
		for index in range(lines.size()):
			found.append([point, index, String(lines[index])])
	return found


func test_a_line_carries_a_stable_translation_key() -> void:
	assert_eq(
		DialogueLocale.line_key("reactive/standing_cold", 1),
		"DialoguePoint/reactive/standing_cold/1",
		"the key names the point and the variant"
	)


func test_an_unanswered_key_falls_back_to_the_authored_line() -> void:
	DialogueLocale.set_locale("fr")
	assert_eq(
		DialogueLocale.line("probe/absent", 0, "We have little to say."),
		"We have little to say.",
		"a key the file does not answer keeps the source"
	)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_true(DialogueLocale.locales().has(DialogueLocale.SOURCE_LOCALE))


func test_the_locale_can_be_switched_and_read_back() -> void:
	DialogueLocale.set_locale("fr")
	assert_eq(DialogueLocale.locale(), "fr", "the game reads the locale it was given")
	DialogueLocale.set_locale("  ")
	assert_eq(DialogueLocale.locale(), "fr", "an empty code changes nothing")
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(DialogueLocale.locale(), DialogueLocale.SOURCE_LOCALE)


func test_a_translation_overrides_the_authored_line() -> void:
	var table := Translation.new()
	table.locale = "fr"
	table.add_message(DialogueLocale.line_key("probe/absent", 0), "Nous n'avons rien à dire.")
	TranslationServer.add_translation(table)
	DialogueLocale.set_locale("fr")
	assert_eq(
		DialogueLocale.line("probe/absent", 0, "We have little to say."),
		"Nous n'avons rien à dire."
	)
	assert_eq(
		DialogueLocale.line("probe/absent", 1, "Our clerks record your name."),
		"Our clerks record your name.",
		"a variant with no translation keeps the source"
	)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	TranslationServer.remove_translation(table)
	assert_eq(
		DialogueLocale.line("probe/absent", 0, "We have little to say."),
		"We have little to say.",
		"the source line comes back"
	)


func test_the_shipped_tongue_answers_every_authored_variant() -> void:
	DialogueLocale.set_locale("fr")
	var silent: Array[String] = []
	for row: Array in _authored_variants():
		var point := String(row[0])
		var index := int(row[1])
		var english := String(row[2])
		var french := DialogueLocale.line(point, index, english)
		if french == english or french.is_empty() or french == DialogueLocale.line_key(point, index):
			silent.append(DialogueLocale.line_key(point, index))
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(silent, [], "every authored variant reads French")


func test_the_shipped_tongue_keeps_the_names_a_line_hands_in() -> void:
	DialogueLocale.set_locale("fr")
	var broken: Array[String] = []
	for row: Array in _authored_variants():
		var english := String(row[2])
		var french := DialogueLocale.line(String(row[0]), int(row[1]), english)
		for holder in ["{speaker}", "{other}"]:
			if english.count(holder) != french.count(holder):
				broken.append(DialogueLocale.line_key(String(row[0]), int(row[1])))
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(broken, [], "a name the line hands in survives the translation")


func test_the_shipped_tongue_carries_no_stale_key() -> void:
	var stale: Array[String] = []
	var keys := _shipped_keys()
	for key in keys:
		var point := key.substr(DialogueLocale.KEY_PREFIX.length() + 1)
		var index := int(point.substr(point.rfind("/") + 1))
		point = point.substr(0, point.rfind("/"))
		if not DialogueCatalog.has_point(point) or index >= DialogueCatalog.lines_for(point).size():
			stale.append(key)
	assert_eq(stale, [], "a key the catalogue no longer authors is a failure")
	assert_eq(keys.size(), _authored_variants().size(), "and every variant is answered")


func test_the_source_tongue_reads_no_translation() -> void:
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	DialogueLocale.load_shipped()
	var changed: Array[String] = []
	for row: Array in _authored_variants():
		var english := String(row[2])
		if DialogueLocale.line(String(row[0]), int(row[1]), english) != english:
			changed.append(DialogueLocale.line_key(String(row[0]), int(row[1])))
	assert_eq(changed, [], "an English court reads exactly what it read before")


func test_the_shipped_tongue_is_registered_once() -> void:
	DialogueLocale.load_shipped()
	DialogueLocale.load_shipped()
	var count := 0
	for code in TranslationServer.get_loaded_locales():
		if String(code) == "fr":
			count += 1
	assert_eq(count, 1, "the file is registered when a court first speaks, and once")


func test_the_shipped_tongue_answers_a_regional_tongue() -> void:
	for code in ["fr", "fr_FR", "fr_CA"]:
		DialogueLocale.set_locale(code)
		assert_eq(
			DialogueCatalog.line_for("reactive/standing_neutral", 0),
			"Nos clercs inscrivent votre nom ; rien de plus aujourd'hui.",
			"a regional French tongue reads the shipped French"
		)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)


func test_the_court_s_own_line_speaks_the_readers_tongue() -> void:
	DialogueLocale.set_locale("fr")
	assert_eq(
		DialogueCatalog.line_for("reactive/standing_neutral", 0),
		"Nos clercs inscrivent votre nom ; rien de plus aujourd'hui.",
		"the panel's line comes back in French"
	)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(
		DialogueCatalog.line_for("reactive/standing_neutral", 0),
		"Our clerks record your name; nothing more today."
	)
# --- test_symbol_plates ---

## One boot for the drawn plates: tech, commodity and unit icons and the map's
## symbol stamp.

## Merged from test_tech_icons, test_commodity_icons, test_unit_icons,
## test_map_symbols.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const KINDS: Array[String] = [
	"mountain", "hill", "tree", "scrub", "dune", "reed", "grass", "field",
	"port", "capital", "town",
]

# --- test_tech_icons ---

func test_every_catalog_tech_names_a_series() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.series_of(tech_id).is_empty():
			missing.append(tech_id)
	assert_eq(missing.size(), 0, "techs without a plate: %s" % ", ".join(missing))

func test_every_series_ships_a_texture() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.texture(tech_id) == null:
			missing.append(TechIcons.series_of(tech_id))
	assert_eq(missing.size(), 0, "plates missing from assets/art/tech: %s" % ", ".join(missing))

func test_a_chain_shares_one_plate() -> void:
	assert_eq(TechIcons.series_of("crop_rotation"), TechIcons.series_of("land_enclosure"))
	assert_eq(TechIcons.series_of("sugar_planting"), TechIcons.series_of("sugar_industry"))

func test_a_long_chain_may_grow_a_grander_plate() -> void:
	assert_ne(TechIcons.series_of("saw_mill"), TechIcons.series_of("circular_saw"))

func test_an_unknown_tech_has_no_plate() -> void:
	assert_eq(TechIcons.series_of("no_such_tech"), "")
	assert_null(TechIcons.texture("no_such_tech"))

func test_no_plate_is_listed_twice() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for tech_id: String in TechIcons.covered_ids():
		if seen.has(tech_id):
			clashes.append(tech_id)
		seen[tech_id] = true
	assert_eq(clashes.size(), 0, "techs claimed by two plates: %s" % ", ".join(clashes))

# --- test_commodity_icons ---

func test_every_catalog_commodity_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if CommodityIcons.texture(id) == null:
			missing.append(id)
	assert_eq(missing.size(), 0, "goods with no plate: %s" % ", ".join(missing))

func test_two_goods_never_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		var art: Texture2D = CommodityIcons.texture(id)
		if art == null:
			continue
		if seen.has(art.resource_path):
			clashes.append("%s/%s" % [seen[art.resource_path], id])
		seen[art.resource_path] = id
	assert_eq(clashes.size(), 0, "goods sharing a plate: %s" % ", ".join(clashes))

func test_an_unknown_good_has_no_plate() -> void:
	assert_null(CommodityIcons.texture("no_such_good"))
	assert_null(CommodityIcons.texture(""))

func test_a_badge_draws_the_good_at_the_row_size() -> void:
	var badge: Control = CommodityIcons.badge("grain")
	var art: TextureRect = badge as TextureRect
	assert_not_null(art, "a known good draws a texture")
	assert_eq(art.texture, CommodityIcons.texture("grain"))
	assert_eq(art.custom_minimum_size, Vector2(CommodityIcons.ROW_SIZE, CommodityIcons.ROW_SIZE))
	badge.free()

func test_a_missing_plate_leaves_a_gap_of_the_same_width() -> void:
	var gap: Control = CommodityIcons.badge("no_such_good", 18)
	assert_null(gap as TextureRect, "a missing plate is not a texture")
	assert_eq(gap.custom_minimum_size, Vector2(18, 18), "the row keeps its columns")
	gap.free()

func test_a_name_cell_keeps_the_column_width() -> void:
	var cell: HBoxContainer = CommodityIcons.cell("timber", 132.0)
	assert_eq(cell.custom_minimum_size.x, 132.0, "the cell owns the column width")
	var labels: Array[Node] = cell.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1, "one label per cell")
	assert_eq((labels[0] as Label).text, CommodityCatalog.label("timber"))
	var art: Array[Node] = cell.find_children("*", "TextureRect", true, false)
	assert_eq(art.size(), 1, "the medallion rides inside the cell")
	assert_eq((art[0] as TextureRect).texture, CommodityIcons.texture("timber"))
	cell.free()

## The plate is 128 px so it survives the phone's 3× draw scale.
func test_a_plate_is_a_128_px_source() -> void:
	var art: Texture2D = CommodityIcons.texture("coal")
	assert_not_null(art)
	assert_eq(art.get_width(), 128)
	assert_eq(art.get_height(), 128)

# --- test_unit_icons ---

func test_every_worker_type_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "workers without a plate: %s" % ", ".join(missing))

func test_every_hull_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: Variant in ShipStats.STATS.keys():
		if ShipArt.medallion(String(type_id)) == null:
			missing.append(String(type_id))
	assert_eq(missing.size(), 0, "hulls without a plate: %s" % ", ".join(missing))

func test_every_regiment_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in RegimentCatalog.ids():
		if RegimentArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "regiments without a plate: %s" % ", ".join(missing))

## Unique icons, not one plate reused under several names: every type resolves
## a file of its own.
func test_no_two_types_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for type_id: String in _every_type():
		var texture: Texture2D = _plate(type_id)
		var path: String = texture.resource_path if texture != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [type_id, String(seen[path])])
		seen[path] = type_id
	assert_eq(clashes.size(), 0, "types sharing a plate: %s" % ", ".join(clashes))

func test_an_unknown_hull_falls_back_to_the_default_plate() -> void:
	assert_eq(
		ShipArt.medallion("no_such_hull").resource_path,
		ShipArt.medallion(ShipStats.DEFAULT_TYPE).resource_path
	)
	assert_eq(
		RegimentArt.medallion("no_such_regiment").resource_path,
		RegimentArt.medallion(RegimentCatalog.DEFAULT_TYPE).resource_path
	)

func test_an_unknown_worker_has_no_plate() -> void:
	assert_null(CivilianArt.medallion("no_such_worker"))

## The row widget wears the plate at its own size, mipmapped, and a missing
## plate leaves a gap of the same width so the row's columns do not shift.
func test_the_row_widget_draws_the_plate_it_is_given() -> void:
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(medallion.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(medallion.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	assert_eq(bare.custom_minimum_size, Vector2(20.0, 20.0), "an absent plate keeps its width")
	add_child(bare)
	bare.queue_free()

func test_a_regiment_medallion_names_its_own_type() -> void:
	var medallion: UnitMedallion = UnitMedallion.of_regiment("grenadiers")
	assert_eq(medallion.texture, RegimentArt.medallion("grenadiers"))
	assert_eq(medallion.custom_minimum_size, Vector2(28.0, 28.0))

func _every_type() -> Array[String]:
	var all: Array[String] = []
	all.append_array(CivilianCatalog.ORDER)
	for type_id: Variant in ShipStats.STATS.keys():
		all.append(String(type_id))
	all.append_array(RegimentCatalog.ids())
	return all

func _plate(type_id: String) -> Texture2D:
	if CivilianCatalog.known(type_id):
		return CivilianArt.medallion(type_id)
	if ShipStats.known(type_id):
		return ShipArt.medallion(type_id)
	return RegimentArt.medallion(type_id)

# --- test_map_symbols ---

func test_every_planned_kind_has_a_painted_stamp() -> void:
	for kind: String in KINDS:
		var tex: Texture2D = MapSymbols.texture(kind)
		assert_not_null(tex, "%s has no painted stamp" % kind)
		assert_gt(tex.get_width(), 63, "%s is drawn from a downscaled source" % kind)

func test_unknown_kind_has_no_stamp() -> void:
	assert_null(MapSymbols.texture("nonesuch"))

## The stamp falls back to the ink vectors rather than drawing nothing.
func test_stamp_refuses_a_kind_it_has_no_art_for() -> void:
	assert_false(MapSymbols.stamp(_probe(), {"kind": "nonesuch", "position": Vector2.ZERO, "size": 20.0}))
	assert_false(MapSymbols.stamp(_probe(), {"kind": "tree", "position": Vector2.ZERO, "size": 0.0}))

## A scattered province uses more than one sprite, so a range is not one stamp.
func test_terrain_mountains_take_several_variants() -> void:
	var seen: Dictionary = {}
	for i in 40:
		var at := Vector2(float(i) * 37.0, float(i) * 91.0)
		seen[MapSymbols.texture("mountain", at)] = true
	assert_gt(seen.size(), 1, "a mountain range repeats one sprite")

func test_stamp_draws_a_scenery_mark() -> void:
	var drawn: bool = await _draw_mark({
		"kind": "tree", "position": Vector2(30, 30), "size": 18.0, "flip": true,
	})
	assert_true(drawn, "the painted stamp drew instead of falling back")

func test_stamp_draws_a_town() -> void:
	assert_true(await _draw_mark({"kind": "town", "position": Vector2(64, 64), "size": 20.0}))

## The capital flies its owner's pennant, and still draws when nobody holds it.
func test_capital_stamp_covers_owner_and_neutral() -> void:
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(90, 90), "size": 24.0, "owner": 2,
	}))
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(120, 120), "size": 24.0,
		"owner": MapModel.NO_ID,
	}))

func test_ship_uses_a_painted_hull() -> void:
	var tex: Texture2D = MapSymbols.texture("ship")
	assert_not_null(tex, "the fleet has no painted hull")
	assert_eq(tex.get_width(), 256)

func _probe() -> _StampProbe:
	return _StampProbe.new()

## Drawing is only legal inside `_draw`, so the probe's own draw runs the stamp
## and the test reads its result after a rendered frame.
func _draw_mark(glyph: Dictionary) -> bool:
	var probe := _probe()
	probe.name = "StampProbe"
	probe.glyph = glyph
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	var drawn: bool = probe.result
	probe.queue_free()
	return drawn

class _StampProbe:
	extends Node2D

	var glyph: Dictionary = {}
	var result: bool = false

	func _draw() -> void:
		result = MapSymbols.stamp(self, glyph)
# --- test_espionage ---

## Espionage rules (wiki: civilian-units § Spy, research-state § Spy RP boost,
## diplomacy § Spy-death penalty) and the rival AI's spy/research policy.

const CivilianFixture = preload("res://tests/civilian_fixture.gd")
const NavalFixture = preload("res://tests/naval_fixture.gd")
const PLAYER: int = 0
const RIVAL: int = 1
const SEED: int = 7


class StubHud extends GameHud:
	var toasts: Array[String] = []

	func toast(text: String, _icon_name: String = "") -> void:
		toasts.append(text)


# --- roster and movement -----------------------------------------------------


func test_spy_is_playable_and_keeps_its_wiki_costs() -> void:
	assert_true(CivilianCatalog.is_implemented("spy"))
	assert_eq(CivilianCatalog.treasury_cost("spy"), 2000)
	assert_eq(CivilianCatalog.paper_cost("spy"), 4)
	assert_in("spy", CivilianCatalog.playable_types())
	assert_eq(CivilianCatalog.works("spy"), [SpyRules.WORK_COUNTER])


func test_spy_may_walk_into_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	assert_true(
		CivilianMovement.may_enter(model, "spy", PLAYER, CivilianFixture.RIVAL_GRAIN_TILE)
	)
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", Vector2i(2, 0)
	)
	var result: Dictionary = CivilianMovement.apply_move(
		model, spy, CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_true(bool(result.get("ok", false)))
	assert_eq(spy.tile, CivilianFixture.RIVAL_GRAIN_TILE)


## Walking a foreign province is quiet; being put ashore there is not. Landing
## needs crown land for every civilian but Explorer and Merchant
## (wiki: civilian-units § Overseas deployment).
func test_a_spy_cannot_land_on_a_foreign_coast() -> void:
	var model: MapModel = NavalFixture.build()
	var fleet: FleetState = FleetState.at_sea(2, PLAYER, 1, ["c"], {"c": "fluyte"})
	var spy: CivilianState = CivilianState.create(5, PLAYER, "spy", Vector2i(0, 0))
	spy.embarked_fleet = fleet.id
	fleet.add_civilian(spy.id)
	var tiles: Array[Vector2i] = CivilianVoyage.landing_tiles(model, spy, fleet)
	assert_false(tiles.has(Vector2i(5, 0)), "a rival coast refuses a spy")
	assert_false(tiles.has(Vector2i(5, 1)), "nor its harbour")
	var explorer: CivilianState = CivilianState.create(6, PLAYER, "explorer", Vector2i(0, 0))
	explorer.embarked_fleet = fleet.id
	fleet.add_civilian(explorer.id)
	assert_true(
		CivilianVoyage.landing_tiles(model, explorer, fleet).has(Vector2i(5, 1)),
		"an explorer still surveys any coast"
	)
	var home: FleetState = FleetState.in_port(3, PLAYER, 0, ["d"], {"d": "fluyte"})
	var home_spy: CivilianState = CivilianState.create(7, PLAYER, "spy", Vector2i(0, 0))
	home_spy.embarked_fleet = home.id
	home.add_civilian(home_spy.id)
	assert_false(
		CivilianVoyage.landing_tiles(model, home_spy, home).is_empty(),
		"crown land still takes the spy ashore"
	)


func test_presence_holds_a_charted_province_for_its_owner_only() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	assert_eq(CivilianMovement.held_provinces(model, [spy], PLAYER), [RIVAL])
	assert_eq(CivilianMovement.held_provinces(model, [spy], RIVAL), [])
	assert_eq(
		SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [RIVAL],
		"a spy on a rival court's land shadows that court"
	)


func test_a_spy_in_its_own_land_observes_nothing() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	assert_eq(SpyNetworks.qualifying_rivals(model, [spy], PLAYER), [])


# --- counter-espionage -------------------------------------------------------


func test_counter_spy_is_an_ongoing_owned_order() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	var units: Array[CivilianState] = [spy]
	var check: Dictionary = CivilianWork.validate(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	)
	assert_true(bool(check.get("ok", false)), "an owned province is a legal screen")
	assert_eq(CivilianWork.assign(
		model, spy, SpyRules.WORK_COUNTER, LandWorks.new(), units,
		CivilianFixture.stockpile()
	).get("ok", false), true)
	assert_true(spy.is_working())
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, units, LandWorks.new()
	)
	assert_true(reports.is_empty(), "the screen never advances or completes")
	assert_true(spy.is_working(), "counter-espionage stays up until cancelled")
	var rival_tile: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var rival_check: Dictionary = CivilianWork.validate(
		model, rival_tile, SpyRules.WORK_COUNTER, LandWorks.new(),
		[rival_tile] as Array[CivilianState], CivilianFixture.stockpile()
	)
	assert_false(
		bool(rival_check.get("ok", false)), "a foreign province is not a legal target"
	)


# --- research intelligence ---------------------------------------------------


func test_research_bonus_stacks_per_observed_rival() -> void:
	var bonus: Dictionary = SpyNetworks.research_boost(
		[RIVAL, 2],
		{RIVAL: {"crop_rotation": true}, 2: {"crop_rotation": true, "saw_mill": true}}
	)
	assert_eq(int(bonus.get("crop_rotation", 0)), 30, "two rivals, two +15%")
	assert_eq(int(bonus.get("saw_mill", 0)), 15)
	var none: Dictionary = SpyNetworks.research_boost(
		[RIVAL], {RIVAL: {"saw_mill": true}}
	)
	assert_eq(int(none.get("crop_rotation", 0)), 0, "a tech the rival lacks earns nothing")


func test_research_turn_applies_the_spy_bonus() -> void:
	var state := ResearchState.make()
	state.assign("crop_rotation", "medium")
	var economy := PlayerEconomy.starting()
	assert_eq(ResearchTurn.points_for(state, "crop_rotation", "medium"), 300)
	assert_eq(
		ResearchTurn.points_for(state, "crop_rotation", "medium", 15), 345,
		"a 15% network lifts 300 RP to 345"
	)
	var report: Dictionary = ResearchTurn.resolve(
		state, economy, {"crop_rotation": 15}
	)
	assert_eq(int(report["slots"][0]["rp"]), 345)
	assert_eq(state.progress_of("crop_rotation"), 345)


func test_map_phase_prepares_the_player_spy_bonus() -> void:
	var play: PlaySession = _play_with_spy()
	var controller: EconomyController = play.economy
	controller.economy.research.slots[0] = {"tech": "crop_rotation", "funding": "medium"}
	var rival_economy: PlayerEconomy = play.ai.economy_for(RIVAL)
	rival_economy.research.unlocked["crop_rotation"] = true
	var bonus: Dictionary = MapPlayEspionage.research_boost(play)
	assert_eq(int(bonus.get("crop_rotation", 0)), 15)
	controller.research_boost = bonus
	assert_eq(int(controller.research_boost.get("crop_rotation", 0)), 15)
	play.hud.free()
	controller.free()


func test_rival_spies_are_invisible_on_the_map() -> void:
	var model: MapModel = CivilianFixture.build()
	var layer := CivilianLayer.new()
	layer.viewer_faction = PLAYER
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	var rival_spy: CivilianState = layer.add_unit(
		RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var own_spy: CivilianState = layer.add_unit(PLAYER, "spy", CivilianFixture.BARE_TILE)
	assert_false(layer.marker_for(rival_spy).visible, "a rival spy leaves no marker")
	assert_true(layer.marker_for(own_spy).visible)
	var rival_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.RIVAL_GRAIN_TILE.x, CivilianFixture.RIVAL_GRAIN_TILE.y,
		PlaySession.TILE_SIZE
	)
	var own_point: Vector2 = MapGeo.tile_center(
		CivilianFixture.BARE_TILE.x, CivilianFixture.BARE_TILE.y, PlaySession.TILE_SIZE
	)
	assert_null(layer.unit_at(rival_point), "a rival spy is not selectable")
	assert_eq(layer.unit_at(own_point), own_spy)
	layer.free()


# --- kill and defection ------------------------------------------------------


func test_counter_espionage_kills_and_turns_spies() -> void:
	var model: MapModel = CivilianFixture.build()
	var rolls: Dictionary = _find_rolls(model)
	assert_true(int(rolls["kill"]) > 0, "5% kill chance lands within the search")
	assert_true(int(rolls["defect"]) > 0, "10% defection lands within the search")
	var units: Array[CivilianState] = _spy_pair()
	var events: Array[Dictionary] = SpyRules.resolve_turn(
		model, units, int(rolls["kill"]), SEED
	)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_eq(units.size(), 1, "the killed spy leaves the roster")
	var defectors: Array[CivilianState] = _spy_pair()
	var defected: Array[Dictionary] = SpyRules.resolve_turn(
		model, defectors, int(rolls["defect"]), SEED
	)
	assert_eq(String(defected[0]["kind"]), "defected")
	assert_eq(int(defected[0]["unit"].owner), RIVAL, "the survivor changes coat")


func test_a_killed_spy_cools_relations_by_eight() -> void:
	var play: PlaySession = _play_with_spy()
	play.turn = int(_find_rolls(play.model)["kill"])
	play.diplomacy.ensure_relation(PLAYER, RIVAL, 1)
	play.diplomacy.relation(PLAYER, RIVAL).score = 60.0
	play.civilian_layer.units = _spy_pair()
	play.civilian_layer.regions.set_region(0, play.civilian_layer.units)
	var events: Array[Dictionary] = MapPlaySpies.resolve(play)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["kind"]), "killed")
	assert_almost_eq(play.diplomacy.relation(PLAYER, RIVAL).score, 52.0, 0.001)
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(
		play.hud.toasts[0].contains("−8 with England"),
		"the court hears what its loss cost: " + play.hud.toasts[0]
	)
	var chronicle: Array[Dictionary] = DiplomacyHistory.entries(play.diplomacy, PLAYER, RIVAL)
	assert_false(chronicle.is_empty(), "the chronicle keeps the act")
	assert_true(
		String(chronicle[0]["text"]).contains("agent was taken in"),
		"the standing shifted for a stated reason: " + String(chronicle[0]["text"])
	)
	play.hud.free()
	play.economy.free()


## Every line the court can hear for a spy event, and the ones it cannot: a
## rival spy's province is invisible to this crown, so another pair's kill stays
## silent (wiki: civilian-units § Spy (4)). A killed spy costs the pair 8, so
## each line names that price (wiki: diplomacy § Spy-death penalty).
func test_spy_notice_names_the_price_and_the_court() -> void:
	var caught: Dictionary = {"kind": "killed", "owner": RIVAL, "territory_owner": PLAYER}
	assert_eq(
		MapPlaySpies.notice(caught, "Coro", PLAYER),
		"Counter-espionage caught England's spy in Coro — −8 with England."
	)
	var lost: Dictionary = {"kind": "killed", "owner": PLAYER, "territory_owner": RIVAL}
	assert_eq(
		MapPlaySpies.notice(lost, "Coro", PLAYER),
		"A spy in Coro has gone silent — −8 with England."
	)
	var turned: Dictionary = {"kind": "defected", "owner": RIVAL, "territory_owner": PLAYER}
	assert_eq(
		MapPlaySpies.notice(turned, "Coro", PLAYER),
		"England's spy in Coro has turned coat and now serves your crown."
	)
	assert_eq(
		MapPlaySpies.notice(turned, "Coro", RIVAL), "A spy in Coro has turned coat."
	)
	var abroad: Dictionary = {"kind": "killed", "owner": 2, "territory_owner": RIVAL}
	assert_eq(MapPlaySpies.notice(abroad, "Coro", PLAYER), "", "another court's business")
	assert_eq(MapPlaySpies.notice({}, "Coro", PLAYER), "")


func test_an_unscreened_spy_is_never_touched() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array[CivilianState] = [spy]
	for turn in 50:
		assert_true(SpyRules.resolve_turn(model, units, turn, SEED).is_empty())
	assert_eq(units.size(), 1, "no counter-spy means no kill or defection roll")


## One spy on `counter_spy` anywhere screens every owned province, so a screen
## kept at home must hunt an enemy spy standing in another region's colony
## (wiki: civilian-units § Spy (3): "empire-wide ... in all owned provinces").
func test_counter_espionage_screen_covers_every_region() -> void:
	var play: PlaySession = _two_region_play()
	var events: Array[Dictionary] = []
	for turn in range(1, 401):
		play.turn = turn
		events.append_array(MapPlaySpies.resolve(play))
	assert_false(events.is_empty(), "the home screen hunts the colonial intruder")
	for event: Dictionary in events:
		assert_eq(int(event.get("region", -1)), 1, "the intruder stood in region 1")


# --- rival AI ----------------------------------------------------------------


func test_ai_spy_walks_toward_a_rival_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var units: Array = [spy]
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, units, LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_eq((plan["moves"] as Array).size(), 1)
	assert_eq((plan["orders"] as Array).size(), 0)
	var step: Vector2i = plan["moves"][0]["tile"]
	assert_true(step.x > CivilianFixture.RIVAL_GRAIN_TILE.x - 2)


func test_ai_spy_holds_a_foreign_province() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, _context()
	)
	assert_true((plan["moves"] as Array).is_empty())
	assert_true((plan["orders"] as Array).is_empty(), "presence duty, not a work order")


func test_ai_spy_raises_a_counter_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1)
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)


func test_ai_war_screen_frees_the_second_spy_to_observe() -> void:
	var model: MapModel = CivilianFixture.build()
	var first: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var second: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [first, second], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_eq((plan["orders"] as Array).size(), 1, "one spy keeps the screen")
	assert_eq(String(plan["orders"][0]["action"]), SpyRules.WORK_COUNTER)
	assert_eq((plan["moves"] as Array).size(), 1, "the other walks abroad")


func test_ai_recalls_a_spy_to_screen_at_war() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var context: Dictionary = _context()
	context["at_war"] = true
	var plan: Dictionary = AiCivilianPlanner.plan(
		AiConfig.build(RIVAL, 1500), model, [spy], LandWorks.new(),
		CivilianFixture.stockpile(), {}, {}, context
	)
	assert_true((plan["orders"] as Array).is_empty())
	assert_eq((plan["moves"] as Array).size(), 1, "the spy walks home to screen")
	assert_true(Vector2i(plan["moves"][0]["tile"]).x > CivilianFixture.BARE_TILE.x)


func test_ai_trains_a_spy_after_its_base_roster() -> void:
	var roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
		CivilianState.create(4, RIVAL, "explorer", CivilianFixture.BARE_TILE),
	]
	var order: Dictionary = AiCivilianPlanner.training_order(
		AiConfig.build(RIVAL, 1500), roster, _context()
	)
	assert_true(bool(order.get("ok", false)))
	assert_eq(String(order["type_id"]), "spy")
	var war_roster: Array[CivilianState] = [
		CivilianState.create(1, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(2, RIVAL, "builder", CivilianFixture.BARE_TILE),
		CivilianState.create(3, RIVAL, "engineer", CivilianFixture.BARE_TILE),
	]
	var war_context: Dictionary = _context()
	war_context["at_war"] = true
	var war_order: Dictionary = AiCivilianPlanner.training_order(
		AiConfig.build(RIVAL, 1500), war_roster, war_context
	)
	assert_eq(String(war_order["type_id"]), "spy", "a war court wants a screen first")


func test_ai_research_planner_opens_a_study() -> void:
	var economy := PlayerEconomy.starting()
	var plan: Dictionary = AiResearchPlanner.plan(
		AiConfig.build(RIVAL, 1500), economy, {}
	)
	var assignments: Array = plan["assignments"]
	assert_false(assignments.is_empty(), "the planner fills a free slot")
	var tech: String = String(assignments[0]["tech"])
	assert_false(tech.is_empty())
	assert_true(ResearchFunding.known(String(assignments[0]["funding"])))
	var before: int = economy.research.progress_of(tech)
	ResearchTurn.resolve(economy.research, economy)
	assert_true(
		economy.research.progress_of(tech) > before
		or economy.research.is_unlocked(tech),
		"the Research phase advances the assigned study"
	)


func test_ai_research_is_deterministic() -> void:
	var first := PlayerEconomy.starting()
	var second := PlayerEconomy.starting()
	var config: AiConfig = AiConfig.build(RIVAL, 1500)
	var left: Dictionary = AiResearchPlanner.plan(config, first, {})
	var right: Dictionary = AiResearchPlanner.plan(config, second, {})
	assert_eq(
		String(left["assignments"][0]["tech"]),
		String(right["assignments"][0]["tech"])
	)


# --- court reports -----------------------------------------------------------


func test_court_report_names_battles_and_techs() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": RIVAL,
		"defender": PLAYER,
		"captured": true,
	}
	var sea: Dictionary = {"region": 0, "zone": 0, "attacker": RIVAL, "defender": PLAYER}
	var report: Dictionary = {
		"factions": {
			RIVAL: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [land], [sea], report)
	assert_eq(play.hud.toasts.size(), 1)
	var line: String = play.hud.toasts[0]
	assert_true(line.begins_with("Spy report — England"))
	assert_true(line.contains("took Coro from Spain"))
	assert_true(line.contains("squadron action in Mar Caribe"))
	assert_true(line.contains("Crop Rotation"))
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_lost_province() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": PLAYER,
		"defender": RIVAL,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(play.hud.toasts[0].contains("lost Coro to Spain"))
	play.hud.free()
	play.economy.free()


func test_court_report_names_a_diplomatic_act() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_eq(play.hud.toasts.size(), 1)
	assert_true(play.hud.toasts[0].contains("declares war"))
	play.hud.free()
	play.economy.free()


## A study the spy watched is written into the chronicle, stamped with the turn
## it resolved, so the dossier can weigh it long after the toast has gone
## (DR-20261110-25).
func test_a_shadowed_study_enters_the_dossier() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			RIVAL: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	var events: Array = play.diplomacy.events
	assert_eq(events.size(), 1, "one study, one observation")
	var event: Dictionary = events[0] as Dictionary
	assert_eq(String(event["kind"]), IntelEvidence.SPY_TECH)
	assert_eq(String((event["data"] as Dictionary)["tech"]), "crop_rotation")
	assert_eq(IntelEvidence.turn_of(event), 1, "stamped with the turn that resolved")
	var scores: Dictionary = IntelDossier.suspicion(
		IntelDossier.evidence(play.diplomacy, play.world, PLAYER, RIVAL)
	)
	assert_eq(int(scores.get(AiAgenda.TECH_THIEF, 0)), IntelEvidence.W_SPY_TECH)
	play.hud.free()
	play.economy.free()


## Only a shadowed court's studies are read; a rival the spy does not watch
## keeps its research (wiki: civilian-units § Spy — court reports).
func test_an_unwatched_court_keeps_its_studies() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			2: {"resolved": {"research": {"researched": ["crop_rotation"]}}},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	assert_true(play.diplomacy.events.is_empty(), "no spy, no despatch")
	play.hud.free()
	play.economy.free()


## Builds are notes: the spy counts what the court's builders begin and the
## dossier lists them without weighing an agenda (DR-20261110-25).
func test_a_shadowed_build_reads_as_a_note_not_evidence() -> void:
	var play: PlaySession = _play_with_spy()
	var report: Dictionary = {
		"factions": {
			RIVAL: {
				"civilians": {
					"orders": [
						{"action": "build_improvement"},
						{"action": "build_improvement"},
						{"action": "upgrade_town"},
						{"action": "counter_spy"},
					],
				},
			},
		},
	}
	MapPlaySpies.report(play, [], [], report)
	var notes: Dictionary = IntelDossier.report(play.diplomacy, play.world, PLAYER, RIVAL)["notes"]
	var build: Dictionary = notes["build"] as Dictionary
	assert_eq(int(build.get("improvement", 0)), 2)
	assert_eq(int(build.get("town", 0)), 1)
	assert_eq(int(notes["war"]), 0, "the build notes do not displace the behaviour counts")
	var scores: Dictionary = IntelDossier.suspicion(
		IntelDossier.evidence(play.diplomacy, play.world, PLAYER, RIVAL)
	)
	assert_true(scores.is_empty(), "a build weighs on no agenda")
	play.hud.free()
	play.economy.free()


func test_court_report_stays_readable_after_the_toast() -> void:
	var play: PlaySession = _play_with_spy()
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": RIVAL,
		"defender": PLAYER,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	assert_eq(int(play.court_reports["turn"]), 1, "the turn that just resolved")
	assert_true((play.court_reports["shadowed"] as Array).has(RIVAL))
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq((kept[RIVAL] as Array).size(), 1, "the toast's line is kept")
	assert_eq(String((kept[RIVAL] as Array)[0]), "took Coro from Spain")
	play.hud.free()
	play.economy.free()


func test_a_despatch_is_a_page_not_a_chronicle() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = []
	for index in 12:
		play.ai_trace.append(
			{"faction": RIVAL, "message": "England word %d." % index}
		)
	MapPlaySpies.report(play, [], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq((kept[RIVAL] as Array).size(), MapPlaySpies.MAX_LINES)
	play.hud.free()
	play.economy.free()


func test_a_stranger_court_stays_masked_in_the_despatch() -> void:
	var play: PlaySession = _play_with_spy()
	var stranger: int = 9
	var land: Dictionary = {
		"region": 0,
		"province": CivilianFixture.RIVAL_PROVINCE,
		"attacker": stranger,
		"defender": RIVAL,
		"captured": true,
	}
	MapPlaySpies.report(play, [land], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq(String((kept[RIVAL] as Array)[0]), "lost Coro to Unknown faction")
	play.hud.free()
	play.economy.free()


func test_a_structured_act_masks_an_unmet_target() -> void:
	var play: PlaySession = _play_with_spy()
	play.ai_trace = [{
		"faction": RIVAL,
		"action": {"kind": AiDiplomacyPlanner.KIND_DECLARE_WAR, "target": 9},
		"message": "England declares war on France.",
	}]
	MapPlaySpies.report(play, [], [], {})
	var kept: Dictionary = play.court_reports["lines"] as Dictionary
	assert_eq(String((kept[RIVAL] as Array)[0]), "England declares war on Unknown faction.")
	play.hud.free()
	play.economy.free()


func test_court_report_is_silent_without_a_spy() -> void:
	var play: PlaySession = _play_with_spy()
	play.civilian_layer.units.clear()
	play.ai_trace = [{"faction": RIVAL, "message": "England declares war on France."}]
	MapPlaySpies.report(play, [], [], {})
	assert_true(play.hud.toasts.is_empty())
	play.hud.free()
	play.economy.free()


# --- rules guards and dossier copy -------------------------------------------


func test_spy_rules_guards_skip_nulls_and_home_tiles() -> void:
	var model: MapModel = CivilianFixture.build()
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var builder: CivilianState = CivilianState.create(
		2, PLAYER, "builder", CivilianFixture.BARE_TILE
	)
	assert_false(SpyRules.is_spy(null))
	assert_false(SpyRules.is_spy(builder))
	assert_false(SpyRules.hidden_from(null, PLAYER))
	assert_false(SpyRules.hidden_from(spy, -1))
	assert_false(SpyRules.hidden_from(spy, PLAYER))
	assert_true(SpyRules.hidden_from(spy, RIVAL))
	assert_false(SpyRules.is_foreign(null, spy))
	assert_false(SpyRules.is_foreign(model, builder))
	spy.embark_on(1)
	assert_false(SpyRules.is_foreign(model, spy))
	spy.put_ashore(Vector2i(0, 4))
	assert_eq(model.owner_at(0, 4), MapModel.NO_ID)
	assert_false(SpyRules.is_foreign(model, spy))
	assert_false(SpyRules.has_counter_spy([null, builder], PLAYER))
	assert_true(SpyRules.screened_owners(null, [spy]).is_empty())
	assert_eq(SpyRules.resolve_turn(null, [spy], 1, SEED).size(), 0)


func test_civilian_panel_names_tradecraft_and_counter_status() -> void:
	var model: MapModel = CivilianFixture.build()
	var abroad: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(
		model, abroad, LandWorks.new(), [abroad], CivilianFixture.stockpile()
	)
	assert_true(panel._status.text.contains("At large"))
	panel.refresh(
		model, screen, LandWorks.new(), [screen], CivilianFixture.stockpile()
	)
	assert_eq(panel._status.text, "Counter-espionage · ongoing.")
	panel.free()


## A dossier may only promise what the standing actually buys: an idle spy keeps
## no screen, and a minor court shares no research (wiki: civilian-units § Spy
## (2)–(3); DR-20261110-03). Both promises used to be unconditional.
func test_the_dossier_promises_only_what_the_standing_buys() -> void:
	var home: MapModel = CivilianFixture.build()
	var idle: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	var panel := CivilianPanel.new()
	add_child(panel)
	panel.refresh(home, idle, LandWorks.new(), [idle], CivilianFixture.stockpile())
	assert_eq(
		_panel_row(panel, "Tradecraft"),
		"No screen up — only the counter-espionage order covers your land"
	)
	idle.start_work(SpyRules.WORK_COUNTER, idle.tile, 1)
	panel.refresh(home, idle, LandWorks.new(), [idle], CivilianFixture.stockpile())
	var screen_row: String = _panel_row(panel, "Tradecraft")
	assert_true(
		screen_row.begins_with("Counter-espionage screen"),
		"the screen exists once the order is up"
	)
	assert_true(
		screen_row.contains("%d%% a turn to take" % SpyRules.KILL_PCT)
		and screen_row.contains("%d%% to turn one" % SpyRules.DEFECT_PCT),
		"the dossier names the trade it buys: " + screen_row
	)
	var minor_model: MapModel = CivilianFixture.build_minor()
	var minor_spy: CivilianState = CivilianState.create(
		2, PLAYER, "spy", Vector2i(2, 0)
	)
	assert_eq(minor_model.owner_at(2, 0), 6, "the fixture tile is Genoa's")
	panel.refresh(
		minor_model, minor_spy, LandWorks.new(), [minor_spy],
		CivilianFixture.stockpile()
	)
	var row: String = _panel_row(panel, "Tradecraft")
	assert_true(row.contains("presence reveal only"))
	assert_false(row.contains("%"), "a minor court never shares research")
	assert_true(panel._status.text.contains("no research share"))
	panel.free()


## The value column of one dossier row, or "" when the caption is absent.
func _panel_row(panel: CivilianPanel, caption: String) -> String:
	var children: Array[Node] = panel._detail.get_children()
	var index: int = 0
	while index + 1 < children.size():
		var key: Label = children[index] as Label
		var value: Label = children[index + 1] as Label
		if key != null and key.text == caption:
			return value.text if value != null else ""
		index += 2
	return ""


# --- fixtures ----------------------------------------------------------------


func _spy_pair() -> Array[CivilianState]:
	var spy: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE
	)
	var screen: CivilianState = CivilianState.create(
		2, RIVAL, "spy", Vector2i(4, 0)
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	var units: Array[CivilianState] = [spy, screen]
	return units


func _find_rolls(model: MapModel) -> Dictionary:
	var kill: int = -1
	var defect: int = -1
	for turn in range(1, 2000):
		var units: Array[CivilianState] = _spy_pair()
		for event: Dictionary in SpyRules.resolve_turn(model, units, turn, SEED):
			if String(event["kind"]) == "killed" and kill < 0:
				kill = turn
			elif String(event["kind"]) == "defected" and defect < 0:
				defect = turn
		if kill > 0 and defect > 0:
			break
	return {"kill": kill, "defect": defect}


## Two regions on one session: the player's counter-espionage screen stands at
## home (region 0) while an enemy spy holds the player's colonial province in
## region 1.
func _two_region_play() -> PlaySession:
	var first: MapModel = CivilianFixture.build()
	first.region_id = 0
	var second: MapModel = CivilianFixture.build()
	second.region_id = 1
	var world := WorldMap.new()
	world.add_region(first)
	world.add_region(second)
	var layer := CivilianLayer.new()
	layer.spawn(first, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	var screen: CivilianState = CivilianState.create(
		1, PLAYER, "spy", CivilianFixture.BARE_TILE
	)
	screen.start_work(SpyRules.WORK_COUNTER, screen.tile, 1)
	layer.units.append(screen)
	layer.regions.set_region(0, layer.units)
	var intruder: CivilianState = CivilianState.create(
		2, RIVAL, "spy", CivilianFixture.BARE_TILE
	)
	var region_one: Array[CivilianState] = [intruder]
	layer.regions.set_region(1, region_one)
	var play := PlaySession.new()
	play.player_faction = PLAYER
	play.world = world
	play.model = first
	play.region_index = 0
	play.civilian_layer = layer
	play.map_seed = SEED
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	return play


func _play_with_spy() -> PlaySession:
	var model: MapModel = CivilianFixture.build()
	var world := WorldMap.new()
	world.add_region(model)
	var layer := CivilianLayer.new()
	layer.spawn(model, CivilianFixture.PLAYER_PROVINCE, PLAYER, [])
	layer.add_unit(PLAYER, "spy", CivilianFixture.RIVAL_GRAIN_TILE)
	var play := PlaySession.new()
	play.player_faction = PLAYER
	play.world = world
	play.model = model
	play.region_index = model.region_id
	play.civilian_layer = layer
	play.map_seed = SEED
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(1)
	play.ai = AiState.new()
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()
	play.economy = controller
	play.hud = StubHud.new()
	add_child(play.hud)
	return play


func _context() -> Dictionary:
	return {
		"treasury": 2500,
		"paper": 8,
		"capital_province": CivilianFixture.PLAYER_PROVINCE,
		"capital_tile": CivilianFixture.BARE_TILE,
		"at_war": false,
	}
