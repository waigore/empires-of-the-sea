class_name FleetYardBlock
extends FleetDrawer
## The fleet dossier's shipyard drawer: the toggle, the launch rows and the
## break-up rows with their confirm arm (wiki: ships-and-naval § Ship build
## economy, § Ship muster and the breaker's yard). The drawer's toggle, list,
## open state and row shell are FleetDrawer's; this block owns only the yard's
## rows and the arm (REQ-P3-01). It reads plain data and emits intents;
## FleetYard owns every rule (REQ-P3-02).
##
## The slip carries one press under its launch rows that lays down a hull for
## every ready type in the yard's order — the shared RaiseBatchPress arm, so a
## mis-tap never spends the realm's stores (REQ-P5-04; DR-20261118-08).

## Breaking up a paid-for hull asks once: the guard holds the hull the crown
## armed and lets the window run out on its own (DR-20261109-01).

## The mark the counsel reads by: the hull the court's own yard would lay wears
## it before her name, the mark the muster's forces and the realm's provinces
## wear (DR-20261122-12).
const COURT_MARK: String = "▸"
## What that mark means, under the claim it answers: the slip keeps no footer, so
## the sentence has nowhere else to stand (REQ-P1-07, REQ-P5-07; DR-20261123-08).
const MARK_LEGEND: String = "A ▸ marks the hull the court would lay this turn."

var _arm: ArmGuard = null
var _fleet: FleetState = null
var _is_player: bool = false
## The pick the court's own yard printed, in gold under the launch heading — the
## published claim's reading, never an order (DR-20261121-02). Kept whole so the
## line and the launch row's mark come off one read (DR-20261122-12).
var _pick: Dictionary = {}
## What the launch rows' mark means, under the claim it answers: the slip clears
## its list on every fill, so the sentence is rebuilt with it (DR-20261123-08).
var _legend: Label = null
## The one press under the slip; it owns the arm, its timeout and its words.
var _batch: RaiseBatchPress = null


func _init() -> void:
	toggle_text = "Shipyard"
	close_text = "Close shipyard"
	drawer_height = 168.0
	row_separation = 8
	# Built with the drawer, so a sheet assembled outside the tree still asks once.
	# The clock is an internal child: it ticks beside the drawer's toggle and list
	# without joining them.
	_arm = ArmGuard.new()
	_arm.expired.connect(_on_arm_expired)
	add_child(_arm, false, Node.INTERNAL_MODE_BACK)


func _ready() -> void:
	super()
	_make_batch()


## The slip's one press, made once however the block is mounted: the drawer's own
## `_ready` or a suite handing it rows straight away.
func _make_batch() -> void:
	if _batch != null:
		return
	_batch = RaiseBatchPress.new()
	_batch.set_verb("launch")
	_batch.confirmed.connect(func() -> void: action_pressed.emit("yard:launch_all"))
	# The sentence that says what the launch rows' mark means, made once so the
	# reading and the words come off one home; `_fill` mounts it under the claim
	# (DR-20261123-08).
	_legend = MarkLegend.make(MARK_LEGEND)


## A fresh fleet: the yard closes unless it may stay, and the rows are redrawn.
## `pick` is the court's own claim, kept whole so the line under the heading and
## the hull's mark come off one read (DR-20261121-02, DR-20261122-12); a rival
## answers to her own court and carries none.
func show_rows(
	fleet: FleetState, rows: Array[Dictionary], is_player: bool, keep_open: bool,
	pick: Dictionary = {}
) -> void:
	_fleet = fleet
	_is_player = is_player
	_pick = pick if is_player and pick != null else {}
	offer(rows, is_player, not rows.is_empty(), "", keep_open, false)
	# A slip that prints no claim explains no glyph (DR-20261123-08).
	MarkLegend.stand(_legend, not mark_type().is_empty())


## The capital slip: no squadron afloat, but the yard still lists what to launch.
func show_slip(rows: Array[Dictionary], is_player: bool, pick: Dictionary = {}) -> void:
	show_rows(null, rows, is_player, true, pick)


## The pick the drawer is printing, for tests and the mobile audit (REQ-P3-02).
func pick_line() -> String:
	return MapPlayPickProse.sentence_of(_pick)


## The hull the slip's launch rows mark, for tests and the mobile audit
## (REQ-P3-02).
func mark_type() -> String:
	return String(_pick.get("type", ""))


## The sentence that says what the launch rows' mark means, for tests and tooling
## (REQ-P3-02, DR-20261123-08). Empty when the slip shows no claim.
func legend_text() -> String:
	return "" if _legend == null else _legend.text


## Whether the legend stands under the claim it answers: only while that claim
## names a hull (REQ-P1-07, REQ-P5-06).
func legend_shown() -> bool:
	return _legend != null and _legend.visible


## The break-up drawer takes the yard's place while a join is on offer, so the
## dossier never grows past a phone's sheet (REQ-P1-05).
func set_offer_join(offers_join: bool) -> void:
	_button.visible = _is_player and not _rows.is_empty() and not offers_join
	_open = _open and _button.visible
	_apply_open()


## First tap arms and relabels, the second confirms (DR-20261109-01).
func on_scrap_pressed(hull_id: String) -> void:
	if _arm.spend(hull_id):
		action_pressed.emit("yard:scrap:%s" % hull_id)
		return
	_arm.arm(hull_id)
	_fill()


