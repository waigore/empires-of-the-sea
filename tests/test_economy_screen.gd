extends GdToolsTest
## Integration: the map screen's ledger drives the real economy (REQ-P2-03).

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so the cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
var _screen: MapScreen = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_screen = mounted


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	_screen = null
	pristine = {}


func test_the_screen_owns_a_starting_economy() -> void:
	assert_not_null(_screen.economy)
	assert_not_null(_screen.economy.economy)
	assert_not_null(_screen.economy.market)
	assert_eq(_screen.treasury, _screen.economy.economy.treasury)
	assert_eq(
		_screen.economy.economy.workers.count(WorkerPool.Tier.PEASANT),
		PlayerEconomy.START_PEASANTS
	)
	assert_gt(_screen.economy.readings.extraction().size(), 0)


func test_the_ledger_opens_and_closes() -> void:
	assert_false(_screen.hud.panels.is_economy_open())
	_screen.economy.open_panel()
	assert_true(_screen.hud.panels.is_economy_open())
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	assert_not_null(panel)
	assert_gt(panel.get_combined_minimum_size().y, 100.0)
	_screen.hud.panels.hide_economy()
	assert_false(_screen.hud.panels.is_economy_open())


func test_buying_stages_a_bid_then_clears_it() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var treasury_before: int = economy.treasury
	var grain_before: int = economy.quantity("grain")
	var unit: int = _screen.economy.market.buy_price("grain")
	_screen.economy.orders.trade("grain", 2, true)
	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), 2)
	assert_eq(economy.quantity("grain"), grain_before, "stock waits for the clearing")
	_clear_market()
	assert_eq(economy.quantity("grain"), grain_before + 2)
	assert_eq(economy.treasury, treasury_before - 2 * unit)
	assert_eq(_screen.treasury, economy.treasury)


func test_selling_needs_stock_and_clears_at_the_close() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 1
	var treasury_before: int = economy.treasury
	var unit: int = _screen.economy.market.sell_price("timber")
	_screen.economy.orders.trade("timber", 1, false)
	assert_eq(economy.quantity("timber"), 1, "the offer waits for the clearing")
	assert_eq(economy.treasury, treasury_before)
	_clear_market()
	assert_eq(economy.quantity("timber"), 0)
	assert_eq(economy.treasury, treasury_before + unit)


func test_production_assignment_reaches_the_projection() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy.orders.set_production("lumber", 2)
	assert_eq(economy.production.assignment_units("lumber"), 2)
	var preview: Dictionary = _screen.economy.readings.projected()
	assert_gt(int(preview["stockpile_delta"].get("lumber", 0)), 0)
	assert_lt(int(preview["stockpile_delta"].get("timber", 0)), 0)


## A recruit joins the pool at the turn's close but turns no wheel until the
## **next** Production phase: same-turn labour from a new hire is a rule the wiki
## refuses (wiki: workers-and-population § Phase placement — the phase sequence
## is not reordered for it). The phase report is the proof: the head ate with the
## court and laboured for nobody.
func test_a_queued_recruit_labours_next_turn() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["fabric"] = 2
	economy.stockpile["grain"] = 200
	economy.stockpile["meat"] = 200
	economy.workers = WorkerPool.make(3)
	_screen.economy.orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 3, "a press only queues")
	var report: Dictionary = _screen.economy.resolve_turn()
	var consumed: Dictionary = report.get("consumption", {}) as Dictionary
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), 4, "the head landed")
	assert_eq(int(consumed.get("fed_workers", 0)), 4, "it eats with the court")
	assert_eq(int(consumed.get("idle_labour", 0)), 3, "three hands labour, not four")
	assert_eq(int(consumed.get("labour_next_turn", 0)), 1, "the fourth turns the next phase")
	var after: Dictionary = _screen.economy.readings.projected()
	assert_eq(
		int((after.get("consumption", {}) as Dictionary)["idle_labour"]), 4,
		"the closed turn hands all four to the next phase",
	)


## The end-of-turn figure the PRODUCTION tab prints is the turn the phase will
## run: Build/work lands the waiting orders before Consumption opens, so the two
## hires eat at this turn's close (and labour nobody until the next Production
## phase) and the muster already paid for eats its ration too. The WORKERS tab's
## larder names the same mouths, so one ledger cannot print two larders for one
## turn (wiki: workers-and-population § Phase placement; § Consumption — every
## appetite the phase pays, the recruits already under orders included;
## stockpiles-and-production § Acceptance Criteria — the preview runs the same
## rules as live turn resolution).
func test_the_projection_feeds_the_mouths_build_work_lands() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.workers = WorkerPool.make(4)
	economy.stockpile = {"grain": 400, "meat": 400, "fabric": 20, "castIron": 20}
	economy.treasury = 9000
	var armies: Array = _screen.army_layer.armies
	var owner: int = _screen.player_faction
	assert_true(
		ArmyTraining.muster_blocked_reason(economy, armies, owner, "pikemen").is_empty(),
		"the court can muster a pike regiment"
	)
	var army_before: int = _screen.economy.readings.army_food()
	economy.queue_recruit(WorkerPool.Tier.PEASANT, 2)
	economy.queue_build(RecruitQueue.KIND_REGIMENT, "pikemen")

	var preview: Dictionary = _screen.economy.readings.projected()
	var promised: Dictionary = preview["consumption"] as Dictionary
	# Four hands, two hires, less the one head the muster takes from the fields.
	assert_eq(int(promised["fed_workers"]), 5, "every hand Build/work lands eats")
	assert_eq(int(promised["idle_labour"]), 3, "the two hires turn no wheel this phase")
	assert_eq(int(promised["labour_next_turn"]), 2, "their labour is the next phase's")
	assert_eq(
		int(promised["army_demand"]),
		army_before + RegimentCatalog.food_upkeep("pikemen"),
		"the muster under orders eats too"
	)
	var promised_grain: int = int((preview["stockpile_delta"] as Dictionary).get("grain", 0))
	var grain_before: int = economy.quantity("grain")

	var report: Dictionary = _screen.economy.resolve_turn()
	var served: Dictionary = report["consumption"] as Dictionary
	assert_eq(int(served["fed_workers"]), int(promised["fed_workers"]), "the phase feeds the promise")
	assert_eq(int(served["idle_labour"]), int(promised["idle_labour"]))
	assert_eq(int((served["arriving"] as Array)[WorkerPool.Tier.PEASANT]), 2, "both hires landed")
	assert_eq(int(served["army_demand"]), int(promised["army_demand"]), "the muster eats as promised")
	assert_eq(
		economy.quantity("grain") - grain_before, promised_grain,
		"the NEXT figure is the store the phase leaves"
	)


## A handed-in report that already names the turn the phase will run is not fed
## a second time: the ledger's own projection counts the waiting orders itself
## (wiki: workers-and-population § Consumption).
func test_a_larder_read_never_counts_a_waiter_twice() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.queue_build(RecruitQueue.KIND_REGIMENT, "pikemen")
	var once: Dictionary = LarderRead.forecast(
		economy, {"army": 0, "ships": 0, "hospital": 0}, false
	)
	assert_eq(int(once["appetites"]["army"]), 0, "the caller's appetite stands alone")
	var twice: Dictionary = LarderRead.forecast(economy, {"army": 0, "ships": 0, "hospital": 0})
	assert_eq(
		int(twice["appetites"]["army"]), RegimentCatalog.food_upkeep("pikemen"),
		"a caller reading a past phase still owns the waiting muster"
	)


## A recruit pressed on the ledger files one order and costs nothing yet
## (wiki: workers-and-population § Phase placement).
func test_recruiting_a_peasant_through_the_ledger() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["fabric"] = 2
	var before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	_screen.economy.orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	# The press only queues: Build/work pays and the peasant joins next turn
	# (wiki: workers-and-population § Phase placement).
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), before)
	assert_eq(economy.quantity("fabric"), 2, "nothing is spent at the press")
	assert_eq(
		economy.recruits.pending(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.PEASANT)), 1
	)
	MapPlayRecruits.complete(_screen.play)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), before + 1)
	assert_eq(economy.quantity("fabric"), 0)
	assert_true(economy.recruits.is_empty(), "the order lands once")


