class_name ProvinceSheetShell
extends VBoxContainer
## The province dossier's frame: the scrolling column its sections print into,
## the gold hairline between them, the standing hint and the dock seal. The
## panel keeps the reading and the order rail; the shell keeps the chrome, so
## the dossier's build stays a list of sections instead of a god method
## (REQ-P3-01, RUB-P3-01).

## The dock seal was pressed: the panel it frames decides which side it opens on.
signal dock_pressed

const HINT: String = "Civilians muster at the capital; estates are managed from the ledger."
const HINT_INK: Color = Color(0.74, 0.68, 0.55, 0.6)
## The gold hairline that divides the dossier's sections.
const RULE_INK: Color = Color(0.83, 0.69, 0.22, 0.35)

## The column the dossier's sections print into, so a compact sheet can move the
## order rail above the survey table.
var column: VBoxContainer = null
## The scrolling body, so a suite can read what a phone shows without scrolling.
var scroll: ScrollContainer = null
## The one dock affordance, pinned under the body.
var dock: Button = null


func _ready() -> void:
	if column != null:
		return
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)
	dock = UiRowBuilder.small_button("◀", "Dock left")
	dock.size_flags_horizontal = Control.SIZE_SHRINK_END
	dock.pressed.connect(func() -> void: dock_pressed.emit())
	footer.add_child(dock)


## A section under a hairline: the dossier never repeats the rule between its
## blocks (REQ-P3-01).
func add_section(section: Control) -> void:
	column.add_child(UiRowBuilder.rule(RULE_INK))
	column.add_child(section)


## A block that sits directly under the one above it — the head and the gold
## counsel line, which the head already divides from the facts.
func add_block(block: Control) -> void:
	column.add_child(block)


## The standing hint under the last section: what the sheet does not order.
func add_hint() -> void:
	UiRowBuilder.spacer(column, 4)
	column.add_child(UiRowBuilder.wrapped_line(HINT, 11, HINT_INK))


## The dock seal's glyph and tip, so the panel names the side it opens on.
func set_dock_affordance(glyph: String, tip: String) -> void:
	if dock == null:
		return
	dock.text = glyph
	dock.tooltip_text = tip
