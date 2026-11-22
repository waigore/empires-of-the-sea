class_name LedgerWorkersRows
extends RefCounted
## How the WORKERS tab paints its larder, tier rows and batch presses. Kept out
## of [LedgerWorkers] so the sheet stays under the P3 size bar (REQ-P3-01);
## presentation only — every block, price and ceiling comes from the rules, and
## every press is an intent the page binds and emits (REQ-P2-03, REQ-P3-02).

const ROW_HEIGHT: float = 38.0
## A phone row is thumb-sized; the desktop ledger stays dense (REQ-P1-05).
const COMPACT_ROW_HEIGHT: float = 44.0
const ACTION_WIDTH: float = 88.0


## The larder the next Consumption phase will eat: what the store holds, what
## every mouth wants, and the tier that strikes first when it runs short. The
## phase report only speaks after the fact, so this is the reading a crown needs
## **before** it recruits into a thin larder (wiki: workers-and-population
## § Consumption; REQ-P5-06). Touch parity: every line is on the tab, not in a
## hover hint (REQ-P1-05, REQ-P5-07).
static func larder_block(economy: PlayerEconomy, report: Dictionary) -> Control:
	# The panel's projection is the turn the phase will run, so it already feeds
	# the hands and the musters Build/work lands: the larder must not count them
	# a second time (wiki: workers-and-population § Phase placement).
	var read: Dictionary = LarderRead.forecast(
		economy, LarderRead.mouths(report), false
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(UiRowBuilder.wrapped_line("LARDER · NEXT TURN", 11, Palette.TEXT_DIM))
	box.add_child(
		UiRowBuilder.wrapped_line(LedgerWorkersText.larder_store(read), 12, Palette.TEXT)
	)
	box.add_child(
		UiRowBuilder.wrapped_line(
			LedgerWorkersText.larder_appetite(read), 12, Palette.TEXT_DIM
		)
	)
	var short: bool = int(read["strikers"]) > 0
	box.add_child(
		UiRowBuilder.wrapped_line(
			LedgerWorkersText.larder_shortfall(read), 12,
			Palette.CRIMSON if short else Palette.TEXT_DIM
		)
	)
	UiRowBuilder.spacer(box, 4.0)
	return box


## One tier of the roster: its medallion, the heads and labour it holds, the two
## row actions and the promise line under them. `buttons`, `marks` and `lines`
## are the page's own keyed tables, so tooling reads a row without walking it
## (REQ-P3-02).
static func tier_block(
	tier: int,
	economy: PlayerEconomy,
	compact: bool,
	pick: Dictionary,
	buttons: Dictionary,
	marks: Dictionary,
	lines: Dictionary,
	on_recruit: Callable,
	on_disband: Callable
) -> Control:
	var height: float = COMPACT_ROW_HEIGHT if compact else ROW_HEIGHT
	var mark: int = WorkerTierArt.MARK_COMPACT if compact else WorkerTierArt.MARK_SIZE
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var row := UiRowBuilder.row(height)
	entry.add_child(row)
	var badge := WorkerTierArt.badge(tier, mark)
	row.add_child(badge)
	marks[tier] = badge
	var name_text: String = WorkerPool.tier_name(tier)
	if (pick.get("tiers", {}) as Dictionary).has(tier):
		name_text = "%s %s" % [LedgerWorkers.COURT_MARK, name_text]
	var name_label := UiRowBuilder.label(name_text, 14, Palette.TEXT)
	name_label.custom_minimum_size = Vector2(132, 0)
	row.add_child(name_label)
	var text: String = "%d  ·  labour %d" % [
		economy.workers.count(tier),
		economy.workers.count(tier) * WorkerPool.LABOUR_PER_WORKER[tier],
	]
	var arriving: int = economy.recruits.pending(RecruitQueue.KIND_WORKER, str(tier))
	if arriving > 0:
		text += "  ·  %d arriving" % arriving
	var detail := UiRowBuilder.label(text, 13, Palette.TEXT_DIM)
	detail.clip_text = true
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	row.add_child(
		action(
			"recruit",
			tier,
			"Recruit",
			economy.recruit_blocked_reason(tier),
			LedgerWorkersText.recruit_cost(tier),
			height,
			buttons,
			on_recruit,
			on_disband
		)
	)
	if WorkerPool.is_trained(tier):
		row.add_child(
			action(
				"disband",
				tier,
				"Disband",
				economy.disband_blocked_reason(tier),
				LedgerWorkersText.disband_hint(tier),
				height,
				buttons,
				on_recruit,
				on_disband
			)
		)
	entry.add_child(promise_line(tier, economy, lines))
	return entry


## The one line under a tier row: the price it pays and, in that order, the study
## a locked tier waits on, the rule that stops it or the ration it eats. On the
## sheet itself, never only in the button's hover, so a touch crown reads what a
## press costs before it pays (wiki: workers-and-population § Recruiting,
## § Tech gates, § Worker Tiers; REQ-P1-05, REQ-P5-05, REQ-P5-06).
static func promise_line(tier: int, economy: PlayerEconomy, lines: Dictionary) -> Label:
	var reason: String = economy.recruit_blocked_reason(tier)
	var missing: Array[String] = WorkerPool.missing_techs(tier, economy.tech_unlocked)
	var line := UiRowBuilder.wrapped_line(
		LedgerWorkersText.recruit_line(tier, reason, missing),
		10,
		Palette.CRIMSON if not reason.is_empty() else Palette.TEXT_DIM
	)
	lines[tier] = line
	return line


## One row action. A blocked row stays visible but inert so the roster keeps its
## shape; the tooltip carries the rules reason or, when payable, the price.
static func action(
	kind: String,
	tier: int,
	text: String,
	reason: String,
	hint: String,
	height: float,
	buttons: Dictionary,
	on_recruit: Callable,
	on_disband: Callable
) -> Button:
	var button := UiRowBuilder.button(text, height)
	button.custom_minimum_size = Vector2(ACTION_WIDTH, height)
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason if not reason.is_empty() else hint
	# Bind the assignment — no lambda capture — so a freed page during teardown
	# cannot leave a Callable holding a dead host (REQ-P3-02).
	if kind == "disband" and on_disband.is_valid():
		button.pressed.connect(on_disband.bind(tier))
	elif kind != "disband" and on_recruit.is_valid():
		button.pressed.connect(on_recruit.bind(tier, 1))
	buttons["%s:%d" % [kind, tier]] = button
	return button


## A tier the crown can pay for more than once gets one full-width batch press
## under its row: the count, the whole batch's price and the press that files
## them all. The single-head RECRUIT stays, so a batch is never forced
## (wiki: workers-and-population § Recruiting; REQ-P5-04, REQ-P5-05).
static func batch_row(
	tier: int, economy: PlayerEconomy, compact: bool, batches: Dictionary,
	on_recruit: Callable
) -> Control:
	if economy == null:
		return null
	var count: int = economy.recruit_affordable(tier)
	if count <= 1:
		return null
	var height: float = COMPACT_ROW_HEIGHT if compact else ROW_HEIGHT
	var button := UiRowBuilder.button(
		"Recruit ×%d  ·  %s" % [count, LedgerWorkersText.recruit_batch_cost(tier, count)],
		height, 0.0
	)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = (
		"Files %d orders at once — each pays its own cost in Build/work." % count
	)
	if on_recruit.is_valid():
		button.pressed.connect(on_recruit.bind(tier, count))
	batches[tier] = button
	return button


## The crown's Build/work queue: each order arrives with next turn, so a player
## can see what the press bought without waiting for the gazette
## (wiki: workers-and-population § Phase placement). Identical orders read as one
## line with their count, so a batch is one promise and not a wall of rows.
static func pending_section(parent: Control, economy: PlayerEconomy) -> void:
	if economy.recruits.is_empty():
		return
	parent.add_child(
		UiRowBuilder.label("UNDER ORDERS · ARRIVES NEXT TURN", 11, Palette.TEXT_DIM)
	)
	for line: Dictionary in grouped_orders(economy.recruits.orders):
		var row: Dictionary = line["row"]
		var count: int = int(line["count"])
		var name: String = RecruitQueue.label(row)
		if count > 1:
			name = "%s ×%d" % [name, count]
		parent.add_child(
			UiRowBuilder.label("%s · %s" % [name, kind_word(row)], 12, Palette.TEXT)
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
static func kind_word(row: Dictionary) -> String:
	match String(row.get("kind", "")):
		RecruitQueue.KIND_REGIMENT:
			return "musters in Build/work"
		RecruitQueue.KIND_SHIP:
			return "launches in Build/work"
		RecruitQueue.KIND_CIVILIAN:
			return "engaged at the capital"
	return "joins the pool in Build/work"
