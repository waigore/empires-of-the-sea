class_name CourtDossier
extends VBoxContainer
## The selected court's dossier in the court panel (wiki: ai-dossier). Presented
## only: [IntelDossier] does the arithmetic, so the panel never infers a rival's
## agenda and never reads one either — the reading is evidence, banded, and a
## "Confirmed" band still does not name the truth (REQ-P2-03, REQ-P1-07).

## The court panel is a summary; the full screen carries every timeline.
signal open_pressed

const EVIDENCE_SHOWN: int = 3


func _init() -> void:
	add_theme_constant_override("separation", 3)


func fill(state: DiplomacyState, world: WorldMap, viewer: int, subject: int) -> void:
	UiRowBuilder.clear(self)
	var report: Dictionary = IntelDossier.report(state, world, viewer, subject)
	add_child(UiRowBuilder.caption("DOSSIER", 11, Palette.TEXT_DIM))
	add_child(UiRowBuilder.wrapped_line(_reading(report), 13, Palette.GOLD_PALE))
	_add_suspicion(report)
	_add_evidence(report)
	add_child(UiRowBuilder.wrapped_line(_behaviour(report), 12, Palette.TEXT_DIM))
	_add_open(report)


## One door to the full reading: every agenda's timeline, the whole evidence
## list and the build notes live there, not in this summary (REQ-P5-01).
func _add_open(report: Dictionary) -> void:
	var seen: int = (report.get("evidence", []) as Array).size()
	var text: String = "Open the full dossier"
	if seen > 0:
		text = "Full dossier  ·  %d observation%s  ·  timeline" % [
			seen, MoneyText.plural(seen)
		]
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(func() -> void: open_pressed.emit())
	add_child(button)


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
			UiRowBuilder.wrapped_line(
				"%s  ·  %s %d%%" % [String(row["label"]), String(row["band"]), int(row["confidence"])],
				13,
				ink
			)
		)


func _add_evidence(report: Dictionary) -> void:
	var entries: Array = report.get("evidence", []) as Array
	if entries.is_empty():
		add_child(
			UiRowBuilder.wrapped_line("No observable act has been written down.", 12, Palette.TEXT_DIM)
		)
		return
	add_child(UiRowBuilder.caption("EVIDENCE", 11, Palette.TEXT_DIM))
	var shown: int = mini(entries.size(), EVIDENCE_SHOWN)
	for index in shown:
		var entry: Dictionary = entries[index] as Dictionary
		add_child(
			UiRowBuilder.wrapped_line(
				"%s  ·  %s" % [
					DiplomacyHistory.stamp_for_turn(int(entry["turn"])), String(entry["text"])
				],
				12,
				Palette.TEXT
			)
		)
	if entries.size() > shown:
		add_child(
			UiRowBuilder.wrapped_line("…and %d earlier observation%s." % [
				entries.size() - shown, MoneyText.plural(entries.size() - shown)
			], 11, Palette.TEXT_DIM)
		)


## Public behaviour, counted — never an inference from it.
static func _behaviour(report: Dictionary) -> String:
	var notes: Dictionary = report.get("notes", {}) as Dictionary
	return "Holds %d province%s  ·  %d war%s  ·  %d alliance%s  ·  %d call%s refused" % [
		int(notes.get("province", 0)), MoneyText.plural(int(notes.get("province", 0))),
		int(notes.get("war", 0)), MoneyText.plural(int(notes.get("war", 0))),
		int(notes.get("alliance", 0)), MoneyText.plural(int(notes.get("alliance", 0))),
		int(notes.get("refused", 0)), MoneyText.plural(int(notes.get("refused", 0))),
	]
