class_name CourtReportsPanel
extends VBoxContainer
## The despatch a shadowed court's turn leaves with the crown's spy (wiki:
## civilian-units § Spy — court reports). Presented only: [CourtReports] filters
## the facts, masks the names and caps the lines, so the panel never reads a
## hidden value (REQ-P2-03, REQ-P1-07). Hidden until a Spy watches this court.


func _init() -> void:
	add_theme_constant_override("separation", 3)


## `reports` is the resolved turn's dispatch: `turn`, `shadowed` and `facts`.
func fill(
	state: DiplomacyState,
	world: WorldMap,
	viewer: int,
	subject: int,
	reports: Dictionary
) -> void:
	_clear()
	var shadowed: Array = reports.get("shadowed", []) as Array
	if not shadowed.has(subject):
		return
	var turn: int = int(reports.get("turn", 0))
	add_child(_caption("COURT REPORTS  ·  %s" % DiplomacyHistory.stamp_for_turn(turn)))
	var lines: Array[String] = CourtReports.digest(
		reports.get("facts", []), state, world, viewer, subject
	)
	if lines.is_empty():
		add_child(_line("The court did nothing worth a despatch this turn.", Palette.TEXT_DIM))
		return
	for text: String in lines:
		var label := _line(text, Palette.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)


func _caption(text: String) -> Label:
	return _line(text, Palette.TEXT_DIM)


func _line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	return label


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
