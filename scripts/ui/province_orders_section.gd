class_name ProvinceOrdersSection
extends VBoxContainer
## The province's order rail: muster, build, the gated town order, the capital
## yard and the civilian muster list. It reads state handed over by the dossier
## and emits intents — the rules decide whether an order may run (REQ-P3-02).

signal action_pressed(action: String)

## A gated row's clause, lifted toward white the way the stat chips lift crimson:
## the dossier is a dark sheet, and the gate must stay legible on a phone.
const GATE_INK := Color(0.765, 0.460, 0.460)
## The mark the counsel reads by: the craft the court's own hire order takes
## wears it before its name, the mark the roster's crews and the yard's rows
## wear (DR-20261122-12).
const COURT_MARK: String = "▸"

var town_button: Button = null
## The province's wall and its ward, pressed from the sheet that reads them:
## each sends the nearest idle Engineer on the same work the civilian panel
## files, and greys with the order's own refusal (wiki: siege-mechanics
## § Fort Levels; combat § Regiment condition; DR-20261116-01, DR-20261116-02).
var wall_button: Button = null
var wall_note: Label = null
var ward_button: Button = null
var ward_note: Label = null
var shipyard_button: Button = null
var training_box: VBoxContainer = null
## The hire reading above the craft rows: the crew the court's own hire order
## takes next at this capital, or the gate that holds it (DR-20261121-06). The
## pick is kept whole so the line and the craft row's mark come off one read
## (DR-20261122-12).
var _hire_line: Label = null
var _hire_pick: Dictionary = {}
## type_id -> {"button", "note", "caption"}: one row per craft the roster offers,
## so a refresh can re-read every hire's study gate (DR-20261118-09) and the
## rail can re-dress the one craft the court's pick names (DR-20261122-12).
var _train_rows: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var caption := Label.new()
	caption.text = "ORDERS"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(caption)

	var recruit := _order_button("Recruit Regiment")
	recruit.tooltip_text = "Muster at your capital; the regiment joins the Home Army."
	recruit.pressed.connect(func() -> void: action_pressed.emit("recruit"))
	add_child(recruit)

	shipyard_button = _order_button("Shipyard")
	shipyard_button.tooltip_text = "Launch and break up hulls at your capital port."
	shipyard_button.pressed.connect(func() -> void: action_pressed.emit("shipyard"))
	shipyard_button.visible = false
	add_child(shipyard_button)

	var build := _order_button("Build Improvement")
	build.pressed.connect(func() -> void: action_pressed.emit("build"))
	add_child(build)

	town_button = _order_button("Upgrade Town")
	town_button.tooltip_text = DossierCopy.TOWN_TIP
	town_button.pressed.connect(func() -> void: action_pressed.emit("upgrade_town"))
	add_child(town_button)

	# The wall and the ward: the sheet that reads them carries the one press
	# that raises each, sending the nearest idle Engineer on the work the
	# civilian panel files (wiki: siege-mechanics § Fort Levels; combat
	# § Regiment condition; DR-20261120-12).
	wall_button = _order_button("Raise Wall")
	wall_button.pressed.connect(func() -> void: action_pressed.emit("raise_wall"))
	add_child(wall_button)
	wall_note = _payoff_note()
	add_child(wall_note)

	ward_button = _order_button("Raise Ward")
	ward_button.pressed.connect(func() -> void: action_pressed.emit("raise_ward"))
	add_child(ward_button)
	ward_note = _payoff_note()
	add_child(ward_note)

	training_box = VBoxContainer.new()
	training_box.add_theme_constant_override("separation", 6)
	training_box.visible = false
	add_child(training_box)

	var training := Label.new()
	training.text = "TRAIN CIVILIANS"
	training.add_theme_font_size_override("font_size", 11)
	training.add_theme_color_override("font_color", Palette.TEXT_DIM)
	training_box.add_child(training)

	# The one reading above the craft rows: the crew the court's own hire order
	# takes next, so a crown with six rails and one purse reads the pick before
	# it presses (wiki: civilian-units § Training; DR-20261121-06).
	_hire_line = Label.new()
	_hire_line.add_theme_font_size_override("font_size", 11)
	_hire_line.add_theme_color_override("font_color", Palette.GOLD)
	_hire_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hire_line.visible = false
	training_box.add_child(_hire_line)

	for type_id: String in CivilianCatalog.playable_types():
		# The button and its line stay one row: what the craft does, and the study
		# it waits on, under the price it is asked (DR-20261118-09).
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		training_box.add_child(row)
		var row_caption: String = "Train %s · %s" % [
			CivilianCatalog.display_name(type_id),
			CivilianCatalog.training_cost_text(type_id),
		]
		var train := _order_button(row_caption)
		train.add_theme_font_size_override("font_size", 13)
		train.pressed.connect(func() -> void: action_pressed.emit("train_%s" % type_id))
		row.add_child(train)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 11)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(note)
		_train_rows[type_id] = {
			"button": train, "note": note, "caption": row_caption,
		}
	# A dossier built before any study is read keeps the gated rows greyed.
	set_training({})


