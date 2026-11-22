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
## what the crown can read of the tile. `FleetCrewGrounds` paints the open list as
## a window of whole rows of its own, so a port province's whole land never grows
## the sheet (DR-20261119-03).
##
## The mark the counsel reads by lives on the block (FleetDossierSection), and
## `FleetCrewMark` reads the press the voyage pick names, so every subclass of the
## dossier prints one glyph (DR-20261122-21).

## The coast whose grounds are open, or -1 for the coast list, and the crew kind
## whose grounds they are. They live on the block, not in the rebuilt rows, so a
## choice survives the redraw every order and every turn makes (REQ-P5-05).
var open_coast: int = -1
var open_crew: String = ""
## The open coast's grounds: a window of whole rows, so a port province's whole
## land never grows the dossier's scroll (DR-20261119-03).
var _grounds: FleetCrewGrounds = null
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
## when the pick names no press this block prints (DR-20261122-21).
var _mark: Dictionary = {}


func _ready() -> void:
	_setup("PASSENGERS")
	_pick = UiRowBuilder.line(12, Palette.GOLD)
	_pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_pick)
	move_child(_pick, _note.get_index() + 1)
	_grounds = FleetCrewGrounds.new()
	add_child(_grounds)
	_make_batch()


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
	_mark = FleetCrewMark.read(pick)
	_legend()
	if _pick != null:
		_pick.text = pick_line
		_pick.visible = not pick_line.is_empty()
	_grounds.clear_grounds()
	if open_coast >= 0:
		_hide_batch()
		_add_grounds(_coast_row(open_coast, open_crew))
		return
	for raw: Variant in land:
		_add_coast(raw as Dictionary)
	for raw: Variant in embark:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Take %s aboard" % String(row.get("name", "a civilian")),
			"crew:embark:%d" % int(row.get("id", -1)),
			FleetCrewMark.marks_embark(_mark, row)
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
	var province: int = int(row.get("province", -1))
	var tiles: Array = row.get("tiles", [])
	if tiles.is_empty():
		return
	if tiles.size() == 1:
		var only: Dictionary = tiles[0] as Dictionary
		_add_row(
			"Put the %s ashore at %s" % [crew_name, name],
			"crew:land:%d:%d:%s" % [int(only.get("x", -1)), int(only.get("y", -1)), crew],
			FleetCrewMark.marks_coast(_mark, province, crew)
		)
		return
	# The crown's own seat reads first, one press: a port province may hold a
	# whole province of legal ground, and a crown that only wants the crew ashore
	# at home should not open the list to find it (wiki: civilian-units § Landing).
	var seat: Dictionary = row.get("seat", {})
	if not seat.is_empty():
		_add_row(
			_seat_text(crew_name, name, seat),
			"crew:land:%d:%d:%s" % [int(seat.get("x", -1)), int(seat.get("y", -1)), crew],
			FleetCrewMark.marks_ground(
				_mark, int(seat.get("x", -1)), int(seat.get("y", -1))
			)
		)
	_add_row_press(
		"Put the %s ashore at %s · %d grounds ›" % [crew_name, name, tiles.size()],
		func() -> void: _open_coast(province, crew),
		FleetCrewMark.marks_coast(_mark, province, crew)
	)


## The chosen coast's grounds, one tap per tile, with the way back above them.
## Each row prints what the crown can read of the ground — its terrain, and the
## commodity an estate there would work — because the tile decides what the
## landing charts and where the crew works next (wiki: civilian-units § Landing).
func _add_grounds(row: Dictionary) -> void:
	var name: String = String(row.get("name", "the coast"))
	var crew: String = String(row.get("crew", ""))
	var tiles: Array = row.get("tiles", [])
	# The way back is pinned above the window, so a long coast never scrolls the
	# one press that leaves it out of reach (DR-20261119-03).
	_add_row_press(
		"‹ Back to the coasts · %d ground%s" % [
			tiles.size(), "" if tiles.size() == 1 else "s"
		],
		func() -> void: _open_coast(-1, "")
	)
	_grounds.show_grounds(name, crew, tiles, _mark, _land)


## Opens a coast's grounds, or closes them on `-1`, and repaints the block, so the
## state the redraw reads and the rows it prints always move together.
func _open_coast(province: int, crew: String) -> void:
	open_coast = province
	open_crew = crew
	_render()


## A ground's press: the crew lands on that very tile and the list closes, so the
## redraw after the landing reads the coasts again (wiki: civilian-units § Landing).
func _land(x: int, y: int, crew: String) -> void:
	_open_coast(-1, "")
	action_pressed.emit("crew:land:%d:%d:%s" % [x, y, crew])


## The seat press's words: the province, the tile and what the chart reads of the
## ground, the same reading a ground row in the list prints.
func _seat_text(crew_name: String, name: String, seat: Dictionary) -> String:
	var text: String = "Put the %s ashore at %s (%d, %d)" % [
		crew_name, name, int(seat.get("x", -1)), int(seat.get("y", -1))
	]
	var ground: String = String(seat.get("ground", ""))
	if not ground.is_empty():
		text += " — %s" % ground
	return text


func _coast_row(province: int, crew: String) -> Dictionary:
	for raw: Variant in _data.get("land", []):
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == province \
			and String(row.get("crew", "")) == crew:
			return row
	return {}


## The block's own legend, on the note line it already prints: a crown that sees
## one press lead with `▸` reads what the glyph means without a hover
## (REQ-P1-05, REQ-P5-03).
func _legend() -> void:
	if _mark.is_empty():
		return
	var legend: String = "%s marks the press the court would take" % COURT_MARK
	_note.text = legend if _note.text.is_empty() else "%s  ·  %s" % [_note.text, legend]
	_note.visible = true


## The mark the block reads by, for tests and the smoke (REQ-P3-02).
func mark() -> Dictionary:
	return _mark


## The open coast's window, for tests and the smoke (REQ-P3-02).
func grounds_window() -> ScrollContainer:
	return _grounds
