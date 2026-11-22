class_name LedgerProduction
extends VBoxContainer
## PRODUCTION tab of the ledger, read as the court's stockpile: holdings in
## catalogue order — Food, Raw materials, Manufactured, Riches — with every
## Manufactured good's recipe rows and their stepper beside the goods they make
## (wiki: commodity-catalog § Categories; stockpiles-and-production § Production
## flow). Food, raw and riches rows are holdings only, never controls.
##
## The page is laid out in columns, so a normal desktop sheet reads the whole
## catalogue without scrolling: three columns (Food | Raw materials |
## Manufactured) and Riches as a strip under them on the atlas; two columns on a
## phone, where the manufactured rows keep the room their note and steppers need
## (issue #1196; REQ-P1-05, REQ-P1-07). Every section pins its figures to the
## column's right edge and its heading reserves the same widths, so a caption
## never drifts from the figures it names (issue #1197).
##
## Presentation only: a press is an assignment intent the controller hands to the
## rules, and a "+" stops at the ceiling the projection reports, so the row never
## offers runs labour or inputs would refuse (REQ-P2-03). Gate and workshop copy
## live on LedgerProductionText and LedgerWorkshop (REQ-P3-01).

signal production_changed(recipe_id: String, units: int)

## A phone row is a thumb target: the steppers are its whole height (REQ-P5-07).
const ROW_HEIGHT: float = 40.0
## The atlas sheet is the one that must fit a 720-high viewport, and a mouse does
## not need the thumb target a phone does (REQ-P1-05, REQ-P5-07).
const ROW_HEIGHT_ATLAS: float = 32.0
const TITLE_PIXELS: int = 14
const TITLE_PIXELS_ATLAS: int = 13
const NOTE_PIXELS: int = 11
const NOTE_PIXELS_ATLAS: int = 10
## Medallion and name column, so every holding's figures start at one x.
const NAME_WIDTH: float = 132.0
## The Riches strip packs five holdings on one line, so its name cell is shorter.
const BAND_NAME_WIDTH: float = 100.0
const QTY_WIDTH: float = 46.0
## The phase's promise for a holding, straight from the projection.
const DELTA_WIDTH: float = 46.0
## The set-this-turn figure; narrow, because the buttons carry the thumb target.
const STEP_WIDTH: float = 36.0
const BUTTON_WIDTH: float = 58.0
const HOLDING_COLUMNS: Array = [["HAVE", QTY_WIDTH], ["NEXT", DELTA_WIDTH]]
## Manufactured rows carry two stepper buttons past their figures, so the heading
## reserves them too and HAVE/SET sit over the figures they name (issue #1197).
const MANUFACTURE_COLUMNS: Array = [
	["HAVE", QTY_WIDTH], ["SET", STEP_WIDTH], ["", BUTTON_WIDTH], ["", BUTTON_WIDTH]
]
## The mark a row wears when the court's own plan names its good — the glyph the
## muster's forces, the estates' rows, the roster's crews and the market's rows
## wear (DR-20261122-10).
const COURT_MARK: String = "▸"
## The heading's own legend for that mark, printed only when a plan books runs.
const COURT_LEGEND: String = "▸ court"

var _economy: PlayerEconomy = null
## The end-of-turn projection: what the phase promises each holding, and the
## post-Consumption store plus idle labour the steppers are capped by.
var _report: Dictionary = {}
## Row widgets by recipe id (manufacture) and commodity id (holdings), so tests
## and the workshop drive read the page without reaching into its children
## (REQ-P3-02).
var _rows: Dictionary = {}
var _holdings: Dictionary = {}
var _row_height: float = ROW_HEIGHT
var _compact: bool = true
## The court's own plan for this phase: the runs its economy pass would book,
## printed in gold above the columns and tinted on the rows it names
## (wiki: stockpiles-and-production § Production flow; DR-20261121-07).
var _counsel: Label = null
var _counsel_runs: Dictionary = {}


