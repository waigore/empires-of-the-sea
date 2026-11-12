class_name CivilianPanel
extends PanelContainer
## Dossier for a selected civilian: posting, development of its tile, and the
## work orders its type may take (wiki: civilian-units § Work Order Summary).

signal action_pressed(action: String)
signal cancel_pressed
signal close_pressed
signal dock_side_pressed

var _title: Label = null
var _subtitle: Label = null
var _status: Label = null
var _detail: GridContainer = null
var _orders: VBoxContainer = null
var _cancel: Button = null
var _stock_line: Label = null
var _dock: Button = null
## The court reading the sheet. A rival's crew is observe-only and its ground is
## read through this court's survey record (DR-20261111-26).
var _viewer: int = FactionCatalog.PLAYER_FACTION


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	_build()


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(shell)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.serif())
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(_subtitle)

	_detail = GridContainer.new()
	_detail.columns = 2
	_detail.add_theme_constant_override("h_separation", 16)
	_detail.add_theme_constant_override("v_separation", 4)
	column.add_child(_detail)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Palette.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var heading := Label.new()
	heading.text = "WORK ORDERS"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(heading)

	_orders = VBoxContainer.new()
	_orders.add_theme_constant_override("separation", 4)
	column.add_child(_orders)

	_stock_line = Label.new()
	_stock_line.add_theme_font_size_override("font_size", 11)
	_stock_line.add_theme_color_override("font_color", Color(0.74, 0.68, 0.55, 0.7))
	_stock_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_stock_line)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	shell.add_child(footer)

	_cancel = _make_button("Cancel Work")
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	footer.add_child(_cancel)

	_dock = _make_button("◀")
	_dock.tooltip_text = "Dock left"
	# A dock affordance is a glyph, not a titled bar: it must match the other
	# dossiers' corner buttons (REQ-P1-02).
	_dock.custom_minimum_size = Vector2(40, 40)
	_dock.add_theme_font_size_override("font_size", 18)
	_dock.size_flags_horizontal = Control.SIZE_SHRINK_END
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	footer.add_child(_dock)

	var close := _make_button("Close")
	close.pressed.connect(func() -> void: close_pressed.emit())
	footer.add_child(close)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


## `viewer` is the court reading the sheet, which is not always the crew's owner:
## a rival's crew is observe-only, and the dossier must read the ground through
## the *viewer's* survey record (wiki: fog-and-exploration § Prospecting — per
## court; DR-20261111-26). The fleet and army dossiers already split the two.
func refresh(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {},
	viewer: int = FactionCatalog.PLAYER_FACTION
) -> void:
	if unit == null:
		return
	_viewer = viewer
	_title.text = unit.display_name()
	_subtitle.text = "Crown of %s · %s" % [
		FactionCatalog.name_of(unit.owner),
		MapModel.TERRAIN_LABELS.get(
			model.terrain_at(unit.tile.x, unit.tile.y), "Unknown"
		),
	]
	_fill_detail(model, unit, works, context)
	_status.text = _status_text(model, unit)
	_cancel.visible = unit.is_working() and _viewer == unit.owner
	_fill_orders(model, unit, works, units, stockpile, visibility, tech_caps, tech_unlocked, context)
	# The stores line prices our own orders; a rival's sheet has none to price.
	_stock_line.visible = _viewer == unit.owner
	_stock_line.text = "Stores: %d lumber · %d cast iron · %d steel · %d bronze · %d paper" % [
		int(stockpile.get("lumber", 0)),
		int(stockpile.get("castIron", 0)),
		int(stockpile.get("steel", 0)),
		int(stockpile.get("bronze", 0)),
		int(stockpile.get("paper", 0)),
	]


## The ground under the crew, read through the viewer's own survey record: a
## crown standing over a rival's crew learns nothing it has not prospected
## itself (wiki: fog-and-exploration § Prospecting — per court; DR-20261111-26).
func _fill_detail(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary
) -> void:
	_clear(_detail)
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	_add_row("Province", model.province_name(province) if province >= 0 else "—")
	_add_row("Tile", "%d, %d" % [unit.tile.x, unit.tile.y])
	_add_row("Held by", FactionCatalog.name_of(model.owner_at(unit.tile.x, unit.tile.y)))
	if model.is_purchased_tile(unit.tile):
		_add_row("Deed", "Purchased land")
	var resource: int = MineralSurvey.known_resource(
		model, works, _viewer, unit.tile
	)
	if resource >= 0:
		_add_row("Resource", String(MapGenerator.resource_info(resource).get("name", "—")))
	elif MineralSurvey.prospectable(model, unit.tile):
		# A hidden mineral is never named here; the ground itself is the news
		# (wiki: fog-and-exploration § Prospecting; DR-20261111-26).
		_add_row("Resource", "Unsurveyed ground")
	else:
		_add_row("Resource", "None surveyed")
	var development: PackedStringArray = PackedStringArray()
	var level: int = works.improvement_at(model, unit.tile)
	if level > 0:
		development.append(
			ImprovementCatalog.display_name(model.resource_at(unit.tile.x, unit.tile.y), level)
		)
	if works.transport_at(model, unit.tile) >= LandWorks.TRANSPORT_RAIL:
		development.append("Railroad")
	elif works.transport_at(model, unit.tile) >= LandWorks.TRANSPORT_IMPROVED_ROAD:
		development.append("Improved road")
	elif works.transport_at(model, unit.tile) >= LandWorks.TRANSPORT_ROAD:
		development.append("Road")
	if works.has_port(model, unit.tile):
		development.append("Port")
	if works.is_prospected(_viewer, model, unit.tile):
		development.append("Prospected")
	_add_row("Works", " · ".join(development) if not development.is_empty() else "—")
	if unit.type_id == "explorer" and _viewer == unit.owner:
		_add_row("Survey", _survey_text(model, works, unit, province, context))
	var province_data: ProvinceState = model.province_data(province)
	if province_data != null and province_data.is_town_tile(unit.tile):
		_add_row("Town", "Level %d / 4" % province_data.town_level())
	if unit.type_id == SpyNetworks.SPY_TYPE:
		_add_row("Tradecraft", _tradecraft_text(model, unit))


