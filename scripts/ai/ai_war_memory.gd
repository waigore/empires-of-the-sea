class_name AiWarMemory
extends RefCounted
## How long a court has been fighting a war, and how recently peace was made
## (wiki: diplomacy § Cooldowns, § War goals and in-war reassessment; issue
## #475). Pure arithmetic over the AI's own book of grudges (`AiState`) and the
## calendar, so a replay never drifts and a save carries the clock with it.
##
## Two memories, one reading:
##
## - **weariness** — beyond `diplomacy.war_weariness_grace` turns a war costs
##   `diplomacy.war_weariness` desire each turn, so a war that takes nothing
##   ends instead of running for the whole campaign. A court that clearly
##   outmatches its enemy carries none: it is winning the war it wants.
## - **truce** — a peace that ends an **unfought** war (one that ran under
##   `diplomacy.truce_fought_turns`) holds the pair `diplomacy.truce_penalty`
##   below the declaration bar for `diplomacy.truce_turns`, so the attacker
##   cannot re-declare at the 4-turn cooldown with the same desire that failed
##   last time. A war actually prosecuted ends in a real settlement.
##
## Neither term deletes a war: the desire is reduced, never the legality, so
## every declaration still passes the rules check (REQ-P2-03). Both read **every**
## pair, colonial ones included: a war on a Minor Nation or a Tribe is still a
## war the court pays for, and the carousel it used to run — declare, white
## peace in the same phase, re-declare at the 4-turn cooldown — is the same
## unfought war the truce exists to stop (issue #511, DR-20261114-01).

const MAX_PENALTY: int = 100


## The penalty this court's desire to fight `target` carries right now: war
## weariness while at war, the truce while at peace. `stronger` is the court's
## own relative-power reading: a clearly stronger court does not tire.
static func penalty(
	config: AiConfig,
	ai_state: AiState,
	turn: int,
	faction: int,
	target: int,
	at_war: bool,
	stronger: bool = false
) -> int:
	if config == null or ai_state == null:
		return 0
	if at_war:
		return weariness(config, ai_state, turn, faction, target, stronger)
	return truce(config, ai_state, turn, faction, target)


## 0 inside the grace, then `diplomacy.war_weariness` per turn beyond it. A
## clearly stronger court carries none: its war is still worth waging.
static func weariness(
	config: AiConfig,
	ai_state: AiState,
	turn: int,
	faction: int,
	target: int,
	stronger: bool = false
) -> int:
	if config == null or ai_state == null or stronger:
		return 0
	var started: int = _turn_of(ai_state.last_war_turn, faction, target)
	if started < 0:
		return 0
	var age: int = maxi(turn - started, 0)
	var grace: int = maxi(config.parameter("diplomacy.war_weariness_grace"), 0)
	if age <= grace:
		return 0
	var step: int = maxi(config.parameter("diplomacy.war_weariness"), 0)
	return mini((age - grace) * step, MAX_PENALTY)


## `diplomacy.truce_penalty` while the pair is inside the truce a short war
## left, else 0.
static func truce(
	config: AiConfig, ai_state: AiState, turn: int, faction: int, target: int
) -> int:
	if config == null or ai_state == null:
		return 0
	var ended: int = _turn_of(ai_state.last_truce_turn, faction, target)
	if ended < 0:
		return 0
	var age: int = maxi(turn - ended, 0)
	if age >= maxi(config.parameter("diplomacy.truce_turns"), 0):
		return 0
	if _fought(ai_state, config, faction, target, ended):
		return 0
	return mini(maxi(config.parameter("diplomacy.truce_penalty"), 0), MAX_PENALTY)


## True when the war the peace ended was actually prosecuted: it ran at least
## `diplomacy.truce_fought_turns` from its declaration to its peace. A churn war
## (the #475 evidence: white peace 1-3 turns after the declaration) is unfought.
static func _fought(
	ai_state: AiState, config: AiConfig, faction: int, target: int, ended: int
) -> bool:
	var started: int = _turn_of(ai_state.last_war_turn, faction, target)
	if started < 0:
		return false
	return ended - started >= maxi(config.parameter("diplomacy.truce_fought_turns"), 0)


## True when this court's own reading of the balance excuses it from tiring: a
## court that clearly outmatches a **peer** is winning the war it wants. That
## reading is peer-only — strength against a Minor Nation or Tribe is the
## precondition for a landing, not evidence of one, so a colonial war still
## wears (issue #511).
static func outmatches(target: int, power_bonus: int) -> bool:
	return (
		power_bonus >= AiPower.BONUS_STRONG
		and FactionCatalog.type_of(target) == FactionCatalog.Type.GREAT_POWER
	)


## The turn recorded for one unordered pair, or -1 when the pair has no entry.
static func _turn_of(table: Dictionary, a: int, b: int) -> int:
	var key: String = AiState.pair_key(a, b)
	if not table.has(key):
		return -1
	return int(table[key])
