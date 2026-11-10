class_name CourtReportsPanel
extends VBoxContainer
## A shadowed court's despatch, kept after its toast has gone (wiki:
## civilian-units § Spy — court reports). Presented only: [MapPlaySpies] builds
## the lines and the session keeps them, so the panel reads no hidden value
## (REQ-P2-03, REQ-P5-02).

const QUIET_LINE: String = "The court did nothing worth a despatch this turn."


func _init() -> void:
	add_theme_constant_override("separation", 3)


## `reports` is the session's kept despatch: `turn`, `shadowed` courts and the
## `lines` each one left. A court without a Spy has no section at all.
func fill(subject: int, reports: Dictionary) -> void:
	_clear()
	var shadowed: Array = reports.get("shadowed", []) as Array
	if not shadowed.has(subject):
		return
	add_child(
		_label(
			"COURT REPORTS  ·  %s" % DiplomacyHistory.stamp_for_turn(int(reports.get("turn", 0))),
			Palette.TEXT_DIM
		)
	)
	var kept: Dictionary = reports.get("lines", {}) as Dictionary
	var lines: Array = kept.get(subject, []) as Array
	if lines.is_empty():
		add_child(_label(QUIET_LINE, Palette.TEXT_DIM))
		return
	for raw: Variant in lines:
		var label := _label(String(raw), Palette.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	return label


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
