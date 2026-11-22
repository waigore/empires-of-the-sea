class_name LedgerProductionRows
extends RefCounted
## How the PRODUCTION tab paints its columns, holdings and recipe steppers.
## Kept out of [LedgerProduction] so the sheet stays under the P3 size bar
## (REQ-P3-01); presentation only — every ceiling comes from the rules, and
## every press is an assignment intent the page emits (REQ-P3-02, REQ-P3-03).


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


## One column of the page: it expands into its share of the sheet's width, and a
## wider ratio buys the Manufactured column the room its steppers need.
static func column(parent: Control, ratio: float) -> VBoxContainer:
	var out := VBoxContainer.new()
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.size_flags_stretch_ratio = ratio
	out.add_theme_constant_override("separation", 2)
	parent.add_child(out)
	return out


## A holdings-only section: its heading and every good the category holds.
static func holdings_section(
	parent: Control,
	title: String,
	hint: String,
	ids: Array,
	economy: PlayerEconomy,
	report: Dictionary,
	row_height: float,
	holdings: Dictionary
) -> void:
	section(parent, title, hint, HOLDING_COLUMNS)
	for id: String in ids:
		parent.add_child(
			holding_row(id, NAME_WIDTH, economy, report, row_height, holdings)
		)


## The workshop's section: its heading and one row per recipe the court can see.
## The heading's legend names the counsel's mark whenever a row wears it, so the
## glyph is read as the court's own reading and never as a gate
## (DR-20261122-10).
static func recipes_section(
	parent: Control,
	economy: PlayerEconomy,
	report: Dictionary,
	counsel_runs: Dictionary,
	row_height: float,
	compact: bool,
	rows: Dictionary,
	on_change: Callable
) -> void:
	section(
		parent, "MANUFACTURED",
		LedgerProductionText.manufacture_hint(
			0 if economy == null else economy.production.made_total()
		),
		MANUFACTURE_COLUMNS,
		LedgerProduction.COURT_LEGEND if not counsel_runs.is_empty() else ""
	)
	for output_id: String in CommodityCatalog.MANUFACTURED:
		for recipe_id: String in LedgerProductionText.recipes_for_output(
			output_id, economy.tech_unlocked
		):
			parent.add_child(
				recipe_row(
					recipe_id, economy, report, counsel_runs, row_height, compact,
					rows, on_change
				)
			)


## Riches read as a strip under the columns: five holdings, one line, so the
## catalogue's last category costs the sheet a heading and a row, not five rows.
static func riches_strip(
	economy: PlayerEconomy,
	report: Dictionary,
	row_height: float,
	holdings: Dictionary
) -> Control:
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	section(
		strip, "RICHES",
		"Cleared to the treasury each turn at their base price; never traded.",
		[], "have · next"
	)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 2)
	strip.add_child(flow)
	for id: String in CommodityCatalog.RICHES:
		flow.add_child(
			holding_row(
				id, BAND_NAME_WIDTH, economy, report, row_height, holdings, true
			)
		)
	return strip


