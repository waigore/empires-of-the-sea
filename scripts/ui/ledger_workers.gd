class_name LedgerWorkers
extends VBoxContainer
## WORKERS tab of the ledger: the tier roster with its recruit and disband
## intents. Presentation only — blocked reasons come from PlayerEconomy, so the
## panel never invents a rule (REQ-P2-03).

signal recruit_requested(tier: int)
signal disband_requested(tier: int)

const ROW_HEIGHT: float = 38.0
## A phone row is thumb-sized; the desktop ledger stays dense (REQ-P1-05).
const COMPACT_ROW_HEIGHT: float = 44.0
const ACTION_WIDTH: float = 88.0

var _economy: PlayerEconomy = null
var _report: Dictionary = {}
var _compact: bool = false
## Row actions keyed "<action>:<tier>" ("recruit:2", "disband:1") for tooling.
var _buttons: Dictionary = {}
## Tier badges keyed by tier, so tooling reads the mark without walking rows.
var _marks: Dictionary = {}


## Phone geometry from the panel that owns the tab; a live rotation re-fills so
## the rows change size with the screen.
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _economy != null:
		fill(_economy, _report)


func fill(economy: PlayerEconomy, report: Dictionary = {}) -> void:
	_economy = economy
	_report = report
	_buttons.clear()
	_marks.clear()
	UiRowBuilder.clear(self)
	add_child(
		UiRowBuilder.label(
			"Trained workers eat grain, meat and their tier luxury. Disband refunds nothing.",
			11,
			Palette.TEXT_DIM
		)
	)
	add_child(_larder(economy, report))
	for tier in WorkerPool.TIER_COUNT:
		add_child(_tier_row(tier))
	UiRowBuilder.spacer(self)
	_pending(economy)


## The larder the next Consumption phase will eat: what the store holds, what
## every mouth wants, and the tier that strikes first when it runs short. The
## phase report only speaks after the fact, so this is the reading a crown needs
## **before** it recruits into a thin larder (wiki: workers-and-population
## § Consumption; REQ-P5-06). Touch parity: every line is on the tab, not in a
## hover hint (REQ-P1-05, REQ-P5-07).
func _larder(economy: PlayerEconomy, report: Dictionary) -> Control:
	var read: Dictionary = LarderRead.forecast(economy, LarderRead.mouths(report))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_line("LARDER · NEXT TURN", 11, Palette.TEXT_DIM))
	box.add_child(_line(_store_copy(read), 12, Palette.TEXT))
	box.add_child(_line(_appetite_copy(read), 12, Palette.TEXT_DIM))
	var short: bool = int(read["strikers"]) > 0
	box.add_child(
		_line(
			_shortfall_copy(read),
			12,
			Palette.CRIMSON if short else Palette.TEXT_DIM
		)
	)
	box.add_child(_pad(4))
	return box


## A wrapping ledger line: a phone narrows instead of clipping the sentence
## (REQ-P1-05).
func _line(text: String, size: int, color: Color) -> Label:
	var out: Label = UiRowBuilder.label(text, size, color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return out


func _pad(height: float) -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, height)
	return pad


## "Store 16 food · 3 Refined Sugar" — the larder as it stands, naming only the
## luxuries this pool actually wants.
func _store_copy(read: Dictionary) -> String:
	var parts: PackedStringArray = ["%d food" % int(read["store_food"])]
	var store: Dictionary = read["store_luxury"]
	for id: Variant in store.keys():
		parts.append("%d %s" % [int(store[id]), CommodityCatalog.label(String(id))])
	return "Store " + "  ·  ".join(parts)


## "24 mouths eat 18 food · 3 Refined Sugar · 2 arriving" — every appetite the
## phase pays before the larder can be called short.
func _appetite_copy(read: Dictionary) -> String:
	var text: String = "%d mouths eat %d food" % [int(read["mouths"]), int(read["food"])]
	var want: Dictionary = read["luxury"]
	for id: Variant in want.keys():
		text += "  ·  %d %s" % [int(want[id]), CommodityCatalog.label(String(id))]
	var arriving: int = int(read["arriving"])
	if arriving > 0:
		text += "  ·  %d arriving" % arriving
	return text


