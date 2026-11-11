extends SceneTree
## Headless playtest drive for the mid-game purse: what the crown's treasury is
## promised and what the turn actually pays (wiki: stockpiles-and-production
## § Production flow, world-market § Trade orders, tech-tree § Research Model).
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://tests/playtest_treasury.gd
##
## The drive opens the turn-100 advanced start (a court with estates, a market
## book and funded research slots), then reads only what a player reads: the top
## bar's treasury chip and its per-turn figure, the ledger's summary and "Next
## turn" preview, the MARKET tab's own rows, and the college's slot funding.
## Every order is pressed on the ledger's own buttons and every turn goes through
## `MapPlayTurn`, so the promise and the payout are the game's, not the drive's.

const Launch = preload("res://tests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const MAX_TURN_ATTEMPTS: int = 4

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s — %s, turn %d, %d provinces, %d ducats" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		_play.model.province_count(), _play.treasury(),
	])
	await _purse_pass()
	await _offer_pass()
	await _funding_pass()
	await _study_pass()
	_finish()


# --- passes ----------------------------------------------------------------


## The purse as the player first meets it: the chip, its per-turn figure and
## tooltip, the ledger's summary and preview, and the market's own rows.
func _purse_pass() -> void:
	_say("")
	_say("--- the purse the player opens: chip, ledger, college ---")
	_read_chip("at the turn's opening")
	# A settle check: the chip animates a change over a few frames, so a value
	# that is still the old purse after half a second is stale, not mid-count.
	for _frame in 30:
		await process_frame
	_read_chip("after 30 frames")
	_say("the purse itself: %d ducats (the chip must agree)" % _play.treasury())
	_play.economy.open_panel()
	await process_frame
	_say("ledger header: %s" % _ledger_summary())
	_say("ledger preview: %s" % _ledger_preview())
	var rows: Array[Dictionary] = _market_rows()
	_say("market rows: %d, %d sellable, %d buyable" % [
		rows.size(), _sellable(rows).size(), rows.size(),
	])
	_say("cargo banner: %s" % _cargo_banner())
	_say("staged: %s" % _staged_text())
	_play.hud.panels.hide_economy()
	_play.economy.open_research()
	await process_frame
	_say("college summary: %s" % _college_summary())
	for line: String in _college_slots():
		_say("  slot: %s" % line)
	_play.hud.panels.hide_research()


## One sale: the biggest surplus the ledger will let the crown offer, pressed on
## the ledger's own Offer button, then the same turn closed. The promise made
## before the press, the promise after it, and the ducats the turn actually paid.
func _offer_pass() -> void:
	_say("")
	_say("--- one sale: what the ledger promises, what the auction pays ---")
	_play.economy.open_panel()
	await process_frame
	var rows: Array[Dictionary] = _market_rows()
	var sellable: Array[Dictionary] = _sellable(rows)
	if sellable.is_empty():
		_say("nothing sellable this turn — the preview cannot be compared")
		_play.hud.panels.hide_economy()
		return
	var best: Dictionary = sellable[0]
	for row: Dictionary in sellable:
		if int(row["held"]) > int(best["held"]):
			best = row
	_say("offering one %s (holding %d at %s ducats)" % [
		String(best["id"]), int(best["held"]), String(best["price"]),
	])
	_say("promise before the press: %s" % _ledger_preview())
	_say("chip before the press: %s" % _chip_line())
	var offer: Button = best["offer"] as Button
	offer.emit_signal("pressed")
	await process_frame
	_say("toast: %s" % _last_toast())
	_say("promise after the press: %s" % _ledger_preview())
	_say("chip after the press: %s" % _chip_line())
	_say("staged: %s" % _staged_text())
	_play.hud.panels.hide_economy()
	var before: int = _play.treasury()
	var promised: int = _promised_delta()
	var report: Dictionary = _projection()
	_say("the projection behind the promise: riches +%d, research -%d, net %+d" % [
		int(report.get("riches_treasury", 0)),
		int((report.get("research", {}) as Dictionary).get("spent", 0)),
		promised,
	])
	var started: int = Time.get_ticks_msec()
	if not _advance():
		_say("the calendar never moved — the turn stayed shut")
		return
	var actual: int = _play.treasury() - before
	_say("calendar: turn %d (%d ms); treasury %d -> %d, actually %+d, promised %+d" % [
		_play.turn, Time.get_ticks_msec() - started, before, _play.treasury(),
		actual, promised,
	])
	_say("turn toast: %s" % _last_toast())
	_say("market report: %s" % _market_line())
	var credits: Dictionary = (_play.market_report.get("credits", {}) as Dictionary).get("by_gp", {})
	_say("first-right credits this turn: %d ducats" % roundi(float(credits.get(
		_play.player_faction, credits.get(str(_play.player_faction), 0.0)))))
	_play.economy.open_panel()
	await process_frame
	_say("ledger after the turn: %s" % _ledger_summary())
	_say("ledger preview after the turn: %s" % _ledger_preview())
	_say("last clearing: %s" % _clearing_text())
	_play.hud.panels.hide_economy()
	_read_chip("after the turn")


