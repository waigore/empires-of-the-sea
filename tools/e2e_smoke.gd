extends SceneTree
## Headless e2e smoke: boot main.tscn, exercise one player turn across every
## unit type (civilian / navy / army), quit. Budget ≤2 minutes.
##   godot --headless --path . --script res://tools/e2e_smoke.gd
##
## The drive reads as its steps: each module in tools/smoke/ owns one stage of
## the flow and prints its own asserts through the shared `SmokeRun`, so a new
## check lands in the step it belongs to instead of growing one long body
## (REQ-P3-01). This file only orders the steps and sets the exit code.

const SmokeRun = preload("res://tools/smoke/smoke_run.gd")
const SmokeLaunch = preload("res://tools/smoke/smoke_launch.gd")
const SmokeMap = preload("res://tools/smoke/smoke_map.gd")
const SmokeArmy = preload("res://tools/smoke/smoke_army.gd")
const SmokeHud = preload("res://tools/smoke/smoke_hud.gd")
const SmokeSheets = preload("res://tools/smoke/smoke_sheets.gd")
const SmokeCivilians = preload("res://tools/smoke/smoke_civilians.gd")
const SmokeForces = preload("res://tools/smoke/smoke_forces.gd")
const SmokeTurn = preload("res://tools/smoke/smoke_turn.gd")
const SmokeVictory = preload("res://tools/smoke/smoke_victory.gd")
const SmokePersistence = preload("res://tools/smoke/smoke_persistence.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var run = SmokeRun.new(self)
	if not await SmokeLaunch.step(run):
		_finish(run)
		return
	await SmokeMap.step(run)
	await SmokeArmy.step(run)
	await SmokeHud.step(run)
	await SmokeSheets.step(run)
	await SmokeCivilians.step(run)
	await SmokeForces.step_navy(run)
	SmokeForces.step_army_recruit(run)
	await SmokeTurn.step(run)
	# The colonist path boards an idle hire, and Build/work only musters the
	# queued explorer once the turn has closed (wiki: workers-and-population
	# § Phase placement).
	await SmokeForces.step_colonists(run)
	await SmokeVictory.step(run)
	await SmokePersistence.step(run)
	_finish(run)


## The gate's exit code: every assert already printed, the tally decides the run.
func _finish(run) -> void:
	if not run.failed():
		print("e2e_smoke: all asserts passed")
		quit(0)
		return
	printerr("e2e_smoke: %s" % run.failure_line())
	quit(1)
