class_name AiBind
extends RefCounted
## Shared bind helpers: config, phase, and mainline script load for BENCH
## baseline rivals. Economy planner routes live on `AiBindEconomy`; field,
## fleet, voyage, and hospital routes live on `AiBindCampaign`.

const MAINLINE_ROOT: String = "res://scripts/ai_mainline/"


static func _baseline(kind: String) -> bool:
	return (
		kind == AiControl.KIND_BASELINE
		and ResourceLoader.exists(MAINLINE_ROOT + "ai_config.gd")
	)


static func config(kind: String, faction: int, game_seed: int) -> Variant:
	if _baseline(kind):
		return _ml("ai_config.gd", "build", [faction, game_seed])
	return AiConfig.build(faction, game_seed)


static func phase_for(kind: String, config: Variant, diplomacy: DiplomacyState) -> String:
	if _baseline(kind):
		return String(_ml("ai_phase_planner.gd", "phase_for", [config, diplomacy]))
	return AiPhasePlanner.phase_for(config, diplomacy)


static func _ml(file: String, method: String, args: Array) -> Variant:
	var path: String = MAINLINE_ROOT + file
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_error("AiBind: failed to load %s" % path)
		return null
	return script.callv(method, args)
