class_name LedgerWorkers
extends VBoxContainer
## WORKERS tab of the ledger: the tier roster with its recruit and disband
## intents. Presentation only — blocked reasons come from PlayerEconomy, so the
## panel never invents a rule (REQ-P2-03). The larder, the tier rows and the
## order queue are painted by [LedgerWorkersRows]; the tab's words live on
## [LedgerWorkersText] (REQ-P3-01).

signal recruit_requested(tier: int, count: int)
signal disband_requested(tier: int)

## The mark a tier row wears when the court's own plan recruits it.
const COURT_MARK: String = "▸"
## What that mark means, printed beside it: the tab keeps no footer, so the
## sentence has nowhere else to stand (REQ-P1-07, REQ-P5-07; DR-20261123-08).
const MARK_LEGEND: String = "A ▸ marks the tier the court would recruit this phase."

var _economy: PlayerEconomy = null
var _report: Dictionary = {}
var _compact: bool = false
## Row actions keyed "<action>:<tier>" ("recruit:2", "disband:1") for tooling.
var _buttons: Dictionary = {}
## Batch presses keyed by tier: one full-width row under a tier the crown can
## pay for more than once (REQ-P5-04).
var _batches: Dictionary = {}
## Tier badges keyed by tier, so tooling reads the mark without walking rows.
var _marks: Dictionary = {}
## The court's own plan for this phase: the workers its economy pass would
## recruit, printed in gold above the tier rows it answers and marked ▸ on
## those rows (wiki: workers-and-population § Recruiting; DR-20261122-01).
var _counsel: Label = null
## What that mark means, under the line: the tier rows wear it, and the tab has
## no footer to explain it (DR-20261123-08).
var _legend: Label = null
var _pick: Dictionary = {}
## The price/ration line under each tier row, keyed by tier (REQ-P5-05).
var _lines: Dictionary = {}


## Phone geometry from the panel that owns the tab; a live rotation re-fills so
## the rows change size with the screen.
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _economy != null:
		fill(_economy, _report, _pick)


## `report` is the projection the panel already holds; `pick` is the court's own
## recruit pick (`MapPlayRecruitPick`), read on the crown's seat — a page filled
## without one carries no gold line (DR-20261122-01).
func fill(
	economy: PlayerEconomy, report: Dictionary = {}, pick: Dictionary = {}
) -> void:
	_economy = economy
	_report = report
	_pick = pick
	_counsel = null
	_legend = null
	_buttons.clear()
	_batches.clear()
	_marks.clear()
	_lines.clear()
	UiRowBuilder.clear(self)
	add_child(UiRowBuilder.label(LedgerWorkersText.INTRO, 11, Palette.TEXT_DIM))
	add_child(LedgerWorkersRows.larder_block(economy, report))
	# The court's own plan for this phase, in the colour every pick wears, above
	# the tier rows whose names it marks (DR-20261122-01), with the sentence that
	# says what that mark means: the tab has no footer to explain it, and a phone
	# would drop one anyway (DR-20261123-08).
	_counsel = UiRowBuilder.wrapped_line(
		String(pick.get("line", "")), 12, Palette.GOLD
	)
	_counsel.visible = not _counsel.text.is_empty()
	add_child(_counsel)
	var marked: bool = not (pick.get("tiers", {}) as Dictionary).is_empty()
	_legend = MarkLegend.make(MARK_LEGEND, self)
	MarkLegend.stand(_legend, marked)
	for tier in WorkerPool.TIER_COUNT:
		add_child(
			LedgerWorkersRows.tier_block(
				tier, economy, _compact, _pick, _buttons, _marks, _lines,
				_emit_recruit, _emit_disband
			)
		)
		var batch: Control = LedgerWorkersRows.batch_row(
			tier, economy, _compact, _batches, _emit_recruit
		)
		if batch != null:
			add_child(batch)
	UiRowBuilder.spacer(self)
	LedgerWorkersRows.pending_section(self, economy)


func _emit_recruit(tier: int, count: int) -> void:
	recruit_requested.emit(tier, count)


func _emit_disband(tier: int) -> void:
	disband_requested.emit(tier)


## Orders in the order they were filed, identical neighbours folded into one
## line with their count. Static and public so a test reads the fold without
## mounting the page (REQ-P3-02). The fold itself lives with the queue paint.
static func grouped_orders(orders: Array[Dictionary]) -> Array[Dictionary]:
	return LedgerWorkersRows.grouped_orders(orders)


## Batch presses keyed by tier; tests and tooling read this instead of walking
## the page's children (REQ-P3-02).
func batch_buttons() -> Dictionary:
	return _batches


## Row action buttons keyed "<action>:<tier>"; tests and tooling read this
## instead of walking row children (REQ-P3-02).
func action_buttons() -> Dictionary:
	return _buttons


## Tier badges keyed by tier; the roster mark a row wears for that rank.
func tier_marks() -> Dictionary:
	return _marks


## The price/ration line under each tier row, keyed by tier (REQ-P5-05).
func tier_lines() -> Dictionary:
	return _lines


## The court's own recruit line on the tab: the workers the published economy
## pass would buy this phase, or the gate that leaves the pool alone. Empty when
## the page was filled without a pick (DR-20261122-01).
func counsel_text() -> String:
	return _counsel.text if _counsel != null else ""


## The sentence that says what a tier row's mark means, for tests and tooling
## (REQ-P3-02, DR-20261123-08). Empty when the tab was filled without one.
func legend_text() -> String:
	return "" if _legend == null else _legend.text


## Whether the legend stands beside the marks it explains: only while the plan
## names a tier (REQ-P1-07, REQ-P5-06).
func legend_shown() -> bool:
	return _legend != null and _legend.visible
