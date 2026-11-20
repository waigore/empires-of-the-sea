class_name ResearchSlotRow
extends HBoxContainer
## One research slot in the college ledger, kept alive between repaints
## (REQ-P1-05 — the gold a study costs is on the line it costs it; REQ-P3-02).
##
## The panel owns one row per slot and only rewrites it. A funding change, a
## treasury change or a repaint therefore never rebuilds the sheet: the gauge
## grows from where it stood, and the button the player pressed keeps its place.
##
## The row paints a `ResearchSlotPrice` and keeps no arithmetic of its own: the
## walk prices the turn, the price says which words read it, and the row puts
## them on its widgets (REQ-P2-03, REQ-P3-03).

signal cancel_pressed(slot: int)
signal funding_pressed(slot: int)

const ROW_HEIGHT: float = 56.0
const IDLE_HEIGHT: float = 40.0
const ICON_SIZE: float = 30.0
const BUTTON_HEIGHT: float = 40.0
const COIN_SIZE: float = 13.0

## Slot index this row draws; set once, so its signals carry it back.
var slot: int = 0
## Phone rows trade height for list room; the buttons keep their thumb size.
var _compact: bool = false
var _idle_now: bool = true
## What the row last painted, so a test reads the slot without walking widgets.
var _price: ResearchSlotPrice = ResearchSlotPrice.new()

var _idle: Label = null
var _pick: Label = null
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


func _init(index: int) -> void:
	slot = index
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	_idle = UiRowBuilder.label("Slot %d — idle" % (index + 1), 14, Palette.TEXT_DIM)
	_idle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_idle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_idle)
	# The court's own pick for this slot, in the gold the crew's sheet and the
	# army dossier give theirs (wiki: tech-tree § Research model; DR-20261121-01).
	# One line, trimmed with an ellipsis, so a handset's idle row keeps the height
	# it always had and the sheet's fit never pays for the advice (REQ-P1-07).
	_pick = UiRowBuilder.label("", 12, Palette.GOLD)
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pick.clip_text = true
	_pick.visible = false
	add_child(_pick)
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


## Rewrites the row from one `ResearchSlotPrice` — the walk's priced turn, so
## the row, the heading and the Research phase price one turn (REQ-P2-03).
## `counsel` is the study the court would open in this slot, printed on an idle
## row only (DR-20261121-01).
func update(price: ResearchSlotPrice, counsel: String = "", animate: bool = true) -> void:
	_price = price
	var idle: bool = price.is_idle()
	_idle_now = idle
	_idle.visible = idle
	_body.visible = not idle
	_pick.visible = idle and not counsel.is_empty()
	_pick.text = counsel if idle else ""
	_apply_height()
	if idle:
		if _bar != null:
			_bar.set_progress(0, 1, 0, true, false)
		return
	if price.tech != _icon_tech:
		_icon_tech = price.tech
		_fill_icon(price.tech)
	_name.text = TechCatalog.display_name(price.tech)
	_name.tooltip_text = TechCatalog.effect_text(price.tech)
	_spend.text = "%s ducats" % TextFormat.thousands(price.gold)
	_spend.add_theme_color_override(
		"font_color", Palette.GOLD if price.gold > 0 else Palette.TEXT_DIM
	)
	_spend.tooltip_text = price.spend_tip()
	_coin.modulate.a = 1.0 if price.gold > 0 else 0.35
	_funding.text = ResearchFunding.label(price.funding)
	_funding.tooltip_text = price.spend_tip()
	_spies.visible = price.boost > 0
	_spies.text = "+%d%%" % price.boost
	_spies.tooltip_text = price.boost_tip()
	_bar.set_progress(price.progress, price.cost, price.rp, price.paid, animate)
	_progress.text = "%s / %s RP" % [
		TextFormat.thousands(price.progress), TextFormat.thousands(price.cost),
	]
	_next.text = price.next_text()
	_next.add_theme_color_override(
		"font_color", Palette.CRIMSON if price.next_warns() else _next_color()
	)
	_next.tooltip_text = price.next_tip()


## Ducats the slot spends next turn, and points it buys (0 for an idle slot).
func gold_next() -> int:
	return _price.gold


func rp_next() -> int:
	return _price.rp


## True when the treasury cannot pay this slot at its preset next turn.
func unpaid_next() -> bool:
	return not _price.paid and not _price.is_idle()


func bar() -> ResearchBar:
	return _bar


## The counsel an idle row carries, or "" — the accessor a test reads instead of
## walking the row's children (REQ-P3-02).
func counsel_text() -> String:
	return _pick.text if _pick.visible else ""


## Phone geometry: a shorter slot row and smaller text, while every button keeps
## its 40-point thumb target (REQ-P1-07).
func set_compact(compact: bool) -> void:
	_compact = compact
	_apply_height()
	_idle.add_theme_font_size_override("font_size", 12 if compact else 14)
	_pick.add_theme_font_size_override("font_size", 11 if compact else 12)
	_name.add_theme_font_size_override("font_size", 13 if compact else 14)
	_spend.add_theme_font_size_override("font_size", 11 if compact else 12)
	_funding.custom_minimum_size = Vector2(84 if compact else 96, BUTTON_HEIGHT)
	_cancel.custom_minimum_size = Vector2(62 if compact else 74, BUTTON_HEIGHT)


# --- construction ------------------------------------------------------------


func _head() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_name = UiRowBuilder.label("", 14, Palette.TEXT)
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
	_spend = UiRowBuilder.label("", 12, Palette.GOLD)
	_spend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.add_child(_spend)
	head.add_child(cost)
	_spies = UiRowBuilder.label("", 12, Palette.GOLD)
	_spies.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spies.visible = false
	head.add_child(_spies)
	_funding = UiRowBuilder.button("", 0.0, 0.0)
	_funding.custom_minimum_size = Vector2(96, BUTTON_HEIGHT)
	_funding.pressed.connect(func() -> void: funding_pressed.emit(slot))
	head.add_child(_funding)
	_cancel = UiRowBuilder.button("Cancel", 0.0, 0.0)
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
	_progress = UiRowBuilder.label("", 12, Palette.TEXT)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_progress)
	_next = UiRowBuilder.label("", 11, Palette.GOLD_PALE)
	_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_next)
	return foot


## The preview line's colour when it names a gain rather than a warning.
func _next_color() -> Color:
	return Palette.TEXT_DIM if _price.silent() else Palette.GOLD_PALE


## An idle row is shorter than a study's, and a phone gives both fewer points.
func _apply_height() -> void:
	var full: float = ROW_HEIGHT
	var idle_height: float = IDLE_HEIGHT
	if _compact:
		full = 46.0
		idle_height = 26.0
	custom_minimum_size = Vector2(0.0, idle_height if _idle_now else full)


func _fill_icon(tech_id: String) -> void:
	for child in _icon_host.get_children():
		_icon_host.remove_child(child)
		child.queue_free()
	_icon_host.add_child(ResearchRow.icon(tech_id, ICON_SIZE))