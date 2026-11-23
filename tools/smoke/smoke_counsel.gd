extends RefCounted
## The court's readings on the bar's ledgers: every sheet that names the orders
## the crown's own passes would give this turn opens from the door the player
## uses, prints its one gold line, marks the rows it answers, and orders nothing
## (DR-20261121-05/06/07/09/11/12/13/14/16/17/19/21, DR-20261122-01/03/04/06/08/12/18).
##
## The court ledger's own envoy and the sound desk stay in the HUD step. This
## file only orders the step's halves, so a new reading lands in the half it
## belongs to and no one body grows past the size bar (REQ-P3-01):
##
## | Half | Owns |
## |------|------|
## | tools/smoke/smoke_counsel_ledger.gd | the estates card, the ledger's production / market / workers tabs, the crown's eyes |
## | tools/smoke/smoke_counsel_sheets.gd | the people, the navy, the army, the muster, the colonies, the realm |
## | tools/smoke/smoke_counsel_yards.gd | the drill yard, the capital slip, the capital rail |
## | tools/smoke/smoke_counsel_reads.gd | the tallies both halves hold their readings to |
##
## No `class_name`: the driver (tools/e2e_smoke.gd) preloads this file.

const SmokeCounselLedger = preload("res://tools/smoke/smoke_counsel_ledger.gd")
const SmokeCounselSheets = preload("res://tools/smoke/smoke_counsel_sheets.gd")
const SmokeCounselYards = preload("res://tools/smoke/smoke_counsel_yards.gd")


static func step(run) -> void:
	var screen: MapScreen = run.screen
	await SmokeCounselLedger.step(run, screen)
	await SmokeCounselSheets.step(run, screen)
	await SmokeCounselYards.step(run, screen)