## The other half of the purse: the college's slots pay gold every turn. The
## drive reads what each slot costs and whether the ledger's promise names it.
func _funding_pass() -> void:
	_say("")
	_say("--- the college: what the slots cost and what the purse is told ---")
	_play.economy.open_research()
	await process_frame
	_say("college summary: %s" % _college_summary())
	for line: String in _college_slots():
		_say("  slot: %s" % line)
	_play.hud.panels.hide_research()
	_play.economy.open_panel()
	await process_frame
	_say("ledger summary: %s" % _ledger_summary())
	_say("ledger preview: %s" % _ledger_preview())
	_play.hud.panels.hide_economy()
	var report: Dictionary = _projection()
	var research: Dictionary = report.get("research", {}) as Dictionary
	_say("the promise's arithmetic: riches +%d, research -%d (%d slot(s)), net %+d" % [
		int(report.get("riches_treasury", 0)), int(research.get("spent", 0)),
		(research.get("slots", []) as Array).size(), _promised_delta(),
	])
	_say("treasury floor: %d (money lending %s, banking %s)" % [
		ResearchFunding.floor_for(_play.tech_unlocked()),
		str(bool(_play.tech_unlocked().get(ResearchFunding.MONEY_LENDING, false))),
		str(bool(_play.tech_unlocked().get(ResearchFunding.BANKING, false))),
	])


## The college's half of the purse: a study is assigned from the panel's own
## row, the promise must name the gold it will pay, and the turn must pay it.
func _study_pass() -> void:
	_say("")
	_say("--- one study: the college's gold against the promise ---")
	_play.economy.open_research()
	await process_frame
	var assign: Button = _find_open_study(_play.hud.panels.research_panel)
	if assign == null:
		_say("no open advance offers a free slot — the college has nothing to start")
		_play.hud.panels.hide_research()
		return
	assign.emit_signal("pressed")
	await process_frame
	_say("chip after starting the study: %s" % _chip_line())
	for line: String in _college_slots():
		_say("  slot: %s" % line)
	_play.hud.panels.hide_research()
	_play.economy.open_panel()
	await process_frame
	_say("promise with a study: %s" % _ledger_preview())
	_play.hud.panels.hide_economy()
	var before: int = _play.treasury()
	var promised: int = _promised_delta()
	var report: Dictionary = _projection()
	var research: Dictionary = report.get("research", {}) as Dictionary
	_say("the promise's arithmetic: riches +%d, research -%d, net %+d" % [
		int(report.get("riches_treasury", 0)), int(research.get("spent", 0)), promised,
	])
	if not _advance():
		_say("the calendar never moved — the turn stayed shut")
		return
	var actual: int = _play.treasury() - before
	_say("calendar: turn %d; treasury %d -> %d, actually %+d, promised %+d" % [
		_play.turn, before, _play.treasury(), actual, promised,
	])
	_say("turn toast: %s" % _last_toast())
	_say("market report: %s" % _market_line())
	_play.economy.open_panel()
	await process_frame
	_say("ledger after the turn: %s" % _ledger_summary())
	_say("ledger preview after the turn: %s" % _ledger_preview())
	_say("last clearing: %s" % _clearing_text())
	_play.hud.panels.hide_economy()
	_play.economy.open_research()
	await process_frame
	_say("college after the turn: %s" % _college_summary())
	for line: String in _college_slots():
		_say("  slot: %s" % line)
	_play.hud.panels.hide_research()


