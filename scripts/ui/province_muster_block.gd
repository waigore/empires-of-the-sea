class_name ProvinceMusterBlock
extends VBoxContainer
## The province dossier's civilian muster: one reading naming the crew the
## court's own hire order takes next, then one row per craft the roster offers —
## the press, its caption and the study it waits on (wiki: civilian-units
## § Training; DR-20261118-09, DR-20261121-06).
##
## The pick is kept whole, so the gold line and the row's mark come off one read
## and the mark can never name a craft the line does not (DR-20261122-12). A gated
## craft greys with the order's own reading, printed under the press, so a crown
## reads on the rail what it would otherwise only hear in a refusal toast
## (REQ-P2-03, REQ-P5-05). The block prints and emits the intent; the rules
## decide whether a hire may run (REQ-P3-02).

signal action_pressed(action: String)

## A gated row's clause, lifted toward white the way the stat chips lift crimson:
## the dossier is a dark sheet, and the gate must stay legible on a phone.
const GATE_INK := Color(0.765, 0.460, 0.460)
const CAPTION: String = "TRAIN CIVILIANS"
## What an open hire does with the press.
const OPEN_HIRE: String = "Engaged at your capital; the crew musters when the turn closes."

## type_id -> {"button", "note", "caption"}: one row per craft the roster offers,
## so a refresh can re-read every hire's study gate and re-dress the one craft
## the court's pick names.
var _train_rows: Dictionary = {}
## The hire reading above the craft rows, or null before the block is built.
var _hire_line: Label = null
## The pick the line is worded from, kept whole for the mark.
var _hire_pick: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 6)
	visible = false
	_build()
	# A block built before any study is read keeps the gated rows greyed.
	set_training({})


func _build() -> void:
	add_child(UiRowBuilder.caption(CAPTION, 11, Palette.TEXT_DIM))
	# The one reading above the craft rows: the crew the court's own hire order
	# takes next, so a crown with six rails and one purse reads the pick before
	# it presses (DR-20261121-06).
	_hire_line = UiRowBuilder.wrapped_line("", 11, Palette.GOLD)
	_hire_line.visible = false
	add_child(_hire_line)
	for type_id: String in CivilianCatalog.playable_types():
		# The button and its line stay one row: what the craft does, and the study
		# it waits on, under the price it is asked (DR-20261118-09).
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		add_child(row)
		var caption: String = "Train %s · %s" % [
			CivilianCatalog.display_name(type_id),
			CivilianCatalog.training_cost_text(type_id),
		]
		var train := UiRowBuilder.button(caption, 40.0, 0.0, 13)
		train.pressed.connect(func() -> void: action_pressed.emit("train_%s" % type_id))
		row.add_child(train)
		var note := UiRowBuilder.wrapped_line("", 11, GATE_INK)
		row.add_child(note)
		_train_rows[type_id] = {"button": train, "note": note, "caption": caption}


## The rail's one reading: the pick the court's own hire order answers with — the
## crew it takes next, or the gate that holds it. An empty pick clears both the
## line and the mark, so a province that hires no crews carries neither.
func set_hire_pick(pick: Dictionary) -> void:
	if _hire_line == null:
		return
	_hire_pick = pick if pick != null else {}
	# The hire words are already a printed sentence (their own full stop), so the
	# rail prints them as the pick words them rather than re-punctuating them.
	var text: String = String(_hire_pick.get("line", ""))
	_hire_line.text = text
	_hire_line.visible = not text.is_empty()
	_apply_hire_mark()


## The craft the court's own hire order names, or empty when it names none
## (`Every crew this region asks for already stands.`): the pick's own `crew`,
## never a second read (DR-20261122-12).
func _apply_hire_mark() -> void:
	var crew: String = String(_hire_pick.get("crew", ""))
	for type_id: String in _train_rows.keys():
		var entry: Dictionary = _train_rows[type_id]
		var button: Button = entry["button"]
		var caption: String = String(entry["caption"])
		var marked: bool = not crew.is_empty() and type_id == crew
		button.text = ("%s %s" % [PressMarks.MARK, caption]) if marked else caption


## The block's hire reading, exposed so a suite asserts the line (REQ-P3-02).
func hire_line_text() -> String:
	return _hire_line.text if _hire_line != null else ""


## The craft the block marks, exposed so a suite asserts the mark instead of
## reading button captions (REQ-P3-02).
func hire_mark_crew() -> String:
	return String(_hire_pick.get("crew", ""))


## Every craft's row: a gated craft greys out with the study it waits on, in the
## order's own words (DR-20261118-09; REQ-P2-03, REQ-P5-05).
func set_training(tech_unlocked: Dictionary) -> void:
	for type_id: String in _train_rows.keys():
		var entry: Dictionary = _train_rows[type_id]
		var tech: String = CivilianHire.locked_tech(type_id, tech_unlocked)
		var open: bool = tech.is_empty()
		var button: Button = entry["button"]
		button.disabled = not open
		button.tooltip_text = (
			OPEN_HIRE if open else "Requires %s." % TechCatalog.display_name(tech)
		)
		var note: Label = entry["note"]
		note.text = CivilianHire.line(type_id, tech_unlocked)
		note.add_theme_color_override("font_color", Palette.GOLD if open else GATE_INK)


## One craft's row, for the sheet's own reading and the tests that prove it.
func training_row(type_id: String) -> Dictionary:
	return _train_rows.get(type_id, {}) as Dictionary