## A tier the crown can pay for more than once offers one batch press under its
## row: the count and the whole price are on the button, so a batch is never a
## surprise (wiki: workers-and-population § Recruiting; REQ-P5-04, REQ-P5-05).
func test_the_workers_tab_offers_a_batch_press() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 4)
	economy.treasury = 2000
	economy.stockpile["paper"] = 10
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var batches: Dictionary = workers.batch_buttons()
	assert_true(batches.has(WorkerPool.Tier.APPRENTICE), "four heads are payable")
	var button: Button = batches[WorkerPool.Tier.APPRENTICE] as Button
	assert_true(button.text.contains("Recruit ×4"), button.text)
	assert_true(button.text.contains("800 ducats"), "the whole price is named: %s" % button.text)
	assert_true(button.text.contains("Paper ×8"), button.text)


## The batch press files every head it names, pays nothing yet, and the queue
## reads as one line instead of four (REQ-P5-04, REQ-P5-05).
func test_a_batch_press_files_every_head() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 4)
	economy.treasury = 2000
	economy.stockpile["paper"] = 10
	_screen.economy.orders.worker_action(WorkerPool.Tier.APPRENTICE, "recruit", 4)
	assert_eq(
		economy.recruits.pending(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.APPRENTICE)), 4
	)
	assert_eq(economy.treasury, 2000, "nothing is paid at the press")
	assert_eq(economy.available_peasants(), 0, "every head is promised")
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	var printed: String = _printed(workers)
	assert_true(printed.contains("Apprentice ×4 · joins the pool in Build/work"), printed)


## A tier the crown can pay for once keeps its single press and no batch row.
func test_a_single_head_offers_no_batch_press() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 4)
	economy.treasury = 200
	economy.stockpile["paper"] = 2
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_false(
		workers.batch_buttons().has(WorkerPool.Tier.APPRENTICE), "one head is all the purse pays"
	)


## Every tier row names the price it pays and, under it, what the tier eats —
## on the sheet, not only in the button's hover, so a touch crown reads the deal
## before it presses (wiki: workers-and-population § Recruiting, § Worker Tiers;
## REQ-P1-05, REQ-P5-05, REQ-P5-06).
func test_every_worker_row_names_its_price_and_ration() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.workers.set_count(WorkerPool.Tier.PEASANT, 4)
	economy.treasury = 2000
	economy.stockpile["paper"] = 10
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var lines: Dictionary = workers.tier_lines()
	assert_eq(lines.size(), WorkerPool.TIER_COUNT, "one line under every tier row")
	var peasant: Label = lines.get(WorkerPool.Tier.PEASANT) as Label
	assert_not_null(peasant)
	assert_eq(peasant.text, "Recruit Fabric ×2 — eats 1 grain or meat a turn")
	var apprentice: Label = lines.get(WorkerPool.Tier.APPRENTICE) as Label
	assert_eq(
		apprentice.text,
		"Recruit 200 ducats · Paper ×2 — eats 1 grain + 1 meat and Refined Sugar a turn",
		"a payable row names its own price and ration"
	)
	assert_eq(
		apprentice.get_theme_color("font_color"), Palette.TEXT_DIM, "a payable line stays quiet"
	)
	# A study-locked tier names the two studies it waits on, not a bare reason.
	var master: Label = lines.get(WorkerPool.Tier.MASTER) as Label
	assert_eq(
		master.text,
		"Recruit 1000 ducats · Paper ×10 — needs Master Artisans and Hat Production",
		"a locked row names the research"
	)
	assert_eq(master.get_theme_color("font_color"), Palette.CRIMSON, "a blocked line reads aloud")


## A tier the purse cannot pay says so on its row: the price stays visible and
## the stopping rule is named, so no touch crown presses a silent refusal
## (wiki: workers-and-population § Order rejection reasons; REQ-P5-05).
func test_a_blocked_worker_row_names_the_rule_that_stops_it() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.tech_unlocked = {"apprentice_workers": true, "sugar_refining": true}
	economy.treasury = 0
	economy.stockpile["paper"] = 10
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	var lines: Dictionary = workers.tier_lines()
	var apprentice: Label = lines.get(WorkerPool.Tier.APPRENTICE) as Label
	assert_eq(
		apprentice.text,
		"Recruit 200 ducats · Paper ×2 — insufficient treasury",
		"the price and the bar are both on the row"
	)
	assert_eq(apprentice.get_theme_color("font_color"), Palette.CRIMSON)


## The WORKERS tab names every order waiting for Build/work, and how many of a
## tier are on the way (wiki: workers-and-population § Phase placement).
func test_the_workers_tab_shows_what_is_under_orders() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.recruits.add(RecruitQueue.KIND_WORKER, str(WorkerPool.Tier.PEASANT))
	economy.recruits.add(RecruitQueue.KIND_CIVILIAN, "builder")
	economy.recruits.add(RecruitQueue.KIND_REGIMENT, "peasant_levies")
	economy.recruits.add(RecruitQueue.KIND_SHIP, "carrack")

	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var texts: Array[String] = []
	for label: Label in workers.find_children("*", "Label", true, false):
		texts.append(label.text)
	var printed: String = "\n".join(texts)

	assert_true(printed.contains("UNDER ORDERS"), "the head names the queue: %s" % printed)
	assert_true(printed.contains("Peasant · joins the pool in Build/work"))
	assert_true(printed.contains("Builder · engaged at the capital"))
	assert_true(printed.contains("Peasant Levies · musters in Build/work"))
	assert_true(printed.contains("Carrack · launches in Build/work"))
	assert_true(printed.contains("1 arriving"), "the peasant row counts the arrival")


## The WORKERS tab reads the larder before the crown recruits into it: the store,
## every appetite and the tier a shortfall strikes first, on the tab rather than
## in a hover hint (wiki: workers-and-population § Consumption; REQ-P5-06,
## REQ-P1-05).
func test_the_workers_tab_reads_the_larder() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.workers = WorkerPool.make(1, 0, 0, 1)
	economy.stockpile = {"grain": 1, "meat": 0, "furHats": 1}
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var printed: String = _printed(workers)

	assert_true(printed.contains("LARDER · NEXT TURN"), "the head names the reading: %s" % printed)
	assert_true(printed.contains("Store 1 food"), "the larder as it stands: %s" % printed)
	assert_true(printed.contains("Fur Hats ×1"), "the luxury the pool wants: %s" % printed)
	var read: Dictionary = LarderRead.forecast(
		economy, LarderRead.mouths(_screen.economy.readings.projected()), false
	)
	assert_true(
		printed.contains(
			"army %d" % int((read["appetites"] as Dictionary)["army"])
		) or int((read["appetites"] as Dictionary)["army"]) <= 0,
		"the army that eats first is named: %s" % printed
	)
	assert_true(
		printed.contains("pool %d" % int((read["appetites"] as Dictionary)["pool"])),
		"the pool's own rations are named: %s" % printed
	)
	# The screen's army and navy eat before the pool, so the master cannot be fed
	# its grain and meat: the shortfall is food and it bites the top tier first.
	assert_true(printed.contains("food — "), "a food shortfall: %s" % printed)
	assert_true(printed.contains("striker"), "someone strikes: %s" % printed)
	assert_true(printed.contains("masters first"), "the top tier first: %s" % printed)

	# A larder the army, the navy and the pool can all eat reads calm instead.
	economy.stockpile = {"grain": 60, "meat": 60, "furHats": 1}
	_screen.economy.open_panel()
	workers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	var calm: String = _printed(workers)
	assert_true(calm.contains("The larder covers every mouth."), calm)
	assert_false(calm.contains("striker,"), "no striker when the larder covers: %s" % calm)


## A store that covers the pool alone must not read as a calm larder: the army
## and the navy eat before the pool, so the larder names every appetite the phase
## pays, in its own order, and the numbers add up
## (wiki: workers-and-population § Consumption; REQ-P2-03).
func test_the_larder_names_the_appetites_that_eat_first() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(6)
	economy.stockpile = {"grain": 12, "meat": 0}
	var report: Dictionary = {
		"consumption": {"army_demand": 8, "navy_demand": 4, "hospital_demand": 2}
	}
	var page := LedgerWorkers.new()
	page.fill(economy, report)
	var printed: String = _printed(page)
	page.free()
	assert_true(printed.contains("Store 12 food"), printed)
	assert_true(
		printed.contains("20 food wanted — army 8 · navy 4 · pool 6 · wards 2"),
		"every appetite, in the phase's own order: %s" % printed
	)
	assert_true(
		printed.contains("Short 8 food"),
		"the whole larder is short, not the pool alone: %s" % printed
	)
	assert_true(printed.contains("6 strikers"), printed)


