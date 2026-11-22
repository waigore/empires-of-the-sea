class_name FleetCrewGrounds
extends ScrollContainer
## The passengers block's open coast (DR-20261119-03): one tap per legal ground,
## laid out as a window of whole rows so a port province's whole land never grows
## the dossier's sheet (wiki: civilian-units § Landing). The block opens it with
## the coast's tiles and its court mark, and closes it on the way back or on a
## landing.
##
## The list owns the paint; GroundsWindow owns the row budget and FleetCrewMark
## says which ground leads. Every press carries its own tile and the crew the
## opening row named (DR-20261118-19, REQ-P3-02).

## The open coast's window: the same tap-sized press the dossier's rows keep,
## built by FleetDossierSection so a row reads the same on the sheet and inside
## the scroll.
var _box: VBoxContainer = null
var _rows: int = 0


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	visible = false
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", GroundsWindow.ROW_GAP)
	add_child(_box)


func _ready() -> void:
	get_viewport().size_changed.connect(fit)


## Opens one coast's grounds: each row lands that very tile on the crew the
## opening row named, through `on_land(x, y, crew)`.
func show_grounds(
	name: String, crew: String, tiles: Array, mark: Dictionary, on_land: Callable
) -> void:
	_rows = tiles.size()
	visible = _rows > 0
	fit()
	for raw: Variant in tiles:
		var tile: Dictionary = raw as Dictionary
		var x: int = int(tile.get("x", -1))
		var y: int = int(tile.get("y", -1))
		_add_ground(name, crew, x, y, String(tile.get("ground", "")), mark, on_land)


## Empties the window when the block reads the coasts again, so no ground of a
## coast that has left the reading can be pressed.
func clear_grounds() -> void:
	_rows = 0
	visible = false
	UiRowBuilder.clear(_box)


## Re-reads the window's room: a phone gives it fewer rows than the atlas, and a
## turn of the device is the same sheet in a new room.
func fit() -> void:
	if not is_inside_tree():
		return
	var compact: bool = HudLayout.is_compact(get_viewport_rect().size)
	custom_minimum_size = Vector2(0.0, GroundsWindow.height(_rows, compact))


## One ground of the open coast: the tile's own press, with what the crown can
## read of the ground — its terrain, and the commodity an estate there would
## work — laid beside the tile.
func _add_ground(
	name: String, crew: String, x: int, y: int, ground: String,
	mark: Dictionary, on_land: Callable
) -> void:
	var text: String = "%s (%d, %d)" % [name, x, y]
	if not ground.is_empty():
		text = "%s (%d, %d) — %s" % [name, x, y, ground]
	_box.add_child(FleetDossierSection.make_press(
		text,
		func() -> void: on_land.call(x, y, crew),
		FleetCrewMark.marks_ground(mark, x, y)
	))
