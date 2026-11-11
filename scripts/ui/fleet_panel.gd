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

var _header: DossierHeader = null
var _location: Label = null
var _ships: Label = null
var _status: Label = null
var _hint: Label = null
var _merge_box: VBoxContainer = null
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
var _strength: FleetStrengthSection = null


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

	_header = DossierHeader.make(20)
	_header.dock_pressed.connect(func() -> void: dock_side_pressed.emit())
	_header.close_pressed.connect(func() -> void: close_pressed.emit())
	column.add_child(_header)

	_location = UiRowBuilder.line(15, Palette.TEXT)
	column.add_child(_location)

	_ships = UiRowBuilder.line(13, Palette.TEXT_DIM)
	_ships.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_ships)

	_strength = FleetStrengthSection.new()
	column.add_child(_strength)

	_status = UiRowBuilder.line(13, Palette.GOLD_PALE)
	column.add_child(_status)

	# The home-fleet merge: one button when the squadron can join now; the note
	# rides the status line so the sheet never grows (wiki: ships-and-naval).
	_merge_box = VBoxContainer.new()
	_merge_box.add_theme_constant_override("separation", 4)
	_merge_box.visible = false
	column.add_child(_merge_box)

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

	_yard_button = UiRowBuilder.button("Shipyard", 36.0, 0.0)
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

	_hint = UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _header != null:
		_header.set_dock_affordance(glyph, tip)


## Opens or closes the yard without rebuilding the dossier.
func set_yard_open(open: bool) -> void:
	_yard_open = open and _yard_button.visible
	_yard_button.text = "Close shipyard" if _yard_open else "Shipyard"
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
	crew: Dictionary = {},
	strength: Dictionary = {},
	merge: Dictionary = {}
) -> void:
	if model == null or fleet == null:
		return
	_fleet = fleet
	_is_player = is_player
	_yard_rows = yard_rows
	_land_rows = land_rows
	_header.flag.color = Palette.faction_color(fleet.owner)
	_header.title.text = "FLEET OF %s" % FactionCatalog.name_of(fleet.owner).to_upper()
	if fleet.is_at_sea():
		_location.text = "At sea · %s" % model.sea_zone_name(fleet.sea_zone)
	else:
		_location.text = "In port · %s" % model.province_name(fleet.province)
	_ships.text = "%d ships · %s · upkeep %d food" % [
		fleet.ship_count(), fleet.hull_summary(), ShipEconomy.food_upkeep_for_fleet(fleet)
	]
	# A home fleet's holds are the reason to merge into her: show them here.
	if bool(merge.get("home", false)):
		_ships.text += " · %s" % String(merge.get("holds_text", ""))
	_strength.set_data(strength)
	_fill_merge(merge)
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
		_status.text = "On station"
		_hint.text = beach_note
	elif fleet.moved:
		_status.text = "Has moved this turn"
		_hint.text = "End the turn to sail again."
	elif bool(merge.get("home", false)):
		_status.text = "Home fleet"
		_hint.text = "She keeps the port; a squadron docking here joins her."
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
	# The merge note rides the status row and its button takes the yard's place,
	# so the dossier never grows past a phone's sheet (REQ-P1-05).
	var merge_note: String = String(merge.get("note", ""))
	if not merge_note.is_empty() and _status.text == "1 move this turn":
		_status.text = merge_note
	_yard_button.visible = is_player and not yard_rows.is_empty() \
		and not bool(merge.get("ok", false))
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
	_header.flag.color = Palette.faction_color(FactionCatalog.PLAYER_FACTION)
	_header.title.text = "SHIPYARD OF %s" % FactionCatalog.name_of(
		FactionCatalog.PLAYER_FACTION
	).to_upper()
	_location.text = "At %s · capital port" % model.province_name(province_id)
	_ships.text = "No home fleet — your first launch founds one."
	_strength.set_data({})
	_status.text = "The yard is open"
	_hint.text = "Launch a hull to found the home fleet; break up hulls from the fleet dossier."
	_land_rows = []
	_fill_merge({})
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


## The home-fleet row: one tap when the squadron can join. Nothing destructive,
## so no confirm (DR-20261109-01); the note rides the status line above.
func _fill_merge(merge: Dictionary) -> void:
	for child in _merge_box.get_children():
		child.queue_free()
	_merge_box.visible = bool(merge.get("ok", false))
	if not _merge_box.visible:
		return
	var button := UiRowBuilder.button(
		String(merge.get("label", "Join the home fleet")), 36.0, 0.0
	)
	button.pressed.connect(func() -> void: action_pressed.emit("join_home"))
	_merge_box.add_child(button)


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
		var button := UiRowBuilder.button(label, 36.0, 0.0)
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
	var name := UiRowBuilder.line(13, Palette.TEXT)
	name.text = String(row["name"])
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name)
	var ok: bool = bool(row["ok"])
	var launch := UiRowBuilder.button("Launch", 36.0, 0.0)
	launch.custom_minimum_size = Vector2(84, 40)
	launch.add_theme_font_size_override("font_size", 12)
	launch.disabled = not ok
	launch.tooltip_text = String(row["cost_text"]) if ok else String(row["reason"])
	var type_id: String = String(row["type_id"])
	launch.pressed.connect(func() -> void: action_pressed.emit("yard:build:%s" % type_id))
	top.add_child(launch)
	var detail := UiRowBuilder.line(10, Color(0.74, 0.68, 0.55, 0.75))
	detail.text = String(row["cost_text"]) if ok else String(row["reason"])
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(detail)
	return entry


func _hull_row(hull_id: String) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	entry.add_child(row)
	var type_id: String = _fleet.type_of(hull_id)
	var hull_name: String = ShipNames.of(_fleet, hull_id)
	var name := UiRowBuilder.line(13, Palette.TEXT)
	name.text = (
		"%s — %s" % [hull_name, ShipStats.display_name(type_id)]
		if not hull_name.is_empty()
		else ShipStats.display_name(type_id)
	)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var armed: bool = _armed_hull == hull_id
	var scrap := UiRowBuilder.button("Confirm scrap" if armed else "Break up", 36.0, 0.0)
	scrap.custom_minimum_size = Vector2(100, 40)
	scrap.add_theme_font_size_override("font_size", 12)
	scrap.tooltip_text = (
		"Break up %s: one peasant returns; no refund." % hull_name
		if armed and not hull_name.is_empty()
		else ("One peasant returns; no refund." if armed else "Break up this hull")
	)
	scrap.pressed.connect(func() -> void: _on_scrap_pressed(hull_id))
	row.add_child(scrap)
	# The hull's own combat numbers, so a breaking up is a reasoned choice.
	var stats := UiRowBuilder.line(10, Color(0.74, 0.68, 0.55, 0.75))
	stats.text = NavalStrength.hull_line(type_id)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(stats)
	return entry


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