## A larder that keeps the workers fed while a ward goes unfed is not calm: the
## ward loses its nurses and the province rests at the field's share, so the tab
## names the shortfall and the mouth that missed it
## (wiki: workers-and-population § Consumption — total food demand;
## combat § Regiment condition; DR-20261112-04).
func test_a_starving_ward_is_never_read_as_a_calm_larder() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	economy.workers = WorkerPool.make(2)
	economy.stockpile = {"grain": 3, "meat": 0}
	var read: Dictionary = LarderRead.forecast(
		economy, {"army": 0, "ships": 0, "hospital": 4, "wards": [4]}
	)
	var page := LedgerWorkers.new()
	assert_eq(
		page._shortfall_copy(read),
		"Short 3 food — the wards go unfed.",
		"the pool ate, the ward did not"
	)
	# A court with no workers at all still reads its army's hunger.
	economy.workers = WorkerPool.make(0)
	economy.stockpile = {"grain": 2, "meat": 0}
	var army: Dictionary = LarderRead.forecast(
		economy, {"army": 5, "ships": 0, "hospital": 0}
	)
	assert_eq(
		page._shortfall_copy(army),
		"Short 3 food — the army goes short.",
		"no striker, and still short"
	)
	page.free()


## Every label a tab printed, so a test reads the page instead of its privates.
func _printed(node: Node) -> String:
	var texts: Array[String] = []
	for label: Label in node.find_children("*", "Label", true, false):
		texts.append(label.text)
	return "\n".join(texts)


func test_the_ledger_sends_a_trained_worker_back_to_the_fields() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.workers.set_count(WorkerPool.Tier.APPRENTICE, 1)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var key: String = "disband:%d" % WorkerPool.Tier.APPRENTICE
	var disband: Button = workers.action_buttons().get(key) as Button
	assert_not_null(disband, "a trained tier offers disband")
	assert_false(disband.disabled, "one apprentice can go home")
	assert_true(
		disband.tooltip_text.contains("no recruit cost is refunded"),
		"the promise is on the control: %s" % disband.tooltip_text
	)
	var peasants_before: int = economy.workers.count(WorkerPool.Tier.PEASANT)
	var treasury_before: int = economy.treasury
	disband.pressed.emit()
	assert_eq(economy.workers.count(WorkerPool.Tier.APPRENTICE), 0)
	assert_eq(economy.workers.count(WorkerPool.Tier.PEASANT), peasants_before + 1)
	assert_eq(economy.treasury, treasury_before, "disband refunds and charges nothing")
	var rebuilt: Dictionary = (
		panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	).action_buttons()
	assert_true(
		(rebuilt.get(key) as Button).disabled,
		"the emptied tier goes inert"
	)
	assert_false(
		rebuilt.has("disband:%d" % WorkerPool.Tier.PEASANT),
		"a peasant is never disbanded"
	)


## The WORKERS tab leads every row with its tier's own medallion, so a rank reads
## by its metal before the label is read (REQ-P1-08).
func test_every_worker_row_wears_its_tier_medallion() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var workers: LedgerWorkers = panel.page_body(EconomyPanel.TAB_WORKERS) as LedgerWorkers
	assert_not_null(workers)
	var marks: Dictionary = workers.tier_marks()
	assert_eq(marks.size(), WorkerPool.TIER_COUNT, "one mark per tier row")
	for tier in WorkerPool.TIER_COUNT:
		var mark: UnitMedallion = marks.get(tier) as UnitMedallion
		assert_not_null(mark, "tier %d wears its plate" % tier)
		assert_eq(mark.texture, WorkerTierArt.medallion(tier))
		assert_eq(
			mark.custom_minimum_size,
			Vector2(WorkerTierArt.MARK_SIZE, WorkerTierArt.MARK_SIZE),
			"a desktop row keeps the dense mark"
		)


func test_ending_the_turn_resolves_the_economy() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var before: Dictionary = economy.stockpile.duplicate()
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.turn, turn_before + 1)
	assert_eq(_screen.treasury, economy.treasury)
	assert_true(economy.stockpile != before)
	assert_gt(economy.total_units(), 0)


func test_the_crowns_wards_eat_from_the_larder() -> void:
	var world: WorldMap = _screen.play.world
	var faction: int = _screen.player_faction
	var province: ProvinceState = world.region(0).province_data(
		_screen.economy.capital_province
	)
	assert_not_null(province)
	province.hospital_level = 1
	assert_eq(HospitalRules.demand_list(world, faction).size(), 1)

	_screen.economy.economy.stockpile["grain"] = 20
	_screen.economy.economy.stockpile["meat"] = 20
	var report: Dictionary = _screen.economy.resolve_turn()
	assert_eq(int((report["consumption"] as Dictionary)["hospital_demand"]), 2)
	assert_eq(int((report["consumption"] as Dictionary)["hospital_fed"]), 2)
	assert_true(province.hospital_staffed, "a fed ward keeps its staff")

	# An empty larder feeds the living first: the ward goes without, and the
	# turn's own summary says so (REQ-P5-05).
	_screen.economy.economy.stockpile["grain"] = 0
	_screen.economy.economy.stockpile["meat"] = 0
	var bare: Dictionary = _screen.economy.resolve_turn()
	assert_false(province.hospital_staffed)
	assert_eq((bare["hospital"] as Dictionary)["hungry"].size(), 1)
	assert_true(LedgerReportText.turn_summary(bare).contains("1 hospital unstaffed"))
	assert_eq(HospitalRules.effective_level(world.region(0), province.id), 0)


# --- merchant cargo ----------------------------------------------------------


func test_the_opening_home_fleet_carries_four_holds() -> void:
	var cargo: Dictionary = _screen.economy.readings.trade_cargo()
	assert_eq(int(cargo["holds"]), 4)
	assert_eq(int(cargo["used"]), 0)
	assert_eq(int(cargo["free"]), 4)
	var seat: int = _screen.play.capital_province
	var home: FleetState = _screen.ship_layer.home_fleet(seat)
	assert_not_null(home, "the opening muster moors a squadron at the seat")
	assert_eq(home.type_of(home.hulls[0]), "fluyte")


func test_imports_stop_when_the_holds_are_full() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var grain_before: int = economy.quantity("grain")
	var free: int = int(_screen.economy.readings.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy.orders.trade("grain", 1, true)
	assert_eq(economy.quantity("grain"), grain_before, "imports clear at the close")
	assert_eq(_screen.economy.readings.trade_cargo()["free"], 0)

	_screen.economy.orders.trade("grain", 1, true)

	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), free)
	_clear_market()
	assert_eq(economy.quantity("grain"), grain_before + free, "one more hold is refused")


