class_name CivilianPanel
extends PanelContainer
## Dossier for a selected civilian: posting, development of its tile, and the
## work orders its type may take (wiki: civilian-units § Work Order Summary).
## This sheet composes and emits intents; the ground is read by
## [CivilianPanelDetail] and the standing lines by [CivilianPanelStatus]
## (REQ-P3-01, REQ-P3-03).

signal action_pressed(action: String)
signal cancel_pressed
signal close_pressed
signal dock_side_pressed

var _title: Label = null
var _subtitle: Label = null
var _status: Label = null
## The court's own pick for a crew that waits: the work its planner would give
## it next, in the crown's gold (DR-20261117-06).
var _pick: Label = null
## The one press that follows a pick naming ground the sheet cannot press: the
## estates ledger for an estate, the province dossier for a road (REQ-P5-06).
var _follow: Button = null
## The pick the sheet is printing, so the follow press files its own ground.
var _pick_data: Dictionary = {}
var _detail: GridContainer = null
var _orders: VBoxContainer = null
## How many of the orders the sheet prints can be taken here: an idle crew with
## none has nothing to choose, and the status must say so (REQ-P5-06).
var _legal: int = 0
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

	_pick = Label.new()
	_pick.add_theme_font_size_override("font_size", 13)
	_pick.add_theme_color_override("font_color", Palette.GOLD)
	_pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.visible = false
	# The line and its door share one row: the words take the width, the press
	# keeps a thumb's height (REQ-P1-05, REQ-P1-07).
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 8)
	pick_row.add_child(_pick)
	column.add_child(pick_row)

	_follow = UiRowBuilder.button("Follow", 38.0, 0.0, 13)
	_follow.visible = false
	_follow.pressed.connect(_on_follow)
	pick_row.add_child(_follow)

	column.add_child(_caption("WORK ORDERS"))

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

	_cancel = UiRowBuilder.button("Cancel Work", 38.0, 0.0, 14)
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	footer.add_child(_cancel)

	_dock = UiRowBuilder.button("◀", 38.0, 0.0, 14)
	_dock.tooltip_text = "Dock left"
	# A dock affordance is a glyph, not a titled bar: it must match the other
	# dossiers' corner buttons (REQ-P1-02).
	_dock.custom_minimum_size = Vector2(40, 40)
	_dock.add_theme_font_size_override("font_size", 18)
	_dock.size_flags_horizontal = Control.SIZE_SHRINK_END
	_dock.pressed.connect(func() -> void: dock_side_pressed.emit())
	footer.add_child(_dock)

	var close := UiRowBuilder.button("Close", 38.0, 0.0, 14)
	close.pressed.connect(func() -> void: close_pressed.emit())
	footer.add_child(close)


func set_dock_affordance(glyph: String, tip: String) -> void:
	if _dock == null:
		return
	_dock.text = glyph
	_dock.tooltip_text = tip


## The follow press: the pick's own ground and door, filed as the sheet's action
## so the map keeps one path for every civilian intent (REQ-P3-02).
func _on_follow() -> void:
	if _pick_data.is_empty():
		return
	action_pressed.emit(
		MapPlayCivilianFollow.press(
			int(_pick_data.get("region", -1)),
			_pick_data.get("tile", CivilianState.NO_TILE),
			String(_pick_data.get("action", ""))
		)
	)


## What the door opens, in the sheet's own words: the estates ledger raises an
## estate, the province dossier carries the road and rail controls (REQ-P5-06).
func _follow_tip() -> String:
	if String(_pick_data.get("door", "")) == MapPlayCivilianPick.DOOR_ESTATES:
		return "Open the estates ledger at this ground"
	return "Open the province at this ground"


## `viewer` is the court reading the sheet, which is not always the crew's owner.
## The fleet and army dossiers already split the two.
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
	# The orders are read before the status: a crew with no order it can take
	# says so, rather than pointing the crown at a list of refusals.
	_fill_orders(model, unit, works, units, stockpile, visibility, tech_caps, tech_unlocked, context)
	_status.text = CivilianPanelStatus.text(model, unit, _viewer, _legal)
	_pick_data = context.get("pick", {}) as Dictionary
	_pick.text = CivilianPanelStatus.pick_line(context)
	_pick.visible = not _pick.text.is_empty()
	_follow.visible = not String(_pick_data.get("door", "")).is_empty()
	_follow.tooltip_text = _follow_tip()
	_cancel.visible = unit.is_working() and _viewer == unit.owner
	# The stores line prices our own orders; a rival's sheet has none to price.
	_stock_line.visible = _viewer == unit.owner
	_stock_line.text = "Stores: %d lumber · %d cast iron · %d steel · %d bronze · %d paper" % [
		int(stockpile.get("lumber", 0)),
		int(stockpile.get("castIron", 0)),
		int(stockpile.get("steel", 0)),
		int(stockpile.get("bronze", 0)),
		int(stockpile.get("paper", 0)),
	]


## The ground under the crew, read through the viewer's own survey record.
func _fill_detail(
	model: MapModel, unit: CivilianState, works: LandWorks, context: Dictionary
) -> void:
	UiRowBuilder.clear(_detail)
	for row: Array in CivilianPanelDetail.rows(model, unit, works, context, _viewer):
		_add_row(String(row[0]), String(row[1]))


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
	UiRowBuilder.clear(_orders)
	_legal = 0
	# Another crown's crew takes no orders from us — the rules refuse every one
	# (MapPlayCivilians.assign_order), so the sheet never offers them.
	if _viewer != unit.owner:
		_orders.add_child(
			_note("Observe only. Orders require your own crew.", Palette.TEXT_DIM)
		)
		return
	for option: Dictionary in CivilianWork.options(
		model, unit, works, units, stockpile, visibility, tech_caps, tech_unlocked,
		context
	):
		var action: String = String(option["action"])
		if bool(option["ok"]):
			_legal += 1
		var button := UiRowBuilder.button(
			"%s · %s" % [String(option["label"]), String(option["cost_text"])],
			38.0,
			0.0,
			14
		)
		button.disabled = not bool(option["ok"]) or unit.is_working()
		button.pressed.connect(func() -> void: action_pressed.emit(action))
		_orders.add_child(button)
		# What the order lands, in the crown's gold under the price: the works
		# no ledger prices name their payoff here (REQ-P5-06; DR-20261117-05).
		var preview_text: String = String(option.get("preview_text", ""))
		if not preview_text.is_empty():
			_orders.add_child(_note(preview_text, Palette.GOLD))
		if not bool(option["ok"]):
			_orders.add_child(
				_note(String(option["reason"]), Color(0.80, 0.63, 0.45, 0.9))
			)


func _caption(text: String) -> Label:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", Palette.TEXT_DIM)
	return heading


## A small wrapped aside under a row or an order: the refusal, the payoff, or a
## rival's observe-only note.
func _note(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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
