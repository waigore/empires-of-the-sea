class_name ObserverProvinceSheet
extends Control
## The observatory's province sheet (docs/ai-observer.md): what one province
## holds, read-only, for the full-AI observer tapping the chart.
##
## The sheet owns no reading and offers no order: `ObserverProvince` decides
## every word, the head and the fact grid paint them, and the estate block is
## the province dossier's own `ProvinceResources` fed with no road plans — so a
## rival province can never offer a press (REQ-P2-03, REQ-P3-02, REQ-P3-03).
##
## It docks on the right, opposite the observatory plate; on a phone it takes the
## screen, and Close gives the chart back (REQ-P1-05, REQ-P1-07).

## The observer pressed Close, so the reading is no longer the subject.
signal closed

const CAPTION: String = "READ-ONLY · THE OBSERVER'S PROVINCE"
const MARGIN: float = 12.0
## A wide chart gives the sheet a column; a phone gives it the screen.
const WIDE_WIDTH: float = 380.0
const DEFENCE_CAPTION: String = "DEFENCE"

var frame: PanelContainer = null
var head: ProvinceSheetHead = null
var grid: ProvinceFactsGrid = null
var band_label: Label = null
var defence_label: Label = null
var estates: ProvinceResources = null
var close_button: Button = null
## The province on the sheet, or -1 when none is (so a turn repaint knows what).
var province_id: int = -1

var _column: VBoxContainer = null
var _play: PlaySession = null


func _ready() -> void:
	name = "ObserverProvinceSheet"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_fit()
	get_viewport().size_changed.connect(_fit)
	visible = false


# --- build -------------------------------------------------------------------


func _build() -> void:
	frame = PanelContainer.new()
	frame.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Palette.with_alpha(Palette.PARCHMENT, 0.97), Palette.GOLD_DIM, 1, 4,
			Vector4(16, 14, 16, 14)
		)
	)
	add_child(frame)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	frame.add_child(shell)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)

	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 10)
	scroll.add_child(_column)

	head = ProvinceSheetHead.new()
	_column.add_child(head)
	# The shared seal is the sheet's one close door, in the head's right slot
	# (docs/ui-panels.md).
	close_button = head.close
	head.close_pressed.connect(func() -> void:
		clear()
		closed.emit()
	)
	# The observatory reads one province, not a crown's realm: the door to the
	# whole holding belongs to the human dossier, so the sheet keeps no press.
	head.realm_button.visible = false

	_column.add_child(_caption(CAPTION, Palette.TEXT_DIM, 11))
	_column.add_child(UiRowBuilder.rule())

	grid = ProvinceFactsGrid.new()
	_column.add_child(grid)

	_column.add_child(UiRowBuilder.rule())

	_column.add_child(_caption(DEFENCE_CAPTION, Palette.TEXT_DIM, 11))
	band_label = _caption("", Palette.GOLD_PALE, 14)
	_column.add_child(band_label)
	defence_label = _caption("", Palette.TEXT, 13)
	_column.add_child(defence_label)

	_column.add_child(UiRowBuilder.rule())

	estates = ProvinceResources.new()
	_column.add_child(estates)


func _caption(text: String, ink: Color, size: int) -> Label:
	return UiRowBuilder.wrapped_line(text, size, ink)


# --- reading -----------------------------------------------------------------


## Reads one province and shows it: the only door the panel calls. A province
## id the chart does not hold closes the sheet instead of printing a void.
func show_province(play: PlaySession, province: int) -> void:
	_play = play
	paint(ObserverProvince.reading(play, province))


## Paints a reading `ObserverProvince` already wrote. An empty reading closes
## the sheet, so the caller never has to ask whether the province exists.
func paint(reading: Dictionary) -> void:
	if reading.is_empty():
		clear()
		return
	province_id = int(reading["id"])
	head.fill(reading)
	grid.fill(reading)
	band_label.text = String(reading.get("band_label", ""))
	defence_label.text = String(reading.get("defence", ""))
	estates.render(
		reading.get("estates", [] as Array[Dictionary]),
		int(reading.get("unsurveyed", 0))
	)
	visible = true
	_fit()


## Re-reads the open province after a turn moved its owner, works or host. A
## closed sheet costs nothing, so the observatory can call it every turn.
func refresh() -> void:
	if province_id < 0 or _play == null:
		return
	show_province(_play, province_id)


## Hides the sheet and forgets the province it read.
func clear() -> void:
	province_id = -1
	visible = false


# --- geometry ----------------------------------------------------------------


## Docked right at a readable column, opposite the observatory's plate; a phone
## (or a handset laid sideways) hands the sheet the screen, and Close returns
## the chart (REQ-P1-05, REQ-P1-07).
func _fit() -> void:
	if frame == null:
		return
	var view: Vector2 = get_viewport_rect().size
	if view.x < 1.0 or view.y < 1.0:
		return
	var compact: bool = HudLayout.is_compact(view)
	var width: float = minf(WIDE_WIDTH, maxf(view.x - MARGIN * 2.0, 220.0))
	var height: float = maxf(view.y - MARGIN * 2.0, 160.0)
	frame.size = Vector2(width if not compact else view.x - MARGIN * 2.0, height)
	frame.position = Vector2(
		MARGIN if compact else view.x - frame.size.x - MARGIN, MARGIN
	)
