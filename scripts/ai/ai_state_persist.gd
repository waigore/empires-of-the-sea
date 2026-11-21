class_name AiStatePersist
extends RefCounted
## Save/load shape for [AiState]: agendas, cooldowns, rival ledgers, claims,
## deferrals and temperaments (REQ-P3-01). The live bookkeeping stays on
## AiState; this module owns the JSON-safe round-trip so a save never re-rolls
## a hidden agenda or drops a profile binding (wiki: hidden-agendas,
## ai-profile-overrides; REQ-P3-03).


## Plain data for local saves. Agendas are rolled once per court and cooldowns
## span turns, so a load must not re-roll a hidden agenda or restart a war
## cooldown (wiki: hidden-agendas, diplomacy § Cooldowns).
static func pack(state: AiState) -> Dictionary:
	return {
		"agendas": state.agendas.duplicate(),
		"last_war_turn": state.last_war_turn.duplicate(),
		"last_overture_turn": state.last_overture_turn.duplicate(),
		"last_truce_turn": state.last_truce_turn.duplicate(),
		"last_attack_turn": state.last_attack_turn.duplicate(),
		"last_peace_turn": state.last_peace_turn.duplicate(),
		"peace_refusals": state.peace_refusals.duplicate(),
		"economies": economy_snapshots(state.economies),
		# The escalation's stall records are plain {aim -> {turns, shortfall}},
		# JSON-safe as they stand (issue #603).
		"deferrals": state.deferrals.duplicate(true),
		"objective_claims": claims_snapshot(state.objective_claims),
		"difficulty": state.difficulty,
		# The temperaments bound at creation: a load must resume the same rivals
		# (wiki: ai-profile-overrides — the binding is fixed for the run).
		"profiles": state.profiles.duplicate(),
	}


static func unpack(data: Dictionary) -> AiState:
	var state := AiState.new()
	var stored_agendas: Dictionary = dictionary(data.get("agendas", {}))
	for key: Variant in stored_agendas.keys():
		state.agendas[int(key)] = String(stored_agendas[key])
	state.last_war_turn = turn_dictionary(data.get("last_war_turn", {}))
	state.last_overture_turn = turn_dictionary(data.get("last_overture_turn", {}))
	state.last_truce_turn = turn_dictionary(data.get("last_truce_turn", {}))
	state.last_attack_turn = turn_dictionary(data.get("last_attack_turn", {}))
	state.last_peace_turn = turn_dictionary(data.get("last_peace_turn", {}))
	state.peace_refusals = turn_dictionary(data.get("peace_refusals", {}))
	state.economies = economies_from(data.get("economies", {}))
	# A JSON round-trip turns the faction keys into strings: file them back as
	# ints, and drop any row a save could not describe (issue #603).
	var stored_deferrals: Dictionary = dictionary(data.get("deferrals", {}))
	for faction: Variant in stored_deferrals.keys():
		var records: Dictionary = AiDeferral.clean(dictionary(stored_deferrals[faction]))
		if not records.is_empty():
			state.deferrals[int(faction)] = records
	state.objective_claims = claims_from(data.get("objective_claims", {}))
	state.difficulty = Difficulty.normalize(String(data.get("difficulty", Difficulty.DEFAULT)))
	# A save from before the temperaments were kept resumes every rival on the
	# neutral profile, the profile a campaign with no binding plans by.
	state.profiles = AiProfile.from_saved(data.get("profiles", {}))
	return state


## One row per court's last ledger: turn, phase, counts and the claim lines. An
## old save has none, so the ledger simply starts empty (issue #491 T1).
static func claims_snapshot(objective_claims: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in objective_claims.keys():
		result[int(raw)] = claim_row(dictionary(objective_claims[raw]))
	return result


static func claims_from(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	var stored: Dictionary = dictionary(raw)
	for key: Variant in stored.keys():
		var row: Dictionary = claim_row(dictionary(stored[key]))
		if row.is_empty():
			continue
		result[int(key)] = row
	return result


## A JSON-safe claim row: the trace lines become strings, never Variants.
static func claim_row(claim: Dictionary) -> Dictionary:
	if claim.is_empty():
		return {}
	var lines: Array[String] = []
	for raw: Variant in claim.get("lines", []):
		lines.append(String(raw))
	var row: Dictionary = {
		"turn": int(claim.get("turn", 0)),
		"phase": String(claim.get("phase", "")),
		"ranked": int(claim.get("ranked", 0)),
		"funded": int(claim.get("funded", 0)),
		"lines": lines,
	}
	for key: String in ["funded_ids", "deferred_ids", "blocked_ids"]:
		var ids: Array[String] = []
		for raw: Variant in claim.get(key, []):
			ids.append(String(raw))
		row[key] = ids
	return row


## One snapshot per rival ledger, keyed by faction id. Missing factions are
## simply seeded from the starting row on first read, so old saves still load.
static func economy_snapshots(economies: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in economies.keys():
		var faction: int = int(raw)
		var economy: PlayerEconomy = economies[raw] as PlayerEconomy
		if economy != null:
			result[faction] = economy.snapshot()
	return result


static func economies_from(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	var stored: Dictionary = dictionary(raw)
	for key: Variant in stored.keys():
		var data: Dictionary = dictionary(stored[key])
		if data.is_empty():
			continue
		var economy := PlayerEconomy.starting()
		economy.apply_snapshot(data)
		result[int(key)] = economy
	return result


static func turn_dictionary(raw: Variant) -> Dictionary:
	var turns: Dictionary = {}
	var stored: Dictionary = dictionary(raw)
	for key: Variant in stored.keys():
		turns[String(key)] = int(stored[key])
	return turns


static func dictionary(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}