func test_selling_still_works_with_full_holds() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 1
	var free: int = int(_screen.economy.readings.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy.orders.trade("grain", 1, true)
	var grain_before: int = economy.quantity("grain")

	_screen.economy.orders.trade("timber", 1, false)
	_clear_market()

	assert_eq(economy.quantity("grain"), grain_before + free)
	assert_eq(economy.quantity("timber"), 0)


func test_the_ledger_names_the_cargo_and_disables_full_imports() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var line: Label = _find_label(market_body, "CARGO")
	assert_not_null(line)
	assert_true(line.text.contains("4 holds"))

	var free: int = int(_screen.economy.readings.trade_cargo()["clear_free"])
	for index in free:
		_screen.economy.orders.trade("grain", 1, true)

	var buys: Array[Button] = []
	_collect_buttons(market_body, buys)
	assert_false(buys.is_empty())
	assert_true(buys[buys.size() - 1].disabled, "a full hold locks the Bid rows")


## A controller that never got a map or a ship layer still answers the ledger:
## no holds, no overseas crossing, no home yield — never a crash.
func test_a_bare_controller_reports_an_empty_ledger() -> void:
	var controller := EconomyController.new()
	controller.economy = PlayerEconomy.starting()

	assert_eq(controller.readings.cargo_holds(), 0)
	assert_eq(controller.readings.extraction(), {})
	assert_eq(int(controller.readings.overseas_plan()["holds"]), 0)
	assert_eq(int(controller.readings.trade_cargo()["free"]), 0)
	# Every owner answers alone: the figures priced, the sheet's own entry points
	# pressed, and each order refused where the rules say so (REQ-P3-01).
	assert_eq(controller.readings.fleet_ships(), 0)
	assert_eq(controller.readings.army_food(), 0)
	assert_eq(controller.readings.feeding_coverage(), 1.0, "no Consumption yet: full rations")
	controller.market = WorldMarket.with_default_prices()
	assert_eq(int(controller.readings.trade_cargo()["holds"]), 0, "no ship layer carries cargo")
	controller.open_panel()
	controller.open_research()
	controller.refresh_panel()
	controller.refresh_research_panel()
	controller.report_research({})
	controller.report_funding()
	assert_false(
		bool(controller.orders.trade("grain", 1, true).get("ok", true)),
		"no holds, no bid",
	)
	controller.orders.offer("no-court-sells-this", 1)
	controller.orders.withdraw("no-such-order")
	controller.orders.worker_action(WorkerPool.Tier.PEASANT, "disband")
	controller.orders.worker_action(WorkerPool.Tier.MASTER, "recruit")  # rules refuse
	controller.orders.assign_research("land_enclosure")
	controller.orders.cancel_research(0)
	controller.orders.cycle_research_funding(0)
	var bare := EconomyController.new()
	assert_eq(bare.readings.tech_caps(), {})
	assert_eq(bare.readings.projected_income(), 0)
	assert_eq(bare.orders.trade("grain", 1, true), {}, "no book, no bid")
	bare.orders.offer("no-court-sells-this", 1)
	bare.orders.withdraw("no-such-order")
	bare.orders.set_production("lumber", 1)
	bare.orders.worker_action(WorkerPool.Tier.PEASANT, "recruit")
	bare.orders.assign_research("land_enclosure")
	bare.orders.cancel_research(0)
	bare.orders.cycle_research_funding(0)
	bare.free()
	controller.free()


## The sheet presses its own orders: `_connect` binds the panel signals to the
## order owner, so a Bid row stages on the book without the controller spelling
## the intent out (one owner per surface, REQ-P3-01; REQ-P2-03).
func test_the_sheet_stages_its_own_trade_press() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var orders: MarketBook = _screen.economy.market.book
	var before: int = orders.orders_for(_screen.player_faction).size()
	panel.trade_requested.emit("grain", 1, true)
	assert_eq(
		orders.orders_for(_screen.player_faction).size(), before + 1,
		"the sheet's bid reached the book through the order owner",
	)


func test_a_crown_without_a_home_fleet_cannot_import() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.refresh(
		_screen.economy.economy, _screen.economy.market, _screen.economy.readings.projected(),
		{"holds": 0, "used": 0, "free": 0}
	)
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var hint: Label = _find_label(market_body, "No cargo holds")
	assert_not_null(hint)
	var buy: Button = _find_button(market_body, "Bid")
	assert_not_null(buy)
	assert_true(buy.disabled)


func test_a_new_world_port_ships_its_yield_on_the_home_holds() -> void:
	var world: WorldMap = _screen.world
	var snapshot: Array = Fixture.snapshot(world)
	var nw: MapModel = world.region(WorldMap.NEW_WORLD)
	var province: ProvinceState = nw.provinces[0]
	var tile: Vector2i = province.tiles[0]
	var resource_index: int = nw.index_of(tile.x, tile.y)
	var old_resource: int = nw.resource[resource_index]
	var home_before: Dictionary = _screen.economy.readings.extraction().duplicate()
	province.owner = _screen.player_faction
	nw.resource[resource_index] = 0
	var works := LandWorks.new()
	works.add_port(nw, tile)
	works.set_improvement(nw, tile, 1)
	_screen.play.civilian_layer.works_regions.set_region(WorldMap.NEW_WORLD, works)

	var plan: Dictionary = _screen.economy.readings.overseas_plan()
	var cargo: Dictionary = _screen.economy.readings.trade_cargo()

	assert_eq(int(plan["used"]), 1, "one connected estate ships one ton")
	assert_eq(plan["shipped"], {"timber": 1})
	assert_eq(
		int(_screen.economy.readings.extraction().get("timber", 0)),
		int(home_before.get("timber", 0)) + 1,
		"the colonial ton reaches the stockpile"
	)
	assert_eq(int(cargo["reserved"]), 1)
	assert_eq(int(cargo["free"]), int(cargo["holds"]) - 1)

	Fixture.restore(world, snapshot)
	nw.resource[resource_index] = old_resource


func test_the_ledger_lists_minor_and_tribe_offers() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, LedgerOffers.OFFER_HEADER))
	assert_gt(
		_screen.economy.market.minor_offers.size(), 0,
		"the Old World's minor courts publish their harvest"
	)


func test_bidding_from_an_offer_row_enters_the_auction() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var stock_before: int = economy.quantity("timber")
	var treasury_before: int = economy.treasury
	_screen.economy.market.minor_offers = [{
		"id": "7:timber",
		"faction": 7,
		"commodity": "timber",
		"quantity": 2,
		"unit_price": _screen.economy.market.price("timber"),
	}]

	_screen.hud.panels.economy_panel.emit_signal("offer_requested", "7:timber", 1)

	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), 1)
	assert_eq(economy.quantity("timber"), stock_before)
	assert_eq(economy.treasury, treasury_before)
	# Deals clear at the old integer price; the clearing's price pass publishes
	# the next turn's price, so the charge is read before the clear
	# (wiki: world-market § Price discovery).
	var charged: int = _screen.economy.market.buy_price("timber")
	_clear_market()
	assert_eq(economy.quantity("timber"), stock_before + 1)
	assert_eq(economy.treasury, treasury_before - charged)


## A term that moves after the book was published moves the deal the clearing
## charges too, so the row reads the ask again where it is drawn: a stale row
## must never name a price the auction will not honour (REQ-P5-05).
func test_an_offer_row_names_the_ask_the_clearing_will_charge() -> void:
	var market: WorldMarket = _screen.economy.market
	var viewer: int = _screen.player_faction
	var stale: Dictionary = {
		"id": "7:timber",
		"faction": 7,
		"commodity": "timber",
		"quantity": 2,
		"unit_price": market.price("timber"),
	}
	# A boycott published after the book went out: 110% imports, 90% exports.
	market.set_terms(viewer, {"buy": {"*": 1.1}, "sell": {"*": 0.9}})
	var page := LedgerMarket.new()
	page.fill(_screen.economy.economy, market, {}, [stale], {}, viewer)
	var buttons: Array[Button] = page.offer_buttons()
	assert_eq(buttons.size(), 1)
	var button: Button = buttons[0]
	var ask: int = market.buy_price("timber", viewer)
	assert_ne(int(stale["unit_price"]), ask, "the terms really moved after the publish")
	assert_true(
		button.tooltip_text.contains("ask of %d" % ask),
		"the row asks the clearing's price: %s" % button.tooltip_text
	)
	assert_eq(
		MinorMarket.ask_for_reader(null, stale), int(stale["unit_price"]),
		"with no market the row keeps the price it was published with"
	)
	market.set_terms(viewer, {})
	page.free()


func test_an_empty_offer_book_says_so() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.refresh(
		_screen.economy.economy, _screen.economy.market, _screen.economy.readings.projected(),
		{"holds": 2, "used": 0, "free": 2}, []
	)
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "No court has goods for sale"))


# --- offer book filters ------------------------------------------------------


## A court book with two sellers and two goods, injected so the chips have
## something to narrow (the live book depends on the generated world).
func _offer_book() -> Array[Dictionary]:
	var market: WorldMarket = _screen.economy.market
	return [
		{
			"id": "7:timber",
			"faction": 7,
			"commodity": "timber",
			"quantity": 2,
			"unit_price": market.price("timber"),
		},
		{
			"id": "7:grain",
			"faction": 7,
			"commodity": "grain",
			"quantity": 1,
			"unit_price": market.price("grain"),
		},
		{
			"id": "9:timber",
			"faction": 9,
			"commodity": "timber",
			"quantity": 4,
			"unit_price": market.price("timber"),
		},
	]


func _market_page() -> LedgerMarket:
	_screen.economy.open_panel()
	return _screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket


