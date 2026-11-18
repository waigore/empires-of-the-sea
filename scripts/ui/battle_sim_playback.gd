class_name BattleSimPlayback
extends RefCounted
## Paints one sandbox moment onto [QuickBattleField]: a round's lines or the
## aftermath the battle left. View-only — the record is already resolved
## (REQ-P3-03, REQ-P2-03).


## Shows one fought round on the plate and returns its status plaque text.
static func show_round(
	field: QuickBattleField, report: Dictionary, index: int, names: Array
) -> Dictionary:
	var rounds: Array = BattleSimDespatch.rounds_of(report)
	if index < 0 or index >= rounds.size():
		return {"ok": false, "aftermath": true}
	var entry: Dictionary = rounds[index] as Dictionary
	field.set_round(
		index, int(entry.get("attacker_count", 0)), int(entry.get("defender_count", 0)),
		int(entry.get("guns", 0)), entry.get("attacker_health", []) as Array,
		entry.get("defender_health", []) as Array, int(entry.get("gates", 0))
	)
	## The wings as this round left them: a wing that emptied is dimmed and one
	## that broke is struck through, so a collapse is read at a glance (wiki:
	## quick-battle § Wings and collapse).
	apply_wings(field, entry)
	return {
		"ok": true,
		"cursor": index,
		"status": BattleSimDespatch.status_for_round(report, index),
	}


## Aftermath: lines as the battle left them, outcome stamp on the status plaque.
static func show_aftermath(
	field: QuickBattleField, report: Dictionary, sandbox: String, names: Array
) -> Dictionary:
	var quick: Dictionary = report["quick"] as Dictionary
	var rounds: Array = BattleSimDespatch.rounds_of(report)
	field.attacker_count = int(quick.get("attacker_left", 0))
	field.defender_count = int(quick.get("defender_left", 0))
	field.guns = int(quick.get("guns_left", 0))
	field.gates_broken = int(quick.get("breaches", 0))
	field.attacker_health = report.get("attacker_health", []) as Array
	field.defender_health = report.get("defender_health", []) as Array
	## The aftermath stands where the last round left the lines, as the game's
	## own plate does, so the sandbox reads like the battle it studies.
	field.round_index = maxi(rounds.size() - 1, 0)
	field.set_outcome(int(report.get("outcome", 0)))
	## The wings as the battle left them, not the deal it opened with: a line
	## whose wings have all broken still shows them struck through (wiki:
	## quick-battle § Wings and collapse).
	apply_wings(field, quick)
	return {
		"cursor": rounds.size(),
		"status": QuickBattleCopy.outcome_text(
			int(report.get("outcome", 0)), report, sandbox, names
		),
	}


## Paints one moment's wings — a round's record or the battle's final one — on
## the plate. A record without wings (a siege garrison, an older plate) clears
## them.
static func apply_wings(field: QuickBattleField, record: Dictionary) -> void:
	var held: Dictionary = record.get("wings", {}) as Dictionary
	var broken: Dictionary = record.get("wings_broken", {}) as Dictionary
	field.set_wings(
		held.get("attacker", {}) as Dictionary, held.get("defender", {}) as Dictionary,
		broken.get("attacker", []) as Array, broken.get("defender", []) as Array
	)


## The round doors a record can open: a round the battle never fought has no
## door, so pressing it cannot quietly mean the aftermath.
static func set_round_buttons(buttons: HFlowContainer, enabled: bool, fought: int) -> void:
	for index in buttons.get_child_count():
		var button: Button = buttons.get_child(index) as Button
		button.disabled = not enabled or (index < QuickBattleTerms.MAX_ROUNDS and index >= fought)


## Clears the plate back to an empty sandbox.
static func reset_field(field: QuickBattleField) -> void:
	field.set_battle({})
	field.attacker_count = 0
	field.defender_count = 0
	field.queue_redraw()
