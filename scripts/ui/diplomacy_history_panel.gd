class_name CourtHistory
extends VBoxContainer
## The selected court's chronicle, under its orders (wiki: diplomacy
## § Diplomatic History). Presentation only: the lines come from
## [DiplomacyHistory], newest first with a calendar stamp, so the panel never
## re-derives an outcome and never prints a locked relation score
## (REQ-P1-07, REQ-P2-03).

const WAR_KINDS: Array[String] = ["warDeclared", "overturesCleared", "allianceBroken"]
const AMITY_KINDS: Array[String] = ["peaceMade", "allianceFormed", "callToArmsAccepted"]
const WAR_INK: Color = Color(0.86, 0.52, 0.42)
const AMITY_INK: Color = Color(0.62, 0.78, 0.56)


func _init() -> void:
	add_theme_constant_override("separation", 3)


func fill(state: DiplomacyState, viewer: int, other: int) -> void:
	_clear()
	add_child(_label("CHRONICLE", 11, Palette.TEXT_DIM))
	var entries: Array[Dictionary] = DiplomacyHistory.entries(state, viewer, other)
	if entries.is_empty():
		add_child(_line("No word of this court has been written yet.", 13, Palette.TEXT_DIM))
		return
	for entry: Dictionary in entries:
		add_child(_line(_row_text(entry), 13, _ink_for(String(entry["kind"]))))


static func _row_text(entry: Dictionary) -> String:
	return "%s  ·  %s" % [
		DiplomacyHistory.stamp_for_turn(int(entry["turn"])), String(entry["text"])
	]


static func _ink_for(kind: String) -> Color:
	if WAR_KINDS.has(kind):
		return WAR_INK
	if AMITY_KINDS.has(kind):
		return AMITY_INK
	return Palette.TEXT


func _line(text: String, size: int, ink: Color) -> Label:
	var label := _label(text, size, ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(text: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	return label


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
