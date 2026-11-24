class_name MapRegionToggle
extends PanelContainer
## The chart switch, on the map's top-left corner rather than the cartouche
## (issue #1164): a short pill naming the chart in play (OLD / NEW) with a
## chevron, small enough to stay off the chart and thumb-sized enough to press
## on a phone (REQ-P1-05, REQ-P1-07, REQ-P5-01).
##
## The screen still owns the swap: a press reports `cycle_pressed`, exactly the
## signal the bar's old region seal sent, so the map's own `_cycle_region` keeps
## one path. A one-chart world keeps the pill as context and stops offering a
## press, the same way the seal went inert (wiki: map-topology).

signal cycle_pressed

const PILL_SIZE := Vector2(58.0, 26.0)
## A one-chart world prints the chart it has and offers nothing to press.
const INERT_TIP := "%s — only charted region"

## The press target; `GameHud._region_button` reads it, so the screen's one
## inert/switchable rule stays where it was.
var button: Button = null
## The short chart word; `GameHud._region_label` reads it.
var label: Label = null


func _init() -> void:
	name = "MapRegionToggle"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Palette.with_alpha(Palette.PARCHMENT, 0.86), Palette.with_alpha(Palette.GOLD_DIM, 0.60), 1, 2,
			Vector4(4, 2, 4, 2)
		)
	)
	button = Button.new()
	button.name = "ChartDoor"
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = PILL_SIZE
	button.tooltip_text = "Switch chart — Old World / New World"
	button.pressed.connect(func() -> void: cycle_pressed.emit())
	add_child(button)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var mark := TextureRect.new()
	mark.name = "Mark"
	mark.texture = ChromeIcons.texture("road")
	mark.custom_minimum_size = Vector2(12, 12)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)

	label = Label.new()
	label.name = "Caption"
	label.text = "OLD"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)


## The chart in play, in the screen's own label ("OLD WORLD" / "NEW WORLD"),
## shortened to the one word the pill has room for. `switchable` is false on a
## one-chart world: the pill stays as context and takes no press.
func set_chart(region_label: String, switchable: bool = true) -> void:
	var full: String = region_label.strip_edges()
	if label != null:
		label.text = full.split(" ")[0].to_upper() if not full.is_empty() else "MAP"
	if button == null:
		return
	button.disabled = not switchable
	button.focus_mode = Control.FOCUS_ALL if switchable else Control.FOCUS_NONE
	button.tooltip_text = (
		"Switch chart — %s" % full if switchable else INERT_TIP % full
	)
