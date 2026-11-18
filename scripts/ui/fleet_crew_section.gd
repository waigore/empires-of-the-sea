class_name FleetCrewSection
extends FleetDossierSection
## The fleet dossier's passenger block (DR-20261109-17): who is aboard, idle
## civilians to take on, coasts to put them ashore, and the home squadron's
## sortie zones. Emits intents; CivilianVoyage and FleetSortie own the rules.
##
## A landing is a **tile**, not a province (wiki: civilian-units § Landing), so a
## coast with one legal ground lands in one press while a coast with several
## opens its grounds first and the crown names the tile it means (DR-20261118-19).

## The coast whose grounds are open, or -1 for the coast list. It lives on the
## block, not in the rebuilt rows, so a choice survives the redraw every order
## and every turn makes (REQ-P5-05).
var open_coast: int = -1
var _data: Dictionary = {}


func _ready() -> void:
	_setup("PASSENGERS")


## Empty data hides the block; every row is one tap on a phone.
func set_data(crew: Dictionary) -> void:
	_data = crew
	# A coast that has left the reading (the last passenger landed on it, the
	# squadron sailed) takes its open grounds with it (REQ-P5-05).
	if open_coast >= 0 and _coast_row(open_coast).is_empty():
		open_coast = -1
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
		_add_grounds(_coast_row(open_coast))
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


## One line per coast: a single legal ground lands in one press, a coast with
## several opens its grounds so the crown reads the tile before it signs.
func _add_coast(row: Dictionary) -> void:
	var name: String = String(row.get("name", "the coast"))
	var tiles: Array = row.get("tiles", [])
	if tiles.is_empty():
		return
	if tiles.size() == 1:
		var only: Dictionary = tiles[0] as Dictionary
		_add_row(
			"Put ashore at %s" % name,
			"crew:land:%d:%d" % [int(only.get("x", -1)), int(only.get("y", -1))]
		)
		return
	_add_press(
		"Put ashore at %s · %d grounds ›" % [name, tiles.size()],
		func() -> void:
			open_coast = int(row.get("province", -1))
			_render()
	)


## The chosen coast's grounds, one tap per tile, with the way back above them.
## A press lands on that very tile and closes the list, so the redraw after the
## landing reads the coasts again (wiki: civilian-units § Landing).
func _add_grounds(row: Dictionary) -> void:
	var name: String = String(row.get("name", "the coast"))
	_add_press(
		"‹ Back to the coasts",
		func() -> void:
			open_coast = -1
			_render()
	)
	var tiles: Array = row.get("tiles", [])
	for raw: Variant in tiles:
		var tile: Dictionary = raw as Dictionary
		var x: int = int(tile.get("x", -1))
		var y: int = int(tile.get("y", -1))
		_add_press(
			"%s (%d, %d)" % [name, x, y],
			func() -> void:
				open_coast = -1
				_render()
				action_pressed.emit("crew:land:%d:%d" % [x, y])
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


func _coast_row(province: int) -> Dictionary:
	for raw: Variant in _data.get("land", []):
		var row: Dictionary = raw as Dictionary
		if int(row.get("province", -1)) == province:
			return row
	return {}
