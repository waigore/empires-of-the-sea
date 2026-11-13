class_name AiPeaceStance
extends RefCounted
## One court's own word on a white peace (wiki: diplomacy § Planner selection;
## hidden-agendas — peacemaker early peace, warmonger keeps the war alive;
## DR-20261111-27).
##
## The same stance answers both halves of the exchange: a court puts peace to an
## enemy whose war it wants less than its bar, and it refuses a peace it is
## offered while its desire still sits at or above that bar. Pure rules: numbers
## in, answer out, nothing written (REQ-P2-03, REQ-P3-03).

## A pair that signed a white peace keeps cooling for this many turns: its war
## desire carries TRUCE_DESIRE_PENALTY below the score, so neither court clears
## the 51-point declaration bar at the 4-turn cooldown and the same war is not
## declared, undone and declared again (wiki: diplomacy § Planner selection;
## DR-20261113-25).
const TRUCE_TURNS: int = 24
const TRUCE_DESIRE_PENALTY: int = 40


## The bar a court's war desire must fall below before it makes or takes peace:
## the base desire shifted by the agenda's `peace_bias` (peacemaker 65,
## warmonger 40, isolationist 55 on the published base).
static func peace_bar(config: AiConfig) -> int:
	var base: int = config.parameter("diplomacy.war_desire_base")
	return clampi(base + config.peace_bias(), 0, 100)


## True when this court still wants the war it is fighting, so it refuses a
## white peace it is offered. Without this half a warmonger signed away the war
## it declared in the phase it declared it, and no war rule ever reached
## Movement.
static func refuses(config: AiConfig, desire: int) -> bool:
	return desire >= peace_bar(config)


## The pair's cooling term after a white peace: how far war desire is pushed
## down for a court that made peace with this one (0 once the truce has run).
## It reads the same per-pair peace clock the peace-offer cooldown uses, so a
## save neither forgets nor restarts the truce (DR-20261109-07). A war in
## progress carries no truce — the term prices a *new* declaration only.
static func truce_penalty(
	ai_state: AiState, turn: int, a: int, b: int, record: DiplomacyRelation
) -> int:
	if ai_state == null or record == null or record.at_war:
		return 0
	if not ai_state.peace_on_cooldown(a, b, turn, TRUCE_TURNS):
		return 0
	return TRUCE_DESIRE_PENALTY
