class_name DiplomacyPanel
extends LedgerFrame
## The court: one row per known crown, with relation stand, overture chain,
## the orders that court will entertain and the pair's chronicle (wiki:
## diplomacy). The open court's sheet lives on CourtDetailBlock; this shell
## owns the crown list, consent lane and body (REQ-P3-01). Presentation only
## — buttons emit intents and the rules layer decides (REQ-P2-03). The sheet,
## masthead and phone profile are LedgerFrame's (REQ-P3-01).

signal order_pressed(kind: String, target: int, arg: String)
## The sheets one press from the court: its eyes, the crowns they shadow
## (DR-20261115-10), and the colonies those courts hold, whose suzerain's
## boycott a crown reads there (DR-20261117-02). Each press names its sheet by
## the HUD's door key.
signal door_pressed(key: String)

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
var _list_column_box: VBoxContainer = null
## The open court's sheet; tests and callers still reach this as `_detail`.
var _detail: CourtDetailBlock = null
var _summary: Label = null
var _call_box: VBoxContainer = null
var _body: HBoxContainer = null
## Last resolved turn's spy despatch (wiki: civilian-units § Spy — court
## reports). Read-only here; the session keeps it.
var _court_reports: Dictionary = {}
## The full dossier sheet this summary opens, set by the HUD that builds both.
var dossier_screen: CourtDossierScreen = null


func _init() -> void:
	title_text = "THE COURT"


## The court's medallion: the same gold crest the cartouche carries.
func _build_crest() -> Control:
	return Icon.new("crest", CREST_PIXELS, Palette.GOLD)


## Phone geometry: the court keeps its two columns but sheds the masthead bulk,
## the standing line and the footer hint so the crown list and the detail keep
## the sheet's height (REQ-P1-07). The masthead and hint are LedgerFrame's.
func _apply_profile(compact: bool) -> void:
	if _summary != null:
		_summary.visible = not compact
	if _list_column_box != null:
		_list_column_box.custom_minimum_size = Vector2(156 if compact else 212, 0)
	if _body != null:
		_body.add_theme_constant_override("separation", 8 if compact else 14)


func _build_body(column: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	_summary = UiRowBuilder.label("", 13, Palette.TEXT_DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_summary)
	# The court's eyes: the intelligence reading sits one press from the crowns
	# it shadows, and stays on a phone where the summary line folds away.
	var eyes := UiRowBuilder.button("EYES ›", 30.0, 78.0, 12)
	eyes.tooltip_text = "The crown's spies, the courts they shadow and the screen (I)"
	eyes.pressed.connect(func() -> void: door_pressed.emit(HudLedgerDoors.EYES))
	head.add_child(eyes)
	# The colonies the courts hold: the boycott a crown issues is read on the
	# colony it shuts, so the sheet sits beside the eyes (DR-20261117-02).
	var colonies := UiRowBuilder.button("COLONIES ›", 30.0, 96.0, 12)
	colonies.tooltip_text = "Every colony, the court that bought it and what bars its trade"
	colonies.pressed.connect(func() -> void: door_pressed.emit(HudLedgerDoors.COLONIES))
	head.add_child(colonies)
	_call_box = VBoxContainer.new()
	_call_box.add_theme_constant_override("separation", 6)
	column.add_child(_call_box)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)
	_body = body
	body.add_child(_list_column())
	body.add_child(_detail_column())
	_make_hint("The relation score stays sealed; only the herald's word is shown.")


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
	_list_column_box = column
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
		% [ids.size(), MoneyText.plural(ids.size()), DiplomacyCatalog.money(treasury)]
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
		# The court's own arms, then its name and stand: a list of twenty courts
		# is a list of shields first, so a crown finds a court by sight and not by
		# reading every name (REQ-P1-07, REQ-P1-08; DR-20261118-30).
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(FactionCrest.of(faction_id))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
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
		column.add_child(button)
		CourtRows.decorate(column, faction_id, _power, _player)
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