## The Minor row's batch is the deal the clearing will pay: the subsidy step
## rides on the ask, so the press stages only what the purse covers and never
## names more ducats than the crown holds (wiki: world-market § Subsidy price
## adjustment, § Treasury budget for bids; REQ-P2-03, REQ-P5-05).
func test_the_minor_batch_pays_the_ask_the_press_prints() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var seller: int = 9
	var market: WorldMarket = _screen.economy.market
	market.subsidy_terms["%d>%d" % [_screen.player_faction, seller]] = 20
	var economy: PlayerEconomy = _screen.economy.economy
	var ask: int = MinorMarket.unit_price(market, "timber", _screen.player_faction, seller)
	# Two tons fit at the ask; three would fit at the world price alone.
	economy.treasury = ask * 2 + ask / 2
	var page: LedgerMarket = _market_page()
	var press: Button = page.batch_buttons().get("%d:timber" % seller) as Button
	assert_not_null(press, "the surcharge still leaves two tons payable")
	assert_true(press.text.begins_with("Bid ×2"), press.text)
	var total: int = int(press.text.split("·")[1].strip_edges().split(" ")[0])
	assert_lte(total, economy.treasury, "the press names only ducats the purse holds")
	press.pressed.emit()
	assert_eq(
		_screen.economy.market.book.pending_buy_units(_screen.player_faction), 2,
		"one press files the whole deal the ask pays for",
	)


## The seller and good chips narrow the court book without leaving the tab
## (REQ-P1-07, REQ-P5-03).
func test_the_market_tab_filters_the_court_book_by_seller_and_good() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var market: LedgerMarket = _market_page()
	assert_not_null(market)
	assert_eq(market.visible_offers().size(), 3)

	var chips: Dictionary = market.offer_filters()
	assert_true(chips.has("seller:7"), "one chip per court: %s" % [chips.keys()])
	assert_true(chips.has("seller:9"))
	assert_true(chips.has("good:grain"))

	(chips["seller:7"] as Button).pressed.emit()
	var rows: Array[Dictionary] = market.visible_offers()
	assert_eq(rows.size(), 2, "only the chosen court's offers are drawn")
	for row: Dictionary in rows:
		assert_eq(int(row["faction"]), 7)
	assert_true((market.offer_filters()["seller:7"] as Button).button_pressed)

	(market.offer_filters()["good:grain"] as Button).pressed.emit()
	assert_eq(market.visible_offers().size(), 1, "seller and good narrow together")
	assert_eq(String(market.visible_offers()[0]["id"]), "7:grain")


## A filter is presentation only: the published book and the staged orders are
## untouched, and a row that survives the filter still stages its bid
## (REQ-P2-03, RUB-P2-03).
func test_a_filter_never_edits_the_book_and_a_shown_row_still_bids() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var market: LedgerMarket = _market_page()
	var published: Array = _screen.economy.market.minor_offers.duplicate(true)

	(market.offer_filters()["sort:quantity"] as Button).pressed.emit()
	assert_eq(_screen.economy.market.minor_offers, published, "the book is not rewritten")
	assert_eq(_screen.economy.market.book.pending_buy_units(_screen.player_faction), 0)

	var bids: Array[Button] = market.offer_buttons()
	assert_eq(bids.size(), 3, "every offer is still on the table")
	bids[0].pressed.emit()
	assert_eq(
		_screen.economy.market.book.pending_buy_units(_screen.player_faction), 1,
		"the deepest book leads under Most stock first"
	)


## The page is repainted in place, so the reading has to be droppable: a chip a
## reader (or a mounted case) pressed would otherwise hide the next book
## (REQ-P5-03).
func test_the_reading_drops_back_to_the_whole_book() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var market: LedgerMarket = _market_page()
	(market.offer_filters()["seller:7"] as Button).pressed.emit()
	assert_eq(market.visible_offers().size(), 2, "the chosen court's book only")

	market.reset_offer_filters()
	assert_eq(market.visible_offers().size(), 3, "the whole book is back")
	var all_chip: Button = market.offer_filters()[
		"seller:%d" % MarketOffersHead.ALL_SELLERS
	] as Button
	assert_true(all_chip.button_pressed, "the strip shows All courts again")


func test_an_empty_offer_book_offers_no_chips() -> void:
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.refresh(
		_screen.economy.economy, _screen.economy.market, _screen.economy.readings.projected(),
		{"holds": 2, "used": 0, "free": 2}, []
	)
	var market: LedgerMarket = panel.page_body(EconomyPanel.TAB_MARKET) as LedgerMarket
	assert_eq(market.offer_filters(), {})
	assert_eq(market.visible_offers().size(), 0)


## Chips are thumb targets on a phone viewport, and stay that size when the
## ledger rebuilds on the next turn (REQ-P5-07).
func test_the_market_chips_grow_for_a_thumb() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var market: LedgerMarket = _market_page()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	panel.set_compact(true)
	for key: Variant in market.offer_filters().keys():
		var chip: Button = market.offer_filters()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT_TOUCH, String(key))
	panel.set_compact(false)
	for key: Variant in market.offer_filters().keys():
		var chip: Button = market.offer_filters()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT, String(key))


func test_the_ledger_shows_trade_terms_and_charges_the_adjusted_price() -> void:
	var market: WorldMarket = _screen.economy.market
	market.set_terms(_screen.player_faction, {"buy": {"*": 0.9}, "sell": {"*": 1.1}})
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var market_body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var line: Label = _find_label(market_body, "imports at 90%")
	assert_not_null(line, "the ledger explains the court's trade terms")

	var economy: PlayerEconomy = _screen.economy.economy
	var before: int = economy.treasury
	var unit: int = market.buy_price("grain", _screen.player_faction)
	_screen.economy.orders.trade("grain", 1, true)
	_clear_market()
	assert_eq(
		economy.treasury,
		before - unit,
		"the clearing charges the pact-adjusted price"
	)


## A subsidy the crown pays is a step on that pair's deals, so the banner names
## it instead of pretending the crown's own rate moved (wiki: world-market
## § Subsidy price adjustment; REQ-P5-05).
func test_the_ledger_names_the_subsidy_the_crown_pays() -> void:
	var market: WorldMarket = _screen.economy.market
	var player: int = _screen.player_faction
	_screen.play.diplomacy.set_subsidy(player, 7, 10)
	DiplomacyTrade.apply_terms(_screen.play.diplomacy, _screen.world, market)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "Subsidy 10%"), "the banner names the step")
	assert_eq(
		market.buy_price("timber", player), market.price("timber"),
		"the crown's own rate stays the world price"
	)
	assert_eq(MarketRules.subsidy_percent(market, player, 7), 10)
	assert_eq(
		MinorMarket.unit_price(market, "timber", player, 7),
		roundi(float(market.price("timber")) * 1.10),
		"the row's ask names what the clearing charges"
	)
	_screen.play.diplomacy.cancel_subsidy(player, 7)
	DiplomacyTrade.apply_terms(_screen.play.diplomacy, _screen.world, market)


## The turn's clearing republishes the Minor/Tribe book for the crown that
## played it: a court sailing as England reads her own terms and subsidy step,
## never Spain's (wiki: world-market § Subsidy price adjustment; REQ-P2-03,
## REQ-P5-05). England's reading books this suite's one mounted chart as her own
## crown: the shared save is re-seated in `before_each`, so the swap never
## outlives the case and the suite pays no second mount.
func test_the_turn_clearing_prices_the_minor_book_for_the_crown() -> void:
	var english: MapScreen = Fixture.attach_faction_screen(_screen, 1)
	var market: WorldMarket = english.economy.market
	market.set_terms(1, {"buy": {"*": 0.9}, "sell": {"*": 1.0}})
	MapPlayMarket.run(english.play, {})
	assert_gt(market.minor_offers.size(), 0, "the minor courts publish their harvest")
	var differs: bool = false
	for offer: Dictionary in market.minor_offers:
		var commodity: String = String(offer["commodity"])
		var seller: int = int(offer["faction"])
		assert_eq(
			int(offer["unit_price"]),
			MinorMarket.unit_price(market, commodity, 1, seller),
			"%s must be priced for England" % String(offer["id"])
		)
		if int(offer["unit_price"]) != MinorMarket.unit_price(market, commodity, 0, seller):
			differs = true
	assert_true(differs, "England's terms move the ask off Spain's")


