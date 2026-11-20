class_name ArmyPanel
extends PanelContainer
## Dockable dossier for the selected land army: station, composition, readiness
## and the detach/merge orders. ArmyRosterBlock owns the regiment column;
## ArmyMusterBlock owns the drill-yard rows. Rules stay in ArmyState/ArmyMovement;
## the panel only reads state and emits intents (REQ-P3-01, REQ-P3-02).

signal close_pressed
signal dock_side_pressed
signal action_pressed(action: String)
## The ledger doors the dossier carries: the crown's whole pool, its medals and
## the road to the next commander (DR-20261115-11). The press names the sheet by
## its HudLedgerDoors key; the dossier never needs the sheet's class.
signal door_pressed(key: String)
## The crown named one of its colours: the roster's edit row committed text
## (wiki: naming § Regiment names; DR-20261113-03).
signal rename_pressed(regiment_id: String, wanted: String)

var _header: DossierHeader = null
var _location: Label = null
var _strength: Label = null
var _command: Label = null
var _command_row: HBoxContainer = null
var _command_icon: TextureRect = null
var _command_door: Button = null
var _composition: Label = null
var _pick: Label = null
var _status: Label = null
var _hint: Label = null
var _roster: ArmyRosterBlock = null
var _scroll: ScrollContainer = null
var _muster_button: Button = null
var _muster_box: ArmyMusterBlock = null
var _muster_open: bool = false
var _detach_all: Button = null
var _dismiss_all: Button = null
var _dismiss_armed: bool = false
var _dismiss_timer: Timer = null
## The regiments the open sheet is reading, so the dismissal press can count
## what it would shed without reaching into the roster block.
var _last_count: int = 0
var _merge: Button = null
var _embark: Button = null
var _plan: Button = null
var _hospital: Button = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 4, Vector4(18, 12, 18, 12)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	add_child(shell)

	_header = DossierHeader.make(19, true)
	_header.dock_pressed.connect(func() -> void: dock_side_pressed.emit())
	_header.close_pressed.connect(func() -> void: close_pressed.emit())
	shell.add_child(_header)

	_location = UiRowBuilder.line(15, Palette.TEXT)
	shell.add_child(_location)

	_strength = UiRowBuilder.line(13, Palette.TEXT_DIM)
	shell.add_child(_strength)

	# The crown's commanders: a general's medallion beside every name and medal,
	# the same shell frame a roster row wears (REQ-P1-08).
	_command_row = HBoxContainer.new()
	_command_row.add_theme_constant_override("separation", 8)
	_command_row.visible = false
	shell.add_child(_command_row)
	_command_icon = TextureRect.new()
	_command_icon.texture = ChromeIcons.texture("commander")
	_command_icon.custom_minimum_size = Vector2(22, 22)
	_command_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_command_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_command_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_command_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_command_row.add_child(_command_icon)

	_command = UiRowBuilder.line(12, Palette.TEXT_DIM)
	_command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_command.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_row.add_child(_command)

	# The command door: the dossier names the crown's commanders, the ledger
	# reads the pool they are drawn from (DR-20261115-11).
	_command_door = UiRowBuilder.button("Commanders", 30.0, 0.0)
	_command_door.custom_minimum_size = Vector2(96, 30)
	_command_door.add_theme_font_size_override("font_size", 11)
	_command_door.tooltip_text = "Every commander the crown holds (G)"
	_command_door.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_command_door.pressed.connect(
		func() -> void: door_pressed.emit(HudLedgerDoors.COMMAND)
	)
	_command_row.add_child(_command_door)

	_composition = UiRowBuilder.line(13, Palette.GOLD_PALE)
	_composition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_composition)

	# The court's own pick sits under the composition, in the gold the crew's and
	# the squadron's picks print in: advice, never state (DR-20261120-10).
	_pick = UiRowBuilder.line(12, Palette.GOLD)
	_pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick.visible = false
	shell.add_child(_pick)

	_muster_button = UiRowBuilder.button("Muster regiments", 36.0, 0.0)
	_muster_button.pressed.connect(func() -> void: set_muster_open(not _muster_open))
	_muster_button.visible = false
	shell.add_child(_muster_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	_scroll = scroll

	# One column inside the scroll: the roster must stack above the drill yard,
	# not share the scroll's origin with it.
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	_roster = ArmyRosterBlock.new()
	_roster.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	_roster.rename_pressed.connect(
		func(regiment_id: String, wanted: String) -> void:
			rename_pressed.emit(regiment_id, wanted)
	)
	content.add_child(_roster)

	_muster_box = ArmyMusterBlock.new()
	_muster_box.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	content.add_child(_muster_box)

	_merge = UiRowBuilder.button("Combine armies here", 36.0, 0.0)
	_merge.pressed.connect(func() -> void: action_pressed.emit("merge"))
	_merge.visible = false
	shell.add_child(_merge)

	_embark = UiRowBuilder.button("Embark aboard the fleet", 36.0, 0.0)
	_embark.pressed.connect(func() -> void: action_pressed.emit("embark"))
	_embark.visible = false
	shell.add_child(_embark)

	_plan = UiRowBuilder.button("Crown battle plan: Balanced", 36.0, 0.0)
	_plan.tooltip_text = (
		"One plan for every battle this crown fights — tap to cycle "
		+ "Aggressive / Balanced / Defensive"
	)
	_plan.pressed.connect(func() -> void: action_pressed.emit("plan:next"))
	_plan.visible = false
	shell.add_child(_plan)

	# The army's own tents (DR-20261112-07): a blocked order still shows, its
	# reason as the caption, so the crown never hunts for a hidden refusal.
	_hospital = UiRowBuilder.button("Pitch a field hospital", 36.0, 0.0)
	_hospital.pressed.connect(func() -> void: action_pressed.emit("hospital"))
	_hospital.visible = false
	shell.add_child(_hospital)

	_detach_all = UiRowBuilder.button("Detach all regiments", 36.0, 0.0)
	_detach_all.pressed.connect(func() -> void: action_pressed.emit("detach_all"))
	_detach_all.visible = false
	shell.add_child(_detach_all)

	# Shedding the whole standard is destructive, so the press asks once
	# (wiki: military-armies § Dismissing regiments; DR-20261109-01).
	_dismiss_all = UiRowBuilder.button("Dismiss all regiments", 36.0, 0.0)
	_dismiss_all.pressed.connect(on_dismiss_all_pressed)
	_dismiss_all.visible = false
	shell.add_child(_dismiss_all)
	_dismiss_timer = Timer.new()
	_dismiss_timer.one_shot = true
	_dismiss_timer.wait_time = ArmyRosterBlock.ARM_SECONDS
	_dismiss_timer.timeout.connect(_clear_dismiss_arm)
	add_child(_dismiss_timer)

	_status = UiRowBuilder.line(13, Palette.GOLD_PALE)
	shell.add_child(_status)

	_hint = UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_hint)


