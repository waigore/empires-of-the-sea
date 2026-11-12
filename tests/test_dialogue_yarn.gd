extends GdToolsTest
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

func test_a_line_carries_a_stable_translation_key() -> void:
	assert_eq(
		DialogueLocale.line_key("reactive/standing_cold", 1),
		"DialoguePoint/reactive/standing_cold/1",
		"the key names the point and the variant"
	)


func test_an_untranslated_key_falls_back_to_the_authored_line() -> void:
	assert_eq(
		DialogueLocale.line("reactive/standing_cold", 0, "We have little to say."),
		"We have little to say.",
		"the source language is never lost"
	)
	assert_true(DialogueLocale.locales().has(DialogueLocale.SOURCE_LOCALE))


func test_the_locale_can_be_switched_and_read_back() -> void:
	DialogueLocale.set_locale("fr")
	assert_eq(DialogueLocale.locale(), "fr", "the game reads the locale it was given")
	DialogueLocale.set_locale("  ")
	assert_eq(DialogueLocale.locale(), "fr", "an empty code changes nothing")
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	assert_eq(DialogueLocale.locale(), DialogueLocale.SOURCE_LOCALE)


func test_a_translation_overrides_the_authored_line() -> void:
	# A tongue no shipped file speaks, so this table is the only one that answers.
	var table := Translation.new()
	table.locale = "nl"
	table.add_message(
		DialogueLocale.line_key("reactive/standing_cold", 0), "Wij hebben u weinig te zeggen."
	)
	TranslationServer.add_translation(table)
	DialogueLocale.set_locale("nl")
	assert_eq(
		DialogueLocale.line("reactive/standing_cold", 0, "We have little to say."),
		"Wij hebben u weinig te zeggen."
	)
	assert_eq(
		DialogueCatalog.line_for("reactive/standing_cold", 0), "Wij hebben u weinig te zeggen.",
		"the court's own line reads the translation"
	)
	assert_eq(
		DialogueLocale.line("reactive/standing_cold", 1, "Our clerks record your name."),
		"Our clerks record your name.",
		"a variant with no translation keeps the source"
	)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	TranslationServer.remove_translation(table)
	assert_eq(
		DialogueCatalog.line_for("reactive/standing_cold", 0),
		"We have little to say to your court.",
		"the source line comes back"
	)


# --- the shipped tongue -----------------------------------------------------

func _authored(point: String, index: int) -> String:
	return String(DialogueCatalog.lines_for(point)[index])


func _authored_line_count() -> int:
	var total: int = 0
	for point: String in DialogueCatalog.points():
		total += DialogueCatalog.lines_for(point).size()
	return total


func test_the_shipped_french_answers_every_authored_line() -> void:
	DialogueLocale.load_shipped()
	var table: Translation = TranslationServer.get_translation_object("fr")
	assert_not_null(table, "the project loads the shipped .po")
	DialogueLocale.set_locale("fr")
	assert_eq(
		table.get_message_count(), _authored_line_count(),
		"the shipped file answers exactly the authored variants"
	)
	var unanswered: PackedStringArray = PackedStringArray()
	for point: String in DialogueCatalog.points():
		for index: int in DialogueCatalog.lines_for(point).size():
			var french: String = DialogueCatalog.line_for(point, index)
			if french.is_empty() or french == DialogueLocale.line_key(point, index):
				unanswered.append(DialogueLocale.line_key(point, index))
			elif french == _authored(point, index):
				unanswered.append(DialogueLocale.line_key(point, index))
	assert_eq(unanswered, PackedStringArray(), "no authored line is left in English")
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)


func test_a_shipped_line_keeps_the_placeholders_it_must_fill() -> void:
	DialogueLocale.load_shipped()
	DialogueLocale.set_locale("fr")
	for point: String in DialogueCatalog.points():
		for index: int in DialogueCatalog.lines_for(point).size():
			var source: String = _authored(point, index)
			var french: String = DialogueCatalog.line_for(point, index)
			for token: String in ["{speaker}", "{other}"]:
				assert_eq(
					french.count(token), source.count(token),
					"%s/%d keeps %s" % [point, index, token]
				)
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)


func test_the_source_tongue_reads_no_translation() -> void:
	DialogueLocale.load_shipped()
	DialogueLocale.set_locale(DialogueLocale.SOURCE_LOCALE)
	for point: String in ["agenda/backstabber", "event/field_won", "negotiation/proposal_peace"]:
		for index: int in DialogueCatalog.lines_for(point).size():
			assert_eq(
				DialogueCatalog.line_for(point, index), _authored(point, index),
				"English is what an English court reads"
			)


func test_the_shipped_file_carries_no_key_the_catalogue_dropped() -> void:
	DialogueLocale.load_shipped()
	var table: Translation = TranslationServer.get_translation_object("fr")
	assert_not_null(table)
	var authored: PackedStringArray = PackedStringArray()
	for point: String in DialogueCatalog.points():
		for index: int in DialogueCatalog.lines_for(point).size():
			authored.append(DialogueLocale.line_key(point, index))
	for key: String in table.get_message_list():
		assert_true(
			authored.has(key), "a shipped key still names an authored line: " + key
		)
