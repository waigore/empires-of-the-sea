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
##   outmatches its enemy carries none: it is winning the war it wants. On top
##   of it, a war that has taken **no attack on the enemy** for
##   `diplomacy.pointless_window` turns erodes `diplomacy.pointless_step` a turn
##   from the first quiet one — the exemption covers a war being prosecuted, not
##   a stronger court standing still (issue #999).
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
## clearly stronger court carries none: its war is still worth waging. The
## pointless-war erosion rides on top and never spares a stronger court — an
## exemption covers a war being prosecuted, not a stronger court standing still
## (issue #999).
static func weariness(
	config: AiConfig,
	ai_state: AiState,
	turn: int,
	faction: int,
	target: int,
	stronger: bool = false
) -> int:
	if config == null or ai_state == null:
		return 0
	var started: int = _turn_of(ai_state.last_war_turn, faction, target)
	if started < 0:
		return 0
	var age: int = maxi(turn - started, 0)
	var grace: int = maxi(config.parameter("diplomacy.war_weariness_grace"), 0)
	var total: int = 0
	if age > grace and not stronger:
		var step: int = maxi(config.parameter("diplomacy.war_weariness"), 0)
		total = (age - grace) * step
	return mini(total + pointless(config, ai_state, turn, faction, target, started), MAX_PENALTY)


## The pointless-war erosion: a war past its grace that has taken no attack on
## the enemy for `diplomacy.pointless_window` turns is yielding nothing, so its
## desire falls `diplomacy.pointless_step` a turn from the first quiet turn —
## fast enough to beat the victory press (+30) and cross the peace bar in a few
## turns (issue #999). A war being prosecuted carries none, and an attack
## restarts the window. Nothing here touches legality.
static func pointless(
	config: AiConfig,
	ai_state: AiState,
	turn: int,
	faction: int,
	target: int,
	started: int = -1
) -> int:
	if config == null or ai_state == null:
		return 0
	var began: int = started
	if began < 0:
		began = _turn_of(ai_state.last_war_turn, faction, target)
	if began < 0:
		return 0
	var grace: int = maxi(config.parameter("diplomacy.war_weariness_grace"), 0)
	if turn - began <= grace:
		return 0
	var window: int = maxi(config.parameter("diplomacy.pointless_window"), 0)
	var quiet_from: int = maxi(began + grace, attack_turn(ai_state, faction, target))
	var quiet: int = turn - quiet_from
	if quiet <= window:
		return 0
	var step: int = maxi(config.parameter("diplomacy.pointless_step"), 0)
	return mini((quiet - window) * step, MAX_PENALTY)


## True when this court has attacked `target`'s ground inside
## `diplomacy.pointless_window` turns: the war's benefit engine is running.
static func prosecuted(
	config: AiConfig, ai_state: AiState, turn: int, faction: int, target: int
) -> bool:
	if config == null or ai_state == null:
		return false
	var last: int = attack_turn(ai_state, faction, target)
	if last < 0:
		return false
	return turn - last <= maxi(config.parameter("diplomacy.pointless_window"), 0)


## True while this court's war footing holds a front the war's own benefit
## engine is still running on: a Great Power war inside its grace, or one the
## court attacked inside the pointless window. A war past its grace with no
## attack is a phoney front — the same read the diplomacy pass erodes to its
## peace (issue #999) — so it holds no coin back: the market's speculative
## top-up may open while the war waits for the peace that ends it (issue #995).
## A caller with no state to read keeps the published footing: an unread war
## is a front. A war on a Minor Nation or a Tribe is colonial business and
## never held the footing, so it holds none here either.
static func holds_front(
	config: AiConfig, ai_state: AiState, state: DiplomacyState,
	turn: int, faction: int
) -> bool:
	if config == null or state == null:
		return true
	for record: DiplomacyRelation in state.relations_of(faction):
		if record == null or not record.at_war:
			continue
		var target: int = record.other(faction)
		if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
			continue
		if pointless(config, ai_state, turn, faction, target) == 0:
			return true
	return false


## An attack on another court's ground is the war's benefit engine running: the
## diplomacy pass reads it to tell a prosecuted war from a pointless one
## (issue #999). The table lives on `AiState` so a save carries the clock.
static func note_attack(ai_state: AiState, a: int, b: int, turn: int) -> void:
	if ai_state == null:
		return
	ai_state.last_attack_turn[attack_key(a, b)] = turn


## The turn this court last attacked `b`'s ground, or -1 when it never has.
static func attack_turn(ai_state: AiState, a: int, b: int) -> int:
	if ai_state == null:
		return -1
	return int(ai_state.last_attack_turn.get(attack_key(a, b), -1))


## Directional pair key: `a` attacked `b`. A truce binds both courts, so the
## cooldown keys are unordered; a war's benefit is one court's own (issue #999).
static func attack_key(a: int, b: int) -> String:
	return "%d>%d" % [a, b]


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