## `report` is the end-of-turn projection the panel already holds; without one
## the live store and the pool's labour stand in, so the page still answers.
## `pick` is the court's own production pick (`MapPlayProductionPick`), read on
## the crown's seat; a page filled without one carries no gold line.
func fill(economy: PlayerEconomy, report: Dictionary = {}, pick: Dictionary = {}) -> void:
	_economy = economy
	_report = report
	_rows = {}
	_holdings = {}
	_counsel = null
	_counsel_runs = pick.get("runs", {}) as Dictionary
	UiRowBuilder.clear(self)
	if economy == null:
		return
	_compact = HudLayout.is_compact(get_viewport_rect().size)
	_row_height = ROW_HEIGHT if _compact else ROW_HEIGHT_ATLAS
	add_theme_constant_override("separation", 4 if _compact else 2)
	# The court's own plan for this phase, in the colour every pick wears, above
	# the columns whose titles it tints (DR-20261121-07). The press it used to sit
	# under is gone — runs are set row by row (issue #1196) — so the reading now
	# opens the page.
	_counsel = UiRowBuilder.wrapped_line(String(pick.get("line", "")), 12, Palette.GOLD)
	_counsel.visible = not _counsel.text.is_empty()
	add_child(_counsel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(columns)
	var food := _column(columns, 1.0)
	_holdings_section(
		food, "FOOD",
		"Rations the court eats each turn: workers, army, navy and hospital staffs.",
		CommodityCatalog.FOOD
	)
	if _compact:
		# Two columns: the holdings share one, the workshop the other, because a
		# recipe row carries a note and two steppers and needs the room.
		_holdings_section(
			food, "RAW MATERIALS",
			"Gathered at home and overseas; industry and trade spend them.",
			CommodityCatalog.RAW
		)
		_recipes_section(_column(columns, 2.0))
	else:
		_holdings_section(
			_column(columns, 1.0), "RAW MATERIALS",
			"Gathered at home and overseas; industry and trade spend them.",
			CommodityCatalog.RAW
		)
		_recipes_section(_column(columns, 1.8))
	add_child(_riches_strip())


## Manufacture rows' widgets by recipe id: title, note (the workshop tag), have,
## stepper, minus, plus and the allowance the "+" was capped by.
func recipe_rows() -> Dictionary:
	return _rows.duplicate()


## Holding rows' widgets by commodity id: the quantity label and the next-turn
## figure beside it. These rows carry no stepper.
func holding_rows() -> Dictionary:
	return _holdings.duplicate()


## The court's own plan as the page printed it, for tests and the workshop drive
## (REQ-P3-02). Empty when the page carries no reading.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


## One column of the page: it expands into its share of the sheet's width, and a
## wider ratio buys the Manufactured column the room its steppers need.
func _column(parent: Control, ratio: float) -> VBoxContainer:
	var out := VBoxContainer.new()
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.size_flags_stretch_ratio = ratio
	out.add_theme_constant_override("separation", 2)
	parent.add_child(out)
	return out


## A holdings-only section: its heading and every good the category holds.
func _holdings_section(
	parent: Control, title: String, hint: String, ids: Array
) -> void:
	_section(parent, title, hint, HOLDING_COLUMNS)
	for id: String in ids:
		parent.add_child(_holding_row(id, NAME_WIDTH))


## The workshop's section: its heading and one row per recipe the court can see.
## The heading's legend names the counsel's mark whenever a row wears it, so the
## glyph is read as the court's own reading and never as a gate
## (DR-20261122-10).
func _recipes_section(parent: Control) -> void:
	_section(
		parent, "MANUFACTURED",
		LedgerProductionText.manufacture_hint(
			0 if _economy == null else _economy.production.made_total()
		),
		MANUFACTURE_COLUMNS,
		COURT_LEGEND if not _counsel_runs.is_empty() else ""
	)
	for output_id: String in CommodityCatalog.MANUFACTURED:
		for recipe_id: String in LedgerProductionText.recipes_for_output(
			output_id, _economy.tech_unlocked
		):
			parent.add_child(_recipe_row(recipe_id))


## Riches read as a strip under the columns: five holdings, one line, so the
## catalogue's last category costs the sheet a heading and a row, not five rows.
func _riches_strip() -> Control:
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	_section(
		strip, "RICHES",
		"Cleared to the treasury each turn at their base price; never traded.",
		[], "have · next"
	)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 2)
	strip.add_child(flow)
	for id: String in CommodityCatalog.RICHES:
		flow.add_child(_holding_row(id, BAND_NAME_WIDTH, true))
	return strip


