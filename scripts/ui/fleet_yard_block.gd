class_name FleetYardBlock
extends FleetDrawer
## The fleet dossier's shipyard drawer: the toggle, the launch rows and the
## break-up rows with their confirm arm (wiki: ships-and-naval § Ship build
## economy, § Ship muster and the breaker's yard). The drawer's toggle, list,
## open state and row shell are FleetDrawer's; this block owns only the yard's
## rows and the arm (REQ-P3-01). It reads plain data and emits intents;
## FleetYard owns every rule (REQ-P3-02).

## Breaking up a paid-for hull asks once: a second tap inside this window
## confirms and an expired arm does nothing (DR-20261109-01).
const ARM_SECONDS: float = 5.0

var _timer: Timer = null
var _armed_hull: String = ""
var _fleet: FleetState = null
var _is_player: bool = false


func _init() -> void:
	toggle_text = "Shipyard"
	close_text = "Close shipyard"
	drawer_height = 168.0
	row_separation = 8


func _ready() -> void:
	super()
	# The arm expires on its own; a freed dossier takes the timer with it.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = ARM_SECONDS
	_timer.timeout.connect(_clear_arm)
	add_child(_timer)


## A fresh fleet: the yard closes unless it may stay, and the rows are redrawn.
func show_rows(
	fleet: FleetState, rows: Array[Dictionary], is_player: bool, keep_open: bool
) -> void:
	_fleet = fleet
	_is_player = is_player
	offer(rows, is_player, not rows.is_empty(), "", keep_open, false)


## The capital slip: no squadron afloat, but the yard still lists what to launch.
func show_slip(rows: Array[Dictionary], is_player: bool) -> void:
	show_rows(null, rows, is_player, true)


## The break-up drawer takes the yard's place while a join is on offer, so the
## dossier never grows past a phone's sheet (REQ-P1-05).
func set_offer_join(offers_join: bool) -> void:
	_button.visible = _is_player and not _rows.is_empty() and not offers_join
	_open = _open and _button.visible
	_apply_open()


## First tap arms and relabels, the second confirms (DR-20261109-01).
func on_scrap_pressed(hull_id: String) -> void:
	if _armed_hull == hull_id:
		_clear_arm()
		action_pressed.emit("yard:scrap:%s" % hull_id)
		return
	_armed_hull = hull_id
	_fill()
	_timer.start()


## The yard prints its two seams: what can be launched and, once the crown has a
## squadron, which hulls may be broken up.
func _fill() -> void:
	UiRowBuilder.clear(_box)
	_box.add_child(UiRowBuilder.caption("LAUNCH A HULL", 11, Palette.TEXT_DIM))
	for row: Dictionary in _rows:
		_box.add_child(_build_row(row))
	if _fleet == null or not _is_player:
		return
	_box.add_child(UiRowBuilder.caption("BREAK UP A HULL", 11, Palette.TEXT_DIM))
	for hull_id: String in _fleet.hulls:
		_box.add_child(_hull_row(hull_id))


## One hull the yard offers to build: what she costs, what she waits on and the
## one tap that orders her.
func _build_row(row: Dictionary) -> Control:
	var ok: bool = bool(row["ok"])
	var reason: String = String(row["reason"])
	var cost: String = String(row["cost_text"])
	var type_id: String = String(row["type_id"])
	var detail: String = cost if ok else reason
	var pending: int = int(row.get("pending", 0))
	if pending > 0:
		detail += "  ·  %d under orders" % pending
	return super({
		"type": type_id,
		"name": String(row["name"]),
		"ok": ok,
		"reason": reason,
		"label": "Launch",
		"tip": cost if ok else reason,
		"action": "yard:build:%s" % type_id,
		"detail": detail,
	})


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
	var armed: bool = _armed_hull == hull_id
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
	# The hull's own combat numbers, so a breaking up is a reasoned choice.
	_row_detail(entry, NavalStrength.hull_line(_fleet.type_of(hull_id)))
	return entry


func _clear_arm() -> void:
	if _armed_hull.is_empty():
		return
	_armed_hull = ""
	_timer.stop()
	if _open:
		_fill()
