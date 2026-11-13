class_name HudStatChips
extends RefCounted
## The cartouche's status plaques: treasury and its net income, ships, civilians
## and troops. TopBar builds the widgets; this owns their state and the copy they
## speak, so GameHud only routes (REQ-P1-02, REQ-P1-05).

var host: Control = null
var treasury_chip: Button = null
var fleet_chip: Button = null
var civilian_chip: Button = null
var army_chip: Button = null
var treasury_label: Label = null
var income_label: Label = null
var fleet_label: Label = null
var civilian_label: Label = null
var army_label: Label = null

var _treasury_value: int = 0
var _income_value: int = 0


## TopBar hands over one chip per plaque: {"root", "value", "delta"}.
func bind(
	hud: Control,
	treasury: Dictionary,
	fleets: Dictionary,
	civilians: Dictionary,
	troops: Dictionary
) -> void:
	host = hud
	treasury_chip = treasury["root"]
	treasury_label = treasury["value"]
	income_label = treasury["delta"]
	fleet_chip = fleets["root"]
	fleet_label = fleets["value"]
	civilian_chip = civilians["root"]
	civilian_label = civilians["value"]
	army_chip = troops["root"]
	army_label = troops["value"]


func set_treasury(value: int, animate: bool = true) -> void:
	if treasury_label == null:
		return
	var from: int = _treasury_value
	_treasury_value = value
	_refresh_treasury_tooltip()
	# A purse below zero is a debt, and the techs decided how deep it may go
	# (wiki: tech-tree-labour-economy § money_lending, banking). Crimson keeps the
	# chip from reading like any other balance (REQ-P5-05).
	treasury_label.add_theme_color_override(
		"font_color", Palette.CRIMSON if value < 0 else Palette.TEXT
	)
	if not animate or host == null:
		treasury_label.text = TextFormat.thousands(value)
		return
	var tween := host.create_tween()
	tween.tween_method(
		func(step: float) -> void:
			treasury_label.text = TextFormat.thousands(int(round(step))),
		float(from), float(value), 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Net treasury movement per turn, shown beside the treasury count so the player
## reads solvency without opening the ledger. Zero is dim, not a fake gain.
func set_income(value: int) -> void:
	_income_value = value
	if income_label == null:
		return
	income_label.text = TextFormat.delta(value)
	income_label.add_theme_color_override(
		"font_color",
		Palette.TEXT_DIM if value == 0 else (
			Palette.GOLD_PALE if value > 0 else Palette.CRIMSON.lerp(Color.WHITE, 0.35)
		)
	)
	_refresh_treasury_tooltip()


func set_fleets(value: int) -> void:
	if fleet_label == null:
		return
	fleet_label.text = str(value)
	if fleet_chip != null:
		fleet_chip.tooltip_text = "Ships — %d · find the next squadron" % value


func set_civilians(value: int) -> void:
	if civilian_label == null:
		return
	civilian_label.text = str(value)
	if civilian_chip != null:
		civilian_chip.tooltip_text = (
			"Civilians — %d · open the empire roster (C)" % value
		)


func set_armies(value: int) -> void:
	if army_label == null:
		return
	army_label.text = str(value)
	if army_chip != null:
		army_chip.tooltip_text = "Troops — %d regiments · find the next army" % value


## The turn's coin movement lifts off the treasury plaque, so a gain reads as an
## event and not a silent repaint (REQ-P5-05).
func flash_income(amount: int) -> void:
	if host == null or treasury_chip == null:
		return
	var label := Label.new()
	label.text = "+%s" % TextFormat.thousands(amount)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(label)
	label.position = treasury_chip.get_global_rect().position + Vector2(0, 4)
	var tween := host.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


## Estates and college only — the world market clears after them (world-market).
## A negative purse is named as debt, so a crown in the lending floor's shadow
## reads why it cannot fund a study (REQ-P5-05).
func _refresh_treasury_tooltip() -> void:
	if treasury_chip == null:
		return
	treasury_chip.tooltip_text = "Treasury %s%s · %s per turn before the auction — open the ledger" % [
		TextFormat.thousands(_treasury_value),
		" (in debt)" if _treasury_value < 0 else "",
		TextFormat.delta(_income_value),
	]