## A category heading with the column captions its rows share. The grouping is
## the catalogue's own, so the stockpile reads in wiki order instead of one long
## list (wiki: commodity-catalog § Categories). The hint is the heading's
## tooltip, so a touch player reads the section by its rows (REQ-P1-05).
func _section(
	parent: Control, title: String, hint: String, columns: Array, legend: String = ""
) -> void:
	var head := UiRowBuilder.row(0.0)
	var heading := UiRowBuilder.label(title, 11, Palette.GOLD_DIM)
	heading.tooltip_text = hint
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	if not legend.is_empty():
		head.add_child(UiRowBuilder.caption(legend, 10, Palette.TEXT_DIM))
	for column: Array in columns:
		if String(column[0]).is_empty():
			# A stepper's own width, reserved so the captions before it stay put.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(float(column[1]), 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			head.add_child(gap)
			continue
		head.add_child(
			UiRowBuilder.caption(String(column[0]), 10, Palette.TEXT_DIM, float(column[1]))
		)
	parent.add_child(head)


## A holding the court cannot set this turn: the good, what it holds and what
## the phase will do to that figure.
func _holding_row(id: String, name_width: float, fixed: bool = false) -> Control:
	var row := UiRowBuilder.row(_row_height)
	var name := CommodityIcons.cell(id, name_width)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fixed:
		# A strip cell keeps its width; five of them share one line.
		name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2(
			name_width + QTY_WIDTH + DELTA_WIDTH + 24.0, _row_height
		)
	row.add_child(name)
	var held := _figure(str(_economy.quantity(id)), 14, Palette.GOLD_PALE, QTY_WIDTH)
	row.add_child(held)
	var next := _next_turn(id)
	row.add_child(next)
	_holdings[id] = {"row": row, "have": held, "next": next}
	return row


## The projection's promise for one holding: pale when the phase adds, dim when
## it spends, blank when the store is left alone.
func _next_turn(id: String) -> Label:
	var deltas: Dictionary = _report.get("stockpile_delta", {}) as Dictionary
	var change: int = int(deltas.get(id, 0))
	var color: Color = Palette.GOLD_PALE if change > 0 else Palette.TEXT_DIM
	var out := _figure(LedgerProductionText.stock_delta_text(change), 12, color, DELTA_WIDTH)
	if change != 0:
		out.tooltip_text = "Next turn:  %s %s" % [
			CommodityCatalog.label(id), LedgerProductionText.stock_delta_text(change)
		]
	return out


