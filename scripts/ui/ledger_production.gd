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
## offers runs labour or inputs would refuse (REQ-P2-03).

signal production_changed(recipe_id: String, units: int)

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


## `report` is the end-of-turn projection the panel already holds; without one
## the live store and the pool's labour stand in, so the page still answers.
func fill(economy: PlayerEconomy, report: Dictionary = {}) -> void:
	_economy = economy
	_report = report
	_rows = {}
	_holdings = {}
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
		_manufacture_hint(),
		MANUFACTURE_COLUMNS
	)
	for output_id: String in CommodityCatalog.MANUFACTURED:
		for recipe_id: String in _recipes_of(output_id):
			add_child(_recipe_row(recipe_id))
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
	var out := _figure(LedgerText.stock_delta_text(change), 12, color, DELTA_WIDTH)
	if change != 0:
		out.tooltip_text = "Next turn:  %s %s" % [
			CommodityCatalog.label(id), LedgerText.stock_delta_text(change)
		]
	return out


## One recipe the court can run: what it holds of the output, what it has set for
## the turn, and the stepper. The workshop tag says what a multi-turn row is
## already serving (wiki: production-recipes § Turns per unit).
func _recipe_row(recipe_id: String) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var output_id: String = ProductionRecipes.output(recipe_id)
	row.add_child(CommodityIcons.badge(output_id))
	var title := UiRowBuilder.label(LedgerText.recipe_title(recipe_id), 14, Palette.TEXT)
	title.tooltip_text = LedgerText.recipe_tooltip(recipe_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	# The workshop tag: how long a multi-turn row waits, and what is already
	# serving its turns. A row whose hand is missing says so here, on the row
	# itself, because a touch player never sees a hover hint (wiki:
	# production-recipes § Worker-tier gates; DR-20261114-07).
	var gated: bool = not ProductionRecipes.tier_met(recipe_id, _economy.workers)
	var note_text: String = (
		_gate_note(recipe_id) if gated
		else _workshop_note(recipe_id)
	)
	var note := UiRowBuilder.label(note_text, 12, Palette.TEXT_DIM)
	if gated:
		note.tooltip_text = _gate_tooltip(recipe_id)
	elif not note_text.is_empty():
		note.tooltip_text = _workshop_tooltip(recipe_id)
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
	var plus := UiRowBuilder.button("+", ROW_HEIGHT, BUTTON_WIDTH)
	plus.disabled = units >= limit
	plus.tooltip_text = (
		_gate_tooltip(recipe_id) if gated
		else LedgerWorkshop.allowance_note(recipe_id, limit)
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


## The court's available recipes for one good: fabric is woven from wool or —
## once Cotton Weaving is known — from cotton, and each weave is its own row. An
## ungated row reads first, so the always-available path sits at the top
## (wiki: production-recipes § Technology-gated recipes).
func _recipes_of(output_id: String) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: String in ProductionRecipes.available_ids(_economy.tech_unlocked):
		if ProductionRecipes.output(recipe_id) != output_id:
			continue
		if ProductionRecipes.required_tech(recipe_id).is_empty():
			out.insert(0, recipe_id)
			continue
		out.append(recipe_id)
	return out


## Units this row may still be set to: the whole runs the coming Production phase
## could start from the projected post-Consumption store and idle labour, less
## the other rows' claims. The rules own the arithmetic; this only picks which
## state the phase will see (REQ-P2-03).
func _allowance(recipe_id: String) -> int:
	var stock: Dictionary = _report.get("after_consumption", _economy.stockpile) as Dictionary
	var labour: int = _economy.workers.labour()
	if not _report.is_empty():
		labour = LedgerText.idle_labour(_report)
	return ProductionRecipes.allowance(
		recipe_id, stock, labour, _economy.production.assignments(), _economy.workers
	)


## The hand a row waits for, said on the row itself: a touch player never sees a
## hover hint, so the gate is text, not a tooltip (wiki: production-recipes
## § Worker-tier gates; DR-20261114-07).
func _gate_note(recipe_id: String) -> String:
	var tier: int = ProductionRecipes.min_tier(recipe_id)
	if tier <= 0:
		return ""
	var hand: String = WorkerPool.TIER_ONE[tier]
	var article: String = "an" if hand.begins_with("A") else "a"
	return "needs %s %s" % [article, hand]


## What the gate asks and where the court trains it.
func _gate_tooltip(recipe_id: String) -> String:
	var tier: int = ProductionRecipes.min_tier(recipe_id)
	if tier <= 0:
		return ""
	var hand: String = WorkerPool.TIER_ONE[tier]
	var article: String = "an" if hand.begins_with("A") else "a"
	return (
		"This row is a trained hand's work: it needs %s %s. Train one in the "
		+ "WORKERS tab and the workshop will take it."
	) % [article, hand]


## The MANUFACTURED heading's hint, plus what the workshop turned out in the last
## Production phase: the phase's own record, so the page remembers the work the
## court just paid for (wiki: production-recipes § Acceptance Criteria,
## `productionByRecipe`).
func _manufacture_hint() -> String:
	var hint: String = "Set this turn's output on each row: labour and raw inputs cap the rest."
	var made: int = 0 if _economy == null else _economy.production.made_total()
	if made <= 0:
		return hint
	var plural: String = "" if made == 1 else "s"
	return "%s Last phase the workshop made %d good%s." % [hint, made, plural]


## The row's workshop tag, or — for an idle one-turn row that worked last phase —
## what it turned out. A row still serving keeps its tag: the present is what the
## next phase pays (DR-20261113-02).
func _workshop_note(recipe_id: String) -> String:
	var tag: String = LedgerWorkshop.note(_economy, recipe_id)
	if not tag.is_empty():
		return tag
	var made: int = 0 if _economy == null else _economy.production.made_units(recipe_id)
	if made <= 0:
		return ""
	return "made %d" % made


## The tag's long form, with the last phase's output for this row when it made
## any: the detail a hover or a long press reads (REQ-P5-07 keeps the row's own
## note the visible reading).
func _workshop_tooltip(recipe_id: String) -> String:
	var text: String = LedgerWorkshop.tooltip(_economy, recipe_id)
	var made: int = 0 if _economy == null else _economy.production.made_units(recipe_id)
	if made <= 0:
		return text
	var good: String = CommodityCatalog.label(ProductionRecipes.output(recipe_id))
	var line: String = "Last phase it made %d %s." % [made, good]
	return line if text.is_empty() else "%s %s" % [text, line]