## A category heading with the column captions its rows share. The grouping is
## the catalogue's own, so the stockpile reads in wiki order instead of one long
## list (wiki: commodity-catalog § Categories). The hint is the heading's
## tooltip, so a touch player reads the section by its rows (REQ-P1-05).
static func section(
	parent: Control, title: String, hint: String, columns: Array, legend: String = ""
) -> void:
	var head := UiRowBuilder.row(0.0)
	var heading := UiRowBuilder.label(title, 11, Palette.GOLD_DIM)
	heading.tooltip_text = hint
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	if not legend.is_empty():
		head.add_child(UiRowBuilder.caption(legend, 10, Palette.TEXT_DIM))
	for column_spec: Array in columns:
		if String(column_spec[0]).is_empty():
			# A stepper's own width, reserved so the captions before it stay put.
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(float(column_spec[1]), 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			head.add_child(gap)
			continue
		head.add_child(
			UiRowBuilder.caption(
				String(column_spec[0]), 10, Palette.TEXT_DIM, float(column_spec[1])
			)
		)
	parent.add_child(head)


## A holding the court cannot set this turn: the good, what it holds and what
## the phase will do to that figure.
static func holding_row(
	id: String,
	name_width: float,
	economy: PlayerEconomy,
	report: Dictionary,
	row_height: float,
	holdings: Dictionary,
	fixed: bool = false
) -> Control:
	var row := UiRowBuilder.row(row_height)
	var name := CommodityIcons.cell(id, name_width)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fixed:
		# A strip cell keeps its width; five of them share one line.
		name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2(
			name_width + QTY_WIDTH + DELTA_WIDTH + 24.0, row_height
		)
	row.add_child(name)
	var held := figure(str(economy.quantity(id)), 14, Palette.GOLD_PALE, QTY_WIDTH)
	row.add_child(held)
	var next := next_turn(id, report)
	row.add_child(next)
	holdings[id] = {"row": row, "have": held, "next": next}
	return row


## The projection's promise for one holding: pale when the phase adds, dim when
## it spends, blank when the store is left alone.
static func next_turn(id: String, report: Dictionary) -> Label:
	var deltas: Dictionary = report.get("stockpile_delta", {}) as Dictionary
	var change: int = int(deltas.get(id, 0))
	var color: Color = Palette.GOLD_PALE if change > 0 else Palette.TEXT_DIM
	var out := figure(
		LedgerProductionText.stock_delta_text(change), 12, color, DELTA_WIDTH
	)
	if change != 0:
		out.tooltip_text = "Next turn:  %s %s" % [
			CommodityCatalog.label(id), LedgerProductionText.stock_delta_text(change)
		]
	return out


## One recipe the court can run: what it holds of the output, what it has set for
## the turn, and the stepper. The workshop tag says what a multi-turn row is
## already serving (wiki: production-recipes § Turns per unit).
static func recipe_row(
	recipe_id: String,
	economy: PlayerEconomy,
	report: Dictionary,
	counsel_runs: Dictionary,
	row_height: float,
	compact: bool,
	rows: Dictionary,
	on_change: Callable
) -> Control:
	var row := UiRowBuilder.row(row_height)
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
	var planned: int = int(counsel_runs.get(recipe_id, 0))
	var title_text: String = LedgerProductionText.recipe_title(recipe_id)
	if planned > 0:
		title_text = "%s %s" % [LedgerProduction.COURT_MARK, title_text]
	var title := UiRowBuilder.label(
		title_text,
		LedgerProduction.TITLE_PIXELS if compact else LedgerProduction.TITLE_PIXELS_ATLAS,
		Palette.GOLD_PALE if planned > 0 else Palette.TEXT
	)
	title.tooltip_text = LedgerProductionText.recipe_tooltip(recipe_id)
	if planned > 0:
		title.tooltip_text += "\nThe court would run this %d time%s this phase." % [
			planned, "" if planned == 1 else "s"
		]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(title)
	var town: int = town_level(report)
	var gated: bool = not (
		ProductionRecipes.tier_met(recipe_id, economy.workers)
		and ProductionRecipes.town_met(recipe_id, town)
	)
	var note_text: String = (
		LedgerProductionText.gate_note(recipe_id, town) if gated
		else LedgerWorkshop.row_note(economy, recipe_id)
	)
	var note := UiRowBuilder.label(
		note_text,
		LedgerProduction.NOTE_PIXELS if compact else LedgerProduction.NOTE_PIXELS_ATLAS,
		Palette.TEXT_DIM
	)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.visible = not note_text.is_empty()
	if gated:
		note.tooltip_text = LedgerProductionText.gate_tooltip(recipe_id, town)
	elif not note_text.is_empty():
		note.tooltip_text = LedgerWorkshop.row_tooltip(economy, recipe_id)
	words.add_child(note)
	row.add_child(words)

	var held := figure(str(economy.quantity(output_id)), 14, Palette.GOLD_PALE, QTY_WIDTH)
	row.add_child(held)
	var units: int = economy.production.assignment_units(recipe_id)
	var stepper := figure("%d" % units, 14, Palette.GOLD_PALE, STEP_WIDTH)
	row.add_child(stepper)

	var minus := UiRowBuilder.button("−", row_height, BUTTON_WIDTH)
	minus.disabled = units <= 0
	minus.tooltip_text = "One fewer %s this turn" % CommodityCatalog.label(output_id)
	# Bind the assignment — no lambda capture — so a freed page during teardown
	# cannot leave a Callable holding a dead host (REQ-P3-02; estates raise walk).
	if on_change.is_valid():
		minus.pressed.connect(on_change.bind(recipe_id, units - 1))
	row.add_child(minus)

	var limit: int = allowance(economy, report, recipe_id)
	var full: bool = ProductionWorkshop.room(
		economy.production_wip, recipe_id, ProductionRecipes.turns(recipe_id)
	) <= 0
	var plus := UiRowBuilder.button("+", row_height, BUTTON_WIDTH)
	plus.disabled = units >= limit
	plus.tooltip_text = (
		LedgerProductionText.gate_tooltip(recipe_id, town) if gated
		else LedgerWorkshop.allowance_note(recipe_id, limit, full)
	)
	if on_change.is_valid():
		plus.pressed.connect(on_change.bind(recipe_id, units + 1))
	row.add_child(plus)

	rows[recipe_id] = {
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
static func figure(text: String, size: int, color: Color, width: float) -> Label:
	var out := UiRowBuilder.label(text, size, color)
	out.custom_minimum_size = Vector2(width, 0)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return out


## Units this row may still be set to: the whole runs the coming Production phase
## could start from the projected post-Consumption store and idle labour, less
## the other rows' claims and the pieces already on the bench. The rules own the
## arithmetic; this only picks which state the phase will see (REQ-P2-03).
static func allowance(
	economy: PlayerEconomy, report: Dictionary, recipe_id: String
) -> int:
	var seen: Dictionary = ProductionBatch.budget(economy, report)
	return ProductionBatch.allowance(
		economy,
		recipe_id,
		town_level(report),
		seen["stock"],
		int(seen["labour"]),
		economy.production.assignments()
	)


## The crown's best town the projection was read against. Without a projection
## the page reads no town, so a gated row fails closed exactly as the phase
## would (DR-20261116-04).
static func town_level(report: Dictionary) -> int:
	return int(report.get("town_level", 0))