## One recipe the court can run: what it holds of the output, what it has set for
## the turn, and the stepper. The workshop tag says what a multi-turn row is
## already serving (wiki: production-recipes § Turns per unit).
func _recipe_row(recipe_id: String) -> Control:
	var row := UiRowBuilder.row(_row_height)
	var output_id: String = ProductionRecipes.output(recipe_id)
	row.add_child(CommodityIcons.badge(output_id))

	# The name, and under it whatever the workshop has to say about the row: how
	# long a multi-turn row waits and what is already serving its turns. A row
	# whose hand or town's works is missing says so here, on the row itself,
	# because a touch player never sees a hover hint (wiki: production-recipes
	# § Worker-tier gates, § Town-works gates; DR-20261114-07, DR-20261116-04).
	# The words take the column's slack, so every figure after them is pinned to
	# the right edge and the heading's captions sit over their own figures.
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	words.mouse_filter = Control.MOUSE_FILTER_PASS
	# A row the court's own plan books is tinted, leads with the counsel's mark
	# and says how many runs it would set, so the reading is read down the page
	# and not only on the line above (DR-20261121-07, DR-20261122-10).
	var planned: int = int(_counsel_runs.get(recipe_id, 0))
	var title_text: String = LedgerProductionText.recipe_title(recipe_id)
	if planned > 0:
		title_text = "%s %s" % [COURT_MARK, title_text]
	var title := UiRowBuilder.label(
		title_text,
		TITLE_PIXELS if _compact else TITLE_PIXELS_ATLAS,
		Palette.GOLD_PALE if planned > 0 else Palette.TEXT
	)
	title.tooltip_text = LedgerProductionText.recipe_tooltip(recipe_id)
	if planned > 0:
		title.tooltip_text += "\nThe court would run this %d time%s this phase." % [
			planned, "" if planned == 1 else "s"
		]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(title)
	var town: int = _town_level()
	var gated: bool = not (
		ProductionRecipes.tier_met(recipe_id, _economy.workers)
		and ProductionRecipes.town_met(recipe_id, town)
	)
	var note_text: String = (
		LedgerProductionText.gate_note(recipe_id, town) if gated
		else LedgerWorkshop.row_note(_economy, recipe_id)
	)
	var note := UiRowBuilder.label(
		note_text, NOTE_PIXELS if _compact else NOTE_PIXELS_ATLAS, Palette.TEXT_DIM
	)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.visible = not note_text.is_empty()
	if gated:
		note.tooltip_text = LedgerProductionText.gate_tooltip(recipe_id, town)
	elif not note_text.is_empty():
		note.tooltip_text = LedgerWorkshop.row_tooltip(_economy, recipe_id)
	words.add_child(note)
	row.add_child(words)

	var held := _figure(str(_economy.quantity(output_id)), 14, Palette.GOLD_PALE, QTY_WIDTH)
	row.add_child(held)
	var units: int = _economy.production.assignment_units(recipe_id)
	var stepper := _figure("%d" % units, 14, Palette.GOLD_PALE, STEP_WIDTH)
	row.add_child(stepper)

	var minus := UiRowBuilder.button("−", _row_height, BUTTON_WIDTH)
	minus.disabled = units <= 0
	minus.tooltip_text = "One fewer %s this turn" % CommodityCatalog.label(output_id)
	minus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units - 1))
	row.add_child(minus)

	var limit: int = _allowance(recipe_id)
	var full: bool = ProductionWorkshop.room(
		_economy.production_wip, recipe_id, ProductionRecipes.turns(recipe_id)
	) <= 0
	var plus := UiRowBuilder.button("+", _row_height, BUTTON_WIDTH)
	plus.disabled = units >= limit
	plus.tooltip_text = (
		LedgerProductionText.gate_tooltip(recipe_id, town) if gated
		else LedgerWorkshop.allowance_note(recipe_id, limit, full)
	)
	plus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units + 1))
	row.add_child(plus)

	_rows[recipe_id] = {
		"row": row,
		"title": title,
		"note": note,
		"have": held,
		"stepper": stepper,
		"minus": minus,
		"plus": plus,
		"allowance": limit,
	}
	return row


## A right-aligned figure in a fixed column, so holdings, promises and steppers
## line up down the column and under their captions.
func _figure(text: String, size: int, color: Color, width: float) -> Label:
	var out := UiRowBuilder.label(text, size, color)
	out.custom_minimum_size = Vector2(width, 0)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return out


## Units this row may still be set to: the whole runs the coming Production phase
## could start from the projected post-Consumption store and idle labour, less
## the other rows' claims and the pieces already on the bench. The rules own the
## arithmetic; this only picks which state the phase will see (REQ-P2-03).
func _allowance(recipe_id: String) -> int:
	var seen: Dictionary = ProductionBatch.budget(_economy, _report)
	return ProductionBatch.allowance(
		_economy,
		recipe_id,
		_town_level(),
		seen["stock"],
		int(seen["labour"]),
		_economy.production.assignments()
	)


## The crown's best town the projection was read against. Without a projection
## the page reads no town, so a gated row fails closed exactly as the phase
## would (DR-20261116-04).
func _town_level() -> int:
	return int(_report.get("town_level", 0))
