class_name SheetFrame
extends ModalShell
## The crown's ledger sheet: a titled header with a Close door, a scrolling body
## and a hint footer, printed in ModalShell's one full-screen plate. The civilian
## roster, the muster roll, the realm ledgers and the court dossier share this
## chrome, so the header, the body, the gold counsel line and the compact profile
## are written once (REQ-P3-01, REQ-P5-07).
##
## A subclass owns what its sheet reads: it names the title, builds its body and
## repaints it. The frame never reads rules and never orders anything.

## A door under a reading that opens another sheet: the press names that sheet by
## the HUD's one door key, so a sheet never needs its sibling's class or signal
## (REQ-P3-02, REQ-P5-01).
signal door_pressed(key: String)

## The sheet is movable by its header, so the chart it covers can be read
## without closing the ledger (REQ-P1-07).
var _drag: ModalDrag = null
var _scroll: ScrollContainer = null
var _title: Label = null
var _subtitle: Label = null
var _crest: Control = null
var _close: Button = null
var _hint: Label = null
var _header_row: HBoxContainer = null

## Chrome a subclass names once, before the frame builds itself.
var title_text: String = ""
var title_pixels: int = 28
var hint_text: String = ""
var hint_pixels: int = 10

# --- the counsel line --------------------------------------------------------


## The court's own reading of this sheet, asked at every refresh: the sheet's
## session wires it to the pass that answers the sheet, or leaves it unwired and
## prints no gold line (REQ-P3-02, REQ-P5-06). A sheet that reads its pick once
## at the refresh paints it with `_show_counsel` instead.
var counsel_source: Callable = Callable()
## The gold line under the filters: the crown's own reading in one sentence, its
## dress and its gate (CounselLine; REQ-P3-01, REQ-P5-06).
var _counsel: CounselLine = null
## The last snapshot the sheet painted from; empty before its first refresh.
var _snapshot: Dictionary = {}


## The gold line, mounted where its reading answers, so no sheet restates the
## size, the colour or the wrap (REQ-P3-01). The host is optional: a sheet whose
## body hook returns the line mounts it itself.
func _counsel_line(host: Container = null) -> CounselLine:
	_counsel = CounselLine.make(host)
	# A closed sheet asks nothing: the pass is a planner walk no one is looking
	# at (REQ-P4-02).
	_counsel.gate = is_open
	return _counsel


## The gold line's text, for tests and tooling (REQ-P3-02). Empty when the sheet
## carries no reading.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


## What the reading is asked with: the snapshot the sheet just painted. A sheet
## whose pass answers something else overrides this.
func _counsel_args() -> Array:
	return [_snapshot]


## Prints a reading the sheet already holds — a pick read once at the refresh,
## not a source asked per paint — or stands the line down (REQ-P5-06).
func _show_counsel(value: Variant) -> void:
	if _counsel != null:
		_counsel.show_value(value)


## Asks the court's own reading once and prints it, or stands the line down: one
## gate, one dress and one place for every ledger, so no two sheets disagree on
## when the crown's page is silent (CounselLine; REQ-P3-02, REQ-P5-06).
func _sync_counsel() -> void:
	if _counsel == null:
		return
	_counsel.source = counsel_source
	_counsel.args = _counsel_args()
	_counsel.sync()


## The one session the sheet reads. Every crown sheet binds it the same way, so
## the family assigns it here instead of repeating the same override
## (REQ-P3-01). A sheet opened from another sheet binds nothing and keeps the
## session the sheet under it carried.
func bind(p_session: PlaySession) -> void:
	play = p_session


# --- subclass hooks ----------------------------------------------------------


## The medallion at the header's left. Roster overrides with a civilian icon.
func _build_crest() -> Control:
	return Icon.new("crest", 42.0, Palette.GOLD)


## The body between the header and the hint: filters, a scrolling row column,
## whatever the sheet reads.
func _build_body(_host: VBoxContainer) -> void:
	pass


## Whether a session is ready for this sheet to open.
func _can_open() -> bool:
	return play != null and play.world != null


## A sheet holds the pause door only for the session it was bound to. The sheets
## opened *from* another sheet — the court's dossier, the college's chart — bind
## nothing, so the seal stays with the ledger standing under them (REQ-P5-07).
func _play() -> PlaySession:
	return play


## The compact/narrow profile, once per fit: the masthead's own title step, the
## crest a phone drops and the standing lines it trades for rows. A subclass
## scales its own titles and repaints rows that fix their size at construction;
## it never repeats this head (REQ-P1-07, RUB-P3-01).
func _apply_profile(compact: bool, narrow: bool) -> void:
	if _title != null:
		_title.add_theme_font_size_override(
			"font_size", 20 if narrow else (22 if compact else title_pixels)
		)
	if _crest != null:
		_crest.visible = not narrow
	if _subtitle != null:
		_subtitle.visible = not compact
	if _hint != null:
		_hint.visible = not compact


# --- shell -------------------------------------------------------------------


func _build_plate(host: VBoxContainer) -> void:
	host.add_child(_header())
	var grabs: Array[Control] = [_header_row]
	_drag = ModalDrag.attach(self, _margin, grabs, _panel)
	_build_body(host)
	host.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(ModalDrag.grip())
	_header_row = header

	_crest = _build_crest()
	_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_crest)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	_title = UiRowBuilder.label(title_text, title_pixels, Palette.GOLD_PALE)
	_title.add_theme_font_override("font", UiTheme.serif())
	titles.add_child(_title)

	_subtitle = UiRowBuilder.label("", 12, Palette.TEXT_DIM)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)

	_close = CloseSeal.make()
	_close.pressed.connect(close)
	header.add_child(_close)
	return header


func _footer() -> Control:
	_hint = UiRowBuilder.label(hint_text, hint_pixels, Color(0.80, 0.74, 0.62, 0.76))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _hint


## A scrolling body column; the roster and the muster print their rows into it.
func _append_scroll(host: VBoxContainer) -> ScrollContainer:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(_scroll)
	return _scroll


## The explanation a ledger prints when a filter leaves no row.
func _make_empty(rows: VBoxContainer, font_size: int = 15) -> Label:
	var empty := UiRowBuilder.label("", font_size, Palette.TEXT_DIM)
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(empty)
	return empty


## A step's door under the reading that raises the question: the one dress every
## sheet's own door wears, and the press names the sheet it opens by the HUD's
## one door key (REQ-P3-02, REQ-P5-01, REQ-P5-04).
func _door(label: String, hint: String, key: String, expand: bool = true) -> Button:
	return UiRowBuilder.door(label, hint, func() -> void: door_pressed.emit(key), expand)