## The town order is offered, not refused: the button greys out with the rule's
## own reason until the crown can actually raise the town (REQ-P2-03).
## `stockpile` is the crown's live purse when the caller knows it; null leaves
## the money gate to the order that charges it.
func set_town_order(
	data: ProvinceState, faction: int, tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	var refusal: String = ""
	if faction >= 0 and data.owner != faction:
		refusal = "This land is not held by your crown."
	if refusal.is_empty():
		refusal = CivilianWorkRefusals.town_upgrade(data, tech_unlocked, stockpile)
	town_button.disabled = not refusal.is_empty()
	town_button.tooltip_text = DossierCopy.TOWN_TIP if refusal.is_empty() else refusal


## The province's wall order: the press carried by the sheet that reads the
## wall. It greys with the order's own refusal — the fort table's level, study
## and stores, or the idle Engineer the press sends — and prints under the
## price what the next level soaks and mounts (wiki: siege-mechanics § Fort
## Levels; DR-20261116-01, DR-20261117-05; REQ-P2-03, REQ-P5-07).
func set_wall_order(
	model: MapModel,
	data: ProvinceState,
	faction: int,
	units: Array[CivilianState],
	tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	if wall_button == null:
		return
	var level: int = FortRules.clamp_level(data.fort_level) if data != null else 0
	var next: int = FortRules.next_level(level)
	var refusal: String = ""
	if data == null or faction < 0 or data.owner != faction:
		refusal = "This land is not held by your crown."
	else:
		refusal = ImprovementOrders.wall_refusal(
			model, units, faction, data.id, tech_unlocked, stockpile
		)
	_show_step(
		wall_button, wall_note, "Raise Wall", refusal,
		WallLedger.preview_text(level, next),
		CivilianWorkPlan.cost_text(FortRules.cost(next)), FortRules.turns(next)
	)


## The province's ward order, on the same one press: the ward table's level,
## study and stores, the idle Engineer and the town tile another crew may hold,
## then what the next ward rests and feeds (wiki: combat § Regiment condition;
## DR-20261116-02; docs/hospitals.md).
func set_ward_order(
	model: MapModel,
	data: ProvinceState,
	faction: int,
	units: Array[CivilianState],
	tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	if ward_button == null:
		return
	var level: int = HospitalRules.clamp_level(data.hospital_level) if data != null else 0
	var next: int = HospitalRules.next_level(level)
	var refusal: String = ""
	if data == null or faction < 0 or data.owner != faction:
		refusal = "This land is not held by your crown."
	else:
		refusal = ImprovementOrders.ward_refusal(
			model, units, faction, data.id, tech_unlocked, stockpile
		)
	_show_step(
		ward_button, ward_note, "Raise Ward", refusal,
		HospitalLedger.preview_text(level, next),
		CivilianWorkPlan.cost_text(HospitalRules.cost(next)), HospitalRules.turns(next)
	)


## One raise press: the caption names the step and its price while the press is
## open, the press greys on the order's own refusal (kept whole in the tooltip
## and in the note, in the gate's ink), and an open press prints what the next
## level buys under it — printed, never a hover, so a phone reads the prize
## before the tap (REQ-P5-07).
func _show_step(
	button: Button, note: Label, caption: String, refusal: String,
	payoff: String, price: String, turns: int
) -> void:
	var open: bool = refusal.is_empty()
	var wait: String = "%d turn%s" % [turns, "" if turns == 1 else "s"]
	if open:
		button.text = "%s · %s" % [caption, price]
		button.tooltip_text = "%s — %s, %s" % [caption, price, wait]
	else:
		button.text = caption
		button.tooltip_text = refusal
	button.disabled = not open
	note.text = payoff if open else refusal
	note.visible = not note.text.is_empty()
	note.add_theme_color_override("font_color", Palette.GOLD if open else GATE_INK)


## A raise press's note line: gold while it prices what the next step buys, the
## gate's ink when it carries the order's refusal.
func _payoff_note() -> Label:
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.visible = false
	return note


## The yard is a capital-port order: it launches hulls into the home fleet
## (wiki: ships-and-naval § Home Fleet).
func set_shipyard_visible(visible: bool) -> void:
	shipyard_button.visible = visible


func set_training_visible(visible: bool) -> void:
	training_box.visible = visible


## The rail's one reading over the craft rows: the pick the court's own hire
## order answers with — the crew it takes next, or the gate that holds it
## (DR-20261121-06). The row that crew's craft stands on leads with COURT_MARK
## off this same pick, so the mark cannot name a craft the line does not
## (DR-20261122-12). An empty pick clears both, so a dossier read for a province
## that hires no crews carries neither.
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
		var caption: String = String(entry.get("caption", ""))
		var button: Button = entry["button"]
		var marked: bool = not crew.is_empty() and type_id == crew
		button.text = ("%s %s" % [COURT_MARK, caption]) if marked else caption


## The rail's hire reading, exposed so a suite asserts the line instead of
## reaching into the label (REQ-P3-02).
func hire_line_text() -> String:
	return _hire_line.text if _hire_line != null else ""


## The craft the rail marks, exposed so a suite asserts the mark instead of
## reading button captions (REQ-P3-02).
func hire_mark_crew() -> String:
	return String(_hire_pick.get("crew", ""))


## Every hire names what the craft does and the study it waits on, and a gated
## row greys out with the same reading the order refuses on — a crown reads on the
## rail what it would otherwise only hear in a refusal toast (wiki: civilian-units
## § Training; DR-20261118-09; REQ-P2-03, REQ-P5-05).
func set_training(tech_unlocked: Dictionary) -> void:
	for type_id: String in _train_rows.keys():
		var entry: Dictionary = _train_rows[type_id]
		var tech: String = CivilianHire.locked_tech(type_id, tech_unlocked)
		var open: bool = tech.is_empty()
		var button: Button = entry["button"]
		button.disabled = not open
		button.tooltip_text = (
			"Engaged at your capital; the crew musters when the turn closes."
			if open
			else "Requires %s." % TechCatalog.display_name(tech)
		)
		var note: Label = entry["note"]
		note.text = CivilianHire.line(type_id, tech_unlocked)
		note.add_theme_color_override("font_color", Palette.GOLD if open else GATE_INK)


## One craft's row, for the sheet's own reading and the tests that prove it.
func training_row(type_id: String) -> Dictionary:
	return _train_rows.get(type_id, {}) as Dictionary


func _order_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 15)
	return button
