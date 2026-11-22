class_name ArmyPanel
extends PanelContainer
## Dockable dossier for the selected land army: station, composition, readiness
## and the detach/merge orders. ArmyRosterBlock owns the regiment column;
## ArmyMusterBlock owns the drill-yard rows; ArmyPanelOrders owns the presses;
## ArmyPanelStatus / ArmyPanelStrength own the standing prose. Rules stay in
## ArmyState/ArmyMovement; the panel only reads state and emits intents
## (REQ-P3-01, REQ-P3-02).

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

## Kept for callers that armed the dismiss press before the orders split.
const DISMISS_ALL: String = ArmyPanelOrders.DISMISS_ALL

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
## The repaint's own reading of the ground: an army with no own province one
## march away gets the walk-home hint instead of the ordinary one (wiki:
## military-armies § Movement and attacks).
var _stranded: bool = false
var _roster: ArmyRosterBlock = null
var _scroll: ScrollContainer = null
var _muster_button: Button = null
var _muster_box: ArmyMusterBlock = null
var _muster_open: bool = false
var _orders: ArmyPanelOrders = null
## Aliases onto `_orders` so existing dossier tests keep their field paths.
var _merge: Button = null
var _embark: Button = null
var _plan: Button = null
var _hospital: Button = null
var _detach_all: Button = null
var _dismiss_all: Button = null


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

	_orders = ArmyPanelOrders.new()
	_orders.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	shell.add_child(_orders)
	_merge = _orders.merge
	_embark = _orders.embark
	_plan = _orders.plan
	_hospital = _orders.hospital
	_detach_all = _orders.detach_all
	_dismiss_all = _orders.dismiss_all

	_status = UiRowBuilder.line(13, Palette.GOLD_PALE)
	shell.add_child(_status)

	_hint = UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(_hint)


## First tap arms and relabels, the second files the order (DR-20261109-01).
func on_dismiss_all_pressed() -> void:
	if _orders != null:
		_orders.on_dismiss_all_pressed()


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


## Repaints the selected army from one named opening (REQ-P3-02).
func refresh(model: MapModel, opening: ArmyDossierOpening) -> void:
	if model == null or opening.army == null:
		return
	var army: ArmyState = opening.army
	var is_player: bool = opening.is_player
	var command: String = opening.command
	var muster: Array[Dictionary] = opening.muster
	var pick: String = opening.pick
	_header.flag.color = Palette.faction_color(army.owner)
	var title: String = "ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	if army.home:
		title = "HOME ARMY OF %s" % FactionCatalog.name_of(army.owner).to_upper()
	_header.title.text = title
	if army.is_embarked():
		_location.text = "Aboard a fleet"
	else:
		_location.text = "At %s%s" % [
			model.province_name(army.province), ArmyPanelStatus.ground_note(model, army)
		]
	_strength.text = ArmyPanelStrength.line(model, army)
	_command.text = _command_head(command)
	_command_row.visible = not command.is_empty()
	_composition.text = army.composition_text()
	_pick.text = pick
	_pick.visible = not pick.is_empty()
	_stranded = is_player and ArmyMovement.stranded(model, army)
	_roster.fill(army, is_player and not army.is_embarked(), model, is_player)
	_muster_box.fill(muster, opening.muster_pick)
	if not (is_player and army.home):
		_muster_open = false
	_muster_button.visible = is_player and army.home and not muster.is_empty()
	_muster_box.visible = _muster_button.visible and _muster_open
	if _orders != null:
		_orders.apply(army, opening)
	# A host off its own ground keeps no interior lines, so the hint must not
	# promise own land the tap list does not hold (DR-20261121-15). A seat on
	# another chart makes the walk itself a sea crossing, so the hint names that
	# instead of a land road home (DR-20261122-07).
	var off_ground: bool = is_player and army.province != MapModel.NO_ID
	if off_ground:
		off_ground = not ArmyMovement.on_own_ground(model, army)
	var over_sea: bool = is_player and ArmyMovement.seat_elsewhere(model, army)
	ArmyPanelStatus.apply(
		_status, _hint, army, is_player, _stranded, off_ground, over_sea, model
	)


## The dossier names the crown's commanders in one line; what a medal buys in
## the field is the command ledger's own note, one press away (DR-20261115-11),
## so a phone sheet is not asked to wrap a paragraph over the orders.
func _command_head(command: String) -> String:
	return command.split("\n")[0]


## Thin forward for suites that still read the larder off the sheet
## (`ArmyPanelStrength.food` owns the bill).
func _food(army: ArmyState) -> int:
	return ArmyPanelStrength.food(army)