func _clear_market() -> Dictionary:
	var cargo: Dictionary = _screen.economy.readings.trade_cargo()
	return MarketClearing.clear(
		_screen.economy.market,
		_screen.world,
		{_screen.player_faction: _screen.economy.economy},
		{_screen.player_faction: int(cargo.get("clear_free", cargo.get("free", 0)))},
		{"diplomacy": _screen.play.diplomacy}
	)


func _find_label(node: Node, needle: String) -> Label:
	if node is Label and (node as Label).text.contains(needle):
		return node
	for child: Node in node.get_children():
		var found: Label = _find_label(child, needle)
		if found != null:
			return found
	return null


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).text == "Bid":
		out.append(node)
	for child: Node in node.get_children():
		_collect_buttons(child, out)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child: Node in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null



func test_the_ledger_names_the_last_clearing() -> void:
	_screen.economy.market.book.last_deals = [{
		"buyer": _screen.player_faction,
		"seller": 6,
		"commodity": "timber",
		"quantity": 1,
		"price": 30,
	}]
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "LAST CLEARING"))
	assert_not_null(_find_label(body, "Bought 1 Timber"))


## A colony's fill that went to its suzerain says so beside the sale, so the
## tiebreak is never a mystery (wiki: diplomacy § R7.1; DR-20261111-11).
func test_the_ledger_names_a_favoured_partner_fill() -> void:
	_screen.economy.market.book.last_deals = [{
		"buyer": _screen.player_faction,
		"seller": 12,
		"commodity": "timber",
		"quantity": 2,
		"price": 30,
		"is_favoured": true,
	}]
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "as its favoured partner"))


## A sale names the ducats the auction paid, and the overseas share the court
## earned from the courts' purchases abroad is its own line — neither is visible
## on any other surface (wiki: world-market § First right of refusal; REQ-P5-05).
func test_the_ledger_names_a_sale_and_the_overseas_share() -> void:
	var faction: int = _screen.player_faction
	_screen.economy.market.book.last_deals = [{
		"buyer": MarketOrder.WORLD,
		"seller": faction,
		"commodity": "grain",
		"quantity": 1,
		"price": 50,
		"earned": 50,
	}]
	_screen.economy.readings.last_clearing = {"credits": {"by_gp": {faction: 89.0}}}
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	assert_not_null(_find_label(body, "Sold 1 Grain to the world market at 50 — 50 ducats"))
	assert_not_null(_find_label(body, "Overseas shares  +89 ducats"))


## The "Next turn" line names the orders the auction settles after it, so a
## staged bid is never read as already counted in the promise (wiki:
## stockpiles-and-production § Production flow).
func test_the_ledger_preview_names_the_staged_auction() -> void:
	_screen.economy.orders.trade("grain", 1, true)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	assert_not_null(_find_label(panel, "settles at the auction"))


## Starting a study is a decision about the purse, so the top bar's per-turn
## figure follows it before the turn closes (wiki: tech-tree § Research Model;
## REQ-P5-05 — a cost the player chose is never a mystery at the auction).
func test_starting_a_study_moves_the_per_turn_figure() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var open: Array[String] = economy.research.researchable()
	assert_gt(open.size(), 0, "the opening college has an advance to start")
	assert_eq(
		_screen.hud._income_label.text, TextFormat.delta(_screen.economy.readings.projected_income())
	)
	_screen.economy.orders.assign_research(open[0])
	var gold: int = ResearchFunding.gold(ResearchFunding.DEFAULT)
	assert_eq(
		_screen.hud._income_label.text, TextFormat.delta(_screen.economy.readings.projected_income()),
		"the chip follows the study it just funded",
	)
	assert_eq(_screen.economy.readings.projected_income(), -gold, "the slot pays its preset")
	_screen.economy.orders.cycle_research_funding(0)
	assert_eq(
		_screen.hud._income_label.text, TextFormat.delta(_screen.economy.readings.projected_income()),
		"a preset change moves the figure too",
	)
	_screen.economy.orders.cancel_research(0)
	assert_eq(
		_screen.hud._income_label.text, TextFormat.delta(_screen.economy.readings.projected_income()),
		"abandoning the study gives the gold back",
	)


## The crown's ledger cannot offer what its own production will eat: the AI
## planners already reserve those inputs (wiki: world-market § Trade orders —
## validation rule 7; REQ-P2-03 one rule for player and AI).
func test_an_offer_cannot_sell_what_production_will_eat() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy.orders.set_production("lumber", 2)  # 2 runs x 2 timber = all of it
	var refused: Dictionary = _screen.economy.orders.trade("timber", 1, false)
	assert_false(bool(refused.get("ok", true)), "the assigned runs have claimed the timber")
	assert_eq(economy.quantity("timber"), 4, "a refused offer leaves the stock alone")
	assert_eq(_screen.economy.market.offer_volume("timber"), 0, "nothing is staged")
	_screen.economy.orders.set_production("lumber", 0)
	var admitted: Dictionary = _screen.economy.orders.trade("timber", 1, false)
	assert_true(bool(admitted.get("ok", false)), String(admitted.get("reason", "")))
	assert_eq(_screen.economy.market.offer_volume("timber"), 1)
	# The admitted ton really ships at the close.
	var unit: int = _screen.economy.market.sell_price("timber")
	var purse: int = economy.treasury
	_clear_market()
	assert_eq(economy.quantity("timber"), 3, "the offered ton left the stockpile")
	assert_eq(economy.treasury, purse + unit, "and the sale paid")


## The MARKET tab's Offer chip is gated by what the court's own production runs
## leave behind, and the tooltip says how much is claimed (wiki: world-market
## § Trade orders — the per-commodity sellable readout).
func test_the_offer_chip_names_what_production_claims() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy.orders.set_production("lumber", 2)
	assert_eq(LedgerMarket.claimed_by_production(economy, "timber"), 4)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var chips: Array[Button] = []
	_collect_offer_chips(body, chips)
	var claimed_chip: Button = null
	for chip: Button in chips:
		if chip.tooltip_text.contains("claimed by production"):
			claimed_chip = chip
	assert_not_null(claimed_chip, "the chip explains the claim")
	assert_true(claimed_chip.disabled, "nothing is left to offer")
	assert_true(claimed_chip.tooltip_text.contains("0 sellable"))


## The claim is a readout on the page, not only a hover: a phone player sees why
## the Offer is dead (wiki: world-market § Trade orders — the per-commodity
## sellable readout; REQ-P1-05, REQ-P5-05).
func test_the_market_row_prints_the_sellable_cap() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	_screen.economy.orders.set_production("lumber", 2)
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var caption: Label = null
	for node: Node in body.find_children("*", "Label", true, false):
		var label: Label = node
		if label.text.contains("claimed by production"):
			caption = label
	assert_not_null(caption, "the row prints the claim, not only a tooltip")
	assert_eq(caption.text, "4 Timber claimed by production — 0 sellable")


## Every MARKET row shows its good's own medallion: grain, wool and timber used
## to share one generic pictogram (REQ-P1-02; tools/art/goods-medallions.md).
func test_every_market_row_carries_its_medallion() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	for category: Variant in LedgerMarket.CATEGORIES:
		for id: String in CommodityCatalog.ids_in(category):
			assert_eq(
				_medallion_of(body, CommodityCatalog.label(id)),
				CommodityIcons.texture(id),
				"the market row for %s draws its own plate" % id
			)


## The PRODUCTION tab names each recipe's output; that good's medallion rides
## beside the name so a run is identifiable without reading the text.
func test_every_production_row_carries_its_output_medallion() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	var economy: PlayerEconomy = _screen.economy.economy
	var recipes: Array[String] = ProductionRecipes.available_ids(economy.tech_unlocked)
	assert_gt(recipes.size(), 0, "the opening court can run a recipe")
	for recipe_id: String in recipes:
		assert_eq(
			_medallion_of(body, LedgerProductionText.recipe_title(recipe_id)),
			CommodityIcons.texture(ProductionRecipes.output(recipe_id)),
			"the %s row draws its output's plate" % recipe_id
		)


