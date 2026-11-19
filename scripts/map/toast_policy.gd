class_name ToastPolicy
extends RefCounted
## The despatch lane's writing rule (wiki: hud-toasts; issue #1056).
##
## The lane is not the news sheet. It raises three things and nothing else:
##
## 1. **The turn clock** — `Turn N — year`, with the market suffix when a
##    clearing was struck. Raised once at the turn's close by
##    `MapPlayTurnFinish._follow_view`.
## 2. **The answer to the crown's own press** — a refusal, a receipt, a move ack,
##    a consent prompt. These fire in the frame of the press that raised them.
## 3. **Danger to the human crown** — a clash it fights, a loss of its own, its
##    court moved, a spy caught in its land, a rival army ashore on its coast,
##    a crown near the bar.
##
## What the turn resolves for other courts — their works, their wall, their
## battles, a spy's despatch — is the Gazette's or a sheet's, never the lane's
## (REQ-P5-02, REQ-P5-06). `tests/test_toast_policy.gd` proves the two readings
## below; the full inventory of the lane's lines is the wiki's
## (hud-toasts § Inventory).


## True when a clash's attacker or defender is the crown (`crown` = its id).
## A fight between other courts is World news for the Gazette.
static func battle_touches_crown(crown: int, battle: Dictionary) -> bool:
	if crown < 0:
		return false
	return (
		int(battle.get("attacker", -1)) == crown
		or int(battle.get("defender", -1)) == crown
	)


## True when a loss, a work or a court move belongs to the crown. A rival's
## loss or move is its own news; the lane is told nothing of it.
static func of_crown(crown: int, faction: int) -> bool:
	return crown >= 0 and faction == crown
