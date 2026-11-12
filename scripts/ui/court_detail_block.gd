class_name CourtDetailBlock
extends VBoxContainer
## THE COURT's selected-crown column: herald stand, overture, orders, trade,
## chronicle, spy despatch and dossier summary. Lifted out of DiplomacyPanel so
## the shell keeps the crown list and consent lane while this block owns only
## the open court's sheet (REQ-P3-01). Presentation only — buttons emit intents
## and the rules layer decides (REQ-P2-03, REQ-P3-02).

signal order_pressed(kind: String, target: int, arg: String)
signal dossier_open_pressed(faction_id: int)

## Section headings for the order list; trade terms render in their own block
## so prices and pacts stay one glance away (REQ-P5-02).
const GROUP_LABELS: Dictionary = {
	DiplomacyOrders.GROUP_ORDERS: "COURT ORDERS",
	DiplomacyOrders.GROUP_TREATIES: "TREATIES",
	DiplomacyOrders.GROUP_AID: "AID",
}


## Rebuilds the open court's sheet for the selected faction.
func fill(
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	selected: int,
	treasury: int,
	tech: Dictionary,
	court_reports: Dictionary,
	power: Dictionary
) -> void:
	UiRowBuilder.clear(self)
	add_theme_constant_override("separation", 8)
	if selected < 0:
		add_child(_label("No court has received an envoy.", 15, Palette.TEXT_DIM))
		return
	var record: DiplomacyRelation = state.relation(player, selected)
	var name_label := _label(FactionCatalog.name_of(selected), 24, Palette.GOLD_PALE)
	name_label.add_theme_font_override("font", UiTheme.serif())
	add_child(name_label)
	var kind: String = FactionCatalog.type_label(FactionCatalog.type_of(selected))
	var land: String = FactionCatalog.region_label(FactionCatalog.region_of(selected))
	add_child(_label("%s  ·  %s" % [kind, land], 12, Palette.TEXT_DIM))
	var status := _label(
		status_line(state, player, selected, record),
		15,
		status_color(record)
	)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	add_child(_meter(record.score))
	add_child(_label("Herald: %s" % record.meter_label(), 13, Palette.TEXT))
	var mark: Dictionary = CourtRows.line(power, player, selected)
	if not mark.is_empty():
		add_child(_label(CourtRows.detail_text(mark), 13, mark["color"] as Color))
	_add_envoy(state, player, selected)
	add_child(_label(overture_line(state, player, selected), 13, Palette.TEXT))
	add_child(_caption("COURT ORDERS"))
	_add_orders(state, world, player, selected, treasury, tech)
	_add_chronicle(state, player, selected)
	# The despatch is news like the chronicle, so it sits above the dossier's
	# analysis (wiki: civilian-units § Spy — court reports; REQ-P5-02).
	var reports := CourtReportsPanel.new()
	reports.fill(selected, court_reports)
	add_child(reports)
	# The dossier sits under the chronicle: analysis after the news, so choice
	# stays first and bookkeeping follows (wiki: ai-dossier; REQ-P5-02).
	var dossier := CourtDossier.new()
	dossier.fill(state, world, player, selected)
	# The summary's one door: the full sheet opens on the court in view
	# (REQ-P5-01, DR-20261110-25).
	dossier.open_pressed.connect(
		func() -> void: dossier_open_pressed.emit(selected)
	)
	add_child(dossier)


## Relation stand for a court row or the open sheet: herald word, war state,
## alliance, trade pact, boycott and colony — never the raw score (REQ-P5-02).
static func status_line(
	state: DiplomacyState, player: int, faction_id: int, record: DiplomacyRelation
) -> String:
	var parts: PackedStringArray = [record.meter_label(), DiplomacyCatalog.state_label(record.at_war)]
	if record.formal_alliance:
		parts.append("Formal Alliance")
	if DiplomacyTrade.is_ftp(state, player, faction_id):
		parts.append("Trade Pact")
	if DiplomacyTrade.is_boycotting(state, player, faction_id):
		parts.append("Boycott")
	var colony_of: int = state.colony_of(faction_id)
	if colony_of >= 0:
		parts.append("Colony of %s" % FactionCatalog.name_of(colony_of))
	return "  ·  ".join(parts)