## First tap arms and relabels, the second files the order (DR-20261109-01).
func on_dismiss_all_pressed() -> void:
	if _dismiss_armed:
		_clear_dismiss_arm()
		action_pressed.emit("dismiss_all")
		return
	_dismiss_armed = true
	_retitle_dismiss(_roster_count())
	if _dismiss_timer != null and _dismiss_timer.is_inside_tree():
		_dismiss_timer.start()


## Forgets an armed dismissal without filing it; an expired arm does nothing.
func _clear_dismiss_arm() -> void:
	_dismiss_armed = false
	if _dismiss_timer != null:
		_dismiss_timer.stop()
	_retitle_dismiss(_roster_count())


## The press names what the second tap does, before the colours leave
## (REQ-P5-05).
func _retitle_dismiss(count: int) -> void:
	if _dismiss_all == null:
		return
	_dismiss_all.text = (
		"Confirm — dismiss all %d regiments" % count
		if _dismiss_armed
		else "Dismiss all regiments"
	)
	_dismiss_all.tooltip_text = (
		"Press again to dismiss every regiment: one peasant each, no refund."
		if _dismiss_armed
		else "Dismiss every regiment of this army: one peasant each, no refund."
	)


## The army the sheet is reading, so the press can count what it would shed.
func _roster_count() -> int:
	return _last_count


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _header != null:
		_header.set_dock_affordance(glyph, tip)


## Opens or closes the drill-yard list without rebuilding the dossier.
func set_muster_open(open: bool) -> void:
	_muster_open = open
	if _muster_box != null:
		_muster_box.visible = open and _muster_button.visible
	if open and _scroll != null:
		_scroll_to_muster.call_deferred()


## Brings the first drill-yard row under the top of the scroll viewport.
func _scroll_to_muster() -> void:
	if _scroll == null or _muster_box == null:
		return
	_scroll.scroll_vertical = int(_muster_box.position.y)


