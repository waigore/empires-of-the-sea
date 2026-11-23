class_name CommandLedgerPanel
extends SheetFrame
## The crown's commanders: every general its pool holds, the medals each wears
## and the study that raises the cap next (wiki: military-generals § Generals,
## § Count and tech-gated cap, § Medals; DR-20261115-11), plus the hosts the land
## pass would lead this turn and how many of them the pool answers
## (DR-20261122-02), one press from the sheet that prints those hosts
## (DR-20261123-06). The projection lives in [CommandLedger] and the map hooks in
## [MapPlayCommand] and [MapPlayCommandPick]; this class only renders the reading
## (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door park come from
## SheetFrame.

## The door under the gold line: the fights the line names are printed on THE
## CROWN'S ARMY, and the press takes the crown there rather than leaving the
## names to be hunted across a closed sheet (REQ-P5-01, REQ-P5-03).
const ARMY_DOOR: String = "Open the army"
const ARMY_TIP: String = (
	"THE CROWN'S ARMY — the standards the fights this line names wear the mark"
)

var _summary: Label = null
var _road: VBoxContainer = null
var _medal: Label = null
var _fallback: Label = null
var _rows: VBoxContainer = null
var _empty: Label = null
var _army_door: Button = null


func _init() -> void:
	title_text = "THE CROWN'S COMMAND"
	hint_text = (
		"A commander is drawn for each battle from this pool. The roll reads "
		+ "the pool as it stands and names the hosts the court would lead; it "
		+ "never appoints one."
	)
	toggle_action = InputActions.COMMAND_LEDGER
	# The reading is the panel's own method, not a closure handed in from the
	# session: a bound callable cannot outlive the session it reads
	# (DR-20261121-14).
	counsel_source = _read_counsel


## The fights the court's own pass would start and the commanders that answer
## them, read off the pool the sheet already painted (wiki: military-generals
## § Assignment; DR-20261122-02). The pick travels whole, so the line and the
## door under it come off one read and the press can never open a sheet the
## sentence does not answer (DR-20261123-06).
func _read_counsel(data: Dictionary) -> Dictionary:
	return MapPlayCommandPick.pick(play, data)


## Re-reads the crown's pool and repaints the view.
func refresh() -> void:
	if play == null:
		return
	_snapshot = MapPlayCommand.snapshot(play)
	_fit()
	_paint()
	_sync_counsel()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	return Icon.new("crown", 42.0, Palette.GOLD)


func _build_body(column: VBoxContainer) -> void:
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)

	# The court's own reading: the hosts the land pass would lead this turn and
	# the commanders that answer them, in the gold every counsel line wears.
	_counsel_line(column)

	# The door the fights answer: the line names hosts, and the sheet that
	# prints them is THE CROWN'S ARMY, whose own line marks the standards they
	# lead — so the reading stands one press from the page it answers
	# (wiki: military-generals § The hosts the court would lead;
	# DR-20261123-06; REQ-P5-01, REQ-P5-03). It stands only while a fight is
	# named: no fight, no sheet to open (REQ-P5-06).
	_army_door = UiRowBuilder.door(ARMY_DOOR, ARMY_TIP, _on_army_door)
	_army_door.visible = false
	column.add_child(_army_door)

	# The road: every study that raises the cap, in the wiki's order, so a
	# crown reads why it holds one commander and what the second costs.
	_road = VBoxContainer.new()
	_road.add_theme_constant_override("separation", 2)
	column.add_child(_road)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	_append_scroll(column).add_child(_rows)
	_empty = _make_empty(_rows)

	_medal = _note(column)
	_fallback = _note(column)


## A footnote under the roll: what a medal buys and who leads when none is free.
func _note(column: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.85))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	return label


func _on_profile_changed() -> void:
	if visible and not _snapshot.is_empty():
		_paint()
		_sync_counsel()


# --- the door the fights answer ----------------------------------------------


## Stands the door under the line, then reads the court's own line: one gate for
## both, so the press and the sentence that raises it appear and stand down
## together (REQ-P5-06, REQ-P1-05).
func _sync_counsel() -> void:
	super()
	_sync_army_door()


## Shown only while the reading names a fight — the fights live on THE CROWN'S
## ARMY, and a reading of no host leaves no page to open (DR-20261123-06).
func _sync_army_door() -> void:
	if _army_door == null:
		return
	var named: bool = _counsel != null and _counsel.visible
	_army_door.visible = named and MapPlayCommandPick.leads(_counsel.pick)


## THE CROWN'S ARMY, where the standards the line names wear the counsel's mark.
## This sheet steps aside for it, and an army sheet already standing is left
## standing rather than toggled shut (DR-20261123-06; REQ-P5-01, REQ-P5-07).
func _on_army_door() -> void:
	var army: SheetFrame = null
	if play != null and play.hud != null:
		army = HudLedgerDoors.sheet_for(play.hud, HudLedgerDoors.ARMY)
	if army == null or not army.is_open():
		door_pressed.emit(HudLedgerDoors.ARMY)
	close()


## The door under the line, for tests and smoke tooling (REQ-P3-02).
func army_press() -> Button:
	return _army_door


## Whether the door stands with the fights its line names (REQ-P5-06).
func army_press_shown() -> bool:
	return _army_door != null and _army_door.visible


# --- rows --------------------------------------------------------------------


func _paint() -> void:
	_paint_road()
	_subtitle.text = CommandLedger.summary(_snapshot)
	_medal.text = CommandLedger.medal_line()
	_fallback.text = CommandLedger.fallback_line(_snapshot)
	var rows: Array = _snapshot.get("rows", []) as Array
	_empty.visible = rows.is_empty()
	if rows.is_empty():
		_empty.text = (
			"The crown holds no commanders: only a Great Power musters a general."
		)
		return
	LedgerList.flat(_rows, _empty, rows, _make_row)


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := CommandLedgerRow.new()
	row.compact = compact
	row.setup(raw as Dictionary)
	return row


func _paint_road() -> void:
	for child: Node in _road.get_children():
		_road.remove_child(child)
		child.queue_free()
	var road: Array = _snapshot.get("road", []) as Array
	if road.is_empty():
		_road.visible = false
		return
	_road.visible = true
	for raw: Variant in road:
		var rung: Dictionary = raw
		var label := Label.new()
		var unlocked: bool = bool(rung.get("unlocked", false))
		label.text = "Cap %d · %s — %s" % [
			int(rung["cap"]),
			String(rung["name"]),
			"studied" if unlocked else "not studied",
		]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override(
			"font_color", Palette.GOLD if unlocked else Palette.TEXT_DIM
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_road.add_child(label)