## "Short 2 food — 1 striker, masters first." or the calm cover line. Food is
## named first because the phase feeds it before any luxury, and the tier named
## is the one a shortfall bites first: the highest tier in the pool
## (wiki: workers-and-population § Consumption).
func _shortfall_copy(read: Dictionary) -> String:
	var strikers: int = int(read["strikers"])
	if strikers <= 0:
		return "The larder covers every mouth."
	var tier: int = int(read["striking_tier"])
	var who: String = "%d striker%s, %s first" % [
		strikers,
		"" if strikers == 1 else "s",
		WorkerPool.tier_name(maxi(tier, 0)).to_lower(),
	]
	var short: int = int(read["food_short"])
	if short > 0:
		return "Short %d food — %s." % [short, who]
	var luxuries: Dictionary = read["luxury_short"]
	for id: Variant in luxuries.keys():
		return "Short %d %s — %s." % [
			int(luxuries[id]), CommodityCatalog.label(String(id)), who
		]
	return "The larder runs short — %s." % who


## The crown's Build/work queue: each order arrives with next turn, so a player
## can see what the press bought without waiting for the gazette
## (wiki: workers-and-population § Phase placement).
func _pending(economy: PlayerEconomy) -> void:
	if economy.recruits.is_empty():
		return
	add_child(
		UiRowBuilder.label("UNDER ORDERS · ARRIVES NEXT TURN", 11, Palette.TEXT_DIM)
	)
	for row: Dictionary in economy.recruits.orders:
		add_child(
			UiRowBuilder.label(
				"%s · %s" % [RecruitQueue.label(row), _kind(row)], 12, Palette.TEXT
			)
		)


## The phasing word on a pending row, so a hull is not read as a hired clerk.
func _kind(row: Dictionary) -> String:
	match String(row.get("kind", "")):
		RecruitQueue.KIND_REGIMENT:
			return "musters in Build/work"
		RecruitQueue.KIND_SHIP:
			return "launches in Build/work"
		RecruitQueue.KIND_CIVILIAN:
			return "engaged at the capital"
	return "joins the pool in Build/work"


func _tier_row(tier: int) -> Control:
	var height: float = COMPACT_ROW_HEIGHT if _compact else ROW_HEIGHT
	var mark: int = WorkerTierArt.MARK_COMPACT if _compact else WorkerTierArt.MARK_SIZE
	var row := UiRowBuilder.row(height)
	var badge := WorkerTierArt.badge(tier, mark)
	row.add_child(badge)
	_marks[tier] = badge
	var name_label := UiRowBuilder.label(WorkerPool.tier_name(tier), 14, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(132, 0)
	row.add_child(name_label)
	var text: String = "%d  ·  labour %d" % [
		_economy.workers.count(tier),
		_economy.workers.count(tier) * WorkerPool.LABOUR_PER_WORKER[tier],
	]
	var arriving: int = _economy.recruits.pending(RecruitQueue.KIND_WORKER, str(tier))
	if arriving > 0:
		text += "  ·  %d arriving" % arriving
	var detail := UiRowBuilder.label(text, 13, Palette.TEXT_DIM)
	detail.clip_text = true
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	row.add_child(
		_action(
			"recruit",
			tier,
			"Recruit",
			_economy.recruit_blocked_reason(tier),
			LedgerText.recruit_cost(tier),
			height
		)
	)
	if WorkerPool.is_trained(tier):
		row.add_child(
			_action(
				"disband",
				tier,
				"Disband",
				_economy.disband_blocked_reason(tier),
				LedgerText.disband_hint(tier),
				height
			)
		)
	return row


## One row action. A blocked row stays visible but inert so the roster keeps its
## shape; the tooltip carries the rules reason or, when payable, the price.
func _action(
	kind: String, tier: int, text: String, reason: String, hint: String, height: float
) -> Button:
	var button := UiRowBuilder.button(text, height)
	button.custom_minimum_size = Vector2(ACTION_WIDTH, height)
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else hint
	if kind == "disband":
		button.pressed.connect(func() -> void: disband_requested.emit(tier))
	else:
		button.pressed.connect(func() -> void: recruit_requested.emit(tier))
	_buttons["%s:%d" % [kind, tier]] = button
	return button


## Row action buttons keyed "<action>:<tier>"; tests and tooling read this
## instead of walking row children (REQ-P3-02).
func action_buttons() -> Dictionary:
	return _buttons


## Tier badges keyed by tier; the roster mark a row wears for that rank.
func tier_marks() -> Dictionary:
	return _marks
