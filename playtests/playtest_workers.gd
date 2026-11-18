extends SceneTree
## Headless playtest drive for the crown's labour: the WORKERS tab, the recruit
## queue, the peasant reservation and the larder the next Consumption will eat
## (wiki: workers-and-population). Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_workers.gd
##
## Pass one plays a turn-0 crown honestly: the tab as a player reads it, one
## peasant recruited from the tab's own press, the queue it files, and a real
## turn closed so the phase — not the drive — pays the fabric and feeds the new
## hand. Pass two opens the turn-100 advanced start, where the trained tiers are
## unlocked: a journeyman disbanded, a journeyman trained, a regiment mustered
## from the army panel, and the reservation read after each. Pass three starves
## the larder and holds the tab's forecast to the phase's own report.

const Launch = preload("res://playtests/playtest_launch.gd")
const SCENE: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED_TEXT: String = "1500"
const MAX_TURN_ATTEMPTS: int = 4

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _opening_pass()
	await _trained_pass()
	await _thin_larder_pass()
	await _promise_pass()
	_finish()


# --- pass one: the tab a crown reads at turn 0 ------------------------------


func _opening_pass() -> void:
	_say("")
	_say("=== the crown's labour at turn 0 ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	var economy: PlayerEconomy = _play.economy.economy
	_say("seed %s — %s, turn %d, %d ducats, fabric %d, paper %d" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction), _play.turn,
		economy.treasury, economy.quantity("fabric"), economy.quantity("paper"),
	])
	_say("pool: %s · labour %d · food demand %d" % [
		_pool_text(economy.workers), economy.workers.labour(), economy.workers.food_demand(),
	])
	await _open_workers()
	_read_tab("turn 0")
	# The peasant row's own press: one head, paid in Build/work.
	var peasant: Button = _action("recruit", WorkerPool.Tier.PEASANT)
	if peasant == null:
		_say("no peasant Recruit press on the tab")
		return
	_say("peasant press: \"%s\" (%s)" % [
		peasant.text, "dead" if peasant.disabled else "live",
	])
	peasant.pressed.emit()
	await process_frame
	_say("toast: %s" % _last_toast())
	_say("after the press: pool %s · available %d · queue %d" % [
		_pool_text(economy.workers), economy.available_peasants(), economy.recruits.total(),
	])
	_read_tab("after the press")
	var fabric_before: int = economy.quantity("fabric")
	var treasury_before: int = economy.treasury
	await _close_turn("after the press")
	_say("the phase paid: fabric %d → %d, treasury %d → %d" % [
		fabric_before, economy.quantity("fabric"), treasury_before, economy.treasury,
	])
	_say("pool now: %s · queue %d" % [_pool_text(economy.workers), economy.recruits.total()])
	_read_consumption("the turn the peasant landed")
	_read_gazette("the turn the peasant landed")


# --- pass two: the trained tiers and the reservation ------------------------


