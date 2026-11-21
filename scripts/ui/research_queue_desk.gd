class_name ResearchQueueDesk
extends RefCounted
## The college's research-slot desk (REQ-P3-01). One persistent row per slot,
## rewritten in place from `ResearchWalk` — the same priced walk the one press
## reads (REQ-P2-03). The panel keeps the window and the intents; this desk owns
## the walk, the row mount, and the unpaid notice words (REQ-P3-02).


## Fills or updates every slot row under `slots_body`. Returns the walk's spend
## totals so the panel can rewrite the heading and the notice without walking
## again: `{gold, rp, unpaid}`. `counsel` rides the first idle slot — the study
## the court would open there — so the advice lands where the choice is made and
## costs the sheet no chrome (wiki: tech-tree § Research model; DR-20261121-01).
static func fill(
	slots_body: VBoxContainer,
	slot_rows: Dictionary,
	state: ResearchState,
	treasury: int,
	boost: Dictionary,
	leader: String,
	on_cancel: Callable,
	on_funding: Callable,
	counsel: String = ""
) -> Dictionary:
	var walk: Dictionary = ResearchWalk.run(state, treasury, "", boost, leader)
	var floor: int = int(walk["floor"])
	# The counsel is the study the court would open, not a slot: it rides the
	# first idle row alone, so two idle slots never repeat one sentence.
	var told: bool = false
	for index in walk["slots"].size():
		var row: ResearchSlotRow = slot_rows.get(index)
		if row == null:
			row = ResearchSlotRow.new(index)
			row.cancel_pressed.connect(on_cancel)
			row.funding_pressed.connect(on_funding)
			slots_body.add_child(row)
			slot_rows[index] = row
		var price: ResearchSlotPrice = ResearchSlotPrice.from_priced(
			walk["slots"][index], floor
		)
		var word: String = ""
		if price.is_idle() and not told and not counsel.is_empty():
			word = counsel
			told = true
		row.update(price, word)
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
