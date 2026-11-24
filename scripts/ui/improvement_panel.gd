class_name ImprovementPanel
extends ModalShell
## The crown's estates ledger: a whole-realm view of improvements, yields,
## active works and vacant resource tiles, with one-click Builder dispatch.
## The panel renders ImprovementLedger rows and emits intents; MapScreen owns
## the rules call and the camera (REQ-P3-02, REQ-P3-03). Summary and filter strip
## live in EstatesHead; grouping/filtering in EstateLedger; list paint in
## EstatesRows; the one press's price walk in EstatesRaise. The wash, the
## safe-area fit, the pause-door park and the back gesture are ModalShell's, so
## the estates door presents like every other cartouche door (REQ-P1-05,
## REQ-P1-07).

signal action_pressed(action: String, tile: Vector2i)
signal focus_pressed(tile: Vector2i)
## Every ready estate the view prints, in its order: the one press files them
## through the screen's own order hook, so the panel stays a view and the rules
## keep the walk (REQ-P3-03, REQ-P5-04; DR-20261116-06).
signal raise_all_pressed(tiles: Array)

## What the card's mark means, printed beside the mark on the sheet itself: a
## phone drops the footer hint, and a card that keeps the meaning only there
## shows a glyph with no sentence (REQ-P1-07, REQ-P5-07; DR-20261123-08).
const MARK_LEGEND: String = "A ▸ marks the estates the court would raise this phase."

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var stockpile: Dictionary = {}
var capital_tile: Vector2i = CivilianState.NO_TILE
var faction: int = 0
var tech_caps: Dictionary = {}
## The crown's sealed coasts, asked at every refresh: a sealed harbour severs a
## colony's harvest, so the ledger prices the rows the way the Extraction phase
## pays them (wiki: capital-and-connectivity § Blockade, REQ-P2-03). Unwired
## seals nothing — the rules fall back to the unsealed chart.
var blockade_source: Callable = Callable()
## The court's own raise reading, asked at every refresh: the estates the
## published Builder pass would raise this phase, or the gate that leaves the
## page with nothing to name (DR-20261121-10). The pick also keys the tiles it
## names, so the rows it answers wear the counsel's mark (DR-20261122-04).
## Unwired prints nothing and marks nothing.
var counsel_source: Callable = Callable()

var _rows: VBoxContainer = null
var _head: EstatesHead = null
var _batch: RaiseBatchPress = null
## The gold counsel line above the press: the estates the court would raise
## (CounselLine; DR-20261121-10, REQ-P5-06).
var _counsel: CounselLine = null
## What the card's mark means, mounted under the line it marks rows for: a phone
## drops the footer hint, so the meaning stands beside the mark (DR-20261123-08).
var _legend: Label = null
## What the press would spend, under it: the stores the ready estates take, or the
## rows the stores and the free Builders leave waiting (DR-20261118-12).
var _line: Label = null
var _title: Label = null
var _subtitle: Label = null
var _footer_box: Control = null
var _close_button: Button = null
var _data: Dictionary = {}
var _province_filter: int = -1


## The estates door reads one province when the chart asked for it, and the whole
## realm otherwise (REQ-P1-07).
func open(province_id: int = -1, filter_key: String = "all") -> void:
	_province_filter = province_id
	if _head != null:
		_head.set_filter(filter_key)
	# A card that opens fresh never carries an arm from the last visit, so one
	# tap on a reopened sheet can never spend the stores (REQ-P5-04).
	if _batch != null:
		_batch.disarm()
	super.open()


func set_data(
	p_model: MapModel,
	p_works: LandWorks,
	p_units: Array[CivilianState],
	p_stockpile: Dictionary,
	p_capital: Vector2i,
	p_faction: int = 0,
	p_tech_caps: Dictionary = {}
) -> void:
	model = p_model
	works = p_works
	units = p_units
	stockpile = p_stockpile
	capital_tile = p_capital
	faction = p_faction
	tech_caps = p_tech_caps


## Research can lift a cap mid-turn; the screen pushes the new table in.
func set_tech_caps(p_tech_caps: Dictionary) -> void:
	tech_caps = p_tech_caps


func refresh() -> void:
	if model == null or works == null:
		return
	_data = ImprovementLedger.snapshot(
		model, works, units, stockpile, faction, capital_tile, tech_caps,
		Blockades.of(blockade_source)
	)
	_head.render(_data, stockpile)
	_subtitle.text = EstatesRows.subtitle(model, _province_filter)
	_sync_counsel()
	_apply_filter()


func refresh_if_open() -> void:
	if is_open():
		refresh()


## The court's own raise reading, asked at every refresh: the estates the
## published Builder pass would raise this phase, or the gate that leaves the
## page with nothing to name (DR-20261121-10). The pick also keys the tiles it
## names, so the rows it answers wear the counsel's mark (DR-20261122-04).
## Unwired prints nothing and marks nothing. The legend under the line stands
## exactly while that reading names an estate, so a quiet card explains no mark
## it does not print (DR-20261123-08).
func _sync_counsel() -> void:
	if _counsel == null:
		return
	_counsel.source = counsel_source
	_counsel.args = [_data]
	_counsel.sync()
	MarkLegend.stand(_legend, _counsel.visible and not _counsel.keys().is_empty())


## The gold counsel line's text, for tests and tooling (REQ-P3-02). Empty when
## the card carries no reading.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


## The sentence that says what the card's mark means, for tests and tooling
## (REQ-P3-02, DR-20261123-08). Empty when the card carries no legend.
func legend_text() -> String:
	return "" if _legend == null else _legend.text


## Whether the legend stands beside the marks it explains (REQ-P1-07). A card
## whose reading names no estate prints neither glyph nor sentence.
func legend_shown() -> bool:
	return _legend != null and _legend.visible


