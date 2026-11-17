class_name ProvinceRailBlock
extends VBoxContainer
## The province dossier's rail block: one line per crown road tile that can
## still go rail, each carrying **Lay railroad** — the press that sends the
## nearest idle Rail Builder onto that tile (wiki: civilian-units § Rail Builder
## work; DR-20261117-10).
##
## The block exists because a railroad is the one work order the crew's own
## sheet cannot press away from its own tile: the court's pick names a road
## ahead of the crew, so the province dossier carries the press that follows it
## (REQ-P5-06). Rows come from [RailWorks], so the block, the pick's line and
## the crew's own order list never disagree about what can be railed
## (REQ-P3-02). The block only prints the plan and emits the intent.

signal rail_pressed(tile: Vector2i)

const CAPTION: String = "RAILROADS"
const RAIL: String = "Lay railroad"

var _rows: Array[Dictionary] = []
var _body: VBoxContainer = null
var _caption: Label = null


func _ready() -> void:
	if _body != null:
		return
	add_theme_constant_override("separation", 5)
	_caption = Label.new()
	_caption.text = CAPTION
	_caption.add_theme_font_size_override("font_size", 11)
	_caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(_caption)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)
	render(_rows)


## Rows as last rendered, so a caller (or a test) can read what the player sees.
func rows() -> Array[Dictionary]:
	return _rows


## One line per rail-ready road tile. An empty list hides the whole block: a
## province with nothing to rail says nothing rather than printing a heading
## over no ground (REQ-P1-07).
func render(rows: Array[Dictionary]) -> void:
	_rows = rows
	if _body == null:
		# The first render builds the block, which renders these rows itself.
		_ready()
		return
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		_body.add_child(_line(row))
	visible = not rows.is_empty()


func _line(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var plan: Dictionary = row.get("plan", {})
	line.tooltip_text = _tip(row, plan)
	var title := _text(_title(row), 13, Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	line.add_child(_text("transport %d" % int(row.get("transport", 0)), 12, Palette.GOLD_PALE))
	line.add_child(_button(row, plan))
	return line


## The one-tap dispatch: disabled with the reason when no idle Rail Builder
## musters, so the control never offers an order the rules would refuse
## (REQ-P2-03).
func _button(row: Dictionary, plan: Dictionary) -> Button:
	var button := Button.new()
	button.text = RAIL
	button.custom_minimum_size = Vector2(0, 40 if _compact() else 30)
	button.add_theme_font_size_override("font_size", 12)
	var ready: bool = bool(plan.get("rail_builder", false))
	button.disabled = not ready
	button.tooltip_text = (
		"A Rail Builder lays a railroad on this tile."
		if ready else String(plan.get("reason", ""))
	)
	button.pressed.connect(func() -> void: rail_pressed.emit(row["tile"]))
	return button


## The estate the tile carries, or plain ground: the line names what the rail
## would serve, then the tile the press names.
func _title(row: Dictionary) -> String:
	var tile: Vector2i = row["tile"]
	var estate: String = String(row.get("estate", ""))
	if estate.is_empty():
		return "Road (%d, %d)" % [tile.x, tile.y]
	return "%s (%d, %d)" % [estate, tile.x, tile.y]


func _tip(row: Dictionary, plan: Dictionary) -> String:
	var tile: Vector2i = row["tile"]
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Road at (%d, %d) · transport %d" % [
		tile.x, tile.y, int(row.get("transport", 0))
	])
	parts.append("a railroad lifts it to transport 4")
	if not bool(plan.get("rail_builder", false)):
		parts.append(String(plan.get("reason", "")))
	return " · ".join(parts)


func _compact() -> bool:
	return HudLayout.is_compact(get_viewport_rect().size)


func _text(value: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
