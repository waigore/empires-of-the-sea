class_name FleetMissionSection
extends FleetDossierSection
## The fleet dossier's mission block: the current station note, the order the
## court's own admiral would give her this turn, and one button per station or
## hostile coast the squadron could take (wiki: ships-and-naval § Missions and
## Movement, DR-20261120-04). Emits intents; the rules modules own validation.

var _pick: Label = null


func _ready() -> void:
	_setup("MISSIONS")
	# The court's pick sits under the station note and above the presses, in the
	# gold the crew's own pick prints in: advice, never state (REQ-P5-06).
	_pick = UiRowBuilder.line(12, Palette.GOLD)
	_pick.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_pick)
	move_child(_pick, _note.get_index() + 1)


## Empty data hides the block: a fresh squadron has no landing duty yet. The pick
## is a reading — a squadron the court would leave alone carries none. `coast`
## is the hostile coast the pick would mark (the expedition's beachhead,
## DR-20261122-20): its row leads with the counsel's mark and the caption prints
## the legend, so the coast the line names is found on the page it is pressed on.
func set_data(note: String, rows: Array[Dictionary], pick: String = "", coast: int = -1) -> void:
	visible = not note.is_empty() or not rows.is_empty() or not pick.is_empty()
	_begin(note)
	_pick.text = pick
	_pick.visible = not pick.is_empty()
	var marked: bool = false
	for row: Dictionary in rows:
		var province: int = int(row.get("province", -1))
		var court: bool = coast != -1 and province == coast
		marked = marked or court
		_add_row(
			String(row.get("label", "Mark %s" % String(row.get("name", "the coast")))),
			String(row.get("action", "beachhead:%d" % province)),
			court
		)
	_set_caption_legend(marked)