# --- shell hooks -------------------------------------------------------------


func _dress_plate(compact: bool) -> void:
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Palette.with_alpha(Palette.PARCHMENT, 0.99),
			Palette.GOLD_DIM,
			1,
			4,
			Vector4(10, 8, 10, 8) if compact else Vector4(20, 16, 20, 16)
		)
	)


func _build_plate(host: VBoxContainer) -> void:
	host.add_child(_header())
	_head = EstatesHead.new()
	_head.filter_selected.connect(_press_filter)
	host.add_child(_head)

	# The court's own raise reading, above the press it answers: the estates the
	# published Builder pass would raise this phase (DR-20261121-10).
	_counsel = CounselLine.make(host)
	# A closed card reads nothing: the pass is a planner walk, and a dossier order
	# that repaints the sheet behind it must not pay for a line nobody sees
	# (REQ-P4-02).
	_counsel.gate = is_open
	# What the mark on those rows means, beside the mark: a phone drops the footer
	# hint, so the sentence cannot live only there (DR-20261123-03/07).
	_legend = MarkLegend.make(MARK_LEGEND, host)

	# The one press under the chips: it names how many estates the view would
	# order and files them on the second tap (REQ-P5-04; DR-20261116-06).
	_batch = RaiseBatchPress.new()
	_batch.confirmed.connect(_raise_all)
	host.add_child(_batch)
	# What the second tap spends, under the press: a phone reads the price with
	# the press, never in a hover (REQ-P1-07, REQ-P5-06; DR-20261118-12).
	_line = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	_line.visible = false
	host.add_child(_line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 5)
	scroll.add_child(_rows)

	_footer_box = _footer()
	host.add_child(_footer_box)


## Compact estates card: a smaller masthead, the subtitle and footer hint traded
## for list rows, thumb-sized filters, and rows that fold their columns into
## full-width lines (REQ-P3-02, REQ-P1-07).
func _apply_profile(compact: bool, _narrow: bool) -> void:
	if _title != null:
		_title.add_theme_font_size_override("font_size", 20 if compact else 26)
	if _rows != null:
		_rows.add_theme_constant_override("separation", 4 if compact else 5)
	if _head != null:
		_head.set_compact(compact)
	if _subtitle != null:
		_subtitle.visible = not compact
	if _footer_box != null:
		_footer_box.visible = not compact
	# The legend is the body's, not the footer's, so a compact card keeps it
	# beside the marks it explains (DR-20261123-03/07, REQ-P5-07).


## Rows are built for one geometry, so an open card repaints for the new one.
func _on_profile_changed() -> void:
	if is_open() and not _data.is_empty():
		_apply_filter()


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)

	_title = Label.new()
	_title.text = "THE CROWN'S ESTATES"
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	titles.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	titles.add_child(_subtitle)

	_close_button = CloseSeal.make()
	_close_button.pressed.connect(close)
	header.add_child(_close_button)
	return header


func _footer() -> Control:
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 4)
	var hint := Label.new()
	# The mark's sentence is not repeated here: it stands beside the marks it
	# explains, where a phone that drops this hint still reads it (DR-20261123-08).
	hint.text = (
		"Build orders place the nearest idle Builder on the estate; materials are "
		+ "spent on assignment and are not refunded if the work is cancelled. "
		+ "Roads and ports carry yields to the crown."
	)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 0.76))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(hint)
	return footer


# --- rendering --------------------------------------------------------------


func _press_filter(_key: String) -> void:
	_apply_filter()


func _apply_filter() -> void:
	if _head == null:
		EstatesRows.clear(_rows)
		return
	# The marks come off the one reading the counsel line holds, so a chip press
	# reorders the same rows without asking the pass again (REQ-P4-01;
	# DR-20261122-04).
	var marks: Dictionary = {} if _counsel == null else _counsel.keys()
	var row_compact: bool = (
		HudLayout.is_compact(get_viewport_rect().size) if is_inside_tree() else _compact
	)
	EstatesRows.fill(
		_rows,
		_data,
		_province_filter,
		_head.filter,
		marks,
		_compact,
		row_compact,
		_on_row_build,
		_on_row_cancel,
		_on_row_focus
	)
	_sync_batch()


# --- the one press -----------------------------------------------------------


## Ready estates the current view prints, in print order: the province the card
## was opened on, then the reading its chips hold (REQ-P3-02, REQ-P5-04).
func ready_tiles() -> Array[Vector2i]:
	var filter_key: String = _head.filter if _head != null else "all"
	var view: Dictionary = EstatesRaise.ready_view(_data, _province_filter, filter_key)
	var tiles: Array[Vector2i] = []
	tiles.assign(view["tiles"])
	return tiles


## The second tap: the screen files the walk and prints its one receipt, so the
## panel never owns an order of its own (REQ-P3-03, REQ-P5-05).
func _raise_all() -> void:
	raise_all_pressed.emit(ready_tiles())


func _sync_batch() -> void:
	var filter_key: String = _head.filter if _head != null else "all"
	EstatesRaise.sync(
		_batch,
		_line,
		_data,
		_province_filter,
		filter_key,
		model,
		stockpile,
		units,
		faction
	)


func _on_row_build(tile: Vector2i) -> void:
	action_pressed.emit("build", tile)


func _on_row_cancel(tile: Vector2i) -> void:
	action_pressed.emit("cancel", tile)


func _on_row_focus(tile: Vector2i) -> void:
	focus_pressed.emit(tile)


## Phone-sized filter buttons, exposed so layout tests assert tap targets
## instead of reaching into the EstatesHead child (REQ-P3-02).
func filter_buttons() -> Dictionary:
	return _head.filter_buttons() if _head != null else {}
