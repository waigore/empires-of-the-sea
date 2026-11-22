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
## live on LedgerProductionText and LedgerWorkshop; column and row paint live on
## LedgerProductionRows (REQ-P3-01).

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
	var food := LedgerProductionRows.column(columns, 1.0)
	LedgerProductionRows.holdings_section(
		food, "FOOD",
		"Rations the court eats each turn: workers, army, navy and hospital staffs.",
		CommodityCatalog.FOOD, _economy, _report, _row_height, _holdings
	)
	if _compact:
		# Two columns: the holdings share one, the workshop the other, because a
		# recipe row carries a note and two steppers and needs the room.
		LedgerProductionRows.holdings_section(
			food, "RAW MATERIALS",
			"Gathered at home and overseas; industry and trade spend them.",
			CommodityCatalog.RAW, _economy, _report, _row_height, _holdings
		)
		LedgerProductionRows.recipes_section(
			LedgerProductionRows.column(columns, 2.0),
			_economy, _report, _counsel_runs, _row_height, _compact, _rows,
			_on_production_changed
		)
	else:
		LedgerProductionRows.holdings_section(
			LedgerProductionRows.column(columns, 1.0), "RAW MATERIALS",
			"Gathered at home and overseas; industry and trade spend them.",
			CommodityCatalog.RAW, _economy, _report, _row_height, _holdings
		)
		LedgerProductionRows.recipes_section(
			LedgerProductionRows.column(columns, 1.8),
			_economy, _report, _counsel_runs, _row_height, _compact, _rows,
			_on_production_changed
		)
	add_child(
		LedgerProductionRows.riches_strip(_economy, _report, _row_height, _holdings)
	)


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


func _on_production_changed(recipe_id: String, units: int) -> void:
	production_changed.emit(recipe_id, units)
