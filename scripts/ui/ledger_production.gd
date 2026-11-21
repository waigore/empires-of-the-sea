class_name LedgerProduction
extends VBoxContainer
## PRODUCTION tab of the ledger, read as the court's stockpile: holdings in
## catalogue order — Food, Raw materials, Manufactured, Riches — with every
## Manufactured good's recipe rows and their stepper beside the goods they make
## (wiki: commodity-catalog § Categories; stockpiles-and-production § Production
## flow). Food, raw and riches rows are holdings only, never controls.
##
## Presentation only: a press is an assignment intent the controller hands to the
## rules, and a "+" stops at the ceiling the projection reports, so the row never
## offers runs labour or inputs would refuse (REQ-P2-03). Gate and workshop copy
## live on LedgerProductionText and LedgerWorkshop (REQ-P3-01).

signal production_changed(recipe_id: String, units: int)
## The PRODUCTION tab's one press: one run on every ready row it prints, applied
## by the controller through the same `set_production` intent a row's "+" emits
## (REQ-P5-04; DR-20261116-08).
signal production_batch_requested(plan: Dictionary)

const ROW_HEIGHT: float = 38.0
## Medallion and name column, so every row's figures start at one x.
const NAME_WIDTH: float = 132.0
const QTY_WIDTH: float = 46.0
## The phase's promise for a holding, straight from the projection.
const DELTA_WIDTH: float = 46.0
## The set-this-turn figure; narrow, because the buttons carry the thumb target.
const STEP_WIDTH: float = 36.0
const BUTTON_WIDTH: float = 58.0
const HOLDING_COLUMNS: Array = [["HAVE", QTY_WIDTH], ["NEXT", DELTA_WIDTH]]
const MANUFACTURE_COLUMNS: Array = [["HAVE", QTY_WIDTH], ["SET", STEP_WIDTH]]

var _economy: PlayerEconomy = null
## The end-of-turn projection: what the phase promises each holding, and the
## post-Consumption store plus idle labour the steppers are capped by.
var _report: Dictionary = {}
## Row widgets by recipe id (manufacture) and commodity id (holdings), so tests
## and the workshop drive read the page without reaching into its children
## (REQ-P3-02).
var _rows: Dictionary = {}
var _holdings: Dictionary = {}
## The one press under the MANUFACTURED heading: one run on every ready row the
## page prints, armed on the first tap and filed on the second (DR-20261116-08).
var _batch: RaiseBatchPress = null
## The line under that press, priced before the crown signs (DR-20261118-24).
var _line: Label = null
## The court's own plan for this phase: the runs its economy pass would book,
## printed in gold under the press and tinted on the rows it names
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
	_batch = null
	_line = null
	_counsel = null
	_counsel_runs = pick.get("runs", {}) as Dictionary
	UiRowBuilder.clear(self)
	if economy == null:
		return
	_section(
		"FOOD",
		"Rations the court eats each turn: workers, army, navy and hospital staffs.",
		HOLDING_COLUMNS
	)
	for id: String in CommodityCatalog.FOOD:
		add_child(_holding_row(id))
	_section(
		"RAW MATERIALS",
		"Gathered at home and overseas; industry and trade spend them.",
		HOLDING_COLUMNS
	)
	for id: String in CommodityCatalog.RAW:
		add_child(_holding_row(id))
	_section(
		"MANUFACTURED",
		LedgerProductionText.manufacture_hint(
			0 if _economy == null else _economy.production.made_total()
		),
		MANUFACTURE_COLUMNS
	)
	_batch = RaiseBatchPress.new()
	_batch.set_verb("queue")
	_batch.confirmed.connect(_queue_all)
	add_child(_batch)
	# The press's own line, under it and above the rows it walks.
	_line = UiRowBuilder.wrapped_line("", 10, Palette.TEXT_DIM)
	add_child(_line)
	# The court's own plan for this phase, in the colour every pick wears, above
	# the rows whose titles it tints (DR-20261121-07).
	_counsel = UiRowBuilder.wrapped_line(String(pick.get("line", "")), 12, Palette.GOLD)
	_counsel.visible = not _counsel.text.is_empty()
	add_child(_counsel)
	for output_id: String in CommodityCatalog.MANUFACTURED:
		for recipe_id: String in LedgerProductionText.recipes_for_output(
			output_id, _economy.tech_unlocked
		):
			add_child(_recipe_row(recipe_id))
	_sync_batch()
	_section(
		"RICHES",
		"Cleared to the treasury each turn at their base price; never traded.",
		HOLDING_COLUMNS
	)
	for id: String in CommodityCatalog.RICHES:
		add_child(_holding_row(id))
	UiRowBuilder.spacer(self)


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


## A category heading with the column captions its rows share. The grouping is
## the catalogue's own, so the stockpile reads in wiki order instead of one long
## list (wiki: commodity-catalog § Categories).
func _section(title: String, hint: String, columns: Array) -> void:
	UiRowBuilder.spacer(self, 8.0)
	var head := UiRowBuilder.row(0.0)
	var heading := UiRowBuilder.label(title, 11, Palette.GOLD_DIM)
	heading.tooltip_text = hint
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	for column: Array in columns:
		head.add_child(
			UiRowBuilder.caption(String(column[0]), 10, Palette.TEXT_DIM, float(column[1]))
		)
	add_child(head)


