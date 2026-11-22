class_name FleetPanel
extends PanelContainer
## Dockable dossier for the selected fleet: colours, station, the remaining move
## and the naval yard (wiki: ships-and-naval § Ship build economy, § Ship muster
## and the breaker's yard). The panel owns the header, the standing lines and the
## merge block; orders under them scroll so a phone sheet never grows past its
## dock (REQ-P1-05). FleetYardBlock owns the shipyard drawer, FleetDossierSection
## subclasses the mission and passenger blocks. The panel reads state and emits
## intents; the rules modules decide what may run (REQ-P3-02, REQ-P3-03).

signal close_pressed
signal dock_side_pressed
signal action_pressed(action: String)

var _header: DossierHeader = null
var _location: Label = null
var _ships: Label = null
var _status: Label = null
var _hint: Label = null
var _merge_box: VBoxContainer = null
var _yard: FleetYardBlock = null
var _fleet: FleetState = null
var _is_player: bool = false
var _land_box: VBoxContainer = null
var _land_rows: Array[Dictionary] = []
var _mission: FleetMissionSection = null
var _crew: FleetCrewSection = null
var _strength: FleetStrengthSection = null
var _split: FleetSplitBlock = null
var _combine: FleetCombineBlock = null
var _scroll: ScrollContainer = null


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
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# Orders scroll under the standing lines so a phone sheet never grows past
	# its dock (REQ-P1-05): missions, passengers, split, combine and the yard.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	_scroll.add_child(body)

	# Every block emits the same intent, so one wire carries them all up.
	_mission = FleetMissionSection.new()
	_mission.visible = false
	_mission.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	body.add_child(_mission)

	_crew = FleetCrewSection.new()
	_crew.visible = false
	_crew.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	body.add_child(_crew)

	_land_box = VBoxContainer.new()
	_land_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_land_box.add_theme_constant_override("separation", 6)
	_land_box.visible = false
	body.add_child(_land_box)

	# The split drawer: one hull leaves as a squadron of her own (DR-20261116-12).
	_split = FleetSplitBlock.new()
	_split.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	body.add_child(_split)

	# The combine drawer: this squadron folds into another of the crown's in the
	# same station (DR-20261116-13).
	_combine = FleetCombineBlock.new()
	_combine.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	body.add_child(_combine)

	_yard = FleetYardBlock.new()
	_yard.action_pressed.connect(func(action: String) -> void: action_pressed.emit(action))
	body.add_child(_yard)

	_hint = UiRowBuilder.line(11, Color(0.74, 0.68, 0.55, 0.75))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint)

	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


## Cap the orders scroll to the sheet's room so the standing lines stay put and
## a phone never clips the dossier (REQ-P1-05, REQ-P1-07).
func _fit_to_viewport() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var view: Vector2 = get_viewport_rect().size
	if view.y < 1.0:
		return
	var compact: bool = HudLayout.is_compact(view)
	var top: float = 64.0 if compact else PanelDock.TOP
	var bottom: float = 10.0 if compact else absf(PanelDock.BOTTOM)
	var room: float = maxf(view.y - top - bottom, 0.0)
	var chrome: float = get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	_scroll.custom_minimum_size = Vector2(0.0, maxf(room - chrome, 0.0))


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _header != null:
		_header.set_dock_affordance(glyph, tip)


## Opens or closes the yard without rebuilding the dossier.
func set_yard_open(open: bool) -> void:
	if _yard != null:
		_yard.set_open(open)


## Repaints the selected squadron from one named opening (REQ-P3-02).
func refresh(model: MapModel, opening: FleetDossierOpening) -> void:
	if model == null or opening.fleet == null:
		return
	var fleet: FleetState = opening.fleet
	var is_player: bool = opening.is_player
	var strength: Dictionary = opening.strength
	var merge: Dictionary = opening.merge
	var carried: int = opening.carried
	_fleet = fleet
	_is_player = is_player
	_land_rows = opening.land_rows
	_header.flag.color = Palette.faction_color(fleet.owner)
	_header.title.text = "FLEET OF %s" % FactionCatalog.name_of(fleet.owner).to_upper()
	if fleet.is_at_sea():
		_location.text = "At sea · %s" % model.sea_zone_name(fleet.sea_zone)
	else:
		_location.text = "In port · %s" % model.province_name(fleet.province)
	_ships.text = _muster_line(fleet, is_player, strength)
	# A home fleet's holds are the reason to merge into her: show them here.
	if bool(merge.get("home", false)):
		_ships.text += " · %s" % String(merge.get("holds_text", ""))
	_strength.set_data(strength)
	_fill_merge(merge)
	if carried > 0:
		_ships.text += " · carrying %d regiment%s" % [carried, "" if carried == 1 else "s"]
	var colonists: int = int(opening.crew.get("count", 0))
	if colonists > 0:
		_ships.text += " · %d colonist%s" % [colonists, "" if colonists == 1 else "s"]
	_fill_land()
	_mission.set_data(opening.beach_note, opening.beach_rows, opening.pick, opening.court_coast)
	_crew.set_data(opening.crew)
	_set_standing(
		fleet, is_player, opening.passage, opening.beach_note, opening.beach_hint,
		merge, carried, colonists
	)
	_show_split(model, fleet, is_player)
	_show_combine(model, opening.roster, fleet, is_player)
	_show_yard(opening.yard_rows, merge, opening.yard_pick)
	_fit_to_viewport()


