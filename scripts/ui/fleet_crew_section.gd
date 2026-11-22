class_name FleetCrewSection
extends FleetDossierSection
## The fleet dossier's passenger block (DR-20261109-17): who is aboard, idle
## civilians to take on, coasts to put them ashore, and the home squadron's
## sortie zones. Emits intents; CivilianVoyage and FleetSortie own the rules.
##
## A landing is a **tile** and a **crew** (wiki: civilian-units § Landing), so the
## block reads one line per crew kind per coast — the crew and the ground are
## both the crown's to name (DR-20261118-19) — a coast with one legal ground lands
## in one press, and a coast with several opens its grounds first, each printing
## what the crown can read of the tile. The open grounds ride a window of whole
## rows of their own, so a port province's whole land never grows the sheet
## (DR-20261119-03).

## The mark the counsel reads by lives on the block (FleetDossierSection), so every
## subclass of the dossier prints one glyph (DR-20261122-21).

## The coast whose grounds are open, or -1 for the coast list, and the crew kind
## whose grounds they are. They live on the block, not in the rebuilt rows, so a
## choice survives the redraw every order and every turn makes (REQ-P5-05).
var open_coast: int = -1
var open_crew: String = ""
## The open coast's grounds ride a window of whole rows of their own, so a port
## province's whole land never grows the dossier's scroll (DR-20261119-03).
## `_ground_rows` is the count the window was last laid out for, so a resize can
## re-read it without a redraw.
var _ground_scroll: ScrollContainer = null
var _ground_box: VBoxContainer = null
var _ground_rows: int = 0
## The block's one press: every idle crew the hulls can hold, taken aboard in one
## signed line (DR-20261119-18). It stands at the block's foot and hides while a
## coast's grounds are open, so the block reads one thing at a time.
var _batch: RaiseBatchPress = null
var _batch_line: Label = null
## The voyage the court's own colonisation pass would make with this squadron,
## under the block's note and above its rows, in the gold the crew's own pick
## prints in: advice, never state (DR-20261121-08, REQ-P5-06).
var _pick: Label = null
var _data: Dictionary = {}
## The press the block's own gold line names, read once per render: `{kind,
## unit}` for a boarding, `{kind, province, crew, tile}` for a landing, and {}
## when the pick names no press this block prints — a sail, a dock, a crossing,
## or no reading at all (DR-20261122-21).
var _mark: Dictionary = {}


func _ready() -> void:
	_setup("PASSENGERS")
	_pick = UiRowBuilder.line(12, Palette.GOLD)
	_pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_pick)
	move_child(_pick, _note.get_index() + 1)
	_ground_scroll = ScrollContainer.new()
	_ground_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ground_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ground_scroll.visible = false
	add_child(_ground_scroll)
	_ground_box = VBoxContainer.new()
	_ground_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ground_box.add_theme_constant_override("separation", GroundsWindow.ROW_GAP)
	_ground_scroll.add_child(_ground_box)
	_make_batch()
	get_viewport().size_changed.connect(_fit_window)


## The block's one press, made once however the block is mounted: a suite hands it
## rows straight away, so it is not built on the first render.
func _make_batch() -> void:
	if _batch != null:
		return
	_batch = RaiseBatchPress.new()
	_batch.set_verb("take")
	_batch.confirmed.connect(func() -> void: action_pressed.emit("crew:embark:all"))
	_batch.visible = false
	add_child(_batch)
	_batch_line = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	_batch_line.visible = false
	add_child(_batch_line)


## Empty data hides the block; every row is one tap on a phone.
func set_data(crew: Dictionary) -> void:
	_make_batch()
	_data = crew
	# A coast that has left the reading (the last passenger landed on it, the
	# squadron sailed) takes its open grounds with it (REQ-P5-05).
	if open_coast >= 0 and _coast_row(open_coast, open_crew).is_empty():
		open_coast = -1
		open_crew = ""
	_render()


func _render() -> void:
	var embark: Array = _data.get("embark", [])
	var land: Array = _data.get("land", [])
	var sortie: Array = _data.get("sortie", [])
	var count: int = int(_data.get("count", 0))
	var pick: Dictionary = _data.get("pick", {})
	var pick_line: String = MapPlayPickProse.sentence(
		String(pick.get("line", ""))
	)
	visible = count > 0 or not embark.is_empty() or not land.is_empty() \
		or not sortie.is_empty() or not pick_line.is_empty()
	_begin(String(_data.get("note", "")))
	# The mark is the pick's own, read once with the sentence it answers, so a
	# marked press is always the one the gold line above it names (REQ-P2-03).
	_mark = _read_mark(pick)
	_legend()
	if _pick != null:
		_pick.text = pick_line
		_pick.visible = not pick_line.is_empty()
	_clear_grounds()
	if open_coast >= 0:
		_hide_batch()
		_add_grounds(_coast_row(open_coast, open_crew))
		return
	for raw: Variant in land:
		_add_coast(raw as Dictionary)
	for raw: Variant in embark:
		var row: Dictionary = raw as Dictionary
		_add_row(
			_mark_text(
				"Take %s aboard" % String(row.get("name", "a civilian")),
				_marks_embark(row)
			),
			"crew:embark:%d" % int(row.get("id", -1))
		)
	_sync_batch()
	for raw: Variant in sortie:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Put to sea into %s" % String(row.get("name", "the roads")),
			"sortie:%d" % int(row.get("zone", -1))
		)


