class_name ArmyPanelOrders
extends VBoxContainer
## Order presses under the army dossier: combine, embark, crown plan, field
## hospital, detach-all and dismiss-all. The panel owns the sheet; this block
## owns the buttons and the dismiss arm (REQ-P3-01, REQ-P3-02; DR-20261109-01).

signal action_pressed(action: String)

## The one order the block carries for the whole standard; the guard's key.
const DISMISS_ALL: String = "dismiss_all"

var merge: Button = null
var embark: Button = null
var plan: Button = null
var hospital: Button = null
var detach_all: Button = null
var dismiss_all: Button = null
## Shedding the whole standard is destructive, so the press asks once.
var _dismiss_arm: ArmGuard = null
## Regiments the open sheet is reading, so the dismissal press can count.
var _last_count: int = 0


func _init() -> void:
	# Built with the block, so a sheet assembled outside the tree still wires
	# its aliases before `_ready` returns (same pattern as ArmyRosterBlock).
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	merge = UiRowBuilder.button("Combine armies here", 36.0, 0.0)
	merge.pressed.connect(func() -> void: action_pressed.emit("merge"))
	merge.visible = false
	add_child(merge)

	embark = UiRowBuilder.button("Embark aboard the fleet", 36.0, 0.0)
	embark.pressed.connect(func() -> void: action_pressed.emit("embark"))
	embark.visible = false
	add_child(embark)

	plan = UiRowBuilder.button("Crown battle plan: Balanced", 36.0, 0.0)
	plan.tooltip_text = (
		"One plan for every battle this crown fights — tap to cycle "
		+ "Aggressive / Balanced / Defensive"
	)
	plan.pressed.connect(func() -> void: action_pressed.emit("plan:next"))
	plan.visible = false
	add_child(plan)

	# The army's own tents (DR-20261112-07): a blocked order still shows, its
	# reason as the caption, so the crown never hunts for a hidden refusal.
	hospital = UiRowBuilder.button("Pitch a field hospital", 36.0, 0.0)
	hospital.pressed.connect(func() -> void: action_pressed.emit("hospital"))
	hospital.visible = false
	add_child(hospital)

	detach_all = UiRowBuilder.button("Detach all regiments", 36.0, 0.0)
	detach_all.pressed.connect(func() -> void: action_pressed.emit("detach_all"))
	detach_all.visible = false
	add_child(detach_all)

	# Shedding the whole standard is destructive, so the press asks once
	# (wiki: military-armies § Dismissing regiments; DR-20261109-01).
	dismiss_all = UiRowBuilder.button("Dismiss all regiments", 36.0, 0.0)
	dismiss_all.pressed.connect(on_dismiss_all_pressed)
	dismiss_all.visible = false
	add_child(dismiss_all)
	_dismiss_arm = ArmGuard.new()
	_dismiss_arm.expired.connect(func() -> void: _retitle_dismiss(_last_count))
	add_child(_dismiss_arm, false, Node.INTERNAL_MODE_BACK)


## First tap arms and relabels, the second files the order (DR-20261109-01).
func on_dismiss_all_pressed() -> void:
	if _dismiss_arm.spend(DISMISS_ALL):
		action_pressed.emit("dismiss_all")
		return
	_dismiss_arm.arm(DISMISS_ALL)
	_retitle_dismiss(_last_count)


## The press names what the second tap does, before the colours leave
## (REQ-P5-05).
func _retitle_dismiss(count: int) -> void:
	if dismiss_all == null:
		return
	var armed: bool = _dismiss_arm != null and _dismiss_arm.holds(DISMISS_ALL)
	dismiss_all.text = (
		"Confirm — dismiss all %s" % MoneyText.counted(count, "regiment")
		if armed
		else "Dismiss all regiments"
	)
	dismiss_all.tooltip_text = (
		"Press again to dismiss every regiment: one peasant each, no refund."
		if armed
		else "Dismiss every regiment of this army: one peasant each, no refund."
	)


## A repaint means the order landed or the view moved: no arm survives it.
func clear_arm() -> void:
	if _dismiss_arm != null:
		_dismiss_arm.clear()


## Shows and captions every order from one named opening (REQ-P3-02).
func apply(army: ArmyState, opening: ArmyDossierOpening) -> void:
	var is_player: bool = opening.is_player
	var embark_note: Dictionary = opening.embark
	var hospital_note: Dictionary = opening.hospital
	var plan_name: String = opening.plan
	_last_count = army.count()
	clear_arm()
	merge.visible = (
		is_player and opening.can_merge and not army.is_embarked() and army.count() > 0
	)
	detach_all.visible = is_player and not army.is_embarked() and army.count() > 1
	dismiss_all.visible = is_player and army.count() > 0
	_retitle_dismiss(army.count())
	embark.visible = is_player and not embark_note.is_empty() and not army.is_embarked()
	# A refused boarding keeps its press, disabled, with the rules' own reason as
	# the caption — the field hospital's own reading (DR-20261112-07): the reason
	# the deck cannot take the host is a reading, not a missing order
	# (wiki: ships-and-naval § Naval transport; DR-20261124-14).
	embark.disabled = not bool(embark_note.get("ok", false))
	embark.text = String(embark_note.get("caption", "Embark aboard the fleet"))
	plan.visible = is_player and not army.is_embarked() and army.count() > 0
	plan.text = "Crown battle plan: %s" % QuickBattleActionLaw.normalize_plan(plan_name).capitalize()
	hospital.visible = is_player and not army.is_embarked() and not hospital_note.is_empty()
	hospital.disabled = not bool(hospital_note.get("ok", false))
	hospital.text = String(hospital_note.get("caption", "Pitch a field hospital"))
