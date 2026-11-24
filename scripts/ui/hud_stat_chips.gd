class_name HudStatChips
extends RefCounted
## The cartouche's status plaques: treasury and its net income, ships, civilians
## and troops. This binds the widgets the bar mounts and owns their readings —
## the build, the treasury tip and the motion each keep their own book so this
## stays the binder (REQ-P1-02, REQ-P1-05, REQ-P3-01, REQ-P3-02).

var host: Control = null
var treasury_chip: Button = null
var fleet_chip: Button = null
var civilian_chip: Button = null
var army_chip: Button = null
var treasury_label: Label = null
var income_label: Label = null
var fleet_label: Label = null
var civilian_label: Label = null
var army_label: Label = null

var _treasury_value: int = 0
var _income_value: int = 0
## What the per-turn figure leaves out, so the plaque never promises the whole
## purse movement: the orders staged for the next clearing, the ducats the last
## clearing moved, and how far the purse actually went over the turn just
## closed (REQ-P5-05).
var _staged_orders: int = 0
var _clearing_value: int = 0
var _purse_moved: int = 0
## False until a close books its movement, so a fresh bar names no last turn.
var _moved_known: bool = false
## True when the closed turn's move beat the label it promised.
var _moved_wider: bool = false
var _motion: HudStatChipMotion = HudStatChipMotion.new()
## One record per plaque: the parts the compact bar narrows, kept from the build
## so the fit never walks the tree for a caption or a value column.
var _parts: Array[Dictionary] = []


## Builds the four plaques on the bar's row and binds them: the treasury and its
## net income, the ships, the crews and the troops. Each plaque is the target of
## its own door, so the display doubles as a shortcut (REQ-P1-02, REQ-P5-01).
func build(hud: GameHud, row: HBoxContainer) -> void:
	var treasury := HudStatChipBuild.make("TreasuryChip", "coin", "TREASURY", true)
	treasury["root"].pressed.connect(func() -> void: hud.economy_pressed.emit())
	_mount(hud, row, treasury)

	var fleets := HudStatChipBuild.make("FleetChip", "ship", "SHIPS", false)
	fleets["root"].pressed.connect(func() -> void: hud.fleet_status_pressed.emit())
	_mount(hud, row, fleets)

	var civilians := HudStatChipBuild.make("CivilianChip", "people", "CREW ›", false)
	civilians["root"].pressed.connect(
		func() -> void: hud.ledger_door_pressed.emit(HudLedgerDoors.CIVILIANS)
	)
	civilians["root"].tooltip_text = "Every civilian in the realm (C)"
	_mount(hud, row, civilians)

	var troops := HudStatChipBuild.make("ArmyChip", "swords", "TROOPS", false)
	troops["root"].pressed.connect(func() -> void: hud.army_status_pressed.emit())
	_mount(hud, row, troops)

	_bind(hud, treasury, fleets, civilians, troops)


## One plaque on the bar: the HUD keeps the chip for its layout, and this keeps
## the parts the compact fit narrows.
func _mount(hud: GameHud, row: HBoxContainer, chip: Dictionary) -> void:
	hud.chips.append(chip["root"])
	row.add_child(chip["root"])
	_parts.append(chip)


## The four plaques' readings, bound once the widgets exist.
func _bind(
	hud: Control,
	treasury: Dictionary,
	fleets: Dictionary,
	civilians: Dictionary,
	troops: Dictionary
) -> void:
	host = hud
	_motion.bind(hud)
	treasury_chip = treasury["root"]
	treasury_label = treasury["value"]
	income_label = treasury["delta"]
	fleet_chip = fleets["root"]
	fleet_label = fleets["value"]
	civilian_chip = civilians["root"]
	civilian_label = civilians["value"]
	army_chip = troops["root"]
	army_label = troops["value"]