## The composition line under the title: count, hull types and the upkeep they
## eat. A rival the crown has sighted but not read keeps her muster to herself —
## no count, no types, no bill — while the map's hull badge stays off her marker
## (wiki: ships-and-naval § Sighted strength).
func _muster_line(fleet: FleetState, is_player: bool, strength: Dictionary) -> String:
	if not is_player and not bool(strength.get("known", true)):
		return "??? hulls — the fog has not yet given up her muster."
	return "%d %s · %s · upkeep %d food" % [
		fleet.ship_count(), "ship" if fleet.ship_count() == 1 else "ships",
		fleet.hull_summary(), ShipEconomy.food_upkeep_for_fleet(fleet)
	]


## The status and hint lines: what the squadron may still do this turn. One
## branch per reason the player cannot give a plain order (REQ-P1-07).
func _set_standing(
	fleet: FleetState,
	is_player: bool,
	passage: String,
	beach_note: String,
	beach_hint: String,
	merge: Dictionary,
	carried: int,
	colonists: int
) -> void:
	if not is_player:
		_status.text = "Enemy colours · no orders"
		_hint.text = "Observe only. Orders require your own fleet."
	elif not beach_note.is_empty():
		_status.text = "On station"
		# The mission block above names the site; this line says what it costs.
		_hint.text = beach_hint
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


## The yard drawer takes the launch rows; a join on offer hides its toggle.
## A refresh keeps the drawer as the player left it, never re-opening it. `pick`
## is the court's own claim, kept whole so the drawer marks the hull it names
## (DR-20261121-02, DR-20261122-12).
func _show_yard(
	yard_rows: Array[Dictionary], merge: Dictionary, pick: Dictionary = {}
) -> void:
	if _yard == null:
		return
	_yard.show_rows(_fleet, yard_rows, _is_player, _yard.is_open(), pick)
	_yard.set_offer_join(bool(merge.get("ok", false)))


## The split drawer: every hull with the tap that detaches her. It stays where
## the player left it, so a repaint never closes the list under a finger.
func _show_split(model: MapModel, fleet: FleetState, is_player: bool) -> void:
	if _split == null:
		return
	_split.show_rows(model, fleet, is_player, _split.is_open())


## The combine drawer: every other squadron in this station with the tap that
## folds this one into her. It stays where the player left it, too.
func _show_combine(
	model: MapModel, roster: Array[FleetState], fleet: FleetState, is_player: bool
) -> void:
	if _combine == null:
		return
	_combine.show_rows(model, roster, fleet, is_player, _combine.is_open())


## The crown's capital yard with no squadron afloat: the first launch founds the
## home fleet, so the dossier still has to list what can be built. `pick` is the
## hull the court's own yard means to lay (DR-20261121-02).
func refresh_slip(
	model: MapModel, province_id: int, rows: Array[Dictionary], is_player: bool,
	pick: Dictionary = {}
) -> void:
	if model == null:
		return
	_fleet = null
	_is_player = is_player
	# The yard belongs to the crown that holds the province, not to the legacy
	# default: a court sailing as England reads her own name over her slip
	# (wiki: game-setup § Human/AI slot assignment; REQ-P2-03).
	var crown: int = model.province_owner(province_id)
	if crown == MapModel.NO_ID:
		crown = FactionCatalog.PLAYER_FACTION
	_header.flag.color = Palette.faction_color(crown)
	_header.title.text = "SHIPYARD OF %s" % FactionCatalog.name_of(crown).to_upper()
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
	if _split != null:
		_split.show_rows(model, null, false, false)
	if _combine != null:
		_combine.show_rows(model, [] as Array[FleetState], null, false, false)
	if _yard != null:
		_yard.show_slip(rows, is_player, pick)
	_fit_to_viewport()


## The home-fleet row: one tap when the squadron can join. Nothing destructive,
## so no confirm (DR-20261109-01); the note rides the status line above.
func _fill_merge(merge: Dictionary) -> void:
	UiRowBuilder.clear(_merge_box)
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
	UiRowBuilder.clear(_land_box)
	_land_box.visible = _is_player and not _land_rows.is_empty()
	if not _land_box.visible:
		return
	var caption := UiRowBuilder.line(11, Palette.TEXT_DIM)
	caption.text = "LAND THE TROOPS"
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


## The yard's break-up arm lives in FleetYardBlock; kept so callers that name
## the dossier still reach it (tests read the arm through the dossier).
func _on_scrap_pressed(hull_id: String) -> void:
	if _yard != null:
		_yard.on_scrap_pressed(hull_id)
