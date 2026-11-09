class_name CourtDossier
extends VBoxContainer
## The selected court's dossier in the court panel (wiki: ai-dossier). Presented
## only: [IntelDossier] does the arithmetic, so the panel never infers a rival's
## agenda and never reads one either — the reading is evidence, banded, and a
## "Confirmed" band still does not name the truth (REQ-P2-03, REQ-P1-07).

const EVIDENCE_SHOWN: int = 3


func _init() -> void:
	add_theme_constant_override("separation", 3)


func fill(state: DiplomacyState, world: WorldMap, viewer: int, subject: int) -> void:
	_clear()
	var report: Dictionary = IntelDossier.report(state, world, viewer, subject)
	add_child(_caption("DOSSIER"))
	add_child(_line(_reading(report), 13, Palette.GOLD_PALE))
	_add_suspicion(report)
	_add_evidence(report)
	add_child(_line(_behaviour(report), 12, Palette.TEXT_DIM))


## The best-guess line: a band and a percentage, never a claim of certainty.
func _reading(report: Dictionary) -> String:
	var guess: Dictionary = report.get("guess", {}) as Dictionary
	if not guess.is_empty():
		return "Reading: %s %s (%d%%)" % [
			String(guess["band"]), String(guess["label"]), int(guess["confidence"])
		]
	if (report.get("evidence", []) as Array).is_empty():
		return "Reading: no act has yet spoken of this court."
	return "Reading: too little to band — the acts below are noted, nothing more."


## Only agendas that have reached a band are listed; ties stay in catalogue
## order from [IntelDossier].
func _add_suspicion(report: Dictionary) -> void:
	var rows: Array = report.get("agendas", []) as Array
	for raw: Variant in rows:
		var row: Dictionary = raw as Dictionary
		if int(row["score"]) < 3:
			continue
		var ink: Color = Palette.TEXT
		if String(row["band"]) == "Confirmed" or String(row["band"]) == "Almost certain":
			ink = Palette.GOLD
		add_child(
			_line(
				"%s  ·  %s %d%%" % [String(row["label"]), String(row["band"]), int(row["confidence"])],
				13,
				ink
			)
		)


func _add_evidence(report: Dictionary) -> void:
	var entries: Array = report.get("evidence", []) as Array
	if entries.is_empty():
		add_child(_line("No observable act has been written down.", 12, Palette.TEXT_DIM))
		return
	add_child(_caption("EVIDENCE"))
	var shown: int = mini(entries.size(), EVIDENCE_SHOWN)
	for index in shown:
		var entry: Dictionary = entries[index] as Dictionary
		add_child(
			_line(
				"%s  ·  %s" % [
					DiplomacyHistory.stamp_for_turn(int(entry["turn"])), String(entry["text"])
				],
				12,
				Palette.TEXT
			)
		)
	if entries.size() > shown:
		add_child(
			_line("…and %d earlier observation%s." % [
				entries.size() - shown, "" if entries.size() - shown == 1 else "s"
			], 11, Palette.TEXT_DIM)
		)


## Public behaviour, counted — never an inference from it.
static func _behaviour(report: Dictionary) -> String:
	var notes: Dictionary = report.get("notes", {}) as Dictionary
	return "Holds %d province%s  ·  %d war%s  ·  %d alliance%s  ·  %d call%s refused" % [
		int(notes.get("province", 0)), "" if int(notes.get("province", 0)) == 1 else "s",
		int(notes.get("war", 0)), "" if int(notes.get("war", 0)) == 1 else "s",
		int(notes.get("alliance", 0)), "" if int(notes.get("alliance", 0)) == 1 else "s",
		int(notes.get("refused", 0)), "" if int(notes.get("refused", 0)) == 1 else "s",
	]


func _caption(text: String) -> Label:
	return _label(text, 11, Palette.TEXT_DIM)


func _line(text: String, size: int, ink: Color) -> Label:
	var label := _label(text, size, ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(text: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	return label


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
