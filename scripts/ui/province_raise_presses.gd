class_name ProvinceRaisePresses
extends VBoxContainer
## The province dossier's raise presses: the gated town order, then the wall and
## the ward, each one press that sends the nearest idle Engineer onto the work
## the civilian panel files (wiki: siege-mechanics § Fort Levels; combat
## § Regiment condition; DR-20261116-01, DR-20261116-02, DR-20261120-12).
##
## A press greys on the order's own refusal and prints why under it in the
## gate's ink; open, it names its price and what the next step buys — printed,
## never a hover, so a phone reads the prize before the tap (REQ-P2-03,
## REQ-P5-07). The captions are registered with the sheet's [PressMarks] book, so
## the raise the court's own pass would file wears the counsel's mark and the
## rules' words are never overwritten (DR-20261122-23). The block prints and
## emits the intent; the rules decide whether an order may run (REQ-P3-02).

signal action_pressed(action: String)

## A gated row's clause, lifted toward white the way the stat chips lift crimson:
## the dossier is a dark sheet, and the gate must stay legible on a phone.
const GATE_INK := Color(0.765, 0.460, 0.460)
## The rail's presses, keyed by the action each files — the same keys the
## court's own reading hands back (DR-20261122-23).
const KEY_TOWN: String = MapPlayProvinceCounsel.KEY_TOWN
const KEY_WALL: String = MapPlayProvinceCounsel.KEY_WALL
const KEY_WARD: String = MapPlayProvinceCounsel.KEY_WARD
## Every raise press this block prints, in the order it prints them.
const PRESS_KEYS: Array[String] = [KEY_TOWN, KEY_WALL, KEY_WARD]
const NOT_HELD: String = "This land is not held by your crown."

var town_button: Button = null
var wall_button: Button = null
var wall_note: Label = null
var ward_button: Button = null
var ward_note: Label = null
## The rail's caption book, owned by the section that prints the whole rail, so
## one reading marks every press on the sheet.
var _marks: PressMarks = null
## The presses by key, so a caption re-dress reads one by lookup.
var _presses: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 8)


## Builds the presses, appending each to the sheet in the rail's order.
func build(marks: PressMarks) -> void:
	if town_button != null:
		return
	_marks = marks
	town_button = _press("Upgrade Town", "upgrade_town", DossierCopy.TOWN_TIP, KEY_TOWN)
	# The wall and the ward: the sheet that reads them carries the one press
	# that raises each (DR-20261120-12).
	wall_button = _press("Raise Wall", "raise_wall", "", KEY_WALL)
	wall_note = _note()
	ward_button = _press("Raise Ward", "raise_ward", "", KEY_WARD)
	ward_note = _note()


## The town order is offered, not refused: the press greys out with the rule's
## own reason until the crown can actually raise the town (REQ-P2-03).
## `stockpile` is the crown's live purse when the caller knows it; null leaves
## the money gate to the order that charges it.
func set_town_order(
	data: ProvinceState, faction: int, tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	if town_button == null:
		return
	var refusal: String = NOT_HELD if faction >= 0 and data.owner != faction else ""
	if refusal.is_empty():
		refusal = CivilianWorkRefusals.town_upgrade(data, tech_unlocked, stockpile)
	town_button.disabled = not refusal.is_empty()
	town_button.tooltip_text = DossierCopy.TOWN_TIP if refusal.is_empty() else refusal


## The province's wall order: the fort table's level, study and stores, or the
## idle Engineer the press sends, then what the next level soaks and mounts
## (wiki: siege-mechanics § Fort Levels; DR-20261116-01, DR-20261117-05).
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
		refusal = NOT_HELD
	else:
		refusal = ImprovementOrders.wall_refusal(
			model, units, faction, data.id, tech_unlocked, stockpile
		)
	_show_step(
		wall_button, wall_note, "Raise Wall", refusal,
		WallLedger.preview_text(level, next),
		CivilianWorkPlan.cost_text(FortRules.cost(next)), FortRules.turns(next),
		KEY_WALL
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
		refusal = NOT_HELD
	else:
		refusal = ImprovementOrders.ward_refusal(
			model, units, faction, data.id, tech_unlocked, stockpile
		)
	_show_step(
		ward_button, ward_note, "Raise Ward", refusal,
		HospitalLedger.preview_text(level, next),
		CivilianWorkPlan.cost_text(HospitalRules.cost(next)), HospitalRules.turns(next),
		KEY_WARD
	)


## Re-dresses every press off the rail's current reading: the caption is the
## rules' own words kept in the book, marked when the court's pass names it.
func refresh_marks() -> void:
	for key: String in PRESS_KEYS:
		var button: Button = _presses.get(key) as Button
		var caption: String = _marks.text(key)
		if button != null and not caption.is_empty():
			button.text = caption


## One press's caption as the rail prints it — marked or plain (REQ-P3-02).
func press_text(key: String) -> String:
	var button: Button = _presses.get(key) as Button
	return button.text if button != null else ""


## The block's readings as the sheet keeps them, so tests and tooling can read
## one raise press without reaching into its children: the wall and ward presses
## with the notes under them (REQ-P5-07), and the town press whose gate the sheet
## reads (REQ-P2-03).
func wall_order() -> Dictionary:
	return {"button": wall_button, "note": wall_note}


func ward_order() -> Dictionary:
	return {"button": ward_button, "note": ward_note}


func town_press() -> Button:
	return town_button


## One raise press: the caption names the step and its price while the press is
## open, and it greys on the order's own refusal (kept whole in the tooltip and
## in the note). The caption is kept as the rules worded it, and wears the
## counsel's mark when the court's own pass would press this step.
func _show_step(
	button: Button, note: Label, caption: String, refusal: String,
	payoff: String, price: String, turns: int, key: String
) -> void:
	var open: bool = refusal.is_empty()
	var wait: String = "%d turn%s" % [turns, "" if turns == 1 else "s"]
	_marks.set_caption(key, ("%s · %s" % [caption, price]) if open else caption)
	button.text = _marks.text(key)
	button.tooltip_text = (
		"%s — %s, %s" % [caption, price, wait] if open else refusal
	)
	button.disabled = not open
	note.text = payoff if open else refusal
	note.visible = not note.text.is_empty()
	note.add_theme_color_override("font_color", Palette.GOLD if open else GATE_INK)


func _press(caption: String, action: String, tip: String, key: String) -> Button:
	var button := UiRowBuilder.button(caption, 40.0, 0.0, 15)
	button.tooltip_text = tip
	button.pressed.connect(func() -> void: action_pressed.emit(action))
	_presses[key] = button
	_marks.set_caption(key, caption)
	add_child(button)
	return button


## A raise press's note line: gold while it prices what the next step buys, the
## gate's ink when it carries the order's refusal.
func _note() -> Label:
	var note := UiRowBuilder.wrapped_line("", 11, Palette.GOLD)
	note.visible = false
	add_child(note)
	return note
