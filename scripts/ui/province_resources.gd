class_name ProvinceResources
extends VBoxContainer
## The province dossier's estate block: one line per resource tile the province
## holds, each saying whether the estate is developed and whether it reaches the
## crown (wiki: extraction-and-improvements, capital-and-connectivity).
## Rows come from ResourceSurvey, so the dossier, the estates ledger and the
## survey lens never disagree about an estate (REQ-P3-02, REQ-P3-03).

const CAPTION: String = "RESOURCES"
const LINKED: String = "linked"
const UNLINKED: String = "no road"
const FOREIGN: String = "foreign"
const EMPTY: String = "No charted resource tiles in this province."

var _lines: Array[Dictionary] = []
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


## The survey hook as last rendered ("" when every prospectable tile is known).
func survey_text() -> String:
	return _survey.text if _survey != null and _survey.visible else ""


## One line per estate. An empty list says the province holds no charted
## resource tile; `unsurveyed` names the ground an Explorer could still read.
func render(rows: Array[Dictionary], unsurveyed: int = 0) -> void:
	_lines = rows
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
	return line


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
## keeps the category pictogram, so the line never loses its mark (REQ-P1-02).
func _art(row: Dictionary) -> Control:
	var commodity: String = String(row["commodity"])
	if not commodity.is_empty():
		return CommodityIcons.badge(commodity, CommodityIcons.LINE_SIZE)
	return Icon.new(String(row["icon"]), 16, Palette.GOLD)


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
