class_name AiState
extends RefCounted
## Per-game AI bookkeeping that outlives one turn: the fixed agenda assignment
## and the per-pair cooldowns (wiki: hidden-agendas, diplomacy § Cooldowns).
## Pure RefCounted data so tests drive it without a map screen (REQ-P3-03).
## Save/load shape lives in [AiStatePersist] so this file stays the live book
## (REQ-P3-01).

## Faction id -> agenda id. Assigned once, then never re-rolled.
var agendas: Dictionary = {}
## "low:high" pair key -> turn the AI last declared war.
var last_war_turn: Dictionary = {}
## "low:high" pair key -> turn the AI last saw an overture accept/reject.
var last_overture_turn: Dictionary = {}
## "low:high" pair key -> turn the AI last made peace on that pair. The truce it
## carries afterwards reads this (docs/ai.md; issue #475).
var last_truce_turn: Dictionary = {}
## "attacker>target" pair key -> turn that court last attacked the other's
## ground. The war-benefit read asks whether a war is being prosecuted: a war
## with no attack on the enemy for `diplomacy.pointless_window` turns is
## yielding nothing, so its desire erodes fast (issue #999). Directional — the
## enemy's attacks are not this court's benefit.
var last_attack_turn: Dictionary = {}
## "low:high" pair key -> turn the human court answered a peace offer.
var last_peace_turn: Dictionary = {}
## "low:high" pair key -> refused white-peace offers since the pair last made
## peace or last went to war. A refusal is information: the planner widens its
## next ask from this count instead of retrying on every cooldown turn (wiki:
## diplomacy § Cooldowns; DR-20261115-01).
var peace_refusals: Dictionary = {}
## Faction id -> that rival court's ledger (stockpile, treasury, workers).
## Rival economies are seeded on first read and then persist like the player's
## (docs/ai.md, wiki: stockpiles-and-production).
var economies: Dictionary = {}
## Faction id -> the deferred-aim stall records the escalation tracker keeps
## (`AiDeferral`, issue #603): how many turns each aim has been deferred
## without its shortfall shrinking. Read back by the readings and the reserve,
## so a stalled war chest re-routes instead of freezing the court.
var deferrals: Dictionary = {}
## Faction id -> the claims the objective ledger last ranked and funded, with
## the trace lines that explain them (docs/ai.md; issue #491 T1). Kept here so a
## save carries the ledger the court reported.
var objective_claims: Dictionary = {}
## Faction id -> the food slack the court's own harvest carries: the ration
## food the extraction just landed, less every mouth the consumption phase
## feeds. Noted by the economy pass each turn (`note_food_slack`) and read by
## the muster's growth gate the next, so a court arms only as fast as its land
## can carry — the army it desires is provisioned before it is raised (issue
## #807). Transient: the economy pass re-notes it every turn, so a save needs
## no copy. A faction the pass has not noted has no reading, and the gates
## that read it stand down.
var food_slack: Dictionary = {}
## Difficulty layer this run plays at; rival ledgers are founded at its level
## (wiki: ruleset-config § Layers). Stamped by `PlaySession.ensure_ai`.
var difficulty: String = Difficulty.DEFAULT
## Faction -> blessed AI parameter profile, bound on the new-game screen and
## fixed for the run; a crown the map does not name plans as the neutral profile
## (wiki: ai-profile-overrides; ai-parameter-registry § Seed profiles). Saved
## with the campaign's AI bookkeeping so a load resumes the same temperaments.
var profiles: Dictionary = AiProfile.roster()


## Keeps the first agenda this court rolled; later configs read it back.
func agenda_for(config: AiConfig) -> String:
	if not agendas.has(config.faction):
		agendas[config.faction] = config.agenda
	return String(agendas[config.faction])


## The rival's ledger, created from the shared starting row at this run's
## difficulty. The same instance is returned every turn, so assignments and
## stockpiles persist (and the start is scaled exactly once).
func economy_for(faction: int) -> PlayerEconomy:
	if not economies.has(faction):
		var economy := PlayerEconomy.starting()
		Difficulty.scale_start(economy, difficulty)
		economies[faction] = economy
	return economies[faction] as PlayerEconomy


## Rival stockpile by faction, for the diplomacy planner's resource-need score
## (wiki: diplomacy-planner § Resource need). `exclude` keeps the human court's
## own fake ledger out of the read model.
func stockpiles(exclude: int = -1) -> Dictionary:
	var result: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		if faction == exclude:
			continue
		result[faction] = economy_for(faction).stockpile
	return result