## The block's one press, read from the plan the intent files: how many of the
## crews the rows print the hulls can hold now, and the reason the next one waits,
## printed under the press before it is signed (REQ-P5-04, REQ-P5-05;
## DR-20261119-18). A block with no idle crew hides it, and so does an open coast.
func _sync_batch() -> void:
	if _batch == null:
		return
	var plan: Dictionary = _data.get("embark_batch", {})
	var ready: int = int(plan.get("count", 0))
	_batch.set_ready(ready, EmbarkBatch.WORD, int(plan.get("filed", 0)))
	_batch.visible = ready > 0
	_batch_line.text = EmbarkBatch.wait_line(plan) if _batch.visible else ""
	_batch_line.visible = not _batch_line.text.is_empty()


## A coast's grounds are open: the block reads that list alone, so the press that
## boards a whole berth waits until the crown is back on the coasts.
func _hide_batch() -> void:
	if _batch == null:
		return
	_batch.disarm()
	_batch.visible = false
	_batch_line.visible = false
	_batch_line.text = ""


## One line per crew kind per coast: a single legal ground lands in one press, a
## coast with several opens its grounds so the crown reads the tile before it
## signs. The row names the crew, so a Builder and an Explorer aboard one
## squadron are not the same press (DR-20261118-19).
func _add_coast(row: Dictionary) -> void:
	var name: String = String(row.get("name", "the coast"))
	var crew: String = String(row.get("crew", ""))
	var crew_name: String = String(row.get("crew_name", "colonist"))
	var tiles: Array = row.get("tiles", [])
	if tiles.is_empty():
		return
	if tiles.size() == 1:
		var only: Dictionary = tiles[0] as Dictionary
		_add_row(
			_mark_text(
				"Put the %s ashore at %s" % [crew_name, name],
				_marks_coast(int(row.get("province", -1)), crew)
			),
			"crew:land:%d:%d:%s" % [int(only.get("x", -1)), int(only.get("y", -1)), crew]
		)
		return
	# The crown's own seat reads first, one press: a port province may hold a
	# whole province of legal ground, and a crown that only wants the crew ashore
	# at home should not open the list to find it (wiki: civilian-units § Landing).
	var seat: Dictionary = row.get("seat", {})
	if not seat.is_empty():
		_add_row(
			_mark_text(
				_seat_text(crew_name, name, seat),
				_marks_ground(int(seat.get("x", -1)), int(seat.get("y", -1)))
			),
			"crew:land:%d:%d:%s" % [int(seat.get("x", -1)), int(seat.get("y", -1)), crew]
		)
	_add_press(
		_mark_text(
			"Put the %s ashore at %s · %d grounds ›" % [crew_name, name, tiles.size()],
			_marks_coast(int(row.get("province", -1)), crew)
		),
		func() -> void:
			open_coast = int(row.get("province", -1))
			open_crew = crew
			_render()
	)


## The chosen coast's grounds, one tap per tile, with the way back above them.
## Each row prints what the crown can read of the ground — its terrain, and the
## commodity an estate there would work — because the tile decides what the
## landing charts and where the crew works next. A press lands that crew on that
## very tile and closes the list, so the redraw after the landing reads the
## coasts again (wiki: civilian-units § Landing).
func _add_grounds(row: Dictionary) -> void:
	var name: String = String(row.get("name", "the coast"))
	var crew: String = String(row.get("crew", ""))
	var tiles: Array = row.get("tiles", [])
	# The way back is pinned above the window, so a long coast never scrolls the
	# one press that leaves it out of reach (DR-20261119-03).
	_add_press(
		"‹ Back to the coasts · %d ground%s" % [tiles.size(), "" if tiles.size() == 1 else "s"],
		func() -> void:
			open_coast = -1
			open_crew = ""
			_render()
	)
	_open_window(tiles.size())
	for raw: Variant in tiles:
		var tile: Dictionary = raw as Dictionary
		_add_ground_row(name, crew, tile)


## Lays the open coast's list out as a window of whole rows: a coast short of
## the window's budget asks for its own height and reads exactly as it did, and
## a longer one scrolls inside the window so the dossier's other drawers stay a
## short swipe away (DR-20261119-03, REQ-P1-07).
func _open_window(count: int) -> void:
	_ground_rows = count
	_ground_scroll.visible = count > 0
	_fit_window()


## Re-reads the window's room: a phone gives it fewer rows than the atlas, and a
## turn of the device is the same sheet in a new room.
func _fit_window() -> void:
	if _ground_scroll == null or not is_inside_tree():
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	_ground_scroll.custom_minimum_size = Vector2(
		0.0, GroundsWindow.height(_ground_rows, compact)
	)


