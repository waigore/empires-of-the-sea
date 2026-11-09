class_name FleetPanel
extends PanelContainer
## Dockable dossier for the selected fleet: colours, station, the remaining move
## and the naval yard (wiki: ships-and-naval § Ship build economy, § Ship muster
## and the breaker's yard). The panel reads state and emits intents; FleetYard
## owns every rule (REQ-P3-02, REQ-P3-03).

signal close_pressed
signal dock_side_pressed
signal action_pressed(action: String)

## Breaking up a paid-for hull asks once: a second tap inside this window
## confirms and an expired arm does nothing (DR-20261109-01).
const ARM_SECONDS: float = 5.0

var _flag: ColorRect = null
var _title: Label = null
var _dock: Button = null
var _location: Label = null
var _ships: Label = null
var _status: Label = null
var _hint: Label = null
var _yard_button: Button = null
var _yard_scroll: ScrollContainer = null
var _yard_box: VBoxContainer = null
var _yard_open: bool = false
var _armed_hull: String = ""
var _arm_timer: Timer = null
var _fleet: FleetState = null
var _is_player: bool = false
var _yard_rows: Array[Dictionary] = []
var _land_box: VBoxContainer = null
var _land_rows: Array[Dictionary] = []
var _mission: FleetMissionSection = null
var _crew: FleetCrewSection = null


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
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_flag = ColorRect.new()
	_flag.custom_minimum_size = Vector2(14, 14)
	_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_flag)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	_dock = _small_button("◀", "Dock left")
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	header.add_child(_dock)

	var close := _small_button("×", "Close")
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)

	_location = _line(15, Palette.TEXT)
	column.add_child(_location)

	_ships = _line(13, Palette.TEXT_DIM)
	_ships.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_ships)

	_status = _line(13, Palette.GOLD_PALE)
	column.add_child(_status)

	_mission = FleetMissionSection.new()
	_mission.visible = false
	_mission.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	column.add_child(_mission)

	_crew = FleetCrewSection.new()
	_crew.visible = false
	_crew.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	column.add_child(_crew)

	_land_box = VBoxContainer.new()
	_land_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_land_box.add_theme_constant_override("separation", 6)
	_land_box.visible = false
	column.add_child(_land_box)

	_yard_button = _button("Shipyard")
	_yard_button.visible = false
	_yard_button.pressed.connect(func() -> void: set_yard_open(not _yard_open))
	column.add_child(_yard_button)

	_yard_scroll = ScrollContainer.new()
	_yard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_yard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_yard_scroll.custom_minimum_size = Vector2(0, 168)
	_yard_scroll.visible = false
	column.add_child(_yard_scroll)

	_yard_box = VBoxContainer.new()
	_yard_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yard_box.add_theme_constant_override("separation", 8)
	_yard_scroll.add_child(_yard_box)

	# The arm expires on its own; a freed dossier takes the timer with it.
	_arm_timer = Timer.new()
	_arm_timer.one_shot = true
	_arm_timer.wait_time = ARM_SECONDS
	_arm_timer.timeout.connect(_clear_arm)
	add_child(_arm_timer)

	_hint = _line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


## Opens or closes the yard without rebuilding the dossier.
func set_yard_open(open: bool) -> void:
	_yard_open = open and _yard_button != null and _yard_button.visible
	if _yard_button != null:
		_yard_button.text = "Close shipyard" if _yard_open else "Shipyard"
	if _yard_scroll != null:
		_yard_scroll.visible = _yard_open
	if _yard_open:
		_fill_yard()


func refresh(
	model: MapModel,
	fleet: FleetState,
	is_player: bool,
	passage: String = "",
	yard_rows: Array[Dictionary] = [],
	land_rows: Array[Dictionary] = [],
	carried: int = 0,
	beach_rows: Array[Dictionary] = [],
	beach_note: String = "",
	crew: Dictionary = {}
) -> void:
	if model == null or fleet == null:
		return
	_fleet = fleet
	_is_player = is_player
	_yard_rows = yard_rows
	_land_rows = land_rows
	_flag.color = Palette.faction_color(fleet.owner)
	_title.text = "FLEET OF %s" % FactionCatalog.name_of(fleet.owner).to_upper()
	if fleet.is_at_sea():
		_location.text = "At sea · %s" % model.sea_zone_name(fleet.sea_zone)
	else:
		_location.text = "In port · %s" % model.province_name(fleet.province)
	var upkeep: int = ShipEconomy.food_upkeep_for_fleet(fleet)
	_ships.text = "%d ships · %s · %d strength · upkeep %d food" % [
		fleet.ship_count(), fleet.hull_summary(), strength_of(fleet), upkeep
	]
	if carried > 0:
		_ships.text += " · carrying %d regiments" % carried
	var colonists: int = int(crew.get("count", 0))
	if colonists > 0:
		_ships.text += " · %d colonists" % colonists
	_fill_land()
	_mission.set_data(beach_note, beach_rows)
	_crew.set_data(crew)
	if not is_player:
		_status.text = "Enemy colours · no orders"
		_hint.text = "Observe only. Orders require your own fleet."
	elif not beach_note.is_empty():
		_status.text = "On beachhead duty"
		_hint.text = beach_note
	elif fleet.moved:
		_status.text = "Has moved this turn"
		_hint.text = "End the turn to sail again."
	elif not passage.is_empty():
		_status.text = "1 move this turn"
		_hint.text = passage
	elif carried > 0 and not _land_rows.is_empty():
		_status.text = "Troops aboard"
		_hint.text = "Choose a friendly coast to land the army."
	elif colonists > 0:
		_status.text = "Colonists aboard"
		_hint.text = "Choose a coast to put them ashore, or put to sea."
	else:
		_status.text = "1 move this turn"
		_hint.text = "Tap a highlighted sea zone or a friendly port."
	_yard_button.visible = is_player and not yard_rows.is_empty()
	if not _yard_button.visible:
		_yard_open = false
	_yard_button.text = "Close shipyard" if _yard_open else "Shipyard"
	_yard_scroll.visible = _yard_open
	if _yard_open:
		_fill_yard()