## A multi-turn row says so, and a batch already on the anvil names the units
## serving their turns and the cadence they land at (wiki: production-recipes
## § Turns per unit; DR-20261112-11, DR-20261113-02).
func test_the_alloy_rows_name_their_wait() -> void:
	var economy: PlayerEconomy = PlayerEconomy.starting()
	assert_eq(LedgerWorkshop.note(economy, "steel"), "2t")
	assert_eq(LedgerWorkshop.note(economy, "lumber"), "", "one-turn rows need no tag")
	assert_eq(LedgerWorkshop.tooltip(economy, "lumber"), "", "nothing waits on a one-turn row")
	assert_true(
		LedgerWorkshop.tooltip(economy, "steel").contains("one unit a turn"),
		"an idle alloy row promises the trickle"
	)
	economy.production_wip = {"steel": [{"units": 3, "turns_left": 1}]}
	assert_eq(LedgerWorkshop.note(economy, "steel"), "3→1t", "a landing frees a place")
	var serving: String = LedgerWorkshop.tooltip(economy, "steel")
	assert_true(serving.contains("3 units"))
	assert_true(serving.contains("one a turn"), "the serving tag says one unit lands a phase")
	# A bench still serving its first turn has no room: the tag says so, and the
	# long form says why no run starts (wiki: production-recipes § Workshop queue).
	economy.production_wip = {"steel": [{"units": 3, "turns_left": 2}]}
	assert_eq(LedgerWorkshop.note(economy, "steel"), "3/3→2t", "a full bench names its three pieces")
	assert_true(
		LedgerWorkshop.tooltip(economy, "steel").contains("no new run starts"),
		"a full bench says why no run starts"
	)
	economy.production_wip = {"steel": [{"units": 1, "turns_left": 1}]}
	assert_true(
		LedgerWorkshop.tooltip(economy, "steel").contains("1 unit already"),
		"one unit left on the anvil reads in the singular"
	)
	assert_eq(LedgerWorkshop.note(economy, "steel"), "1→1t", "a bench with room keeps the plain tag")
	# A row left set starts a fresh batch every phase, and each batch gives up a
	# unit: two batches land two a phase, so the note must not promise one.
	economy.production_wip = {
		"steel": [{"units": 2, "turns_left": 1}, {"units": 3, "turns_left": 1}],
	}
	assert_eq(LedgerWorkshop.note(economy, "steel"), "5/3→1t", "the tag counts every unit")
	var twinned: String = LedgerWorkshop.tooltip(economy, "steel")
	assert_true(twinned.contains("5 units"), "the note counts what is on the anvil")
	assert_true(twinned.contains("2 landing a turn"), "two batches land two a turn: %s" % twinned)
	assert_false(twinned.contains("one a turn"), "a twin batch is never promised as a trickle")
	economy.production_wip = {"steel": [{"units": 4, "turns_left": 2}]}
	assert_true(
		LedgerWorkshop.tooltip(economy, "steel").contains("still serving their turns"),
		"a batch that does not land this phase promises no unit"
	)
	_screen.economy.open_panel()
	var body: Node = _screen.hud.panels.economy_panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_true(_row_has_text(body, "2t"), "the idle alloy row shows its two-turn wait")


## A luxury row names the hand it waits for on the row itself, and its "+" is
## inert until the court trains one: a touch player never sees a hover hint
## (wiki: production-recipes § Worker-tier gates; DR-20261114-07).
##
## The row remembers the phase the court paid for: an idle row that worked says
## what it turned out, and the MANUFACTURED heading totals the workshop's last
## phase (wiki: production-recipes § Acceptance Criteria, `productionByRecipe`).
func test_a_production_row_reports_the_phase_it_just_worked() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var economy: PlayerEconomy = _screen.economy.economy
	economy.production.set_made({"lumber": 2, "steel": 1})
	_screen.economy.open_panel()
	var body: Node = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_true(_row_has_text(body, "made 2"), "the lumber row names its last output")
	assert_eq(
		LedgerWorkshop.note(economy, "steel"), "2t",
		"a waiting row keeps its tag: the present is what the next phase pays"
	)
	var hints: PackedStringArray = []
	for node: Node in body.find_children("*", "Label", true, false):
		var label: Label = node
		if label.text == "MANUFACTURED":
			hints.append(label.tooltip_text)
	assert_true(
		not hints.is_empty() and hints[0].contains("Last phase the workshop made 3 goods"),
		"the heading totals the workshop's last phase: %s" % [hints]
	)
	economy.production.set_made({})
	_screen.economy.open_panel()
	body = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_false(_row_has_text(body, "made 2"), "an idle workshop claims no last output")


func test_a_luxury_row_names_the_hand_it_waits_for() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	var economy: PlayerEconomy = _screen.economy.economy
	assert_eq(
		economy.workers.count(WorkerPool.Tier.APPRENTICE), 0,
		"the opening court has no trained hand"
	)
	assert_true(_row_has_text(body, "needs an Apprentice"), "the cigar row names its gate")
	assert_true(_row_has_text(body, "needs a Journeyman"), "the fur hat row names its gate")
	var rows: Dictionary = (body as LedgerProduction).recipe_rows()
	assert_true((rows["cigars"]["plus"] as Button).disabled, "a gated row offers no run")
	economy.workers.set_count(WorkerPool.Tier.APPRENTICE, 1)
	_screen.economy.open_panel()
	body = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_false(_row_has_text(body, "needs an Apprentice"), "the trained hand opens the row")
	assert_true(_row_has_text(body, "needs a Journeyman"), "fur hats still wait for a journeyman")


## A second-stage row names the town's works it waits for on the row itself, and
## its "+" is inert until the crown holds a town at that level: a touch player
## never sees a hover hint (wiki: production-recipes § Town-works gates;
## DR-20261116-04).
func test_a_town_row_names_the_works_it_waits_for() -> void:
	var faction: int = _screen.economy.player_faction
	var own: Array[ProvinceState] = []
	for index in _screen.world.region_count():
		var model: MapModel = _screen.world.region(index)
		for province in model.province_count():
			var data: ProvinceState = model.province_data(province)
			if data != null and data.owner == faction:
				data.town_development = 1
				own.append(data)
	assert_gt(own.size(), 0, "the crown holds a province to read")
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_true(_row_has_text(body, "needs a level-2 town"), "the garments row names its works")
	assert_true(_row_has_text(body, "needs a level-4 town"), "the rum row names the finer works")
	var rows: Dictionary = (body as LedgerProduction).recipe_rows()
	assert_true((rows["garments"]["plus"] as Button).disabled, "a gated row offers no run")
	own[0].town_development = 2
	_screen.economy.open_panel()
	body = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_false(_row_has_text(body, "needs a level-2 town"), "a level-2 town opens the garments row")
	assert_true(_row_has_text(body, "needs a level-4 town"), "rum still waits for a level-4 town")


## A full bench is named on the row itself and its "+" is inert: a touch player
## never sees a hover hint (wiki: production-recipes § Workshop queue;
## DR-20261114-12).
func test_a_full_bench_names_itself_and_offers_no_run() -> void:
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var economy: PlayerEconomy = _screen.economy.economy
	economy.workers.set_count(WorkerPool.Tier.APPRENTICE, 1)
	economy.stockpile["tobacco"] = 20
	economy.production_wip = {"cigars": [{"units": 3, "turns_left": 2}]}
	_screen.economy.open_panel()
	var body: Node = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	assert_true(_row_has_text(body, "3/3→2t"), "the row names its full bench")
	var rows: Dictionary = (body as LedgerProduction).recipe_rows()
	assert_true((rows["cigars"]["plus"] as Button).disabled, "a full bench offers no run")
	assert_true(
		(rows["cigars"]["plus"] as Button).tooltip_text.contains("holds 3 pieces"),
		"the + says why it is inert"
	)
	economy.production_wip = {"cigars": [{"units": 1, "turns_left": 1}]}
	_screen.economy.open_panel()
	body = panel.page_body(EconomyPanel.TAB_PRODUCTION)
	rows = (body as LedgerProduction).recipe_rows()
	assert_false((rows["cigars"]["plus"] as Button).disabled, "room on the bench opens the +")


func _row_has_text(body: Node, text: String) -> bool:
	for node: Node in body.find_children("*", "Label", true, false):
		if (node as Label).text == text:
			return true
	return false


## The texture beside a label, so a row's medallion can be read without
## depending on where in the row it was added.
func _medallion_of(body: Node, text: String) -> Texture2D:
	for node: Node in body.find_children("*", "Label", true, false):
		var label: Label = node
		if label.text != text:
			continue
		for sibling: Node in label.get_parent().get_children():
			if sibling is TextureRect:
				return (sibling as TextureRect).texture
	return null


