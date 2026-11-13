class_name ResearchSlotRow
extends HBoxContainer
## One research slot in the college ledger, kept alive between repaints
## (REQ-P1-05 — the gold a study costs is on the line it costs it; REQ-P3-02).
##
## The panel owns one row per slot and only rewrites it. A funding change, a
## treasury change or a repaint therefore never rebuilds the sheet: the gauge
## grows from where it stood, and the button the player pressed keeps its place.

signal cancel_pressed(slot: int)
signal funding_pressed(slot: int)

const ROW_HEIGHT: float = 56.0
const IDLE_HEIGHT: float = 40.0
const ICON_SIZE: float = 30.0
const BUTTON_HEIGHT: float = 40.0
const COIN_SIZE: float = 13.0

## Slot index this row draws; set once, so its signals carry it back.
var slot: int = 0

var _idle: Label = null
var _body: HBoxContainer = null
var _icon_host: Control = null
var _icon_tech: String = ""
var _name: Label = null
var _coin: TextureRect = null
var _spend: Label = null
var _spies: Label = null
var _funding: Button = null
var _cancel: Button = null
var _bar: ResearchBar = null
var _progress: Label = null
var _next: Label = null

var _gold_next: int = 0
var _rp_next: int = 0
## True when the Research phase cannot pay this slot at its preset next turn.
var _unpaid: bool = false


func _init(index: int) -> void:
	slot = index
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	_idle = _label("Slot %d — idle" % (index + 1), 14, Palette.TEXT_DIM)
	_idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_idle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_idle)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_icon_host = Control.new()
	_icon_host.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_body.add_child(_icon_host)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(column)
	column.add_child(_head())
	column.add_child(_foot())


## Rewrites the row from live research state. `boost` maps tech id -> spy-network
## percent, so the row can name the share a shadowed court hands over
## (DR-20261110-03). `leader` is the crown's leaderKey, whose published funding
## multiplier the next-turn RP already includes (leader-bonuses — Victoria).
func update(
	state: ResearchState, boost: Dictionary, treasury: int, leader: String = "",
	animate: bool = true
) -> void:
	var tech_id: String = state.tech_at(slot)
	var idle: bool = tech_id.is_empty()
	_idle.visible = idle
	_body.visible = not idle
	custom_minimum_size = Vector2(0.0, IDLE_HEIGHT if idle else ROW_HEIGHT)
	_gold_next = 0
	_rp_next = 0
	_unpaid = false
	if idle:
		_bar.set_progress(0, 1, 0, true, false)
		return
	if tech_id != _icon_tech:
		_icon_tech = tech_id
		_fill_icon(tech_id)
	var funding: String = state.funding_at(slot)
	var plan: Dictionary = ResearchTurn.preview(
		state, tech_id, funding, treasury, SpyNetworks.boost_for(boost, tech_id), leader
	)
	_gold_next = int(plan["gold"])
	_rp_next = int(plan["rp"])
	_unpaid = not bool(plan["paid"])
	var cost: int = int(plan["cost"])
	var banked: int = int(plan["progress"])
	_name.text = TechCatalog.display_name(tech_id)
	_name.tooltip_text = TechCatalog.effect_text(tech_id)
	_spend.text = "%s ducats" % TextFormat.thousands(_gold_next)
	_spend.add_theme_color_override(
		"font_color", Palette.GOLD if _gold_next > 0 else Palette.TEXT_DIM
	)
	_spend.tooltip_text = _spend_tip()
	_coin.modulate.a = 1.0 if _gold_next > 0 else 0.35
	_funding.text = ResearchFunding.label(funding)
	_funding.tooltip_text = _spend_tip()
	var spies: int = int(plan["boost"])
	_spies.visible = spies > 0
	_spies.text = "+%d%%" % spies
	_spies.tooltip_text = (
		"Spy network: +%d%% research points from the rival courts it shadows"
		% spies
	)
	_bar.set_progress(banked, cost, _rp_next, bool(plan["paid"]), animate)
	_progress.text = "%s / %s RP" % [
		TextFormat.thousands(banked), TextFormat.thousands(cost),
	]
	_fill_next(banked, cost, bool(plan["paid"]), state.treasury_floor())


## Ducats the slot spends next turn, and points it buys (0 for an idle slot).
func gold_next() -> int:
	return _gold_next


## True when the treasury cannot pay this slot at its preset next turn.
func unpaid_next() -> bool:
	return _unpaid


func rp_next() -> int:
	return _rp_next


func bar() -> ResearchBar:
	return _bar


# --- construction ------------------------------------------------------------


func _head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_name = _label("", 14, Palette.TEXT)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	head.add_child(_name)
	var cost := HBoxContainer.new()
	cost.add_theme_constant_override("separation", 4)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coin = TextureRect.new()
	_coin.texture = ChromeIcons.texture("coin")
	_coin.custom_minimum_size = Vector2(COIN_SIZE, COIN_SIZE)
	_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_child(_coin)
	_spend = _label("", 12, Palette.GOLD)
	_spend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_child(_spend)
	head.add_child(cost)
	_spies = _label("", 12, Palette.GOLD)
	_spies.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spies.visible = false
	head.add_child(_spies)
	_funding = _button("")
	_funding.custom_minimum_size = Vector2(96, BUTTON_HEIGHT)
	_funding.pressed.connect(func() -> void: funding_pressed.emit(slot))
	head.add_child(_funding)
	_cancel = _button("Cancel")
	_cancel.custom_minimum_size = Vector2(74, BUTTON_HEIGHT)
	_cancel.tooltip_text = "Abandon the study; all progress is lost"
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit(slot))
	head.add_child(_cancel)
	return head


func _foot() -> HBoxContainer:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	_bar = ResearchBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_bar)
	_progress = _label("", 12, Palette.TEXT)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_progress)
	_next = _label("", 11, Palette.GOLD_PALE)
	_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_next)
	return foot


func _fill_icon(tech_id: String) -> void:
	for child in _icon_host.get_children():
		_icon_host.remove_child(child)
		child.queue_free()
	_icon_host.add_child(ResearchRow.icon(tech_id, ICON_SIZE))


## The preview line: what the next phase adds and where it leaves the study.
## An unpaid slot says so in crimson rather than implying a gain it cannot pay
## for (wiki: tech-tree § Research Model — no partial funding), and its tooltip
## names the borrowing floor that stops it, so the crown never reads a rule as a
## broken purse (REQ-P5-05).
func _fill_next(banked: int, cost: int, paid: bool, floor: int) -> void:
	if not paid:
		_next.text = "unpaid next turn"
		_next.add_theme_color_override("font_color", Palette.CRIMSON)
		_next.tooltip_text = "The treasury cannot cover this slot next turn — %s." % (
			LedgerText.research_floor_line(floor)
		)
		return
	if _rp_next <= 0:
		_next.text = "earns nothing"
		_next.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_next.tooltip_text = "No funding buys no research points."
		return
	var lands: int = mini(banked + _rp_next, cost)
	_next.text = "+%s → %s" % [
		TextFormat.thousands(_rp_next), TextFormat.thousands(lands),
	]
	_next.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_next.tooltip_text = "%s research points next turn, %s of %s met" % [
		TextFormat.thousands(_rp_next), TextFormat.thousands(lands),
		TextFormat.thousands(cost),
	]


func _spend_tip() -> String:
	if _gold_next <= 0:
		return "This slot buys no research points this turn"
	return "%s ducats buys %s research points each turn" % [
		TextFormat.thousands(_gold_next), TextFormat.thousands(_rp_next),
	]


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	return button
