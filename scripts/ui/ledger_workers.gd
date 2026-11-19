class_name LedgerWorkers
extends VBoxContainer
## WORKERS tab of the ledger: the tier roster with its recruit and disband
## intents. Presentation only — blocked reasons come from PlayerEconomy, so the
## panel never invents a rule (REQ-P2-03).

signal recruit_requested(tier: int, count: int)
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
## Batch presses keyed by tier: one full-width row under a tier the crown can
## pay for more than once (REQ-P5-04).
var _batches: Dictionary = {}
## Tier badges keyed by tier, so tooling reads the mark without walking rows.
var _marks: Dictionary = {}
## The price/ration line under each tier row, keyed by tier (REQ-P5-05).
var _lines: Dictionary = {}


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
	_batches.clear()
	_marks.clear()
	_lines.clear()
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
		var batch: Control = _batch_row(tier)
		if batch != null:
			add_child(batch)
	UiRowBuilder.spacer(self)
	_pending(economy)


## The larder the next Consumption phase will eat: what the store holds, what
## every mouth wants, and the tier that strikes first when it runs short. The
## phase report only speaks after the fact, so this is the reading a crown needs
## **before** it recruits into a thin larder (wiki: workers-and-population
## § Consumption; REQ-P5-06). Touch parity: every line is on the tab, not in a
## hover hint (REQ-P1-05, REQ-P5-07).
func _larder(economy: PlayerEconomy, report: Dictionary) -> Control:
	# The panel's projection is the turn the phase will run, so it already feeds
	# the hands and the musters Build/work lands: the larder must not count them
	# a second time (wiki: workers-and-population § Phase placement).
	var read: Dictionary = LarderRead.forecast(
		economy, LarderRead.mouths(report), false
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiRowBuilder.wrapped_line("LARDER · NEXT TURN", 11, Palette.TEXT_DIM))
	box.add_child(UiRowBuilder.wrapped_line(_store_copy(read), 12, Palette.TEXT))
	box.add_child(UiRowBuilder.wrapped_line(_appetite_copy(read), 12, Palette.TEXT_DIM))
	var short: bool = int(read["strikers"]) > 0
	box.add_child(
		UiRowBuilder.wrapped_line(
			_shortfall_copy(read), 12, Palette.CRIMSON if short else Palette.TEXT_DIM
		)
	)
	UiRowBuilder.spacer(box, 4.0)
	return box


## "Store 16 food · Fur Hats ×1" — the larder as it stands, naming only the
## luxuries this pool actually wants.
func _store_copy(read: Dictionary) -> String:
	var parts: PackedStringArray = ["%d food" % int(read["store_food"])]
	var store: Dictionary = read["store_luxury"]
	for id: Variant in store.keys():
		parts.append("%s ×%d" % [CommodityCatalog.label(String(id)), int(store[id])])
	return "Store " + "  ·  ".join(parts)


## "20 food wanted — army 8 · navy 4 · pool 6 · wards 2 · Refined Sugar ×3", or
## the short form "24 mouths eat 24 food" when the pool is the only appetite.
## Every appetite the phase pays is named in its own deduction order, because the
## army and the navy eat before the pool: a store that covers the pool alone still
## strikes it, and a reading that showed only the pool's mouths had the store
## cover them (wiki: workers-and-population § Consumption; REQ-P2-03).
func _appetite_copy(read: Dictionary) -> String:
	var appetites: Dictionary = read.get("appetites", {}) as Dictionary
	var army: int = int(appetites.get("army", 0))
	var navy: int = int(appetites.get("navy", 0))
	var pool: int = int(appetites.get("pool", int(read["food"])))
	var wards: int = int(appetites.get("wards", 0))
	var text: String
	if army + navy + wards <= 0:
		text = "%d mouths eat %d food" % [int(read["mouths"]), pool]
	else:
		var parts: PackedStringArray = []
		if army > 0:
			parts.append("army %d" % army)
		if navy > 0:
			parts.append("navy %d" % navy)
		if pool > 0:
			parts.append("pool %d" % pool)
		if wards > 0:
			parts.append("wards %d" % wards)
		text = "%d food wanted — %s" % [
			army + navy + pool + wards, " · ".join(parts),
		]
	var want: Dictionary = read["luxury"]
	for id: Variant in want.keys():
		text += "  ·  %s ×%d" % [CommodityCatalog.label(String(id)), int(want[id])]
	var arriving: int = int(read["arriving"])
	if arriving > 0:
		text += "  ·  %d arriving" % arriving
	return text