## One ground of the open coast: the tile's own press in the window.
func _add_ground_row(name: String, crew: String, tile: Dictionary) -> void:
	var x: int = int(tile.get("x", -1))
	var y: int = int(tile.get("y", -1))
	var ground: String = String(tile.get("ground", ""))
	var text: String = "%s (%d, %d)" % [name, x, y]
	if not ground.is_empty():
		text = "%s (%d, %d) — %s" % [name, x, y, ground]
	_add_ground_press(
		_mark_text(text, _marks_ground(x, y)),
		func() -> void:
			open_coast = -1
			open_crew = ""
			_render()
			action_pressed.emit("crew:land:%d:%d:%s" % [x, y, crew])
	)


## Empties the window when the block reads the coasts again, so no ground of a
## coast that has left the reading can be pressed.
func _clear_grounds() -> void:
	_ground_rows = 0
	if _ground_scroll == null:
		return
	_ground_scroll.visible = false
	UiRowBuilder.clear(_ground_box)


## The seat press's words: the province, the tile and what the chart reads of
## the ground, the same reading a ground row in the list prints.
func _seat_text(crew_name: String, name: String, seat: Dictionary) -> String:
	var text: String = "Put the %s ashore at %s (%d, %d)" % [
		crew_name, name, int(seat.get("x", -1)), int(seat.get("y", -1))
	]
	var ground: String = String(seat.get("ground", ""))
	if not ground.is_empty():
		text += " — %s" % ground
	return text


## A row that runs a local press instead of emitting an intent (opening a
## coast's grounds, and the way back out of them).
func _add_press(text: String, run: Callable) -> void:
	_rows_box.add_child(_press_button(text, run))


## The window's own rows: the same tap-sized press, kept in the scrolling box so
## a long coast never grows the sheet (DR-20261119-03).
func _add_ground_press(text: String, run: Callable) -> void:
	_ground_box.add_child(_press_button(text, run))


func _press_button(text: String, run: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, GroundsWindow.ROW_HEIGHT)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(run)
	return button


func _coast_row(province: int, crew: String) -> Dictionary:
	for raw: Variant in _data.get("land", []):
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == province \
			and String(row.get("crew", "")) == crew:
			return row
	return {}


# --- the court's mark (DR-20261122-21) ---------------------------------------


## The press the pick names, as this block prints it: a boarding names the crew
## it would take aboard, a landing the coast and the ground it would put her
## ashore on. Every other step — a sail, a dock, a crossing — names no press
## here, so it marks none (REQ-P2-03).
static func _read_mark(pick: Dictionary) -> Dictionary:
	var kind: String = String(pick.get("kind", ""))
	if kind == MapPlayVoyagePick.KIND_EMBARK:
		var unit: int = int(pick.get("unit", -1))
		return {"kind": kind, "unit": unit} if unit >= 0 else {}
	if kind != MapPlayVoyagePick.KIND_LAND:
		return {}
	var crew: String = String(pick.get("crew", ""))
	if crew.is_empty():
		return {}
	return {
		"kind": kind,
		"province": int(pick.get("province", -1)),
		"crew": crew,
		"tile": pick.get("tile", CivilianState.NO_TILE),
	}


## The block's own legend, on the note line it already prints: a crown that sees
## one press lead with `▸` reads what the glyph means without a hover
## (REQ-P1-05, REQ-P5-03).
func _legend() -> void:
	if _mark.is_empty():
		return
	var legend: String = "%s marks the press the court would take" % COURT_MARK
	_note.text = legend if _note.text.is_empty() else "%s  ·  %s" % [_note.text, legend]
	_note.visible = true


## The counsel's mark leads the press the line names, so a crown finds that row
## among the block's whole list (DR-20261122-21).
static func _mark_text(text: String, marked: bool) -> String:
	return "%s %s" % [COURT_MARK, text] if marked else text


## Whether this embark row is the crew the line would take aboard.
func _marks_embark(row: Dictionary) -> bool:
	return String(_mark.get("kind", "")) == MapPlayVoyagePick.KIND_EMBARK \
		and int(_mark.get("unit", -1)) == int(row.get("id", -2))


## Whether this coast is the one the line would put the crew ashore on.
func _marks_coast(province: int, crew: String) -> bool:
	return String(_mark.get("kind", "")) == MapPlayVoyagePick.KIND_LAND \
		and int(_mark.get("province", -1)) == province \
		and String(_mark.get("crew", "")) == crew


## Whether this ground is the tile the line would land on.
func _marks_ground(x: int, y: int) -> bool:
	return String(_mark.get("kind", "")) == MapPlayVoyagePick.KIND_LAND \
		and _mark.get("tile", CivilianState.NO_TILE) == Vector2i(x, y)


## The mark the block reads by, for tests and the smoke (REQ-P3-02).
func mark() -> Dictionary:
	return _mark
