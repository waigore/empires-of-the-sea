class_name FleetCombineBlock
extends FleetDrawer
## The fleet dossier's combine drawer: every other squadron of the crown in the
## same station with the one tap that folds this one into her (wiki:
## ships-and-naval § Ship instances; DR-20261116-13). It reads the rules' own
## rows and emits intents; FleetCombine decides what may join (REQ-P3-02,
## REQ-P3-03). The drawer's toggle, list and row shell are FleetDrawer's; this
## block names the neighbours' words and the join press (REQ-P3-01).

func _init() -> void:
	toggle_text = "Combine the squadron"
	close_text = "Close combine"
	has_note = true


## A fresh squadron: the drawer closes unless it may stay, and the rows redraw.
## A squadron that may join nothing prints the gate's own reason instead of a
## press, so a phone never has to hover for the rule (REQ-P1-07).
func show_rows(
	model: MapModel,
	roster: Array[FleetState],
	fleet: FleetState,
	is_player: bool,
	keep_open: bool
) -> void:
	var rows: Array[Dictionary] = []
	if is_player:
		rows = FleetCombine.rows(model, roster, fleet)
	# A squadron standing alone has nothing to combine and nothing to explain.
	offer(rows, is_player, not rows.is_empty(), FleetCombine.NOTE, keep_open)


## One squadron: her flagship's medallion, the hull count she brings and the one
## tap that folds this one into her. A squadron the rules hold back keeps its row
## and prints why.
func _build_row(row: Dictionary) -> Control:
	var ok: bool = bool(row["ok"])
	var reason: String = String(row["reason"])
	var target: int = int(row["fleet"])
	var hulls: int = int(row["hulls"])
	return super({
		"type": String(row["type"]),
		"name": "%s — %d hull%s" % [
			String(row["name"]), hulls, "" if hulls == 1 else "s"
		],
		"ok": ok,
		"reason": reason,
		"label": "Join her",
		"tip": "Fold this squadron into her" if ok else reason,
		"action": "combine:%d" % target,
		# The squadron the press folds into her, for a drive reading the row.
		"fleet": target,
	})