func refresh(
	model: MapModel,
	army: ArmyState,
	is_player: bool,
	can_merge: bool = false,
	command: String = "",
	muster: Array[Dictionary] = [],
	embark: String = "",
	plan: String = "balanced",
	hospital: Dictionary = {},
	pick: String = ""
) -> void:
	if model == null or army == null:
		return
	_header.flag.color = Palette.faction_color(army.owner)
	var title: String = "ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	if army.home:
		title = "HOME ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	_header.title.text = title
	if army.is_embarked():
		_location.text = "Aboard a fleet"
	else:
		_location.text = "At %s" % model.province_name(army.province)
	_strength.text = _strength_line(model, army)
	_command.text = _command_head(command)
	_command_row.visible = not command.is_empty()
	_composition.text = army.composition_text()
	_pick.text = pick
	_pick.visible = not pick.is_empty()
	_last_count = army.count()
	# A repaint means the order landed or the view moved: no arm survives it.
	_dismiss_armed = false
	if _dismiss_timer != null:
		_dismiss_timer.stop()
	_roster.fill(army, is_player and not army.is_embarked(), model, is_player)
	_muster_box.fill(muster)
	if not (is_player and army.home):
		_muster_open = false
	_muster_button.visible = is_player and army.home and not muster.is_empty()
	_muster_box.visible = _muster_button.visible and _muster_open
	_merge.visible = is_player and can_merge and not army.is_embarked() and army.count() > 0
	_detach_all.visible = is_player and not army.is_embarked() and army.count() > 1
	_dismiss_all.visible = is_player and army.count() > 0
	_retitle_dismiss(army.count())
	_embark.visible = is_player and not embark.is_empty() and not army.is_embarked()
	_plan.visible = is_player and not army.is_embarked() and army.count() > 0
	_plan.text = "Crown battle plan: %s" % QuickBattleActions.normalize_plan(plan).capitalize()
	_hospital.visible = is_player and not army.is_embarked() and not hospital.is_empty()
	_hospital.disabled = not bool(hospital.get("ok", false))
	_hospital.text = String(hospital.get("caption", "Pitch a field hospital"))
	_apply_status(army, is_player)


## The dossier names the crown's commanders in one line; what a medal buys in
## the field is the command ledger's own note, one press away (DR-20261115-11),
## so a phone sheet is not asked to wrap a paragraph over the orders.
func _command_head(command: String) -> String:
	return command.split("\n")[0]


## Strength line: count, firepower, food, chevrons and the ward or train. The
## strength is the resolver's own aggregation, so the dossier, the muster roll
## and the battle name one figure for a decorated standard (wiki: combat
## § Strength, military-armies § The muster roll; REQ-P2-03).
func _strength_line(model: MapModel, army: ArmyState) -> String:
	var one: Array[ArmyState] = [army]
	var text: String = "%d regiments · %d strength · %d food" % [
		army.count(), roundi(ArmyForce.side_strength(one)), _food(army)
	]
	var chevrons: int = RegimentCondition.chevrons(one)
	if chevrons > 0:
		text += " · %d chevrons" % chevrons
	if army.is_embarked():
		return text
	var ward: int = HospitalRules.effective_level(model, army.province)
	if army.field_hospital:
		# The tents carry the field's tempo anywhere; a fed ward can still
		# beat them, so both shares are named (DR-20261112-07).
		text += " · field hospital · rest %d%%" % roundi(
			HospitalTrain.REST_SHARE * 100.0
		)
		var ward_share: float = HospitalRules.rest_share(ward)
		if ward > 0 and ward_share > HospitalTrain.REST_SHARE:
			text += " · ward %d%%" % roundi(ward_share * 100.0)
	elif ward > 0:
		text += " · rest %d%%" % roundi(HospitalRules.rest_share(ward) * 100.0)
	elif HospitalRules.level_at(model, army.province) > 0:
		# The ward is there but its staff went unfed (DR-20261112-04).
		text += " · hospital unstaffed"
	return text


func _apply_status(army: ArmyState, is_player: bool) -> void:
	if not is_player:
		_status.text = "Enemy colours · no orders"
		_hint.text = "Observe only. Orders require your own army."
	elif army.is_embarked():
		_status.text = "Aboard the fleet"
		_hint.text = "The squadron carries the army; land on an owned coast."
	elif army.home:
		_status.text = "Home Army · never leaves the capital"
		_hint.text = "Detach a regiment to form a field army, then march it."
	elif army.moved:
		_status.text = "Has marched this turn"
		_hint.text = "End the turn to march again."
	else:
		_status.text = "1 march this turn"
		_hint.text = "Tap a highlighted province; your own land is open, enemy land must border you."


## The dossier's larder line: the rules' own bill, so the dossier and the crown's
## army sheet never name one standard two ways (wiki: military-armies § The
## regiments behind an army, combat § Feeding; DR-20261112-07).
func _food(army: ArmyState) -> int:
	var one: Array[ArmyState] = [army]
	return ArmyRoster.food_upkeep_of(one, army.owner)