## The compact cartouche keeps each plaque's medallion and value and drops its
## caption, narrowing the value column to the room a phone has (REQ-P1-05,
## REQ-P1-07). The parts come from the build, never a tree search.
func apply_compact(compact: bool) -> void:
	for part: Dictionary in _parts:
		var root: Button = part["root"]
		if not is_instance_valid(root):
			continue
		var caption: Label = part["caption"]
		if caption != null:
			caption.visible = not compact
		root.custom_minimum_size.x = float(
			part["compact_width"] if compact else part["wide_width"]
		)
		var column: Control = part["column"]
		if column != null:
			column.custom_minimum_size.x = float(
				part["compact_column"] if compact else part["wide_column"]
			)


func set_treasury(value: int, animate: bool = true) -> void:
	if treasury_label == null:
		return
	var from: int = _treasury_value
	_treasury_value = value
	_refresh_treasury_tooltip()
	# A purse below zero is a debt, and the techs decided how deep it may go
	# (wiki: tech-tree-labour-economy § money_lending, banking). Crimson keeps the
	# chip from reading like any other balance (REQ-P5-05).
	treasury_label.add_theme_color_override(
		"font_color", Palette.CRIMSON if value < 0 else Palette.TEXT
	)
	_motion.count_treasury(treasury_label, from, value, animate)


## Net treasury movement per turn, shown beside the treasury count so the player
## reads solvency without opening the ledger. Zero is dim, not a fake gain.
func set_income(value: int) -> void:
	_income_value = value
	if income_label == null:
		return
	income_label.text = TextFormat.delta(value)
	income_label.add_theme_color_override(
		"font_color",
		Palette.TEXT_DIM if value == 0 else (
			Palette.GOLD_PALE if value > 0 else Palette.CRIMSON.lerp(Color.WHITE, 0.35)
		)
	)
	_refresh_treasury_tooltip()


## What the per-turn figure does not include: the orders the court has staged for
## the next clearing and the ducats the last clearing moved. The label is the
## phases alone, so the plaque names the two passes that settle after them
## (wiki: world-market § Trade orders; REQ-P5-05).
func set_income_scope(staged_orders: int, clearing: int) -> void:
	_staged_orders = maxi(staged_orders, 0)
	_clearing_value = clearing
	_refresh_treasury_tooltip()


## How far the purse actually moved over the turn just closed. Called before the
## new turn's label lands, so the move is judged against the figure the player
## read during that turn; a turn wider than it promised is named on the bar,
## never left for the ledger to explain (REQ-P5-05).
func set_purse_moved(amount: int) -> void:
	_purse_moved = amount
	_moved_known = true
	_moved_wider = amount != _income_value
	_refresh_treasury_tooltip()


func set_fleets(value: int) -> void:
	if fleet_label == null:
		return
	fleet_label.text = str(value)
	if fleet_chip != null:
		fleet_chip.tooltip_text = "Ships — %d · find the next squadron" % value


func set_civilians(value: int) -> void:
	if civilian_label == null:
		return
	civilian_label.text = str(value)
	if civilian_chip != null:
		civilian_chip.tooltip_text = (
			"Civilians — %d · open the empire roster (C)" % value
		)


func set_armies(value: int) -> void:
	if army_label == null:
		return
	army_label.text = str(value)
	if army_chip != null:
		army_chip.tooltip_text = "Troops — %d regiments · find the next army" % value


## The turn's coin movement lifts off the treasury plaque, so a gain reads as an
## event and not a silent repaint (REQ-P5-05).
func flash_income(amount: int) -> void:
	_motion.flash_income(amount, treasury_chip)


## Suite re-seat and a fresh count-up must not leave a prior plaque tween
## writing into a label mid-reset (gd-tools reports freed lambda captures).
func clear_animations() -> void:
	_motion.clear_all()
	if treasury_label != null:
		treasury_label.text = TextFormat.thousands(_treasury_value)


## Estates and college only — the world market clears after them
## (world-market). A negative purse is named as debt, so a crown in the
## lending floor's shadow reads why it cannot fund a study (REQ-P5-05).
func _refresh_treasury_tooltip() -> void:
	if treasury_chip == null:
		return
	treasury_chip.tooltip_text = HudTreasuryTooltip.text(
		_treasury_value,
		_income_value,
		_staged_orders,
		_clearing_value,
		_moved_known,
		_moved_wider,
		_purse_moved,
	)