## The first "Research" button the college offers with a free slot
## (ResearchRow.available; the disabled ones are already taken).
func _find_open_study(node: Node) -> Button:
	if node is Button:
		var button: Button = node
		if button.text == "Research" and not button.disabled:
			return button
	for child: Node in node.get_children():
		var found: Button = _find_open_study(child)
		if found != null:
			return found
	return null


# --- reads -----------------------------------------------------------------


func _chip_line() -> String:
	return "%s / %s — tooltip \"%s\"" % [
		_play.hud._treasury_label.text, _play.hud._income_label.text,
		_play.hud._treasury_chip.tooltip_text,
	]


func _read_chip(label: String) -> void:
	_say("chip %s: %s" % [label, _chip_line()])


func _promised_delta() -> int:
	return _play.economy.projected_income()


func _projection() -> Dictionary:
	return _play.economy.projected()


## The panel's summary sentence: treasury, labour, food need and strikes
## (LedgerText.summary).
func _ledger_summary() -> String:
	for text: String in _body_labels("PRODUCTION"):
		if " ducats" in text and " labour " in text:
			return text
	for text: String in _panel_labels():
		if " ducats" in text and " labour " in text:
			return text
	return "no summary line"


## The "Next turn: …" promise under the header (LedgerText.preview).
func _ledger_preview() -> String:
	for text: String in _panel_labels():
		if text.begins_with("Next turn:"):
			return text
	return "no preview line"


func _panel_labels() -> Array[String]:
	var out: Array[String] = []
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud.panels.economy_panel, labels)
	for text: String in labels:
		out.append(text)
	return out


func _college_summary() -> String:
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud.panels.research_panel, labels)
	for text: String in labels:
		if " slot" in text:
			return text
	return labels[0] if not labels.is_empty() else "no line"


## One line per occupied slot: the tech, its progress and the funding preset
## with the gold that preset costs (ResearchRow.slot).
func _college_slots() -> Array[String]:
	var out: Array[String] = []
	for row: Node in _play.hud.panels.research_panel.find_children("*", "HBoxContainer", true, false):
		var labels: PackedStringArray = PackedStringArray()
		_collect(row, labels)
		if labels.size() < 2 or not labels[1].ends_with("RP") or not " / " in labels[1]:
			continue
		var funding := ""
		for child: Node in row.get_children():
			if child is Button and funding.is_empty():
				# The first button is the funding preset; Cancel follows it.
				funding = "%s (%s)" % [(child as Button).text, (child as Button).tooltip_text]
		if funding.is_empty():
			continue
		out.append("%s — %s — %s" % [labels[0], labels[1], funding])
	return out


func _cargo_banner() -> String:
	for text: String in _body_labels("MARKET"):
		if text.begins_with("CARGO") or text.begins_with("No cargo"):
			return text
	return "no cargo banner"


## The crown's staged bids and offers, read from the MARKET tab's own rows
## (LedgerMarket._staged_row: the side, the good, the units and the notional).
func _staged_text() -> String:
	var lines: Array[String] = []
	for text: String in _body_labels("MARKET"):
		if text.begins_with("No orders staged"):
			return text
	var body: Node = _play.hud.panels.economy_panel.page_body("MARKET")
	if body == null:
		return "no market tab"
	for child: Node in body.get_children():
		if not (child is HBoxContainer):
			continue
		var labels: PackedStringArray = PackedStringArray()
		_collect(child, labels)
		if labels.size() > 0 and (labels[0] == "BID" or labels[0] == "OFFER"):
			lines.append(" / ".join(labels))
	return "none" if lines.is_empty() else "  ·  ".join(lines)


