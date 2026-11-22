class_name ProvinceOrdersSection
extends VBoxContainer
## The province's order rail: muster, build, the gated town order, the capital
## yard and the civilian muster list. It reads state handed over by the dossier
## and emits intents — the rules decide whether an order may run (REQ-P3-02).
##
## The sheet's three jobs live in their own blocks: [ProvinceRaisePresses] owns
## the town, wall and ward presses and their gates, and the muster list below
## owns each craft's row and study gate. This rail prints them in order, settles
## the yard, and dresses every press off the one [PressMarks] reading.

signal action_pressed(action: String)

## The mark the counsel reads by: the craft the court's own hire order takes
## wears it before its name, the mark the roster's crews and the yard's rows
## wear (DR-20261122-12). The book's own glyph, so no sheet mints a second.
const COURT_MARK: String = PressMarks.MARK
## The rail's presses, keyed by the action each files — the same keys the
## court's own reading hands back, so the gold line and the marked press come
## off one read (DR-20261122-23).
const KEY_IMPROVEMENT: String = MapPlayProvinceCounsel.KEY_IMPROVEMENT
const KEY_TOWN: String = MapPlayProvinceCounsel.KEY_TOWN
const KEY_WALL: String = MapPlayProvinceCounsel.KEY_WALL
const KEY_WARD: String = MapPlayProvinceCounsel.KEY_WARD
## Every press the rail prints, in the order it prints them.
const PRESS_KEYS: Array[String] = [KEY_IMPROVEMENT, KEY_TOWN, KEY_WALL, KEY_WARD]
## What the mark means, printed under the rail while one stands: a phone reads
## no footer hint and never shows a hover (REQ-P1-07).
const MARK_LEGEND: String = "▸ marks the order the court would give here"

var shipyard_button: Button = null
## The estate raise's own press: the court's Builder order on this ground.
var build_button: Button = null
## The town, wall and ward presses, with the gates that grey them.
var _raises: ProvinceRaisePresses = null
## The craft rows and the hire reading above them.
var _muster: ProvinceMusterBlock = null
## The rail's press captions and the keys the court's own reading names: the
## book prints each press as the rules worded it, marked when its key stands
## (DR-20261122-23).
var _marks: PressMarks = PressMarks.new()
## The rail's presses by key, so a reading marks one by lookup.
var _presses: Dictionary = {}
## The mark's legend under the rail, standing only while a mark does.
var _legend: Label = null


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiRowBuilder.caption("ORDERS", 11, Palette.TEXT_DIM))

	var recruit := _order_button("Recruit Regiment")
	recruit.tooltip_text = "Muster at your capital; the regiment joins the Home Army."
	recruit.pressed.connect(func() -> void: action_pressed.emit("recruit"))
	add_child(recruit)

	shipyard_button = _order_button("Shipyard")
	shipyard_button.tooltip_text = "Launch and break up hulls at your capital port."
	shipyard_button.pressed.connect(func() -> void: action_pressed.emit("shipyard"))
	shipyard_button.visible = false
	add_child(shipyard_button)

	build_button = _order_button("Build Improvement")
	build_button.pressed.connect(func() -> void: action_pressed.emit("build"))
	_presses[KEY_IMPROVEMENT] = build_button
	_marks.set_caption(KEY_IMPROVEMENT, build_button.text)
	add_child(build_button)

	# The town, wall and ward: each one press, each greying on its own order's
	# refusal, each marking with the same reading the gold line prints.
	_raises = ProvinceRaisePresses.new()
	_raises.build(_marks)
	_raises.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	add_child(_raises)

	# The mark's legend under the rail, standing only while a press wears the
	# mark: a phone reads what ▸ means without a hover (REQ-P1-07).
	_legend = UiRowBuilder.wrapped_line(MARK_LEGEND, 10, Palette.TEXT_DIM)
	_legend.visible = false
	add_child(_legend)

	# The muster list: the one hire reading over one row per craft the roster
	# offers, each row carrying its study gate (DR-20261118-09, DR-20261121-06).
	_muster = ProvinceMusterBlock.new()
	_muster.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	add_child(_muster)


