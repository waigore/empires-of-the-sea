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
