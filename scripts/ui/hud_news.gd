class_name HudNews
extends RefCounted
## The court's transient news: despatch toasts and the Quick Battle plate queue.
## A plate covers the court for seconds, so news raised under it waits for the
## last plate to close instead of expiring unread (REQ-P5-05, REQ-P5-06).

## A turn cannot bury the court in plates: the newest despatches are the ones its
## orders produced, so the oldest lines go first (REQ-P5-06).
const PENDING_CAP: int = 6
## How long a despatch holds the lane; a loss with a medallion is read, not
## mistaken for the turn's chatter (REQ-P5-05, DR-20261110-22).
const HOLD: float = 2.8
const HOLD_MEDALLION: float = 4.4

var host: Control = null
var box: VBoxContainer = null
var plate: QuickBattleOverlay = null
## Despatches raised while a battle plate covers the court.
var pending: PackedStringArray = PackedStringArray()
## Battles the rules resolved for the human, replayed one plate at a time.
var battles: Array[Dictionary] = []


func bind(hud: Control, toast_box: VBoxContainer, battle_plate: QuickBattleOverlay) -> void:
	host = hud
	box = toast_box
	plate = battle_plate


## A despatch toast. `icon_name` raises the plate with a medallion (an
## auto-resolved siege's silenced battery) and holds it longer.
func toast(text: String, icon_name: String = "") -> void:
	# The observer hides the human chrome; building toast plates for a hidden
	# court would only churn nodes every turn (REQ-P4-04).
	if host == null or not host.visible:
		return
	# A battle plate covers the whole court: a despatch raised under it is
	# neither readable nor still alive when it closes (REQ-P5-06, REQ-P2-03).
	if is_battle_shown():
		if pending.size() >= PENDING_CAP:
			pending.remove_at(0)
		pending.append(text)
		return
	var panel: PanelContainer = _plate(text, icon_name)
	box.add_child(panel)
	_fade(panel, HOLD if icon_name.is_empty() else HOLD_MEDALLION)


func show_battle(battle: Dictionary, province: String) -> void:
	if plate == null:
		return
	if plate.is_shown():
		battles.append({"battle": battle, "province": province})
		return
	plate.show_battle(battle, province, FactionCatalog.names())


func is_battle_shown() -> bool:
	return plate != null and plate.is_shown()


## A plate closes: the next battle of the turn takes the court, or the news the
## turn raised while the fighting played finally reaches it, in its own order.
func on_battle_finished() -> void:
	if not battles.is_empty():
		var next: Dictionary = battles.pop_front()
		plate.show_battle(next["battle"], String(next["province"]), FactionCatalog.names())
		return
	var waiting: PackedStringArray = pending
	pending = PackedStringArray()
	for held: String in waiting:
		toast(held)


func _plate(text: String, icon_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var accent: Color = Palette.GOLD if icon_name.is_empty() else Palette.CRIMSON
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.95), accent, 1, 3, Vector4(18, 8, 18, 8))
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15 if icon_name.is_empty() else 16)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	if icon_name.is_empty():
		panel.add_child(label)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var medallion := TextureRect.new()
		medallion.texture = ChromeIcons.texture(icon_name)
		medallion.custom_minimum_size = Vector2(26.0, 26.0)
		medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(medallion)
		row.add_child(label)
		panel.add_child(row)
	panel.modulate.a = 0.0
	return panel


func _fade(panel: PanelContainer, hold: float) -> void:
	var tween := host.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(hold)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