func _collect_offer_chips(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).text == "Offer":
		out.append(node)
	for child: Node in node.get_children():
		_collect_offer_chips(child, out)


## One press files the whole order the rules accept, so a court buying a turn's
## ration never taps Bid ten times (wiki: world-market § Trade orders;
## REQ-P5-04, REQ-P5-05).
func test_the_market_row_files_its_batch_in_one_press() -> void:
	var market: LedgerMarket = _market_page()
	var batches: Dictionary = market.batch_buttons()
	assert_true(batches.has("bid:grain"), "a grain bid batches")
	var press: Button = batches["bid:grain"] as Button
	var units: int = int(press.text.split("×")[1].split(" ")[0])
	assert_gt(units, 1, "a batch is more than the single press")
	assert_true(press.text.contains("ducats"), "the press names the whole order's ducats")
	assert_gte(press.custom_minimum_size.y, 38.0, "the press is a row-height target")
	press.pressed.emit()
	assert_eq(
		_screen.economy.market.book.pending_buy_units(_screen.player_faction), units,
		"one press staged the whole order",
	)


## The Minor/Tribe row batches the seller's whole row, and a row with one ton
## left keeps its single press alone (REQ-P5-04, REQ-P1-07).
func test_the_minor_book_row_files_the_sellers_left_in_one_press() -> void:
	_screen.economy.market.minor_offers = _offer_book()
	var market: LedgerMarket = _market_page()
	var batches: Dictionary = market.batch_buttons()
	assert_true(batches.has("7:timber"), "two tons left batch")
	assert_false(batches.has("7:grain"), "one ton left is the single press")
	var press: Button = batches["7:timber"] as Button
	press.pressed.emit()
	assert_eq(
		_screen.economy.market.book.pending_buy_units(_screen.player_faction), 2,
		"the seller's whole row is one order",
	)


## The offer batch is the stock the assigned runs leave, so the press and the
## rules price one cap (wiki: world-market § Trade orders — the offer cap is the
## post-production stockpile minus industry reservations; REQ-P2-03).
func test_the_offer_batch_leaves_the_assigned_runs_their_inputs() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 4
	economy.production.set_assignment("lumber", 1)
	var market: LedgerMarket = _market_page()
	var batches: Dictionary = market.batch_buttons()
	assert_true(batches.has("offer:timber"), "the two spare tons batch")
	var press: Button = batches["offer:timber"] as Button
	var units: int = int(press.text.split("×")[1].split(" ")[0])
	assert_eq(units, 2, "four held less the lumber run's two tons")
	press.pressed.emit()
	assert_eq(
		_screen.economy.market.book.pending_sell_units(_screen.player_faction, "timber"), 2,
		"the press stages only what the rules accept",
	)


## A ton already staged is not sellable twice: the chip, the readout and the
## rules price one cap (wiki: world-market § Trade orders — the offer cap is the
## post-production stockpile; § Order persistence).
func test_a_staged_offer_spends_the_sellable_cap() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 3
	_screen.economy.open_panel()
	var staged: Dictionary = _screen.economy.orders.trade("timber", 3, false)
	assert_true(bool(staged.get("ok", false)), String(staged.get("reason", "")))
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var chip: Button = _row_button(body, "timber", "Offer")
	assert_not_null(chip, "the timber row draws its Offer")
	assert_true(chip.disabled, "the staged tons are not offered twice")
	assert_true(chip.tooltip_text.contains("3 Timber already offered"), chip.tooltip_text)
	var caption: Label = null
	for node: Node in body.find_children("*", "Label", true, false):
		if (node as Label).text.contains("already offered"):
			caption = node
	assert_not_null(caption, "the row prints what is already offered")
	assert_eq(caption.text, "3 Timber already offered — 0 sellable")


## A purse the rules will not open files no bid: the chip dies before the press
## (wiki: world-market § Treasury budget for bids — the UI clamps the bid chip).
func test_a_spent_purse_disables_the_bid_chip() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.treasury = 0
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: Node = panel.page_body(EconomyPanel.TAB_MARKET)
	var chips: Array[Button] = []
	for node: Node in body.find_children("*", "Button", true, false):
		if (node as Button).text == "Bid":
			chips.append(node as Button)
	assert_gt(chips.size(), 0, "the page draws Bid chips")
	for chip: Button in chips:
		assert_true(chip.disabled, "an empty purse files no bid")
		assert_true(chip.tooltip_text.contains("cannot cover"), chip.tooltip_text)
	# Printed, never only a hover: a phone player reads why the Bid is shut
	# (wiki: world-market § Treasury budget for bids; REQ-P1-05, REQ-P5-05).
	var printed: bool = false
	for node: Node in body.find_children("*", "Label", true, false):
		if (node as Label).text == "The treasury cannot cover that bid.":
			printed = true
	assert_true(printed, "the row prints the reason the Bid is shut")


## The single press on a commodity row, found by the row's own good name.
func _row_button(body: Node, commodity: String, text: String) -> Button:
	for node: Node in body.find_children("*", "Label", true, false):
		if (node as Label).text != CommodityCatalog.label(commodity):
			continue
		var row: Node = node.get_parent()
		while row != null and row != body:
			for child: Node in row.get_children():
				if child is Button and (child as Button).text == text:
					return child as Button
			row = row.get_parent()
	return null


## The PRODUCTION tab's one press: a crown that set its runs row by row now files
## one step on every ready row in a single confirmed press, and the press names
## what it would set before any labour or input is claimed (REQ-P5-04;
## DR-20261116-08).
func test_the_production_tab_files_one_run_on_every_ready_row() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	economy.stockpile["timber"] = 10
	economy.stockpile["wool"] = 10
	economy.stockpile["iron"] = 6
	economy.stockpile["coal"] = 6
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: LedgerProduction = panel.page_body(EconomyPanel.TAB_PRODUCTION) as LedgerProduction
	var press: RaiseBatchPress = body.batch_press()
	assert_not_null(press, "the tab carries the one press")
	assert_true(press.visible, "the press stands when a row is ready")
	var ready: int = int(body._plan()["runs"])
	assert_gt(ready, 1, "the opening store opens more than one row: %d" % ready)
	assert_eq(press.text, "Queue all ready (%d)" % ready, "the press names the count")
	press.pressed.emit()
	assert_true(press.is_armed(), "the first tap only arms")
	assert_eq(press.text, "Confirm — queue %d runs" % ready, "the second tap is named")
	press.pressed.emit()
	assert_false(press.is_armed(), "the press forgets the arm once it files")
	var set_rows: Dictionary = {}
	for entry: Dictionary in economy.production.assignments():
		set_rows[String(entry["recipe"])] = int(entry["units"])
	assert_eq(set_rows.size(), ready, "every ready row took one run")
	for recipe_id: String in set_rows.keys():
		assert_eq(int(set_rows[recipe_id]), 1, "%s took exactly one run" % recipe_id)
	assert_true(
		_toast_texts().has(ProductionBatch.receipt(ready)),
		"the press prints one receipt: %s" % str(_toast_texts())
	)


## A page with nothing ready carries no press, so a crown is never offered a
## press that would file nothing (REQ-P5-03).
func test_the_production_press_stands_down_when_nothing_is_ready() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	_screen.economy.open_panel()
	var panel: EconomyPanel = _screen.hud.panels.economy_panel
	var body: LedgerProduction = panel.page_body(EconomyPanel.TAB_PRODUCTION) as LedgerProduction
	# Every row set past any ceiling the store could open: no row has a step left.
	for recipe_id: String in body.recipe_rows().keys():
		economy.production.set_assignment(recipe_id, 99)
	_screen.economy.open_panel()
	body = panel.page_body(EconomyPanel.TAB_PRODUCTION) as LedgerProduction
	assert_eq(int(body._plan()["runs"]), 0, "no row has a step left to file")
	assert_false(body.batch_press().visible, "a view with nothing ready carries no press")


## Every line the court's toasts currently show.
func _toast_texts() -> Array[String]:
	var texts: Array[String] = []
	for panel: Node in _screen.hud._toast_box.get_children():
		for label: Label in panel.find_children("*", "Label", true, false):
			texts.append(label.text)
	return texts
