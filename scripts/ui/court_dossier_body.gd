class_name CourtDossierBody
extends VBoxContainer
## The full dossier's page (wiki: ai-dossier § Logical sections): intel, the
## reading, one row per agenda with the timeline that fed it, the whole
## observation list, and the behaviour/build notes. Presentation only —
## [IntelDossier] does the arithmetic, so this body never reads a rival's agenda
## and never names it (REQ-P2-03, REQ-P5-01).
##
## Rows are collapsed by default; the reading worth naming starts open so the
## first thing the court reads is the agenda the evidence points at.

const MAX_PER_AGENDA: int = 8

var subject: int = -1

var _expanded: Dictionary = {}


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)


## Renders one court's reading. `report` is [IntelDossier.report]'s answer.
func show_report(
	report: Dictionary, state: DiplomacyState, world: WorldMap, viewer: int, faction_id: int
) -> void:
	subject = faction_id
	_expanded.clear()
	var guess: Dictionary = report.get("guess", {}) as Dictionary
	if not guess.is_empty():
		_expanded[String(guess["id"])] = true
	_clear()
	_add_intel(state, world, viewer, report)
	_reading(report)
	_add_agendas(report)
	_add_timeline(report)
	_add_notes(report)


## Basic intel: the court's public face, holdings against the crown's and the
## herald's word. Never a private order of battle.
func _add_intel(
	state: DiplomacyState, world: WorldMap, viewer: int, report: Dictionary
) -> void:
	var flavour: Dictionary = _flavour(subject)
	var face: String = String(flavour.get("title", ""))
	var leader: String = String(flavour.get("leader", ""))
	var line: String = leader
	if not face.is_empty():
		line = "%s  ·  %s" % [leader, face] if not leader.is_empty() else face
	if not line.is_empty():
		add_child(_line(line, 13, Palette.TEXT))
	var provinces: int = int((report.get("notes", {}) as Dictionary).get("province", 0))
	var mine: int = DiplomacyRules.provinces_owned(world, viewer) if world != null else 0
	add_child(
		_line(
			"Holds %d province%s to your %d." % [
				provinces, "" if provinces == 1 else "s", mine
			],
			13,
			Palette.TEXT
		)
	)
	var record: DiplomacyRelation = state.relation(viewer, subject) if state != null else null
	if record != null:
		add_child(
			_line(
				"Herald: %s  ·  %s" % [record.meter_label(), _standing(record)],
				13,
				Palette.TEXT_DIM
			)
		)
	add_child(_caption("SUSPICION"))


## The best guess in one line: a band and a percentage, never a claim of what
## the agenda truly is.
func _reading(report: Dictionary) -> void:
	var guess: Dictionary = report.get("guess", {}) as Dictionary
	var text: String = "Reading: too little to band — the acts below are noted, nothing more."
	if not guess.is_empty():
		text = "Reading: %s %s (%d%%)." % [
			String(guess["band"]), String(guess["label"]), int(guess["confidence"])
		]
	elif (report.get("evidence", []) as Array).is_empty():
		text = "Reading: no act has yet spoken of this court."
	add_child(_line(text, 16, Palette.GOLD_PALE))


func _add_agendas(report: Dictionary) -> void:
	var rows: Array = report.get("agendas", []) as Array
	for raw: Variant in rows:
		_add_agenda(raw as Dictionary)


## One agenda: a row that toggles its own timeline, so the page reads as a table
## at a glance and as a story on demand.
func _add_agenda(row: Dictionary) -> void:
	var open: bool = bool(_expanded.get(String(row["id"]), false))
	var button := _row_button(_agenda_text(row, open))
	add_child(button)
	var timeline := VBoxContainer.new()
	timeline.add_theme_constant_override("separation", 2)
	timeline.visible = open
	_add_agenda_lines(timeline, row["timeline"] as Array)
	add_child(timeline)
	button.pressed.connect(
		func() -> void:
			var now: bool = not timeline.visible
			timeline.visible = now
			_expanded[String(row["id"])] = now
			button.text = _agenda_text(row, now)
	)


func _add_agenda_lines(box: VBoxContainer, timeline: Array) -> void:
	if timeline.is_empty():
		box.add_child(_line("No observable act feeds this reading yet.", 12, Palette.TEXT_DIM))
		return
	var shown: int = mini(timeline.size(), MAX_PER_AGENDA)
	for index in shown:
		var entry: Dictionary = timeline[index] as Dictionary
		box.add_child(
			_line(
				"%s  ·  %s  ·  +%d" % [
					DiplomacyHistory.stamp_for_turn(int(entry["turn"])),
					String(entry["text"]),
					int(entry["points"]),
				],
				12,
				Palette.TEXT
			)
		)
	if timeline.size() > shown:
		box.add_child(
			_line(
				"…and %d earlier observation%s." % [
					timeline.size() - shown, "" if timeline.size() - shown == 1 else "s"
				],
				11,
				Palette.TEXT_DIM
			)
		)