static func status_color(record: DiplomacyRelation) -> Color:
	if record.at_war:
		return Color(0.85, 0.38, 0.32)
	if record.formal_alliance:
		return Color(0.58, 0.78, 0.52)
	return Palette.TEXT


static func overture_line(state: DiplomacyState, player: int, faction_id: int) -> String:
	var stage: String = state.overture(player, faction_id)
	var next: String = DiplomacyCatalog.next_stage(stage)
	var line: String = "Overture: %s" % DiplomacyCatalog.stage_label(stage)
	if not next.is_empty():
		line += "  ·  next: %s" % DiplomacyCatalog.stage_label(next)
	return line


## The court's own word under its herald line: the newest voiced act between the
## pair, else its standing remark, with the face it wears (wiki:
## dialogue-and-mood; REQ-P1-07). Presentation only — the reader is never the
## speaker (REQ-P2-03).
func _add_envoy(state: DiplomacyState, player: int, selected: int) -> void:
	var spoken: Dictionary = DialogueEvents.for_pair(state, player, selected)
	if spoken.is_empty():
		return
	var face: String = DialogueMood.label(String(spoken["mood"])).to_upper()
	add_child(_caption("THEIR ENVOY  ·  %s" % face))
	var words := _label("“%s”" % String(spoken["text"]), 14, Palette.GOLD_PALE)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)


## The pair's chronicle sits under the orders: choice first, bookkeeping after
## (wiki: diplomacy § Diplomatic History; REQ-P5-02).
func _add_chronicle(state: DiplomacyState, player: int, selected: int) -> void:
	var chronicle := CourtHistory.new()
	chronicle.fill(state, player, selected)
	add_child(chronicle)


func _add_orders(
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	selected: int,
	treasury: int,
	tech: Dictionary
) -> void:
	var options: Array[Dictionary] = DiplomacyOrders.options(
		state, world, treasury, player, selected, tech
	)
	var last_group: String = DiplomacyOrders.GROUP_ORDERS
	var trade_options: Array[Dictionary] = []
	for option: Dictionary in options:
		if String(option.get("group", "")) == DiplomacyOrders.GROUP_TRADE:
			trade_options.append(option)
			continue
		var group: String = String(option.get("group", DiplomacyOrders.GROUP_ORDERS))
		if group != last_group:
			last_group = group
			add_child(_caption(String(GROUP_LABELS.get(group, "COURT ORDERS"))))
		_add_option(option, selected)
	if trade_options.is_empty():
		return
	var trade := CourtTrade.new()
	trade.fill(state, world, player, selected, trade_options)
	trade.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			order_pressed.emit(kind, target, arg)
	)
	add_child(trade)


func _add_option(option: Dictionary, selected: int) -> void:
	var cost: String = String(option.get("cost_text", ""))
	var text: String = String(option["label"])
	if bool(option.get("active", false)):
		text = "✓ %s" % text
	if not cost.is_empty():
		text = "%s  ·  %s" % [text, cost]
	var button := UiRowBuilder.button(text, 36.0, 0.0)
	button.disabled = not bool(option["ok"])
	var kind: String = String(option["kind"])
	var arg: String = String(option.get("arg", ""))
	button.pressed.connect(func() -> void: order_pressed.emit(kind, selected, arg))
	add_child(button)
	if not bool(option["ok"]):
		var reason := _label(String(option["reason"]), 11, Color(0.80, 0.63, 0.45, 0.9))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(reason)
		return
	var hint: String = String(option.get("hint", ""))
	if not hint.is_empty():
		var note := _label(hint, 11, Palette.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(note)


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
	return UiRowBuilder.label(text, size, color)