## What an Explorer has left to read here: the survey is the one order whose
## target is not the ground underfoot, so the dossier says how much is left and
## whether this province can be read at all (DR-20261111-26). A Minor or Tribe
## province without a Consulate offers no ground to survey, so the row names the
## gate rather than promising taps the rules would refuse (REQ-P2-03).
func _survey_text(
	model: MapModel,
	works: LandWorks,
	unit: CivilianState,
	province: int,
	context: Dictionary
) -> String:
	var gate: String = CivilianExplorerGates.consulate_refusal(
		model, unit.owner, province, context
	)
	if not gate.is_empty():
		return gate
	var left: int = MineralSurvey.unsurveyed_in_province(
		model, works, unit.owner, province
	).size()
	if left <= 0:
		return "Every prospectable tile here is charted"
	return "%d tile%s still to survey — tap one on the map" % [
		left, "" if left == 1 else "s"
	]


## What the spy's standing actually buys where it stands: a shadowed court only
## shares its research when it is a Great Power (wiki: civilian-units § Spy (2);
## DR-20261110-03), and the counter-espionage screen exists only while the order
## is up (wiki: civilian-units § Spy (3)). A dossier that promised a share from
## a minor court, or a screen from an idle spy, would claim an outcome the rules
## never grant (REQ-P2-03).
func _tradecraft_text(model: MapModel, unit: CivilianState) -> String:
	var host: int = model.owner_at(unit.tile.x, unit.tile.y)
	if host == MapModel.NO_ID:
		return "Unclaimed land — no court to shadow"
	if host == unit.owner:
		if unit.work_action() == SpyRules.WORK_COUNTER:
			# The order costs a spy that could be shadowing a rival for +15% RP,
			# so the dossier names what the screen buys before the court commits
			# (wiki: civilian-units § Spy (3)).
			return (
				"Counter-espionage screen — empire-wide; %d%% a turn to take a"
				+ " rival agent, %d%% to turn one."
			) % [SpyRules.KILL_PCT, SpyRules.DEFECT_PCT]
		return "No screen up — only the counter-espionage order covers your land"
	var name: String = FactionCatalog.name_of(host)
	if FactionCatalog.type_of(host) == FactionCatalog.Type.GREAT_POWER:
		return "Shadows %s — presence reveal, +%d%% RP" % [name, SpyNetworks.BOOST_PERCENT]
	return "Shadows %s — presence reveal only; only Great Powers share research" % name


## A rival's crew answers to its own crown: the sheet says so with the same
## words the fleet and army dossiers use, so no control is offered that the
## rules would refuse (REQ-P2-03, REQ-P5-06).
func _status_text(model: MapModel, unit: CivilianState) -> String:
	if _viewer != unit.owner:
		return "Enemy colours · no orders"
	if not unit.is_working():
		if unit.type_id == SpyNetworks.SPY_TYPE:
			return _spy_status(model, unit)
		return "Idle — choose an order below."
	if unit.work_action() == SpyRules.WORK_COUNTER:
		return "Counter-espionage · ongoing."
	return "%s · %d turn%s left." % [
		CivilianWork.label(unit.work_action()),
		unit.remaining_turns(),
		"" if unit.remaining_turns() == 1 else "s",
	]


## An idle spy is unseen and unscreened: the line says where its trade pays, so
## a court that shares nothing is never sent there twice.
func _spy_status(model: MapModel, unit: CivilianState) -> String:
	var host: int = model.owner_at(unit.tile.x, unit.tile.y)
	if host == MapModel.NO_ID or host == unit.owner:
		return (
			"At large — post it on a rival Great Power's land, or keep it home as a screen."
		)
	var name: String = FactionCatalog.name_of(host)
	if FactionCatalog.type_of(host) == FactionCatalog.Type.GREAT_POWER:
		return "At large — shadowing %s: presence reveal and a research share." % name
	return "At large — shadowing %s: presence reveal only, no research share." % name


func _fill_orders(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {}
) -> void:
	_clear(_orders)
	# Another crown's crew takes no orders from us — the rules refuse every one
	# (MapPlayCivilians.assign_order), so the sheet never offers them.
	if _viewer != unit.owner:
		var note := Label.new()
		note.text = "Observe only. Orders require your own crew."
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Palette.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_orders.add_child(note)
		return
	for option: Dictionary in CivilianWork.options(
		model, unit, works, units, stockpile, visibility, tech_caps, tech_unlocked,
		context
	):
		var action: String = String(option["action"])
		var button := _make_button(
			"%s · %s" % [String(option["label"]), String(option["cost_text"])]
		)
		button.disabled = not bool(option["ok"]) or unit.is_working()
		button.pressed.connect(func() -> void: action_pressed.emit(action))
		_orders.add_child(button)
		if not bool(option["ok"]):
			var reason := Label.new()
			reason.text = String(option["reason"])
			reason.add_theme_font_size_override("font_size", 11)
			reason.add_theme_color_override("font_color", Color(0.80, 0.63, 0.45, 0.9))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_orders.add_child(reason)


func _add_row(caption: String, value: String) -> void:
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 12)
	key.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_detail.add_child(key)
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Palette.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_child(label)


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 14)
	return button
