class_name ResearchQueueDesk
extends RefCounted
## The college's research-slot desk (REQ-P3-01). One persistent row per slot,
## rewritten in place from `ResearchWalk` — the same priced walk the one press
## reads (REQ-P2-03). The panel keeps the window and the intents; this desk owns
## the walk, the row mount, and the unpaid notice words (REQ-P3-02).


## Fills or updates every slot row under `slots_body`. Returns the walk's spend
## totals so the panel can rewrite the heading and the notice without walking
## again: `{gold, rp, unpaid}`.
static func fill(
	slots_body: VBoxContainer,
	slot_rows: Dictionary,
	state: ResearchState,
	treasury: int,
	boost: Dictionary,
	leader: String,
	on_cancel: Callable,
	on_funding: Callable
) -> Dictionary:
	var walk: Dictionary = ResearchWalk.run(state, treasury, "", boost, leader)
	var priced: Array[Dictionary] = walk["slots"]
	var floor: int = int(walk["floor"])
	for index in priced.size():
		var row: ResearchSlotRow = slot_rows.get(index)
		if row == null:
			row = ResearchSlotRow.new(index)
			row.cancel_pressed.connect(on_cancel)
			row.funding_pressed.connect(on_funding)
			slots_body.add_child(row)
			slot_rows[index] = row
		row.update(priced[index], floor)
	return {
		"gold": int(walk["gold"]),
		"rp": int(walk["rp"]),
		"unpaid": int(walk["unpaid"]),
	}


## The rule that stops the studies a purse cannot pay (wiki:
## tech-tree-labour-economy § money_lending, banking; REQ-P5-05). The words are
## `ResearchBatch`'s, the floor line the ledger's.
static func notice_line(state: ResearchState, unpaid: int) -> String:
	return ResearchBatch.notice_line(
		unpaid, LedgerReportText.research_floor_line(state.treasury_floor())
	)
