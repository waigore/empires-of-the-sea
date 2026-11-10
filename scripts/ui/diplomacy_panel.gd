class_name DiplomacyPanel
extends PanelContainer
## The court: one row per known crown, with relation stand, overture chain,
## the orders that court will entertain and the pair's chronicle (wiki:
## diplomacy). Presentation only — buttons emit intents and the rules layer
## decides (REQ-P2-03).

signal order_pressed(kind: String, target: int, arg: String)
signal close_pressed

## Section headings for the order list; trade terms render in their own block
## so prices and pacts stay one glance away (REQ-P5-02).
const GROUP_LABELS: Dictionary = {
	DiplomacyOrders.GROUP_ORDERS: "COURT ORDERS",
	DiplomacyOrders.GROUP_TREATIES: "TREATIES",
	DiplomacyOrders.GROUP_AID: "AID",
}

var _state: DiplomacyState = null
var _world: WorldMap = null
var _player: int = FactionCatalog.PLAYER_FACTION
var _treasury: int = 0
var _tech: Dictionary = {}
var _selected: int = -1
var _last_group: String = ""
var _list: VBoxContainer = null
var _detail: VBoxContainer = null
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
	_summary = _label("", 13, Palette.TEXT_DIM)
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
	var title := _label("THE COURT", 24, Palette.GOLD_PALE)
	title.add_theme_font_override("font", UiTheme.serif())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _small_button("Close")
	close.pressed.connect(func() -> void: close_pressed.emit())
	header.add_child(close)
	return header


func _list_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(212, 0)
	column.add_child(_caption("CROWNS & TRIBES"))
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
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	scroll.add_child(_detail)
	return scroll


func _footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	var hint := _label(
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
	court_reports: Dictionary = {}
) -> void:
	_state = state
	_world = world
	_player = player
	_treasury = treasury
	_tech = tech
	_court_reports = court_reports
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
	_fill_detail()


func selected_faction() -> int:
	return _selected


func select_faction(faction_id: int) -> void:
	if _state == null or not _state.has_relation(_player, faction_id):
		return
	_selected = faction_id
	refresh(_state, _world, _player, _treasury, _tech, _court_reports)


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
	_clear(_list)
	for faction_id: int in ids:
		var record: DiplomacyRelation = _state.relation(_player, faction_id)
		var button := Button.new()
		button.text = "%s\n%s" % [
			FactionCatalog.name_of(faction_id), _status_line(faction_id, record)
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 46)
		button.add_theme_font_size_override("font_size", 13)
		if faction_id == _selected:
			button.add_theme_stylebox_override(
				"normal", UiTheme.box(Color(0.27, 0.22, 0.16), Palette.GOLD, 1, 3, Vector4(8, 4, 8, 4))
			)
			button.add_theme_color_override("font_color", Palette.GOLD_PALE)
		button.pressed.connect(func() -> void: select_faction(faction_id))
		_list.add_child(button)


func _fill_detail() -> void:
	_clear(_detail)
	if _selected < 0:
		_detail.add_child(_label("No court has received an envoy.", 15, Palette.TEXT_DIM))
		return
	var record: DiplomacyRelation = _state.relation(_player, _selected)
	var name_label := _label(FactionCatalog.name_of(_selected), 24, Palette.GOLD_PALE)
	name_label.add_theme_font_override("font", UiTheme.serif())
	_detail.add_child(name_label)
	_detail.add_child(
		_label(
			"%s  ·  %s"
			% [
				FactionCatalog.type_label(FactionCatalog.type_of(_selected)),
				FactionCatalog.region_label(FactionCatalog.region_of(_selected)),
			],
			12,
			Palette.TEXT_DIM
		)
	)
	var status := _label(_status_line(_selected, record), 15, _status_color(_selected, record))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(status)
	_detail.add_child(_meter(record.score))
	_detail.add_child(_label("Herald: %s" % record.meter_label(), 13, Palette.TEXT))
	_add_envoy()
	_detail.add_child(_label(_overture_line(_selected), 13, Palette.TEXT))
	_detail.add_child(_caption("COURT ORDERS"))
	var options: Array[Dictionary] = DiplomacyOrders.options(
		_state, _world, _treasury, _player, _selected, _tech
	)
	_last_group = DiplomacyOrders.GROUP_ORDERS
	var trade_options: Array[Dictionary] = []
	for option: Dictionary in options:
		if String(option.get("group", "")) == DiplomacyOrders.GROUP_TRADE:
			trade_options.append(option)
			continue
		var group: String = String(option.get("group", DiplomacyOrders.GROUP_ORDERS))
		if group != _last_group:
			_last_group = group
			_detail.add_child(_caption(String(GROUP_LABELS.get(group, "COURT ORDERS"))))
		_add_option(option)
	if not trade_options.is_empty():
		var trade := CourtTrade.new()
		trade.fill(_state, _world, _player, _selected, trade_options)
		trade.order_pressed.connect(
			func(kind: String, target: int, arg: String) -> void:
				order_pressed.emit(kind, target, arg)
		)
		_detail.add_child(trade)
	_add_chronicle()
	# The despatch is news like the chronicle, so it sits above the dossier's
	# analysis (wiki: civilian-units § Spy — court reports; REQ-P5-02).
	var reports := CourtReportsPanel.new()
	reports.fill(_selected, _court_reports)
	_detail.add_child(reports)
	# The dossier sits under the chronicle: analysis after the news, so choice
	# stays first and bookkeeping follows (wiki: ai-dossier; REQ-P5-02).
	var dossier := CourtDossier.new()
	dossier.fill(_state, _world, _player, _selected)
	# The summary's one door: the full sheet opens on the court in view
	# (REQ-P5-01, DR-20261110-25).
	dossier.open_pressed.connect(
		func() -> void:
			if dossier_screen != null and _selected >= 0:
				dossier_screen.show_for(_state, _world, _player, _selected)
	)
	_detail.add_child(dossier)


