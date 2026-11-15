class_name ProvinceResources
extends VBoxContainer
## The province dossier's estate block: one line per resource tile the province
## holds, each saying whether the estate is developed and whether it reaches the
## crown (wiki: extraction-and-improvements, capital-and-connectivity).
## Rows come from ResourceSurvey, so the dossier, the estates ledger and the
## survey lens never disagree about an estate (REQ-P3-02, REQ-P3-03).
##
## A developed estate the crown cannot reach carries **Build road**: one tap
## dispatches an idle Engineer onto the first tile of the route RoadWorks plans
## (issue #671). The block only prints the plan and emits the intent.

signal road_pressed(tile: Vector2i)

const CAPTION: String = "RESOURCES"
const LINKED: String = "linked"
const UNLINKED: String = "no road"
const FOREIGN: String = "foreign"
const EMPTY: String = "No charted resource tiles in this province."
const ROAD: String = "Build road"

var _lines: Array[Dictionary] = []
var _roads: Dictionary = {}
var _body: VBoxContainer = null
var _empty: Label = null
var _survey: Label = null


func _ready() -> void:
	if _body != null:
		return
	add_theme_constant_override("separation", 5)
	var caption := Label.new()
	caption.text = CAPTION
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(caption)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	add_child(_body)
	_empty = Label.new()
	_empty.text = EMPTY
	_empty.add_theme_font_size_override("font_size", 12)
	_empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty)
	# Ground still to survey: the hook that sends an Explorer out, since a
	# mineral is hidden until the crown prospects its tile (DR-20261111-26).
	_survey = Label.new()
	_survey.add_theme_font_size_override("font_size", 12)
	_survey.add_theme_color_override("font_color", Palette.GOLD_DIM)
	_survey.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_survey.visible = false
	add_child(_survey)
	render(_lines)


## Rows as last rendered, so a caller (or a test) can read what the player sees.
func lines() -> Array[Dictionary]:
	return _lines


## The road plan RoadWorks handed in for one estate, or {} when it needs none.
func road_plan(tile: Vector2i) -> Dictionary:
	return _roads.get(tile, {})


## The survey hook as last rendered ("" when every prospectable tile is known).
func survey_text() -> String:
	return _survey.text if _survey != null and _survey.visible else ""


## One line per estate. An empty list says the province holds no charted
## resource tile; `unsurveyed` names the ground an Explorer could still read.
## `roads` maps a tile to the plan RoadWorks read for it, so a cut-off estate
## carries its Build road control (issue #671).
func render(rows: Array[Dictionary], unsurveyed: int = 0, roads: Dictionary = {}) -> void:
	_lines = rows
	_roads = roads
	if _body == null:
		_ready()
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows:
		_body.add_child(_line(row))
	_empty.visible = rows.is_empty()
	if rows.is_empty() and unsurveyed > 0:
		_empty.text = "No estates charted — %s still unsurveyed." % _tiles(unsurveyed)
	else:
		_empty.text = EMPTY
	_survey.visible = unsurveyed > 0
	_survey.text = "Unsurveyed ground: %s — an Explorer can prospect it." % _tiles(unsurveyed)


func _tiles(count: int) -> String:
	return "%d tile%s" % [count, "" if count == 1 else "s"]


# --- one estate --------------------------------------------------------------


func _line(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.tooltip_text = _tip(row)
	line.add_child(_art(row))
	var title := _text(_title(row), 14, Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	line.add_child(_text(_level_text(row), 13, _level_color(row), 30))
	line.add_child(_text(_link_text(row), 12, _link_color(row), 62))
	var road: Dictionary = _roads.get(row["tile"], {})
	if bool(road.get("needed", false)):
		line.add_child(_road_button(row, road))
	return line


## The one-tap dispatch for a cut-off estate: an idle Engineer takes the first
## tile of the route. Disabled with the reason when no crew or no route exists,
## so the control never offers an order the rules would refuse (REQ-P2-03).
func _road_button(row: Dictionary, road: Dictionary) -> Button:
	var button := Button.new()
	button.text = ROAD
	button.custom_minimum_size = Vector2(0, 40 if _compact() else 30)
	button.add_theme_font_size_override("font_size", 12)
	var ready: bool = (
		bool(road.get("engineer", false))
		and not (road.get("route", []) as Array).is_empty()
	)
	button.disabled = not ready
	button.tooltip_text = _road_tip(road) if ready else String(road.get("reason", ""))
	button.pressed.connect(func() -> void: road_pressed.emit(row["tile"]))
	return button


func _road_tip(road: Dictionary) -> String:
	var gap: int = int(road.get("gap", 0))
	if gap <= 1:
		return "An Engineer lays the last road tile to this estate."
	return "An Engineer lays the first of %d road tiles to this estate." % gap


func _compact() -> bool:
	return HudLayout.is_compact(get_viewport_rect().size)



func _text(value: String, size: int, ink: Color, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0)
	return label


## The estate's own commodity medallion; a row whose good is not in the catalog
## keeps the category pictogram in that kind's commodity ink, so the line never
## loses its mark and the pictogram matches the survey lens (REQ-P1-02).
func _art(row: Dictionary) -> Control:
	var commodity: String = String(row["commodity"])
	if not commodity.is_empty():
		return CommodityIcons.badge(commodity, CommodityIcons.LINE_SIZE)
	var kind: String = String(row["icon"])
	return Icon.new(kind, 16, Palette.resource_ink(kind))


## The raw resource, not the works: "Timber", "Iron", "Grain".
func _title(row: Dictionary) -> String:
	var commodity: String = String(row["commodity"])
	if commodity.is_empty():
		return ImprovementCatalog.base_name(int(row["resource"]))
	return ImprovementCatalog.commodity_label(commodity).capitalize()


## Development is a level, or a dash while the tile is still bare.
func _level_text(row: Dictionary) -> String:
	var level: int = int(row["level"])
	return "L%d" % level if level > 0 else "—"


func _level_color(row: Dictionary) -> Color:
	if bool(row["working"]):
		return Palette.SURVEY_BUILDING
	if int(row["level"]) > 0:
		return Palette.GOLD_PALE
	return Palette.TEXT_DIM


## The second fact the dossier must carry: does this estate reach the crown?
func _link_text(row: Dictionary) -> String:
	if not bool(row["ours"]):
		return FOREIGN
	if bool(row["connected"]):
		return LINKED
	return UNLINKED


func _link_color(row: Dictionary) -> Color:
	if not bool(row["ours"]):
		return Palette.SURVEY_FOREIGN
	if bool(row["connected"]):
		return Palette.SURVEY_YIELDING
	return Palette.SURVEY_VACANT


func _tip(row: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var works: String = ImprovementCatalog.base_name(int(row["resource"]))
	var level: int = int(row["level"])
	var grade: String = "level %d" % level if level > 0 else "vacant"
	parts.append("%s · %s" % [works, grade])
	if bool(row["working"]):
		var left: int = int(row["remaining"])
		parts.append("Builder at work · %d turn%s left" % [left, "" if left == 1 else "s"])
	if not bool(row["ours"]):
		parts.append("held by another crown")
	elif not bool(row["connected"]):
		parts.append("no road to the capital — it yields nothing yet")
	elif int(row["output"]) > 0:
		parts.append("reaches the capital · %s" % ImprovementCatalog.output_text(
			int(row["resource"]), int(row["output"])
		))
	else:
		parts.append("reaches the capital")
	return " · ".join(parts)