## The crown's capital yard with no squadron afloat: the first launch founds the
## home fleet, so the dossier still has to list what can be built.
func refresh_slip(
	model: MapModel, province_id: int, rows: Array[Dictionary], is_player: bool
) -> void:
	if model == null:
		return
	_fleet = null
	_is_player = is_player
	_yard_rows = rows
	_armed_hull = ""
	_flag.color = Palette.faction_color(FactionCatalog.PLAYER_FACTION)
	_title.text = "SHIPYARD OF %s" % FactionCatalog.name_of(
		FactionCatalog.PLAYER_FACTION
	).to_upper()
	_location.text = "At %s · capital port" % model.province_name(province_id)
	_ships.text = "No home fleet — your first launch founds one."
	_status.text = "The yard is open"
	_hint.text = "Launch a hull to found the home fleet; break up hulls from the fleet dossier."
	_land_rows = []
	if _crew != null:
		_crew.set_data({})
	if _land_box != null:
		_land_box.visible = false
	if _mission != null:
		_mission.set_data("", [] as Array[Dictionary])
	_yard_button.visible = is_player and not rows.is_empty()
	_yard_open = _yard_button.visible
	_yard_button.text = "Close shipyard" if _yard_open else "Shipyard"
	_yard_scroll.visible = _yard_open
	if _yard_open:
		_fill_yard()


## Ship strength of the squadron: Σ FRP over its hulls (DR-20261109-01).
static func strength_of(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	var total: int = 0
	for hull_id: String in fleet.hulls:
		total += ShipStats.firepower(fleet.type_of(hull_id))
	return total


## Landing choices for the carried army: one button per owned coast.
func _fill_land() -> void:
	if _land_box == null:
		return
	for child in _land_box.get_children():
		child.queue_free()
	_land_box.visible = _is_player and not _land_rows.is_empty()
	if not _land_box.visible:
		return
	var caption := Label.new()
	caption.text = "LAND THE TROOPS"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_land_box.add_child(caption)
	for row: Dictionary in _land_rows:
		var invade: bool = bool(row.get("invade", false))
		var label: String = (
			"Invade %s" if invade else "Land at %s"
		) % String(row.get("name", "the coast"))
		var button := _button(label)
		var province: int = int(row.get("province", -1))
		button.pressed.connect(
			func() -> void: action_pressed.emit("land:%d" % province)
		)
		_land_box.add_child(button)


func _fill_yard() -> void:
	for child in _yard_box.get_children():
		child.queue_free()
	var launch := Label.new()
	launch.text = "LAUNCH A HULL"
	launch.add_theme_font_size_override("font_size", 11)
	launch.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_yard_box.add_child(launch)
	for row: Dictionary in _yard_rows:
		_yard_box.add_child(_build_row(row))
	if _fleet == null or not _is_player:
		return
	var breakups := Label.new()
	breakups.text = "BREAK UP A HULL"
	breakups.add_theme_font_size_override("font_size", 11)
	breakups.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_yard_box.add_child(breakups)
	for hull_id: String in _fleet.hulls:
		_yard_box.add_child(_hull_row(hull_id))


func _build_row(row: Dictionary) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	entry.add_child(top)
	var name := _line(13, Palette.TEXT)
	name.text = String(row["name"])
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name)
	var ok: bool = bool(row["ok"])
	var launch := _button("Launch")
	launch.custom_minimum_size = Vector2(84, 40)
	launch.add_theme_font_size_override("font_size", 12)
	launch.disabled = not ok
	launch.tooltip_text = String(row["cost_text"]) if ok else String(row["reason"])
	var type_id: String = String(row["type_id"])
	launch.pressed.connect(func() -> void: action_pressed.emit("yard:build:%s" % type_id))
	top.add_child(launch)
	var detail := _line(10, Color(0.74, 0.68, 0.55, 0.75))
	detail.text = String(row["cost_text"]) if ok else String(row["reason"])
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(detail)
	return entry


func _hull_row(hull_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := _line(13, Palette.TEXT)
	name.text = ShipStats.display_name(_fleet.type_of(hull_id))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var armed: bool = _armed_hull == hull_id
	var scrap := _button("Confirm scrap" if armed else "Break up")
	scrap.custom_minimum_size = Vector2(100, 40)
	scrap.add_theme_font_size_override("font_size", 12)
	scrap.tooltip_text = "One peasant returns; no refund." if armed else "Break up this hull"
	scrap.pressed.connect(func() -> void: _on_scrap_pressed(hull_id))
	row.add_child(scrap)
	return row


## First tap arms and relabels, the second confirms (DR-20261109-01).
func _on_scrap_pressed(hull_id: String) -> void:
	if _armed_hull == hull_id:
		_clear_arm()
		action_pressed.emit("yard:scrap:%s" % hull_id)
		return
	_armed_hull = hull_id
	_fill_yard()
	if _arm_timer != null:
		_arm_timer.start()


func _clear_arm() -> void:
	if _armed_hull.is_empty():
		return
	_armed_hull = ""
	if _arm_timer != null:
		_arm_timer.stop()
	if _yard_open:
		_fill_yard()


func _line(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _small_button(text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(40, 40)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	return button