## The court's own word under its herald line: the newest voiced act between the
## pair, else its standing remark, with the face it wears (wiki:
## dialogue-and-mood; REQ-P1-07). Presentation only — the reader is never the
## speaker (REQ-P2-03).
func _add_envoy() -> void:
	var spoken: Dictionary = DialogueEvents.for_pair(_state, _player, _selected)
	if spoken.is_empty():
		return
	var face: String = DialogueMood.label(String(spoken["mood"])).to_upper()
	_detail.add_child(_caption("THEIR ENVOY  ·  %s" % face))
	var words := _label("“%s”" % String(spoken["text"]), 14, Palette.GOLD_PALE)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(words)


## The pair's chronicle sits under the orders: choice first, bookkeeping after
## (wiki: diplomacy § Diplomatic History; REQ-P5-02).
func _add_chronicle() -> void:
	var chronicle := CourtHistory.new()
	chronicle.fill(_state, _player, _selected)
	_detail.add_child(chronicle)


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


func _add_option(option: Dictionary) -> void:
	var cost: String = String(option.get("cost_text", ""))
	var text: String = String(option["label"])
	if bool(option.get("active", false)):
		text = "✓ %s" % text
	if not cost.is_empty():
		text = "%s  ·  %s" % [text, cost]
	var button := _small_button(text)
	button.disabled = not bool(option["ok"])
	var kind: String = String(option["kind"])
	var arg: String = String(option.get("arg", ""))
	button.pressed.connect(func() -> void: order_pressed.emit(kind, _selected, arg))
	_detail.add_child(button)
	if not bool(option["ok"]):
		var reason := _label(String(option["reason"]), 11, Color(0.80, 0.63, 0.45, 0.9))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(reason)
		return
	var hint: String = String(option.get("hint", ""))
	if not hint.is_empty():
		var note := _label(hint, 11, Palette.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(note)


func _status_line(faction_id: int, record: DiplomacyRelation) -> String:
	var parts: PackedStringArray = [record.meter_label(), DiplomacyCatalog.state_label(record.at_war)]
	if record.formal_alliance:
		parts.append("Formal Alliance")
	if DiplomacyTrade.is_ftp(_state, _player, faction_id):
		parts.append("Trade Pact")
	if DiplomacyTrade.is_boycotting(_state, _player, faction_id):
		parts.append("Boycott")
	var colony_of: int = _state.colony_of(faction_id)
	if colony_of >= 0:
		parts.append("Colony of %s" % FactionCatalog.name_of(colony_of))
	return "  ·  ".join(parts)


func _status_color(_faction_id: int, record: DiplomacyRelation) -> Color:
	if record.at_war:
		return Color(0.85, 0.38, 0.32)
	if record.formal_alliance:
		return Color(0.58, 0.78, 0.52)
	return Palette.TEXT


func _overture_line(faction_id: int) -> String:
	var stage: String = _state.overture(_player, faction_id)
	var next: String = DiplomacyCatalog.next_stage(stage)
	var line: String = "Overture: %s" % DiplomacyCatalog.stage_label(stage)
	if not next.is_empty():
		line += "  ·  next: %s" % DiplomacyCatalog.stage_label(next)
	return line


func _meter(score: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var active: int = DiplomacyCatalog.meter_step(score)
	for step in range(1, 11):
		var block := Panel.new()
		block.custom_minimum_size = Vector2(18, 12)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: float = float(step - 1) / 9.0
		var color: Color = Color.from_hsv(lerpf(0.0, 0.33, t), 0.62, 0.78)
		if step > active:
			color = Color(0.24, 0.20, 0.15, 0.65)
		block.add_theme_stylebox_override("panel", UiTheme.box(color, color, 1, 2, Vector4.ZERO))
		row.add_child(block)
	return row


func _caption(text: String) -> Label:
	return _label(text, 11, Palette.TEXT_DIM)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()