func _trained_pass() -> void:
	_say("")
	_say("=== the trained tiers (turn-100 advanced start) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		return
	_play = _screen.play
	var economy: PlayerEconomy = _play.economy.economy
	_say("turn %d, %d ducats, paper %d, fabric %d" % [
		_play.turn, economy.treasury, economy.quantity("paper"), economy.quantity("fabric"),
	])
	_say("pool: %s · available %d" % [_pool_text(economy.workers), economy.available_peasants()])
	await _open_workers()
	_read_tab("turn 100")
	# A trained worker sent back to the fields: immediate, no refund, no order.
	var sent: int = WorkerPool.Tier.JOURNEYMAN
	if economy.workers.count(sent) <= 0:
		sent = WorkerPool.Tier.APPRENTICE
	if economy.workers.count(sent) > 0:
		var peasants_before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
		_play.economy.orders.worker_action(sent, "disband")
		await process_frame
		_say("disband a %s: toast \"%s\"" % [WorkerPool.tier_one(sent).to_lower(), _last_toast()])
		_say("  pool %s · peasants %d → %d · queue %d" % [
			_pool_text(economy.workers), peasants_before,
			economy.workers.count(WorkerPool.Tier.PEASANT), economy.recruits.total(),
		])
	else:
		_say("no trained worker in the pool to disband")
	# A journeyman trained: one peasant consumed, paid in Build/work.
	var before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	_play.economy.orders.worker_action(WorkerPool.Tier.JOURNEYMAN, "recruit", 1)
	await process_frame
	_say("train one journeyman: toast \"%s\"" % _last_toast())
	_say("  peasants %d → %d (nothing paid yet) · available %d · queue %d" % [
		before, economy.workers.count(WorkerPool.Tier.PEASANT),
		economy.available_peasants(), economy.recruits.total(),
	])
	# A regiment mustered from the army panel's own press: one peasant reserved.
	MapPlayArmyMuster.recruit(_play, "peasant_levies")
	await process_frame
	_say("muster a levy: toast \"%s\"" % _last_toast())
	_say("  available %d · reserved %d · queue %d" % [
		economy.available_peasants(), economy.reserved_peasants(), economy.recruits.total(),
	])
	_read_tab("with a train and a muster under orders")
	# The reservation's own refusal: one more trained head than the pool holds.
	var spare: int = economy.available_peasants()
	var refused: Dictionary = economy.queue_recruit(WorkerPool.Tier.MASTER, spare + 1)
	_say("queue %d masters with %d peasants free: queued %d, reason \"%s\"" % [
		spare + 1, spare, int(refused.get("queued", 0)), String(refused.get("reason", "")),
	])
	await _close_turn("with the train and the muster under orders")
	_say("pool now: %s · queue %d" % [_pool_text(economy.workers), economy.recruits.total()])
	_read_consumption("the turn the train and the muster landed")
	_read_gazette("the turn the train and the muster landed")


# --- pass three: a larder that cannot feed the pool -------------------------


func _thin_larder_pass() -> void:
	_say("")
	_say("=== a thin larder (turn-100 advanced start) ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0, AdvancedStart.TURNS100)
	if _screen == null:
		return
	_play = _screen.play
	var economy: PlayerEconomy = _play.economy.economy
	# The store keeps its luxuries and loses its food: the phase must strike the
	# top tier first and leave every head in the pool.
	economy.stockpile["grain"] = 0
	economy.stockpile["meat"] = 0
	_say("pool: %s · store grain %d, meat %d" % [
		_pool_text(economy.workers), economy.quantity("grain"), economy.quantity("meat"),
	])
	await _open_workers()
	_read_tab("starved")
	var forecast: Dictionary = LarderRead.forecast(
		economy, LarderRead.mouths(_play.economy.readings.projected()), false
	)
	_say("forecast: %d strikers, tier %d, store short %d, food short %d" % [
		int(forecast["strikers"]), int(forecast["striking_tier"]),
		int(forecast["store_short"]), int(forecast["food_short"]),
	])
	var pool_before: String = _pool_text(economy.workers)
	await _close_turn("starved")
	_say("pool after the starved turn: %s (was %s)" % [
		_pool_text(economy.workers), pool_before,
	])
	_read_consumption("the starved turn")
	_read_gazette("the starved turn")


# --- pass four: what the board promises once the queue holds an order --------


## The tab's own press, pressed twice: a single head first, then the batch the
## row still offers. The wiki says a batch is never a promise the crown cannot
## keep, so the second press must not file heads the first has already paid for.
func _promise_pass() -> void:
	_say("")
	_say("=== a press after the queue already promised the store ===")
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		return
	_play = _screen.play
	var economy: PlayerEconomy = _play.economy.economy
	_say("turn 0: fabric %d, treasury %d" % [
		economy.quantity("fabric"), economy.treasury,
	])
	await _open_workers()
	_read_tab("before any press")
	var peasant: Button = _action("recruit", WorkerPool.Tier.PEASANT)
	if peasant == null:
		return
	peasant.pressed.emit()
	await process_frame
	_say("one peasant engaged: toast \"%s\" · queue %d · fabric promised %d" % [
		_last_toast(), economy.recruits.total(), _promised_fabric(economy),
	])
	# The batch row the tab still offers after that press.
	var panel: EconomyPanel = _play.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	var batch: Button = workers.batch_buttons().get(WorkerPool.Tier.PEASANT, null) as Button
	if batch == null:
		_say("no peasant batch after the first press")
		return
	_say("the batch still reads: \"%s\" (fabric held %d, promised %d)" % [
		batch.text, economy.quantity("fabric"), _promised_fabric(economy),
	])
	batch.pressed.emit()
	await process_frame
	_say("batch pressed: toast \"%s\" · queue %d · fabric promised %d" % [
		_last_toast(), economy.recruits.total(), _promised_fabric(economy),
	])
	_say("%d orders now wait on %d fabric" % [
		economy.recruits.total(), economy.quantity("fabric"),
	])
	await _close_turn("after the batch")
	_say("fabric after the turn: %d · pool %s" % [
		economy.quantity("fabric"), _pool_text(economy.workers),
	])
	_read_consumption("the turn the batch landed")


func _promised_fabric(economy: PlayerEconomy) -> int:
	var total: int = 0
	for row: Dictionary in economy.recruits.orders:
		if String(row.get("kind", "")) != RecruitQueue.KIND_WORKER:
			continue
		var cost: Dictionary = WorkerPool.recruit_cost(int(String(row.get("key", "-1"))))
		var materials: Dictionary = cost.get("materials", {}) as Dictionary
		total += int(materials.get("fabric", 0))
	return total


# --- readings ---------------------------------------------------------------


func _read_tab(label: String) -> void:
	# Read the sheet as a player opens it: the ledger rebuilds from live state,
	# so a press made elsewhere (a muster in the army panel) is already priced.
	_play.economy.open_panel()
	await process_frame
	var panel: EconomyPanel = _play.hud.panels.economy_panel
	if panel == null:
		_say("workers %s: no ledger panel" % label)
		return
	panel.select_tab(2)
	await process_frame
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	if workers == null:
		_say("workers %s: no WORKERS tab" % label)
		return
	_say("workers %s:" % label)
	for text: String in _labels(workers):
		_say("  | %s" % text)
	for tier: int in WorkerPool.TIER_COUNT:
		var batch: Button = workers.batch_buttons().get(tier, null) as Button
		if batch != null:
			_say("  batch %s: \"%s\"" % [WorkerPool.tier_name(tier), batch.text])


func _read_consumption(label: String) -> void:
	var report: Dictionary = _play.economy.readings.last_consumption
	if report.is_empty():
		_say("consumption %s: no report" % label)
		return
	_say("consumption %s: army %d/%d · navy %d/%d · wards %d/%d · fed %d · strikers %d" % [
		label, int(report.get("army_fed", 0)), int(report.get("army_demand", 0)),
		int(report.get("navy_fed", 0)), int(report.get("navy_demand", 0)),
		int(report.get("hospital_fed", 0)), int(report.get("hospital_demand", 0)),
		int(report.get("fed_workers", 0)), int(report.get("strikers", 0)),
	])
	_say("  arriving %s · idle labour %d · labour next turn %d · luxury spent %s" % [
		str(report.get("arriving", [])), int(report.get("idle_labour", 0)),
		int(report.get("labour_next_turn", 0)), str(report.get("luxury_spent", {})),
	])


func _read_gazette(label: String) -> void:
	if _play.gazette == null:
		_say("gazette %s: none" % label)
		return
	var sheet: Dictionary = _play.gazette.newest()
	var items: Array = sheet.get("items", []) as Array
	_say("gazette %s: turn %d, %d items" % [label, int(sheet.get("turn", -1)), items.size()])
	for raw: Variant in items:
		var item: Dictionary = raw
		_say("  | %s" % String(item.get("text", "")))


# --- the ledger's own presses ----------------------------------------------


func _open_workers() -> void:
	_play.economy.open_panel()
	for _frame in 3:
		await process_frame


func _action(kind: String, tier: int) -> Button:
	var panel: EconomyPanel = _play.hud.panels.economy_panel
	if panel == null:
		return null
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	if workers == null:
		return null
	return workers.action_buttons().get("%s:%d" % [kind, tier], null) as Button


func _pool_text(pool: WorkerPool) -> String:
	var parts: PackedStringArray = []
	for tier: int in WorkerPool.TIER_COUNT:
		parts.append("%s %d" % [WorkerPool.tier_name(tier).to_lower(), pool.count(tier)])
	return ", ".join(parts)


# --- the turn ---------------------------------------------------------------


func _close_turn(label: String) -> void:
	_play.hud.panels.hide_economy()
	for _frame in 2:
		await process_frame
	if not _advance():
		_say("%s: the calendar never moved — the turn stayed shut" % label)
		return
	for _frame in 30:
		await process_frame
	_say("%s: turn %d, %d ducats" % [label, _play.turn, _play.treasury()])
	for text: String in _toasts():
		_say("  turn toast: %s" % text)


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


# --- printing ---------------------------------------------------------------


func _labels(node: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if node == null:
		return out
	for label: Label in node.find_children("*", "Label", true, false):
		if not label.text.strip_edges().is_empty():
			out.append(label.text)
	return out


func _toasts() -> Array[String]:
	var out: Array[String] = []
	if _play == null or _play.hud == null or _play.hud._toast_box == null:
		return out
	for text: String in _labels(_play.hud._toast_box):
		out.append(text)
	return out


func _last_toast() -> String:
	var labels: PackedStringArray = _labels(_play.hud._toast_box)
	if labels.is_empty():
		return "nothing on the bar"
	return labels[labels.size() - 1]


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_workers: %d steps ---" % _steps.size())
	quit()
