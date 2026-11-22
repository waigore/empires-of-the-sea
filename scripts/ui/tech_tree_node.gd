class_name TechTreeNode
extends Button
## One advance on the college's chart: its series medallion and its name, ringed
## in the ink its standing earns — known, at study, open now, or still shut —
## and lit gold when it lies on the aimed advance's road (DR-20261115-15). The
## canvas owns selection; this node only reports a press and a hover.

signal hovered(tech_id: String)

const FONT_PIXELS: int = 11
## The medallion is its own child rather than `Button.icon`: a 128 px plate
## would set the button's minimum height and overlap the row below it.
const ICON_PIXELS: float = 20.0
const ICON_LEFT: float = 7.0
const TEXT_LEFT: float = 32.0
const MARGIN: Vector4 = Vector4(TEXT_LEFT, 2.0, 7.0, 2.0)

var tech_id: String = ""
var _plate: TextureRect = null


func setup(id: String) -> void:
	tech_id = id
	flat = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size = Vector2(TechTreeLayout.NODE_WIDTH, TechTreeLayout.NODE_HEIGHT)
	size = custom_minimum_size
	add_theme_font_size_override("font_size", FONT_PIXELS)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	tooltip_text = TechCatalog.effect_text(id)
	mouse_entered.connect(func() -> void: hovered.emit(tech_id))
	mouse_exited.connect(func() -> void: hovered.emit(""))
	_plate = _medallion(TechIcons.texture(id))
	if _plate != null:
		add_child(_plate)


## Repaints the node for this crown: the standing's ink, the goal diamond, the
## court's own `▸` when the published research policy would open this advance
## (DR-20261121-20), and, when the advance is on the aimed road, a gold ring
## heavier than the rest.
func paint(
	state: ResearchState, goal: String, on_path: bool, court: bool = false
) -> void:
	var kind: int = TechPlan.state_of(state, tech_id)
	var ink: Color = Palette.TEXT
	var ring: Color = Color(0.36, 0.30, 0.21)
	match kind:
		TechPlan.State.KNOWN:
			ink = Palette.GOLD_PALE
			ring = Palette.GOLD_DIM
		TechPlan.State.STUDYING:
			ink = Palette.GOLD
			ring = Palette.GOLD
		TechPlan.State.OPEN:
			ink = Palette.TEXT
			ring = Palette.TEXT_DIM
	var fill: Color = Color(0.13, 0.10, 0.07, 0.97)
	var width: int = 1
	if on_path:
		ring = Palette.GOLD_PALE
		fill = Color(0.22, 0.18, 0.08, 0.98)
		width = 2
	add_theme_color_override("font_color", ink)
	add_theme_color_override("font_hover_color", Palette.GOLD_PALE)
	add_theme_color_override("font_pressed_color", Palette.GOLD_PALE)
	add_theme_stylebox_override("normal", UiTheme.box(fill, ring, width, 3, MARGIN))
	add_theme_stylebox_override(
		"hover", UiTheme.box(fill.lightened(0.10), Palette.GOLD_PALE, width, 3, MARGIN)
	)
	add_theme_stylebox_override(
		"pressed", UiTheme.box(fill.lightened(0.18), Palette.GOLD_PALE, width, 3, MARGIN)
	)
	text = (
		("◆ " if tech_id == goal else "")
		+ ("▸ " if court else "")
		+ TechCatalog.display_name(tech_id)
	)


## The series medallion at the node's left edge, at a fixed size whatever the
## plate's own resolution. Null when no plate covers the tech.
static func _medallion(texture: Texture2D) -> TextureRect:
	if texture == null:
		return null
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.size = Vector2(ICON_PIXELS, ICON_PIXELS)
	picture.position = Vector2(ICON_LEFT, (TechTreeLayout.NODE_HEIGHT - ICON_PIXELS) * 0.5)
	return picture
