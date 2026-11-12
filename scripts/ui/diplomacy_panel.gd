class_name DiplomacyPanel
extends PanelContainer
## The court: one row per known crown, with relation stand, overture chain,
## the orders that court will entertain and the pair's chronicle (wiki:
## diplomacy). The open court's sheet lives on CourtDetailBlock; this shell
## owns the crown list, consent lane and chrome (REQ-P3-01). Presentation only
## — buttons emit intents and the rules layer decides (REQ-P2-03).

signal order_pressed(kind: String, target: int, arg: String)
signal close_pressed

var _state: DiplomacyState = null
var _world: WorldMap = null
var _player: int = FactionCatalog.PLAYER_FACTION
var _treasury: int = 0
var _tech: Dictionary = {}
## Public power score per Great Power, from the session's order of battle; empty
## in a fixture that supplies none, which simply shows no power line.
var _power: Dictionary = {}
var _selected: int = -1
var _list: VBoxContainer = null
## The open court's sheet; tests and callers still reach this as `_detail`.
var _detail: CourtDetailBlock = null
var _summary: Label = null
var _call_box: VBoxContainer = null
## Last resolved turn's spy despatch (wiki: civilian-units § Spy — court
## reports). Read-only here; the session keeps it.
var _court_reports: Dictionary = {}
## The full dossier sheet this summary opens, set by the HUD that builds both.
var dossier_screen: CourtDossierScreen = null


func _ready() -> void:
	add_theme_stylebox_override(
		"panel", UiTheme.box(Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD_DIM, 1, 4, Vector4(20, 16, 20, 16))
	)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_header())
	_summary = UiRowBuilder.label("", 13, Palette.TEXT_DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary)
	_call_box = VBoxContainer.new()
	_call_box.add_theme_constant_override("separation", 6)
	root.add_child(_call_box)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	body.add_child(_list_column())
	body.add_child(_detail_column())
	root.add_child(_footer())


func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(Icon.new("crest", 30, Palette.GOLD))
	var title := UiRowBuilder.label("THE COURT", 24, Palette.GOLD_PALE)
	title.add_theme_font_override("font", UiTheme.serif())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UiRowBuilder.button("Close", 36.0, 0.0)
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)
	return header


func _list_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(212, 0)
	column.add_child(UiRowBuilder.label("CROWNS & TRIBES", 11, Palette.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	return column


func _detail_column() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = CourtDetailBlock.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			order_pressed.emit(kind, target, arg)
	)
	_detail.dossier_open_pressed.connect(_on_dossier_open)
	scroll.add_child(_detail)
	return scroll


func _footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	var hint := UiRowBuilder.label(
		"The relation score stays sealed; only the herald's word is shown.", 11, Palette.TEXT_DIM
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	return footer


func refresh(
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	treasury: int,
	tech: Dictionary = {},
	court_reports: Dictionary = {},
	power: Dictionary = {}
) -> void:
	_state = state
	_world = world
	_player = player
	_treasury = treasury
	_tech = tech
	_court_reports = court_reports
	_power = power
	if _list == null or _detail == null:
		return
	var ids: Array[int] = _known_ids()
	if not ids.has(_selected):
		_selected = ids[0] if not ids.is_empty() else -1
	_summary.text = (
		"%d court%s in contact  ·  treasury %s"
		% [ids.size(), "" if ids.size() == 1 else "s", DiplomacyCatalog.money(treasury)]
	)
	_fill_call()
	_fill_list(ids)
	_detail.fill(
		_state, _world, _player, _selected, _treasury, _tech, _court_reports, _power
	)


func selected_faction() -> int:
	return _selected


func select_faction(faction_id: int) -> void:
	if _state == null or not _state.has_relation(_player, faction_id):
		return
	_selected = faction_id
	refresh(_state, _world, _player, _treasury, _tech, _court_reports, _power)


func _known_ids() -> Array[int]:
	var ids: Array[int] = []
	for record: DiplomacyRelation in _state.relations_of(_player):
		ids.append(record.other(_player))
	ids.sort_custom(_sorts_before)
	return ids


func _sorts_before(left: int, right: int) -> bool:
	var left_type: int = FactionCatalog.type_of(left)
	var right_type: int = FactionCatalog.type_of(right)
	if left_type != right_type:
		return left_type < right_type
	return FactionCatalog.name_of(left) < FactionCatalog.name_of(right)


func _fill_list(ids: Array[int]) -> void:
	UiRowBuilder.clear(_list)
	for faction_id: int in ids:
		var record: DiplomacyRelation = _state.relation(_player, faction_id)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var button := Button.new()
		var stand: String = CourtDetailBlock.status_line(_state, _player, faction_id, record)
		button.text = "%s\n%s" % [FactionCatalog.name_of(faction_id), stand]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 46)
		button.add_theme_font_size_override("font_size", 13)
		if faction_id == _selected:
			button.add_theme_stylebox_override(
				"normal", UiTheme.box(Color(0.27, 0.22, 0.16), Palette.GOLD, 1, 3, Vector4(8, 4, 8, 4))
			)
			button.add_theme_color_override("font_color", Palette.GOLD_PALE)
		button.pressed.connect(func() -> void: select_faction(faction_id))
		row.add_child(button)
		CourtRows.decorate(row, faction_id, _power, _player)
		_list.add_child(row)


## A waiting consent decision (call to arms, intervention, rival proposal) sits
## above the ledger until the player answers it. The turn stays suspended
## meanwhile (wiki: diplomacy § Alliances, § Intervention, § GP AI policy).
func _fill_call() -> void:
	if _call_box == null:
		return
	CourtPrompts.fill(
		_call_box,
		_state,
		_player,
		func(kind: String, target: int, _arg: String) -> void:
			order_pressed.emit(kind, target, "")
	)


func _on_dossier_open(faction_id: int) -> void:
	if dossier_screen == null or faction_id < 0 or _state == null:
		return
	dossier_screen.show_for(_state, _world, _player, faction_id)
