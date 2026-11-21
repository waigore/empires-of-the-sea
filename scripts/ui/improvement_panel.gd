class_name ImprovementPanel
extends ModalShell
## The crown's estates ledger: a whole-realm view of improvements, yields,
## active works and vacant resource tiles, with one-click Builder dispatch.
## The panel renders ImprovementLedger rows and emits intents; MapScreen owns
## the rules call and the camera (REQ-P3-02, REQ-P3-03). Summary and filter strip
## live in EstatesHead; grouping/filtering in EstateLedger. The wash, the
## safe-area fit, the pause-door park and the back gesture are ModalShell's, so
## the estates door presents like every other cartouche door (REQ-P1-05,
## REQ-P1-07).

signal action_pressed(action: String, tile: Vector2i)
signal focus_pressed(tile: Vector2i)
## Every ready estate the view prints, in its order: the one press files them
## through the screen's own order hook, so the panel stays a view and the rules
## keep the walk (REQ-P3-03, REQ-P5-04; DR-20261116-06).
signal raise_all_pressed(tiles: Array)

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
## page with nothing to name (DR-20261121-10). Unwired prints nothing.
var counsel_source: Callable = Callable()

var _rows: VBoxContainer = null
var _head: EstatesHead = null
var _batch: RaiseBatchPress = null
## The gold counsel line above the press: the estates the court would raise.
var _counsel: Label = null
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
	_subtitle.text = _subtitle_text()
	_sync_counsel()
	_apply_filter()


func refresh_if_open() -> void:
	if is_open():
		refresh()


## The court's own raise reading, asked at every refresh: the estates the
## published Builder pass would raise this phase, or the gate that leaves the
## page with nothing to name (DR-20261121-10). Unwired prints nothing.
func _sync_counsel() -> void:
	if _counsel == null:
		return
	# A closed card reads nothing: the pass is a planner walk, and a dossier
	# order that repaints the sheet behind it must not pay for a line nobody
	# sees (REQ-P4-02).
	var text: String = ""
	if is_open() and counsel_source.is_valid():
		text = String(counsel_source.call(_data))
	_counsel.text = text
	_counsel.visible = not text.is_empty()


## The gold counsel line's text, for tests and tooling (REQ-P3-02). Empty when
## the card carries no reading.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


# --- shell hooks -------------------------------------------------------------


func _dress_plate(compact: bool) -> void:
	_panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.99),
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
	_counsel = UiRowBuilder.wrapped_line("", 12, Palette.GOLD)
	_counsel.visible = false
	host.add_child(_counsel)

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


func _subtitle_text() -> String:
	if _province_filter >= 0 and model != null:
		return "%s · every resource tile in this province." % model.province_name(_province_filter)
	return "Every owned resource tile, its works and its road to the crown."


func _press_filter(_key: String) -> void:
	_apply_filter()


func _apply_filter() -> void:
	_clear_rows()
	if _head == null:
		return
	var groups: Array[Dictionary] = EstateLedger.grouped(_data)
	var shown: int = 0
	for group: Dictionary in EstateLedger.in_province(groups, _province_filter):
		var rows: Array[Dictionary] = EstateLedger.matching(group["rows"], _head.filter)
		if rows.is_empty():
			continue
		shown += rows.size()
		_add_group(group, rows)
	if shown == 0:
		var empty := Label.new()
		empty.text = "No estates match this view."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_rows.add_child(empty)
	_sync_batch()


# --- the one press -----------------------------------------------------------


## The ready estates the current view prints, in the order it prints them: the
## province the card was opened on, then the reading its chips hold, so the press
## files exactly what the crown can see (REQ-P5-04; DR-20261116-06).
func _ready_tiles() -> Array[Vector2i]:
	return EstateLedger.ready_tiles(
		EstateLedger.in_province(EstateLedger.grouped(_data), _province_filter),
		_head.filter
	)


## The ready rows the same view prints, priced: one estate's price is the
## bootstrap's, which reads the stores the estates before it leave, so the line
## is walked rather than summed (DR-20261118-12).
func _ready_rows() -> Array[Dictionary]:
	return EstateLedger.ready_rows(
		EstateLedger.in_province(EstateLedger.grouped(_data), _province_filter),
		_head.filter
	)


## The press names how many estates it would order, so the count is read before
## the stores are spent; a view with nothing ready carries no press (REQ-P5-03).
## The line under it names what the walk would take, or what waits and why — and
## the armed face takes the line's own count from that walk, so the confirm names
## what will be filed rather than what the view prints (DR-20261118-21).
func _sync_batch() -> void:
	if _line == null:
		_batch.set_ready(_ready_tiles().size(), "estates")
		return
	var reading: Dictionary = RaiseLine.plan(
		_ready_rows(),
		stockpile,
		ImprovementOrders.idle_builders(units, faction).size(),
		CivilianCatalog.display_name("builder"),
		_price_row
	)
	_line.text = RaiseLine.sheet_line(reading)
	_line.visible = not _line.text.is_empty()
	_batch.set_ready(_ready_tiles().size(), "estates", int(reading["filed"]))


## One estate's price inside the line, read against the stores the orders before
## it leave: the H8 bootstrap waives a level-1 raise's feedstock while the court
## holds none, so the fifth estate is not the first's price (wiki:
## extraction-and-improvements § H8 feedstock bootstrap; #878, REQ-P2-03).
func _price_row(row: Dictionary, left: Dictionary) -> Dictionary:
	var tile: Variant = row.get("tile", CivilianState.NO_TILE)
	if model == null or not (tile is Vector2i):
		var raw: Variant = row.get("cost", {})
		return raw as Dictionary if raw is Dictionary else {}
	return CivilianWorkPlan.bootstrap_cost(
		model, tile as Vector2i, left, int(row.get("next_level", 1))
	)


## The second tap: the screen files the walk and prints its one receipt, so the
## panel never owns an order of its own (REQ-P3-03, REQ-P5-05).
func _raise_all() -> void:
	raise_all_pressed.emit(_ready_tiles())


func _add_group(group: Dictionary, rows: Array[Dictionary]) -> void:
	var heading := Label.new()
	heading.text = "%s  ·  %d estate%s  ·  %d producing" % [
		String(group["name"]).to_upper(),
		rows.size(),
		"" if rows.size() == 1 else "s",
		int(group["producing"]),
	]
	heading.add_theme_font_size_override("font_size", 10 if _compact else 11)
	heading.add_theme_color_override("font_color", Palette.GOLD_DIM)
	_rows.add_child(heading)
	for row: Dictionary in rows:
		var item := ImprovementRow.new()
		item.compact = HudLayout.is_compact(get_viewport_rect().size)
		item.build_pressed.connect(func(tile: Vector2i) -> void: action_pressed.emit("build", tile))
		item.cancel_pressed.connect(func(tile: Vector2i) -> void: action_pressed.emit("cancel", tile))
		item.focus_pressed.connect(func(tile: Vector2i) -> void: focus_pressed.emit(tile))
		_rows.add_child(item)
		item.setup(row)


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## Phone-sized filter buttons, exposed so layout tests assert tap targets
## instead of reaching into the EstatesHead child (REQ-P3-02).
func filter_buttons() -> Dictionary:
	return _head.filter_buttons() if _head != null else {}
