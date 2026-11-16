class_name FleetSplitBlock
extends FleetDrawer
## The fleet dossier's split drawer: every hull of the selected squadron with the
## one tap that detaches her into a squadron of her own (wiki: ships-and-naval
## § Ship instances; DR-20261116-12). It reads the rules' own rows and emits
## intents; FleetSplit decides what may leave (REQ-P3-02, REQ-P3-03). The
## drawer's toggle, list and row shell are FleetDrawer's; this block names the
## hulls' words and the detach press (REQ-P3-01).


func _init() -> void:
	toggle_text = "Split the squadron"
	close_text = "Close split"
	has_note = true


## A fresh squadron: the drawer closes unless it may stay, and the rows redraw.
## A squadron that may detach nothing prints the gate's own reason instead of a
## press, so a phone never has to hover for the rule (REQ-P1-07).
func show_rows(
	model: MapModel, fleet: FleetState, is_player: bool, keep_open: bool
) -> void:
	var rows: Array[Dictionary] = []
	if is_player:
		rows = FleetSplit.rows(model, fleet)
	offer(rows, is_player, rows.size() > 1, FleetSplit.NOTE, keep_open)


## One hull: her medallion, the name she flies and the one tap that detaches
## her. A hull the rules hold back keeps her row and prints why.
func _build_row(row: Dictionary) -> Control:
	var ok: bool = bool(row["ok"])
	var reason: String = String(row["reason"])
	var hull_name: String = String(row["name"])
	var type_name: String = String(row["type_name"])
	return super({
		"type": String(row["type"]),
		"name": type_name if hull_name.is_empty() else "%s — %s" % [hull_name, type_name],
		"ok": ok,
		"reason": reason,
		"label": "Detach",
		"tip": "Detach this hull" if ok else reason,
		"action": "split:%s" % String(row["hull"]),
	})