## "Short 2 food — 1 striker, masters first." or the calm cover line. Food is
## named first because the phase feeds it before any luxury, and the tier named
## is the one a shortfall bites first: the highest tier in the pool
## (wiki: workers-and-population § Consumption). The figure is the **whole
## larder's** shortfall — every appetite the phase pays, not the pool alone — so a
## store that keeps the workers fed while a ward or an army goes short never
## reads calm (total food demand = workers + navy + army + hospital staffs), and
## the mouth that missed is named from the dry run's own fed figures.
func _shortfall_copy(read: Dictionary) -> String:
	var short: int = int(read.get("store_short", read.get("food_short", 0)))
	var strikers: int = int(read["strikers"])
	if strikers <= 0:
		if short <= 0:
			return "The larder covers every mouth."
		return "Short %d food — %s." % [short, _hungry_mouth(read)]
	var tier: int = int(read["striking_tier"])
	var who: String = "%d striker%s, %s first" % [
		strikers,
		MoneyText.plural(strikers),
		WorkerPool.tier_name(maxi(tier, 0)).to_lower(),
	]
	if short > 0:
		return "Short %d food — %s." % [short, who]
	var luxuries: Dictionary = read["luxury_short"]
	for id: Variant in luxuries.keys():
		return "Short %d %s — %s." % [
			int(luxuries[id]), CommodityCatalog.label(String(id)), who
		]
	return "The larder runs short — %s." % who


## The appetite the dry run could not serve, in the phase's own order, for a
## crown whose workers ate: a starving army or navy, or a ward that lost its
## staff (wiki: combat § Regiment condition; DR-20261112-04).
func _hungry_mouth(read: Dictionary) -> String:
	var report: Dictionary = read.get("report", {}) as Dictionary
	if int(report.get("army_demand", 0)) > int(report.get("army_fed", 0)):
		return "the army goes short"
	if int(report.get("navy_demand", 0)) > int(report.get("navy_fed", 0)):
		return "the navy goes short"
	if int(report.get("hospital_demand", 0)) > int(report.get("hospital_fed", 0)):
		return "the wards go unfed"
	return "the store cannot cover every mouth"


## The crown's Build/work queue: each order arrives with next turn, so a player
## can see what the press bought without waiting for the gazette
## (wiki: workers-and-population § Phase placement). Identical orders read as one
## line with their count, so a batch is one promise and not a wall of rows.
func _pending(economy: PlayerEconomy) -> void:
	if economy.recruits.is_empty():
		return
	add_child(
		UiRowBuilder.label("UNDER ORDERS · ARRIVES NEXT TURN", 11, Palette.TEXT_DIM)
	)
	for line: Dictionary in grouped_orders(economy.recruits.orders):
		var row: Dictionary = line["row"]
		var count: int = int(line["count"])
		var name: String = RecruitQueue.label(row)
		if count > 1:
			name = "%s ×%d" % [name, count]
		add_child(
			UiRowBuilder.label("%s · %s" % [name, _kind(row)], 12, Palette.TEXT)
		)


## Orders in the order they were filed, identical neighbours folded into one
## line with their count. Static and public so a test reads the fold without
## mounting the page (REQ-P3-02).
static func grouped_orders(orders: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in orders:
		if not out.is_empty():
			var last: Dictionary = out[out.size() - 1]
			var seen: Dictionary = last["row"]
			if (
				String(seen.get("kind", "")) == String(row.get("kind", ""))
				and String(seen.get("key", "")) == String(row.get("key", ""))
			):
				last["count"] = int(last["count"]) + 1
				continue
		out.append({"row": row, "count": 1})
	return out


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
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var row := UiRowBuilder.row(height)
	entry.add_child(row)
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
			LedgerWorkersText.recruit_cost(tier),
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
				LedgerWorkersText.disband_hint(tier),
				height
			)
		)
	entry.add_child(_recruit_line(tier))
	return entry


## The one line under a tier row: the price it pays and, in that order, the study
## a locked tier waits on, the rule that stops it or the ration it eats. On the
## sheet itself, never only in the button's hover, so a touch crown reads what a
## press costs before it pays (wiki: workers-and-population § Recruiting,
## § Tech gates, § Worker Tiers; REQ-P1-05, REQ-P5-05, REQ-P5-06).
func _recruit_line(tier: int) -> Label:
	var reason: String = _economy.recruit_blocked_reason(tier)
	var missing: Array[String] = WorkerPool.missing_techs(tier, _economy.tech_unlocked)
	var line := UiRowBuilder.wrapped_line(
		LedgerWorkersText.recruit_line(tier, reason, missing),
		10,
		Palette.CRIMSON if not reason.is_empty() else Palette.TEXT_DIM
	)
	_lines[tier] = line
	return line


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
		button.pressed.connect(func() -> void: recruit_requested.emit(tier, 1))
	_buttons["%s:%d" % [kind, tier]] = button
	return button


## A tier the crown can pay for more than once gets one full-width batch press
## under its row: the count, the whole batch's price and the press that files
## them all. The single-head RECRUIT stays, so a batch is never forced
## (wiki: workers-and-population § Recruiting; REQ-P5-04, REQ-P5-05).
func _batch_row(tier: int) -> Control:
	if _economy == null:
		return null
	var count: int = _economy.recruit_affordable(tier)
	if count <= 1:
		return null
	var height: float = COMPACT_ROW_HEIGHT if _compact else ROW_HEIGHT
	var button := UiRowBuilder.button(
		"Recruit ×%d  ·  %s" % [count, LedgerWorkersText.recruit_batch_cost(tier, count)], height, 0.0
	)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = (
		"Files %d orders at once — each pays its own cost in Build/work." % count
	)
	button.pressed.connect(func() -> void: recruit_requested.emit(tier, count))
	_batches[tier] = button
	return button


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