func _clearing_text() -> String:
	var lines: Array[String] = []
	for text: String in _body_labels("MARKET"):
		if text.begins_with("Bought ") or text.begins_with("Sold "):
			lines.append(text)
		elif text.begins_with("Overseas shares") or text.ends_with(" more deals"):
			lines.append(text)
	return "no deals" if lines.is_empty() else "  ·  ".join(lines)


func _market_line() -> String:
	var line: String = LedgerText.market_summary(_play.market_report, _play.player_faction)
	return line if not line.is_empty() else "nothing cleared"


func _body_labels(tab: String) -> Array[String]:
	var out: Array[String] = []
	var body: Node = _play.hud.panels.economy_panel.page_body(tab)
	if body == null:
		return out
	var labels: PackedStringArray = PackedStringArray()
	_collect(body, labels)
	for text: String in labels:
		out.append(text)
	return out


## The MARKET tab's commodity rows: the row's own medallion cell, the held
## count, the price and the two order buttons (LedgerMarket._market_row).
func _market_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[String] = []
	for category: Variant in LedgerMarket.CATEGORIES:
		for id: String in CommodityCatalog.ids_in(category):
			ids.append(id)
	var rows: Array[Node] = _market_row_nodes()
	for index in mini(ids.size(), rows.size()):
		var row: Node = rows[index]
		var labels: PackedStringArray = PackedStringArray()
		_collect(row, labels)
		if labels.size() < 2:
			continue
		var offer: Button = null
		var bid: Button = null
		for child: Node in row.get_children():
			if child is Button:
				var button: Button = child
				if button.text == "Offer":
					offer = button
				elif button.text == "Bid":
					bid = button
		out.append({
			"id": ids[index],
			"held": int(labels[1]) if labels[1].is_valid_int() else 0,
			"price": labels[2] if labels.size() > 2 else "?",
			"offer": offer,
			"bid": bid,
		})
	return out


func _market_row_nodes() -> Array[Node]:
	var out: Array[Node] = []
	var body: Node = _play.hud.panels.economy_panel.page_body("MARKET")
	if body == null:
		return out
	for child: Node in body.get_children():
		if not (child is HBoxContainer):
			continue
		var buttons: int = 0
		for sub: Node in child.get_children():
			if sub is Button:
				buttons += 1
		# Commodity rows carry Offer and Bid; offer/staged rows carry one button.
		if buttons >= 2:
			out.append(child)
	return out


func _sellable(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		var offer: Button = row.get("offer", null) as Button
		if offer != null and not offer.disabled:
			out.append(row)
	return out


func _last_toast() -> String:
	if _play.hud.despatches.lane == null:
		return "none"
	var labels: PackedStringArray = PackedStringArray()
	_collect(_play.hud.despatches.lane, labels)
	return labels[labels.size() - 1] if not labels.is_empty() else "none"


func _collect(node: Node, into: PackedStringArray) -> void:
	if node is Label:
		var label: Label = node
		if label.visible and not label.text.strip_edges().is_empty():
			into.append(label.text)
	elif node is Button:
		var button: Button = node
		if button.visible and not button.text.strip_edges().is_empty():
			into.append(button.text)
	for child: Node in node.get_children():
		_collect(child, into)


# --- turns -----------------------------------------------------------------


## Closes one turn, answering whatever consent decision a rival court raised
## (the player would answer the court plate). False when the turn stays shut.
func _advance() -> bool:
	for _attempt in MAX_TURN_ATTEMPTS:
		var before: int = _play.turn
		MapPlayTurn.end_turn(_play)
		if _play.turn > before:
			return true
		if not _answer_pending():
			return false
		if _play.turn > before:
			return true
	return false


func _answer_pending() -> bool:
	if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: call to arms — stood aside")
		MapPlayTurn.answer_call(_play, false)
		return true
	if Intervention.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: intervention — did nothing")
		MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		return true
	if DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
		_say("  court asks: a proposal — refused")
		MapPlayTurn.answer_offer(_play, false)
		return true
	return false


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_treasury: %d steps ---" % _steps.size())
	quit()
