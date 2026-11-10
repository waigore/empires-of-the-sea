class_name CourtTrade
extends VBoxContainer
## THE COURT's trade block: what this court's standing does to our world-market
## prices, then the trade orders in one place (wiki: world-market § FTP,
## § Subsidy price adjustment; diplomacy § GP–Tribe — Boycott). Presentation
## only — buttons emit intents and the rules layer decides (REQ-P2-03).

signal order_pressed(kind: String, target: int, arg: String)

var _target: int = -1


func fill(
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	target: int,
	options: Array[Dictionary]
) -> void:
	_target = target
	UiRowBuilder.clear(self)
	if options.is_empty():
		return
	add_theme_constant_override("separation", 6)
	add_child(_caption("TRADE TERMS"))
	if state != null:
		_add_summary(state, world, player, target)
	for option: Dictionary in options:
		_add_option(option)


## Plain sentences, never multipliers the player has to decode: what we pay,
## what we earn, and which pact, subsidy or boycott caused it.
func _add_summary(
	state: DiplomacyState, world: WorldMap, player: int, target: int
) -> void:
	var terms: Dictionary = DiplomacyTrade.terms_for_court(state, world, player)
	var buy: Dictionary = terms.get("buy", {})
	var sell: Dictionary = terms.get("sell", {})
	add_child(
		_label(
			"Our merchants buy at %d%% and sell at %d%% of the world price."
			% [roundi(float(buy.get("*", 1.0)) * 100.0), roundi(float(sell.get("*", 1.0)) * 100.0)],
			12, Palette.TEXT
		)
	)
	var percent: int = state.subsidy(player, target)
	if percent > 0:
		add_child(
			_label(
				"Subsidy %d%% to %s: their goods cost us %d%% more; ours earn %d%% less among them."
				% [percent, FactionCatalog.name_of(target), percent, percent],
				12, Palette.GOLD_PALE
			)
		)
	if DiplomacyTrade.is_ftp(state, player, target):
		add_child(
			_label(
				"Favoured trading pact: our lots clear first in their ports.",
				12, Palette.GOLD_PALE
			)
		)
	if DiplomacyTrade.is_boycotting(state, player, target):
		add_child(
			_label(
				"Our colonies are closed to %s: their market terms worsen 10%%."
				% FactionCatalog.name_of(target),
				12, Color(0.85, 0.62, 0.42)
			)
		)
	var boycotts: Array[int] = DiplomacyTrade.boycotts_against(state, player)
	if not boycotts.is_empty():
		var names: PackedStringArray = []
		for issuer: int in boycotts:
			names.append(FactionCatalog.name_of(issuer))
		add_child(
			_label(
				"Boycotted by %s: our market terms worsen 10%%." % ", ".join(names),
				12, Color(0.85, 0.62, 0.42)
			)
		)


func _add_option(option: Dictionary) -> void:
	var cost: String = String(option.get("cost_text", ""))
	var text: String = String(option["label"])
	if bool(option.get("active", false)):
		text = "✓ %s" % text
	if not cost.is_empty():
		text = "%s  ·  %s" % [text, cost]
	var button := _button(text)
	button.disabled = not bool(option["ok"])
	var kind: String = String(option["kind"])
	var arg: String = String(option.get("arg", ""))
	button.pressed.connect(func() -> void: order_pressed.emit(kind, _target, arg))
	add_child(button)
	if not bool(option["ok"]):
		add_child(_label(String(option["reason"]), 11, Color(0.80, 0.63, 0.45, 0.9)))
		return
	var hint: String = String(option.get("hint", ""))
	if not hint.is_empty():
		add_child(_label(hint, 11, Palette.TEXT_DIM))


func _caption(text: String) -> Label:
	return _label(text, 11, Palette.TEXT_DIM)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(240, 0)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_size_override("font_size", 13)
	return button
