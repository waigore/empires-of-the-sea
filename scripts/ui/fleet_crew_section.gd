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
## what the crown can read of the tile.

## The coast whose grounds are open, or -1 for the coast list, and the crew kind
## whose grounds they are. They live on the block, not in the rebuilt rows, so a
## choice survives the redraw every order and every turn makes (REQ-P5-05).
var open_coast: int = -1
var open_crew: String = ""
var _data: Dictionary = {}


func _ready() -> void:
	_setup("PASSENGERS")


## Empty data hides the block; every row is one tap on a phone.
func set_data(crew: Dictionary) -> void:
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
	visible = count > 0 or not embark.is_empty() or not land.is_empty() \
		or not sortie.is_empty()
	_begin(String(_data.get("note", "")))
	if open_coast >= 0:
		_add_grounds(_coast_row(open_coast, open_crew))
		return
	for raw: Variant in land:
		_add_coast(raw as Dictionary)
	for raw: Variant in embark:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Take %s aboard" % String(row.get("name", "a civilian")),
			"crew:embark:%d" % int(row.get("id", -1))
		)
	for raw: Variant in sortie:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Put to sea into %s" % String(row.get("name", "the roads")),
			"sortie:%d" % int(row.get("zone", -1))
		)


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
			"Put the %s ashore at %s" % [crew_name, name],
			"crew:land:%d:%d:%s" % [int(only.get("x", -1)), int(only.get("y", -1)), crew]
		)
		return
	_add_press(
		"Put the %s ashore at %s · %d grounds ›" % [crew_name, name, tiles.size()],
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
	_add_press(
		"‹ Back to the coasts",
		func() -> void:
			open_coast = -1
			open_crew = ""
			_render()
	)
	var tiles: Array = row.get("tiles", [])
	for raw: Variant in tiles:
		var tile: Dictionary = raw as Dictionary
		var x: int = int(tile.get("x", -1))
		var y: int = int(tile.get("y", -1))
		var ground: String = String(tile.get("ground", ""))
		var text: String = "%s (%d, %d)" % [name, x, y]
		if not ground.is_empty():
			text = "%s (%d, %d) — %s" % [name, x, y, ground]
		_add_press(
			text,
			func() -> void:
				open_coast = -1
				open_crew = ""
				_render()
				action_pressed.emit("crew:land:%d:%d:%s" % [x, y, crew])
		)


## A row that runs a local press instead of emitting an intent (opening a
## coast's grounds, and the way back out of them).
func _add_press(text: String, run: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(run)
	_rows_box.add_child(button)


func _coast_row(province: int, crew: String) -> Dictionary:
	for raw: Variant in _data.get("land", []):
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == province \
			and String(row.get("crew", "")) == crew:
			return row
	return {}