## A holding the court cannot set this turn: the good, what it holds and what
## the phase will do to that figure.
func _holding_row(id: String) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(CommodityIcons.cell(id, NAME_WIDTH))
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
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var output_id: String = ProductionRecipes.output(recipe_id)
	row.add_child(CommodityIcons.badge(output_id))
	# A row the court's own plan books is tinted and says how many runs it would
	# set, so the reading is read down the page and not only on the line above
	# (DR-20261121-07).
	var planned: int = int(_counsel_runs.get(recipe_id, 0))
	var title := UiRowBuilder.label(
		LedgerProductionText.recipe_title(recipe_id), 14,
		Palette.GOLD_PALE if planned > 0 else Palette.TEXT
	)
	title.tooltip_text = LedgerProductionText.recipe_tooltip(recipe_id)
	if planned > 0:
		title.tooltip_text += "\nThe court would run this %d time%s this phase." % [
			planned, "" if planned == 1 else "s"
		]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	# The workshop tag: how long a multi-turn row waits, and what is already
	# serving its turns. A row whose hand or town's works is missing says so
	# here, on the row itself, because a touch player never sees a hover hint
	# (wiki: production-recipes § Worker-tier gates, § Town-works gates;
	# DR-20261114-07, DR-20261116-04).
	var town: int = _town_level()
	var gated: bool = not (
		ProductionRecipes.tier_met(recipe_id, _economy.workers)
		and ProductionRecipes.town_met(recipe_id, town)
	)
	var note_text: String = (
		LedgerProductionText.gate_note(recipe_id, town) if gated
		else LedgerWorkshop.row_note(_economy, recipe_id)
	)
	var note := UiRowBuilder.label(note_text, 12, Palette.TEXT_DIM)
	if gated:
		note.tooltip_text = LedgerProductionText.gate_tooltip(recipe_id, town)
	elif not note_text.is_empty():
		note.tooltip_text = LedgerWorkshop.row_tooltip(_economy, recipe_id)
	row.add_child(note)

	var held := _figure(str(_economy.quantity(output_id)), 14, Palette.GOLD_PALE, QTY_WIDTH)
	row.add_child(held)
	var units: int = _economy.production.assignment_units(recipe_id)
	var stepper := _figure("%d" % units, 14, Palette.GOLD_PALE, STEP_WIDTH)
	row.add_child(stepper)

	var minus := UiRowBuilder.button("−", ROW_HEIGHT, BUTTON_WIDTH)
	minus.disabled = units <= 0
	minus.tooltip_text = "One fewer %s this turn" % CommodityCatalog.label(output_id)
	minus.pressed.connect(func() -> void: production_changed.emit(recipe_id, units - 1))
	row.add_child(minus)

	var limit: int = _allowance(recipe_id)
	var full: bool = ProductionWorkshop.room(
		_economy.production_wip, recipe_id, ProductionRecipes.turns(recipe_id)
	) <= 0
	var plus := UiRowBuilder.button("+", ROW_HEIGHT, BUTTON_WIDTH)
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
## line up down the page.
func _figure(text: String, size: int, color: Color, width: float) -> Label:
	var out := UiRowBuilder.label(text, size, color)
	out.custom_minimum_size = Vector2(width, 0)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return out


## Units this row may still be set to: the whole runs the coming Production phase
## could start from the projected post-Consumption store and idle labour, less
## the other rows' claims and the pieces already on the bench. The rules own the
## arithmetic; this only picks which state the phase will see (REQ-P2-03). The
## batch press reads the same function, so the press and the row's "+" can never
## disagree about a ceiling (DR-20261116-08).
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


# --- the one press -----------------------------------------------------------


## The press, for tests and the workshop drive (REQ-P3-02).
func batch_press() -> RaiseBatchPress:
	return _batch


## One run on every ready row the page prints, in its own order, each capped by
## the allowance the rows before it leave (REQ-P5-04; DR-20261116-08).
func _plan() -> Dictionary:
	if _economy == null:
		return ProductionBatch.blank()
	var seen: Dictionary = ProductionBatch.budget(_economy, _report)
	return ProductionBatch.plan(
		_rows.keys(),
		_economy,
		_town_level(),
		seen["stock"],
		int(seen["labour"]),
		_economy.production.assignments()
	)


## The press names how many runs it would set, so the count is read before the
## labour and inputs are claimed (REQ-P5-03, REQ-P5-05), and the line under it
## prices that walk (DR-20261118-24).
func _sync_batch() -> void:
	if _batch == null or _line == null:
		return
	var reading: Dictionary = _plan()
	_batch.set_ready(int(reading["runs"]), "runs")
	_line.text = ProductionBatch.sheet_line(reading)
	_line.visible = not _line.text.is_empty()


## Files the plan as one intent: the controller applies every set through the
## same `set_production` the row's "+" emits and repaints once, so the page never
## rebuilds itself under a press that is still emitting (REQ-P2-03, REQ-P5-06).
func _queue_all() -> void:
	var plan: Dictionary = _plan()["plan"] as Dictionary
	if plan.is_empty():
		return
	production_batch_requested.emit(plan)


## The crown's best town the projection was read against. Without a projection
## the page reads no town, so a gated row fails closed exactly as the phase
## would (DR-20261116-04).
func _town_level() -> int:
	return int(_report.get("town_level", 0))
