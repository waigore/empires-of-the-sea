class_name CourtReportsPanel
extends VBoxContainer
## A shadowed court's despatch, kept after its toast has gone (wiki:
## civilian-units § Spy — court reports). Presented only: [MapPlaySpyReports]
## builds the lines and the session keeps them, so the panel reads no hidden
## value (REQ-P2-03, REQ-P5-02).

const QUIET_LINE: String = "The court did nothing worth a despatch this turn."


func _init() -> void:
	add_theme_constant_override("separation", 3)


## `reports` is the session's kept despatch: `turn`, `shadowed` courts and the
## `lines` each one left. A court without a Spy has no section at all.
func fill(subject: int, reports: Dictionary) -> void:
	UiRowBuilder.clear(self)
	var shadowed: Array = reports.get("shadowed", []) as Array
	if not shadowed.has(subject):
		return
	add_child(
		UiRowBuilder.caption(
			"COURT REPORTS  ·  %s" % DiplomacyHistory.stamp_for_turn(int(reports.get("turn", 0))),
			12,
			Palette.TEXT_DIM
		)
	)
	var kept: Dictionary = reports.get("lines", {}) as Dictionary
	var lines: Array = kept.get(subject, []) as Array
	if lines.is_empty():
		add_child(UiRowBuilder.caption(QUIET_LINE, 12, Palette.TEXT_DIM))
		return
	for raw: Variant in lines:
		add_child(UiRowBuilder.wrapped_line(String(raw), 12, Palette.TEXT))