func note_war(a: int, b: int, turn: int) -> void:
	last_war_turn[pair_key(a, b)] = turn
	# A new war is a new question: the refusals of the last one are spent, and
	# neither court's prosecution clock carries over (issue #999).
	peace_refusals.erase(pair_key(a, b))
	last_attack_turn.erase(AiWarMemory.attack_key(a, b))
	last_attack_turn.erase(AiWarMemory.attack_key(b, a))


func war_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_war_turn.has(key):
		return false
	return turn - int(last_war_turn[key]) < cooldown


func note_overture(a: int, b: int, turn: int) -> void:
	last_overture_turn[pair_key(a, b)] = turn


## A concluded peace starts the pair's truce: the war it ended leaves both
## courts unwilling to fight again for `diplomacy.truce_turns` (issue #475).
func note_truce(a: int, b: int, turn: int) -> void:
	last_truce_turn[pair_key(a, b)] = turn
	# The war is over, so the refusals it collected are no longer a reason to
	# wait when it resumes (DR-20261115-01).
	peace_refusals.erase(pair_key(a, b))


func overture_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_overture_turn.has(key):
		return false
	return turn - int(last_overture_turn[key]) < cooldown


## A refused peace offer is not repeated immediately: the peace cooldown runs
## from the turn the court answering it spoke (DR-20261109-07). A refusal is
## also remembered, because the same answer asked again on every cooldown turn
## is not a question — the planner widens the wait from this count
## (DR-20261115-01).
func note_peace(a: int, b: int, turn: int, accepted: bool = true) -> void:
	var key: String = pair_key(a, b)
	last_peace_turn[key] = turn
	if accepted:
		peace_refusals.erase(key)
		return
	peace_refusals[key] = int(peace_refusals.get(key, 0)) + 1


## How many white-peace offers this pair has refused since it last made peace
## (or last went to war). 0 means the court has not been told no.
func peace_refusals_for(a: int, b: int) -> int:
	return int(peace_refusals.get(pair_key(a, b), 0))


func peace_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_peace_turn.has(key):
		return false
	return turn - int(last_peace_turn[key]) < cooldown


## Same unordered-pair key as DiplomacyState, so cooldowns cannot drift.
static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## The turn's ledger summary for one court: what it ranked, what it funded and
## the lines that explain the rest. Claims are per turn, so a later turn simply
## replaces the row (docs/ai.md; issue #491 T1).
func note_objectives(faction: int, report: Dictionary, turn: int) -> void:
	var lines: Array[String] = []
	for raw: Variant in report.get("lines", []):
		lines.append(String(raw))
	# The ids by status let the next turn's planners consult the claim they were
	# granted (e.g. the expedition's hull before the muster gate opens, #497).
	var ids: Dictionary = {"funded": [], "deferred": [], "blocked": []}
	_collect_ids(report.get("objectives", []), ids)
	objective_claims[faction] = {
		"turn": turn,
		"phase": String(report.get("phase", "")),
		"ranked": int(report.get("ranked", 0)),
		"funded": int(report.get("funded", 0)),
		"funded_ids": ids["funded"],
		"deferred_ids": ids["deferred"],
		"blocked_ids": ids["blocked"],
		"lines": lines,
	}
	# The escalation tracker folds the same rows: one stall map per court, so a
	# save carries how long each aim has stood still (issue #603).
	deferrals[faction] = AiDeferral.note(
		AiStatePersist.dictionary(deferrals.get(faction, {})),
		report.get("objectives", [])
	)


## Walks the ledger tree and files every objective id under its status.
static func _collect_ids(rows: Variant, ids: Dictionary) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for raw: Variant in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var status: String = String(row.get("status", ""))
		var list: Variant = ids.get(status, null)
		if typeof(list) == TYPE_ARRAY:
			(list as Array).append(String(row.get("id", "")))
		_collect_ids(row.get("children", []), ids)


## The claims this court's last turn reported, or an empty row.
func objectives_for(faction: int) -> Dictionary:
	return AiStatePersist.dictionary(objective_claims.get(faction, {}))


## Notes the harvest slack the economy pass just read for this court.
func note_food_slack(faction: int, slack: int) -> void:
	food_slack[faction] = slack


## Plain data for local saves — see [AiStatePersist.pack].
func to_dict() -> Dictionary:
	return AiStatePersist.pack(self)


static func from_dict(data: Dictionary) -> AiState:
	return AiStatePersist.unpack(data)
