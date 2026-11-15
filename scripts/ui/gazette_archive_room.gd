class_name GazetteArchiveRoom
extends VBoxContainer
## The history screen's page: the reading filter, the sheet it selects and the
## walk through the archive (wiki: the-gazette § History screen;
## DR-20261115-06). A campaign files one sheet a turn and keeps every one, so a
## long age's archive is a hundred pages of three classes mixed together; the
## chips let the crown read one class across the whole campaign instead of
## stepping turn by turn.
##
## Presentation only: every line is what [Gazette] filed, in the order and the
## prose the turn wrote, and the filter only chooses which of them print
## (REQ-P2-03, REQ-P3-03, REQ-P5-03).

signal filter_changed(cls: int)

const INK_SOFT: Color = Color(0.34, 0.26, 0.16)
const CHIP_HEIGHT: float = 30.0
const CHIP_CAPTION_WIDTH: float = 38.0
## An archive that has filed nothing yet: the presses have not run.
const NO_HISTORY: String = "The presses have not run yet."

## The reading filter: every class, or one class alone.
var filter: int = GazetteArchive.ALL
## Index into the pages the filter walks (newest first).
var at: int = 0

var _state: GazetteState = null
var _chips: Dictionary = {}
var _flow: HBoxContainer = null
var _page: VBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", 4)
	add_child(_strip())
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 4)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_page)


## Rebuilds the chips and the page for `state` under `cls`.
func fill(state: GazetteState, cls: int) -> void:
	_state = state
	filter = cls
	_build_chips()
	_render_page()


## One step through the pages the filter walks; a step past either end stays.
func step(delta: int) -> void:
	var walked: Array[Dictionary] = pages()
	if walked.is_empty():
		return
	at = clampi(at + delta, 0, walked.size() - 1)
	_render_page()


## The pages the archive walks under the filter, newest first. The unfiltered
## reading is every filed sheet, quiet turns included, so the history still has
## no gaps (wiki: the-gazette § When it appears, § History screen).
func pages() -> Array[Dictionary]:
	if _state == null:
		return []
	return GazetteArchive.walk(_state.history(), filter)


## "3 of 12" — where the reader stands among the pages the filter walks.
func position_text() -> String:
	var walked: Array[Dictionary] = pages()
	if walked.is_empty():
		return ""
	return "%d of %d" % [clampi(at, 0, walked.size() - 1) + 1, walked.size()]


## The calendar stamp of the page on screen; empty when the filter matches none.
func stamp() -> String:
	var walked: Array[Dictionary] = pages()
	if walked.is_empty():
		return ""
	return DiplomacyHistory.stamp_for_turn(
		int(walked[clampi(at, 0, walked.size() - 1)].get("turn", 0))
	)


func at_newest() -> bool:
	return at <= 0


func at_oldest() -> bool:
	return at >= pages().size() - 1


## Chip lookup for tests and the mobile layout audit (REQ-P5-07).
func filter_buttons() -> Dictionary:
	return _chips.duplicate()


# --- construction ------------------------------------------------------------


## The filter chips: every class, or one class alone, each carrying how many
## lines of it the whole archive holds. The strip scrolls sideways, so a phone's
## plate never widens for it (REQ-P1-05, REQ-P5-07).
func _strip() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var caption := GazetteParts.label("READ", 10, INK_SOFT)
	caption.custom_minimum_size = Vector2(CHIP_CAPTION_WIDTH, 0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	_flow = HBoxContainer.new()
	_flow.add_theme_constant_override("separation", 4)
	scroll.add_child(_flow)
	return row


func _build_chips() -> void:
	UiRowBuilder.clear(_flow)
	_chips.clear()
	var sheets: Array[Dictionary] = _state.history() if _state != null else []
	for cls: int in GazetteArchive.ORDER:
		var chip := Button.new()
		chip.text = "%s %d" % [GazetteArchive.label(cls), GazetteArchive.tally(sheets, cls)]
		chip.tooltip_text = GazetteArchive.hint(cls)
		chip.toggle_mode = true
		chip.button_pressed = cls == filter
		chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
		chip.add_theme_font_size_override("font_size", 12)
		chip.pressed.connect(_press.bind(cls))
		_flow.add_child(chip)
		_chips[cls] = chip


## A chip press: the archive re-reads from the newest page that holds the class.
func _press(cls: int) -> void:
	if cls == filter:
		return
	filter = cls
	at = 0
	for key: Variant in _chips.keys():
		(_chips[key] as Button).button_pressed = int(key) == filter
	_render_page()
	filter_changed.emit(filter)


# --- render ------------------------------------------------------------------


func _render_page() -> void:
	UiRowBuilder.clear(_page)
	var walked: Array[Dictionary] = pages()
	if walked.is_empty():
		var line: String = (
			NO_HISTORY if _state == null or _state.sheets.is_empty() else GazetteArchive.NONE_LINE
		)
		_page.add_child(GazetteParts.label(line, 14, Palette.INK))
		return
	at = clampi(at, 0, walked.size() - 1)
	GazetteParts.sections(_page, GazetteArchive.sheet(walked[at], filter))