## The yard prints its two seams: what can be launched and, once the crown has a
## squadron, which hulls may be broken up. The one press stands at the slip's own
## foot, under the launch rows it files, so a phone reads it with the prices
## (REQ-P5-04; DR-20261118-08).
func _fill() -> void:
	_make_batch()
	# The legend is the block's, not the list's: lift it out before the list is
	# cleared, so the next fill can stand it under the claim again
	# (DR-20261123-08).
	if _legend != null and _legend.get_parent() != null:
		_legend.get_parent().remove_child(_legend)
	UiRowBuilder.clear_except(_box, _batch)
	_box.add_child(UiRowBuilder.caption("LAUNCH A HULL", 11, Palette.TEXT_DIM))
	# The court's own yard would lay one hull and not the list: the pick stands
	# under the heading, in the gold the crew's and the squadron's picks use, so
	# the advice reads before the rows' prices do (REQ-P5-03; DR-20261121-02).
	var advice_text: String = MapPlayPickProse.sentence_of(_pick)
	if not advice_text.is_empty():
		var advice := UiRowBuilder.line(12, Palette.GOLD)
		advice.text = advice_text
		advice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(advice)
		# What the mark on the launch rows means, under the claim it answers: the
		# slip has no footer, and a phone would drop one anyway (DR-20261123-08).
		if _legend != null and _legend.visible:
			_box.add_child(_legend)
	var ready: int = 0
	for row: Dictionary in _rows:
		if bool(row.get("batch_ready", false)):
			ready += 1
		_box.add_child(_build_row(row))
	# What the whole line costs, before it is pressed: the walk's own sum and the
	# purse it leaves, printed from the plan the press files, so a crown never
	# learns the price of 19,500 ducats after it signs (REQ-P5-06; DR-20261118-11).
	var plan: Dictionary = _batch_plan()
	var sum_line: String = RaiseBatchSum.sheet_line(plan)
	if not sum_line.is_empty():
		_box.add_child(UiRowBuilder.wrapped_line(sum_line, 10, Palette.TEXT_DIM))
	# The count is the yard's own `batch_ready` flag, so the face names what the
	# second tap would lay down before the stores are spent (REQ-P5-05) — and the
	# armed face takes the line's own count from the plan, so the confirm names
	# what will be filed and not what the view prints (DR-20261118-21).
	_batch.set_ready(ready, "hulls", RaiseBatchSum.carries(plan))
	# Already a child of the list from the last fill; it only moves to the foot of
	# the launch rows.
	if _batch.get_parent() == null:
		_box.add_child(_batch)
	else:
		_box.move_child(_batch, _box.get_child_count() - 1)
	if _fleet == null or not _is_player:
		return
	_box.add_child(UiRowBuilder.caption("BREAK UP A HULL", 11, Palette.TEXT_DIM))
	for hull_id: String in _fleet.hulls:
		_box.add_child(_hull_row(hull_id))


## One hull the yard offers to build: what she is, what she costs, what she waits
## on and the one tap that orders her. Her own numbers print under the price on
## every row — a hull the crown cannot launch yet included, because the study
## that opens her is a plan the numbers decide (REQ-P5-06).
func _build_row(row: Dictionary) -> Control:
	var ok: bool = bool(row["ok"])
	var reason: String = String(row["reason"])
	var cost: String = String(row["cost_text"])
	var type_id: String = String(row["type_id"])
	var detail: String = cost if ok else reason
	var pending: int = int(row.get("pending", 0))
	if pending > 0:
		detail += "  ·  %d under orders" % pending
	# The counsel's mark leads the hull the line would lay, so the crown finds
	# that row among the slip's whole list (DR-20261122-12).
	var hull_name: String = String(row["name"])
	var mark: String = mark_type()
	if not mark.is_empty() and type_id == mark:
		hull_name = "%s %s" % [COURT_MARK, hull_name]
	var entry: VBoxContainer = super({
		"type": type_id,
		"name": hull_name,
		"ok": ok,
		"reason": reason,
		"label": "Launch",
		"tip": cost if ok else reason,
		"action": "yard:build:%s" % type_id,
		"detail": detail,
	})
	var line: String = String(row.get("line", ""))
	if not line.is_empty():
		_row_detail(entry, line)
	return entry


## One hull afloat the yard may break up: her name, her own combat numbers and
## the arm the first tap takes (DR-20261109-01).
func _hull_row(hull_id: String) -> Control:
	var shell: Dictionary = _row_head(_fleet.type_of(hull_id))
	var entry: VBoxContainer = shell["entry"]
	var top: HBoxContainer = shell["top"]
	var hull_name: String = ShipNames.of(_fleet, hull_id)
	var hull_type: String = ShipStats.display_name(_fleet.type_of(hull_id))
	_row_reading(
		top, "%s — %s" % [hull_name, hull_type] if not hull_name.is_empty() else hull_type
	)
	var armed: bool = _arm.holds(hull_id)
	var scrap := _row_press(
		top,
		"Confirm scrap" if armed else "Break up",
		true,
		(
			"Break up %s: one peasant returns; no refund." % hull_name
			if armed and not hull_name.is_empty()
			else ("One peasant returns; no refund." if armed else "Break up this hull")
		),
		"",
		100.0
	)
	# The arm owns the press: one tap arms, the next confirms (DR-20261109-01).
	scrap.pressed.connect(func() -> void: on_scrap_pressed(hull_id))
	# The hull's own combat numbers and her holds, the same line the launch row
	# and the navy sheet print, so a breaking up is a reasoned choice.
	_row_detail(entry, FleetYard.hull_line(_fleet.type_of(hull_id)))
	return entry


## The plan the slip's rows carry, or an empty one when a caller handed the block
## rows of its own with no ledger behind them (a suite's fixture): the sum line
## then prints nothing and the press keeps its published face (DR-20261118-11).
func _batch_plan() -> Dictionary:
	for row: Dictionary in _rows:
		if row.has("batch"):
			return row["batch"]
	return RaiseBatchSum.blank()


## The window ran out: the break-up rows forget the first tap and print their
## resting face again, filing nothing.
func _on_arm_expired() -> void:
	if _open:
		_fill()