## The whole record, newest first — the same page the summary trims to three.
func _add_timeline(report: Dictionary) -> void:
	var entries: Array = report.get("evidence", []) as Array
	add_child(_caption("TIMELINE  ·  EVERY OBSERVATION"))
	if entries.is_empty():
		add_child(_line("No observable act has been written down.", 13, Palette.TEXT_DIM))
		return
	for raw: Variant in entries:
		var entry: Dictionary = raw as Dictionary
		add_child(
			_line(
				"%s  ·  %s" % [
					DiplomacyHistory.stamp_for_turn(int(entry["turn"])), String(entry["text"])
				],
				13,
				Palette.TEXT
			)
		)


## Behaviour, counted, plus what a spy watched the court build: themes, never an
## inference, and no agenda weighed on them (DR-20261110-25).
func _add_notes(report: Dictionary) -> void:
	var notes: Dictionary = report.get("notes", {}) as Dictionary
	add_child(_caption("BEHAVIOUR & BUILD NOTES"))
	add_child(
		_line(
			"%d war%s  ·  %d alliance%s  ·  %d broken  ·  %d call%s refused  ·  %d peace%s" % [
				int(notes.get("war", 0)), _plural(int(notes.get("war", 0))),
				int(notes.get("alliance", 0)), _plural(int(notes.get("alliance", 0))),
				int(notes.get("broken", 0)),
				int(notes.get("refused", 0)), _plural(int(notes.get("refused", 0))),
				int(notes.get("peace", 0)), _plural(int(notes.get("peace", 0))),
			],
			13,
			Palette.TEXT
		)
	)
	add_child(_line(_build_line(notes), 13, Palette.TEXT_DIM))


func _agenda_text(row: Dictionary, open: bool) -> String:
	var marker: String = "▾" if open else "▸"
	return "%s  %s  ·  %s %d%%  ·  %d pt%s" % [
		marker,
		String(row["label"]),
		String(row["band"]),
		int(row["confidence"]),
		int(row["score"]),
		"" if int(row["score"]) == 1 else "s",
	]


func _build_line(notes: Dictionary) -> String:
	var builds: Dictionary = notes.get("build", {}) as Dictionary
	var studies: int = int(notes.get("spy_tech", 0))
	if builds.is_empty() and studies == 0:
		return "No spy has watched this court's builders or its studies yet."
	var parts: PackedStringArray = []
	if studies > 0:
		parts.append("%d finished stud%s" % [studies, "y" if studies == 1 else "ies"])
	for what: String in ["improvement", "town", "road", "port", "fort", "hospital", "rail"]:
		var count: int = int(builds.get(what, 0))
		if count > 0:
			parts.append("%d %s" % [count, _build_label(what, count)])
	return "Under your spy's eye: %s." % ", ".join(parts)


## The public face of a crown: the leader it fields and the archetype that
## leader plays (leader-bonuses, ai-personalities). Never its hidden agenda.
func _flavour(faction: int) -> Dictionary:
	var leader: String = LeaderCatalog.default_key(faction)
	var title: String = ""
	for entry: Dictionary in LeaderCatalog.VARIANTS:
		if String(entry["key"]) == leader and int(entry["faction"]) == faction:
			title = String(entry["name"])
			break
	var profile: Dictionary = AiPersonality.ARCHETYPES.get(leader, AiPersonality.NEUTRAL)
	return {"leader": title, "title": String(profile.get("title", "")).capitalize()}


static func _standing(record: DiplomacyRelation) -> String:
	if record.at_war:
		return "at war"
	if record.formal_alliance:
		return "formal alliance"
	return DiplomacyCatalog.state_label(false)


static func _plural(count: int) -> String:
	return "" if count == 1 else "s"


static func _build_label(what: String, count: int) -> String:
	var labels: Dictionary = {
		"improvement": "estate%s",
		"town": "town%s finished",
		"road": "road%s",
		"port": "port%s",
		"fort": "fort%s",
		"hospital": "hospital%s",
		"rail": "rail line%s",
	}
	return String(labels.get(what, "%ss")) % _plural(count)


func _row_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _caption(text: String) -> Label:
	return _label(text, 11, Palette.GOLD_DIM)


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
