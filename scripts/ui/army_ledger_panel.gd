class_name ArmyLedgerPanel
extends ForceLedgerSheet
## The crown's army: every regiment the crown fields in both charts, read
## standard by standard — its class, its stat line, the condition it holds and
## the colours it wears (wiki: military-armies § The regiments behind an army;
## DR-20261116-16). The projection lives in [ArmyLedger]; this sheet only names
## its words and asks MapPlayForceLedger to jump to a regiment's standard
## (REQ-P3-02, REQ-P3-03). The sheet chrome, fade and pause-door park come from
## SheetFrame; the chips, rows, headings and empty notice from ForceLedgerSheet.


func _init() -> void:
	title_text = "THE CROWN'S ARMY"
	mark_legend = "A ▸ marks the standards the court would order this turn."
	hint_text = (
		"Visit opens the standard's chart and dossier. The sheet reads every "
		+ "regiment as it stands; it never musters, detaches or dismisses one."
	)
	# The gold line's reading is the panel's own method, not a closure handed in
	# from the session: a bound callable cannot outlive the session it reads
	# (DR-20261121-14).
	counsel_source = _read_counsel


## The orders the court's own staff would give its standards this turn, read off
## the sheet's bound session (wiki: military-armies § The army sheet names the
## orders the court would give; DR-20261121-14). The pick also keys the standards
## it names, so their headings wear the counsel's mark (DR-20261122-05).
func _read_counsel(data: Dictionary) -> Dictionary:
	return MapPlayArmyOrdersPick.pick(play, data)


## Whether the court's own reading names this standard, so its heading leads with
## the mark a crown finds it by among a long roll (DR-20261122-05).
func _is_marked(group: Dictionary) -> bool:
	return _counsel.keys().has(MapPlayPickProse.row_key(group, "army"))


# --- what the army names -----------------------------------------------------


func _layer_ready() -> bool:
	return play.army_layer != null


func _read() -> Dictionary:
	return ArmyLedger.snapshot(
		play.world,
		play.army_layer.regions,
		play.ship_layer.regions if play.ship_layer != null else null,
		play.player_faction
	)


func _filters() -> Array:
	return ArmyLedger.READINGS


func _reading_word(key: String) -> String:
	return ArmyLedger.reading_label(key)


func _row_word(count: int) -> String:
	return "regiment" if count == 1 else "regiments"


func _groups(region_key: String, reading_key: String) -> Array[Dictionary]:
	return ArmyLedger.groups(_snapshot, region_key, reading_key)


func _count(region_key: String, reading_key: String) -> int:
	return ArmyLedger.count(_snapshot, region_key, reading_key)


## Where one standard stands and what it is doing, above the regiments it flies:
## place, footing, strength and the food the men eat.
func _standing_text(group: Dictionary) -> String:
	return "%s  ·  %s  ·  %.1f strength  ·  %d food" % [
		String(group["place"]),
		String(group["standing"]),
		float(group["strength"]),
		int(group["food"]),
	]


## The rule a crown fields men by sits on the sheet, not in a hover: a phone
## hides the footer hint (REQ-P1-07, REQ-P5-03).
func _note() -> Control:
	var note := UiRowBuilder.label(ArmyLedger.note(), 11, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


## The count line the army prints: the view against the chart it is read in,
## with the army's own totals when every regiment is shown (REQ-P5-05).
func _subtitle_text(_shown: int) -> String:
	return ArmyLedger.summary(_snapshot, _region, _reading)


func _make_row(raw: Variant, compact: bool) -> Control:
	var row := ArmyLedgerRow.new()
	row.compact = compact
	row.visit_pressed.connect(_visit)
	row.setup(raw as Dictionary)
	return row


## The explanation a filter that empties the sheet earns: the crown may field no
## regiment yet, the filter may be hiding them, or the chart may hold none at all
## (REQ-P5-05).
func _empty_text() -> String:
	if int(_snapshot.get("total", 0)) == 0:
		var armies: int = ArmyLedger.army_count(_snapshot, _region)
		if armies > 0:
			return (
				"No regiment musters in %s — the drill yard raises the first, "
				+ "and every regiment it raises is read here."
			) % ArmyLedger.scope_text(_region)
		return "No standard answers this chart. Clear a filter to see the whole army."
	return "No regiment answers this view. Clear a filter to see the whole army."


## Visit frames the standard that flies the colours and opens its dossier: a
## regiment has no marker of its own, so the standard is what the map can show.
func _visit(region: int, army_id: int) -> void:
	if play == null:
		return
	if MapPlayForceLedger.focus(play, region, ForceLedger.KIND_ARMY, army_id):
		close()