## The town order is offered, not refused: the button greys out with the rule's
## own reason until the crown can actually raise the town (REQ-P2-03).
## `stockpile` is the crown's live purse when the caller knows it; null leaves
## the money gate to the order that charges it.
func set_town_order(
	data: ProvinceState, faction: int, tech_unlocked: Dictionary,
	stockpile: Variant = null
) -> void:
	_raises.set_town_order(data, faction, tech_unlocked, stockpile)


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
	_raises.set_wall_order(model, data, faction, units, tech_unlocked, stockpile)


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
	_raises.set_ward_order(model, data, faction, units, tech_unlocked, stockpile)


## The yard is a capital-port order: it launches hulls into the home fleet
## (wiki: ships-and-naval § Home Fleet).
func set_shipyard_visible(visible: bool) -> void:
	shipyard_button.visible = visible


func set_training_visible(visible: bool) -> void:
	_muster.visible = visible


## The rail's one reading over the craft rows: the pick the court's own hire
## order answers with — the crew it takes next, or the gate that holds it
## (DR-20261121-06). The row that crew's craft stands on leads with COURT_MARK
## off this same pick, so the mark cannot name a craft the line does not
## (DR-20261122-12). An empty pick clears both.
func set_hire_pick(pick: Dictionary) -> void:
	_muster.set_hire_pick(pick)


## The rail's hire reading, exposed so a suite asserts the line (REQ-P3-02).
func hire_line_text() -> String:
	return _muster.hire_line_text()


## The craft the rail marks, exposed so a suite asserts the mark instead of
## reading button captions (REQ-P3-02).
func hire_mark_crew() -> String:
	return _muster.hire_mark_crew()


## The rail's reading of the court's own pass: the presses it would file here,
## keyed by the action each files. Each named press leads with COURT_MARK and the
## legend stands, off the one read the gold line above prints; an empty reading
## clears every mark (wiki: world-model § The crown's provinces; DR-20261122-23).
func set_court_marks(marks: Dictionary) -> void:
	_marks.mark(marks)
	_raises.refresh_marks()
	for key: String in PRESS_KEYS:
		var button: Button = _presses.get(key) as Button
		var caption: String = _marks.text(key)
		if button != null and not caption.is_empty():
			button.text = caption
	if _legend != null:
		_legend.visible = _marks.any()


## The presses this reading names, exposed so a suite asserts the marks instead
## of reading button captions (REQ-P3-02).
func court_marks() -> Dictionary:
	return _marks.keys()


## One press's caption as the rail prints it — marked or plain (REQ-P3-02).
func press_text(key: String) -> String:
	var button: Button = _presses.get(key) as Button
	if button != null:
		return button.text
	return _raises.press_text(key)


## The legend's own words, or "" while no mark stands (REQ-P1-07).
func court_legend_text() -> String:
	return _legend.text if _legend != null and _legend.visible else ""


## Every craft's row: what the craft does and the study it waits on, and a gated
## row greys out with the same reading the order refuses on — a crown reads on the
## rail what it would otherwise only hear in a refusal toast (wiki: civilian-units
## § Training; DR-20261118-09; REQ-P2-03, REQ-P5-05).
func set_training(tech_unlocked: Dictionary) -> void:
	_muster.set_training(tech_unlocked)


## One craft's row, for the sheet's own reading and the tests that prove it.
func training_row(type_id: String) -> Dictionary:
	return _muster.training_row(type_id)


## The town press whose gate the sheet reads (REQ-P2-03).
func town_press() -> Button:
	return _raises.town_press()


## The wall press and the note under it, as one reading (REQ-P5-07).
func wall_order() -> Dictionary:
	return _raises.wall_order()


## The ward press and the note under it, as one reading (REQ-P5-07).
func ward_order() -> Dictionary:
	return _raises.ward_order()


func _order_button(text: String) -> Button:
	return UiRowBuilder.button(text, 40.0, 0.0, 15)
